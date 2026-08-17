import 'package:flutter/foundation.dart';

/// Where playback telemetry goes and how hard it tries to get there.
@immutable
class FTelemetryConfig {
  const FTelemetryConfig({
    required this.endpoint,
    this.authToken,
    this.tokenProvider,
    this.headers = const {},
    this.appVersion,
    this.deviceType,
    this.progressInterval = const Duration(seconds: 30),
    this.flushInterval = const Duration(seconds: 60),
    this.maxBatchSize = 50,
    this.maxQueuedEvents = 500,
    this.retryBaseDelay = const Duration(seconds: 5),
    this.maxRetryDelay = const Duration(minutes: 5),
    this.requestTimeout = const Duration(seconds: 15),
    this.enabled = true,
    this.verbose = false,
  });

  /// Endpoint that accepts a JSON body of `{"events": [...]}`.
  final Uri endpoint;

  /// Static bearer token. Ignored when [tokenProvider] is set.
  final String? authToken;

  /// Resolves a bearer token per request.
  ///
  /// Preferred over [authToken] for anything that expires: telemetry outlives a session, and a
  /// token captured at construction is often stale by the time a queued batch finally goes out.
  final Future<String?> Function()? tokenProvider;

  /// Extra headers sent with every batch.
  final Map<String, String> headers;

  final String? appVersion;

  /// Free-form device class the backend groups by: `phone`, `tv`, `tablet`.
  final String? deviceType;

  /// How often the tracker should emit a progress heartbeat. Pass it to
  /// `FPlaybackSessionTracker.progressInterval`; it lives here so an app configures reporting in
  /// one place.
  final Duration progressInterval;

  /// How often the queue is drained.
  final Duration flushInterval;

  final int maxBatchSize;

  /// Cap on the queue. Past it the oldest events are dropped.
  ///
  /// Bounded on purpose: a device that is offline for a week must not fill its storage with
  /// analytics nobody will read.
  final int maxQueuedEvents;

  final Duration retryBaseDelay;
  final Duration maxRetryDelay;
  final Duration requestTimeout;

  /// Turns reporting off without removing it from the tree.
  final bool enabled;

  /// Logs queue and delivery activity through `debugPrint`.
  final bool verbose;

  /// Backoff before attempt number [attempt], counting from zero, capped at [maxRetryDelay].
  Duration delayFor(int attempt) {
    final capped = attempt.clamp(0, 16);
    final ms = retryBaseDelay.inMilliseconds * (1 << capped);
    return ms >= maxRetryDelay.inMilliseconds
        ? maxRetryDelay
        : Duration(milliseconds: ms);
  }

  FTelemetryConfig copyWith({
    Uri? endpoint,
    String? authToken,
    Future<String?> Function()? tokenProvider,
    Map<String, String>? headers,
    String? appVersion,
    String? deviceType,
    Duration? progressInterval,
    Duration? flushInterval,
    int? maxBatchSize,
    int? maxQueuedEvents,
    Duration? retryBaseDelay,
    Duration? maxRetryDelay,
    Duration? requestTimeout,
    bool? enabled,
    bool? verbose,
  }) =>
      FTelemetryConfig(
        endpoint: endpoint ?? this.endpoint,
        authToken: authToken ?? this.authToken,
        tokenProvider: tokenProvider ?? this.tokenProvider,
        headers: headers ?? this.headers,
        appVersion: appVersion ?? this.appVersion,
        deviceType: deviceType ?? this.deviceType,
        progressInterval: progressInterval ?? this.progressInterval,
        flushInterval: flushInterval ?? this.flushInterval,
        maxBatchSize: maxBatchSize ?? this.maxBatchSize,
        maxQueuedEvents: maxQueuedEvents ?? this.maxQueuedEvents,
        retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
        maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
        requestTimeout: requestTimeout ?? this.requestTimeout,
        enabled: enabled ?? this.enabled,
        verbose: verbose ?? this.verbose,
      );
}
