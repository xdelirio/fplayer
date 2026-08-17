import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';
import 'package:fplayer_telemetry/fplayer_telemetry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

FPlaybackMetrics metrics({
  String sessionId = 'session-1',
  Duration watched = Duration.zero,
  int stallCount = 0,
  Duration stallTime = Duration.zero,
  int seekCount = 0,
  Duration position = Duration.zero,
}) =>
    FPlaybackMetrics(
      sessionId: sessionId,
      startedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026).add(watched),
      contentTitle: 'Episode 1',
      sourceMetadata: {'contentId': 42},
      watchedTime: watched,
      rebufferCount: stallCount,
      rebufferTime: stallTime,
      seekCount: seekCount,
      position: position,
      duration: const Duration(minutes: 20),
    );

void main() {
  late Directory directory;
  late File file;

  FTelemetryConfig configWith({int maxBatchSize = 50, int maxQueued = 500}) => FTelemetryConfig(
        endpoint: Uri.parse('https://api.example.com/telemetry'),
        maxBatchSize: maxBatchSize,
        maxQueuedEvents: maxQueued,
        retryBaseDelay: const Duration(milliseconds: 5),
        maxRetryDelay: const Duration(milliseconds: 20),
        flushInterval: const Duration(milliseconds: 20),
      );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('fplayer_reporter_test');
    file = File('${directory.path}/queue.jsonl');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('reports deltas between consecutive observations of a session', () async {
    final sent = <Map<String, Object?>>[];
    final config = configWith();
    final reporter = FTelemetryReporter(
      config: config,
      queue: FTelemetryQueue(file: file, maxEntries: config.maxQueuedEvents),
      client: FTelemetryClient(
        config: config,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          sent.addAll(
            (body['events']! as List<Object?>).cast<Map<String, Object?>>(),
          );
          return http.Response('', 204);
        }),
      ),
    );

    reporter
      ..onSessionStart(metrics())
      ..onProgress(metrics(watched: const Duration(seconds: 30)))
      ..onProgress(metrics(watched: const Duration(seconds: 75), stallCount: 1));

    await reporter.flush();

    expect(sent, hasLength(3));
    expect(sent[1]['watchedDeltaMs'], 30000);
    expect(sent[2]['watchedDeltaMs'], 45000);
    expect(sent[2]['watchedTotalMs'], 75000);
    expect(sent[2]['stallCountDelta'], 1);
    expect(sent.first['metadata'], {'contentId': 42});
    expect(sent.first['contentTitle'], 'Episode 1');

    await reporter.dispose();
  });

  test('keeps the batch queued when delivery fails, and retries it later', () async {
    var attempts = 0;
    final config = configWith();
    final queue = FTelemetryQueue(file: file, maxEntries: config.maxQueuedEvents);
    final reporter = FTelemetryReporter(
      config: config,
      queue: queue,
      client: FTelemetryClient(
        config: config,
        httpClient: MockClient((_) async {
          attempts++;
          return attempts == 1
              ? http.Response('', 503)
              : http.Response('', 204);
        }),
      ),
    );

    reporter.onSessionStart(metrics());
    await reporter.flush();

    expect(attempts, 1);
    expect(queue.length, 1, reason: 'a failed batch must stay queued');

    await reporter.flush();
    expect(attempts, 2);
    expect(queue.length, 0);

    await reporter.dispose();
  });

  test('drops a batch the backend rejects, so the queue can drain', () async {
    final config = configWith();
    final queue = FTelemetryQueue(file: file, maxEntries: config.maxQueuedEvents);
    final reporter = FTelemetryReporter(
      config: config,
      queue: queue,
      client: FTelemetryClient(
        config: config,
        httpClient: MockClient((_) async => http.Response('bad schema', 422)),
      ),
    );

    reporter.onSessionStart(metrics());
    await reporter.flush();

    expect(queue.length, 0);

    await reporter.dispose();
  });

  test('sends in batches no larger than configured', () async {
    final batchSizes = <int>[];
    final config = configWith(maxBatchSize: 2);
    final reporter = FTelemetryReporter(
      config: config,
      queue: FTelemetryQueue(file: file, maxEntries: config.maxQueuedEvents),
      client: FTelemetryClient(
        config: config,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          batchSizes.add((body['events']! as List<Object?>).length);
          return http.Response('', 204);
        }),
      ),
    );

    for (var i = 0; i < 5; i++) {
      reporter.onProgress(metrics(watched: Duration(seconds: i * 10)));
    }
    await reporter.flush();

    expect(batchSizes, [2, 2, 1]);

    await reporter.dispose();
  });

  test('only fatal errors are reported', () async {
    final kinds = <String>[];
    final config = configWith();
    final reporter = FTelemetryReporter(
      config: config,
      queue: FTelemetryQueue(file: file, maxEntries: config.maxQueuedEvents),
      client: FTelemetryClient(
        config: config,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          for (final event in (body['events']! as List<Object?>).cast<Map<String, Object?>>()) {
            kinds.add(event['kind']! as String);
          }
          return http.Response('', 204);
        }),
      ),
    );

    reporter
      ..onError(
        metrics(),
        const FPlayerError(code: FPlayerErrorCode.network, message: 'blip'),
        isFatal: false,
      )
      ..onError(
        metrics(),
        const FPlayerError(
          code: FPlayerErrorCode.notFound,
          message: 'gone',
          httpStatus: 404,
        ),
        isFatal: true,
      );

    await reporter.flush();

    expect(kinds, ['error']);

    await reporter.dispose();
  });

  test('a disabled reporter queues nothing', () async {
    final config = configWith().copyWith(enabled: false);
    final queue = FTelemetryQueue(file: file);
    final reporter = FTelemetryReporter(config: config, queue: queue);

    reporter.onSessionStart(metrics());

    expect(queue.length, 0);
    await reporter.dispose();
  });

  test('what could not be delivered survives to the next run', () async {
    final config = configWith();
    final failing = FTelemetryReporter(
      config: config,
      queue: FTelemetryQueue(file: file, maxEntries: config.maxQueuedEvents),
      client: FTelemetryClient(
        config: config,
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
      ),
    );

    failing.onSessionStart(metrics());
    await failing.flush();
    await failing.dispose();

    final recovered = FTelemetryQueue(file: file);
    await recovered.load();

    expect(recovered.length, 1);
    expect(recovered.events.single.kind, FTelemetryEventKind.start);
  });
}
