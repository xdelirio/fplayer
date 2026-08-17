import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'telemetry_config.dart';
import 'telemetry_event.dart';

/// What to do with a batch after trying to deliver it.
enum FTelemetryDeliveryStatus {
  /// The backend took it. Remove it from the queue.
  delivered,

  /// Something temporary got in the way. Keep it and try again.
  retry,

  /// The backend will never accept it. Remove it, or the queue never drains.
  dropped,
}

@immutable
class FTelemetryDelivery {
  const FTelemetryDelivery(this.status, {this.retryAfter, this.statusCode});

  final FTelemetryDeliveryStatus status;

  /// Wait the server asked for, when it named one.
  final Duration? retryAfter;

  final int? statusCode;

  @override
  String toString() => 'FTelemetryDelivery(${status.name}, code: $statusCode)';
}

/// Posts batches of events and classifies the answer.
///
/// The classification is the whole point: a queue that retries a `422` forever never drains, and
/// one that drops a `429` throws away data the server only asked it to slow down about.
class FTelemetryClient {
  FTelemetryClient({required this.config, http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final FTelemetryConfig config;
  final http.Client _http;
  final bool _ownsClient;

  Future<FTelemetryDelivery> send(List<FTelemetryEvent> batch) async {
    if (batch.isEmpty) return const FTelemetryDelivery(FTelemetryDeliveryStatus.delivered);

    final token = await (config.tokenProvider?.call() ?? Future.value(config.authToken));

    try {
      final response = await _http
          .post(
            config.endpoint,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
              ...config.headers,
            },
            body: jsonEncode({
              'events': batch.map((event) => event.toJson()).toList(),
            }),
          )
          .timeout(config.requestTimeout);

      return _classify(response);
    } on Object catch (error) {
      // Anything that stopped the request from completing — DNS, timeout, socket, TLS — is worth
      // another go later. The device being offline is the normal case, not an exception.
      _log('delivery failed, will retry: $error');
      return const FTelemetryDelivery(FTelemetryDeliveryStatus.retry);
    }
  }

  FTelemetryDelivery _classify(http.Response response) {
    final code = response.statusCode;

    if (code >= 200 && code < 300) {
      _log('delivered ($code)');
      return FTelemetryDelivery(FTelemetryDeliveryStatus.delivered, statusCode: code);
    }

    if (code == 429 || code == 408) {
      final retryAfter = _retryAfter(response.headers['retry-after']);
      _log('throttled ($code), retry after $retryAfter');
      return FTelemetryDelivery(
        FTelemetryDeliveryStatus.retry,
        retryAfter: retryAfter,
        statusCode: code,
      );
    }

    if (code == 401 || code == 403) {
      // Credentials, not content. The token provider is asked again on the next attempt, so
      // this is worth retrying — dropping the batch would discard everything collected while a
      // token happened to be expired, which on a cold start is the whole session.
      _log('unauthorised ($code), will retry with a fresh token');
      return FTelemetryDelivery(FTelemetryDeliveryStatus.retry, statusCode: code);
    }

    if (code >= 400 && code < 500) {
      // The request itself is wrong — a schema mismatch, a route that no longer exists.
      // Repeating it verbatim cannot help.
      _log('rejected ($code), dropping batch');
      return FTelemetryDelivery(FTelemetryDeliveryStatus.dropped, statusCode: code);
    }

    _log('server error ($code), will retry');
    return FTelemetryDelivery(FTelemetryDeliveryStatus.retry, statusCode: code);
  }

  /// `Retry-After` is either a number of seconds or an HTTP date; both are in the wild.
  static Duration? _retryAfter(String? header) {
    if (header == null || header.isEmpty) return null;

    final seconds = int.tryParse(header.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 86400));

    try {
      final until = HttpDate.parse(header);
      final delay = until.difference(DateTime.now());
      return delay.isNegative ? Duration.zero : delay;
    } on Exception {
      return null;
    }
  }

  void _log(String message) {
    if (config.verbose) debugPrint('[fplayer_telemetry] $message');
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
