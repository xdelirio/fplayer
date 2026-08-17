import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer_telemetry/fplayer_telemetry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

FTelemetryConfig configWith({
  String? authToken,
  Future<String?> Function()? tokenProvider,
}) =>
    FTelemetryConfig(
      endpoint: Uri.parse('https://api.example.com/telemetry'),
      authToken: authToken,
      tokenProvider: tokenProvider,
      retryBaseDelay: const Duration(milliseconds: 5),
    );

final batch = [
  FTelemetryEvent(
    sessionId: 'a',
    kind: FTelemetryEventKind.progress,
    occurredAt: DateTime.utc(2026),
    position: const Duration(seconds: 10),
  ),
];

void main() {
  test('a 2xx is delivered', () async {
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient((_) async => http.Response('', 204)),
    );

    final result = await client.send(batch);

    expect(result.status, FTelemetryDeliveryStatus.delivered);
    expect(result.statusCode, 204);
  });

  test('sends the events as a JSON envelope with a bearer token', () async {
    late http.Request captured;
    final client = FTelemetryClient(
      config: configWith(authToken: 'secret'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      }),
    );

    await client.send(batch);

    expect(captured.headers['Authorization'], 'Bearer secret');
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    final events = body['events']! as List<Object?>;
    expect(events, hasLength(1));
    expect((events.first! as Map)['sessionId'], 'a');
  });

  test('resolves a fresh token per request', () async {
    var calls = 0;
    late http.Request captured;
    final client = FTelemetryClient(
      config: configWith(tokenProvider: () async => 'token-${++calls}'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      }),
    );

    await client.send(batch);
    await client.send(batch);

    expect(captured.headers['Authorization'], 'Bearer token-2');
  });

  test('a 429 is retried, honouring Retry-After in seconds', () async {
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': '17'}),
      ),
    );

    final result = await client.send(batch);

    expect(result.status, FTelemetryDeliveryStatus.retry);
    expect(result.retryAfter, const Duration(seconds: 17));
  });

  test('a 429 with an HTTP-date Retry-After is understood too', () async {
    final until = DateTime.now().toUtc().add(const Duration(seconds: 40));
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': HttpDate.format(until)}),
      ),
    );

    final result = await client.send(batch);

    expect(result.status, FTelemetryDeliveryStatus.retry);
    expect(result.retryAfter!.inSeconds, closeTo(40, 2));
  });

  test('a 422 is dropped, because repeating it cannot help', () async {
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient((_) async => http.Response('bad schema', 422)),
    );

    expect((await client.send(batch)).status, FTelemetryDeliveryStatus.dropped);
  });

  test('a 401 and a 404 are dropped as well', () async {
    for (final code in [401, 404]) {
      final client = FTelemetryClient(
        config: configWith(),
        httpClient: MockClient((_) async => http.Response('', code)),
      );
      expect(
        (await client.send(batch)).status,
        FTelemetryDeliveryStatus.dropped,
        reason: 'status $code',
      );
    }
  });

  test('a 5xx is retried', () async {
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient((_) async => http.Response('', 503)),
    );

    expect((await client.send(batch)).status, FTelemetryDeliveryStatus.retry);
  });

  test('a network failure is retried rather than surfaced', () async {
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient((_) async => throw http.ClientException('offline')),
    );

    expect((await client.send(batch)).status, FTelemetryDeliveryStatus.retry);
  });

  test('an empty batch is a no-op', () async {
    final client = FTelemetryClient(
      config: configWith(),
      httpClient: MockClient((_) async => throw StateError('must not be called')),
    );

    expect((await client.send([])).status, FTelemetryDeliveryStatus.delivered);
  });

  test('backoff grows and then flattens at the cap', () {
    final config = FTelemetryConfig(
      endpoint: Uri.parse('https://api.example.com/telemetry'),
      retryBaseDelay: const Duration(seconds: 2),
      maxRetryDelay: const Duration(seconds: 30),
    );

    expect(config.delayFor(0), const Duration(seconds: 2));
    expect(config.delayFor(1), const Duration(seconds: 4));
    expect(config.delayFor(2), const Duration(seconds: 8));
    expect(config.delayFor(10), const Duration(seconds: 30));
  });
}
