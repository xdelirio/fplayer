import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer_telemetry/fplayer_telemetry.dart';

FTelemetryEvent event(String id, {FTelemetryEventKind kind = FTelemetryEventKind.progress}) =>
    FTelemetryEvent(
      sessionId: id,
      kind: kind,
      occurredAt: DateTime.utc(2026, 1, 1, 12),
      position: const Duration(seconds: 30),
      duration: const Duration(minutes: 20),
      watchedDelta: const Duration(seconds: 30),
    );

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('fplayer_telemetry_test');
    file = File('${directory.path}/queue.jsonl');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('appends events and writes them as one JSON object per line', () async {
    final queue = FTelemetryQueue(file: file);
    await queue.load();

    queue
      ..add(event('a'))
      ..add(event('b'));
    await queue.flushToDisk();

    expect(queue.length, 2);
    final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
    expect(lines, hasLength(2));
    expect(lines.first, contains('"sessionId":"a"'));
  });

  test('survives a restart', () async {
    final first = FTelemetryQueue(file: file);
    await first.load();
    first
      ..add(event('a'))
      ..add(event('b'));
    await first.flushToDisk();

    final second = FTelemetryQueue(file: file);
    await second.load();

    expect(second.length, 2);
    expect(second.events.map((e) => e.sessionId), ['a', 'b']);
    expect(second.events.first.watchedDelta, const Duration(seconds: 30));
  });

  test('drops the oldest events past the cap', () async {
    final queue = FTelemetryQueue(file: file, maxEntries: 3);
    await queue.load();

    for (var i = 0; i < 6; i++) {
      queue.add(event('s$i'));
    }
    await queue.flushToDisk();

    expect(queue.length, 3);
    expect(queue.events.map((e) => e.sessionId), ['s3', 's4', 's5']);

    final reloaded = FTelemetryQueue(file: file, maxEntries: 3);
    await reloaded.load();
    expect(reloaded.events.map((e) => e.sessionId), ['s3', 's4', 's5']);
  });

  test('trims an oversized file left by a previous, larger cap', () async {
    final generous = FTelemetryQueue(file: file, maxEntries: 100);
    await generous.load();
    for (var i = 0; i < 10; i++) {
      generous.add(event('s$i'));
    }
    await generous.flushToDisk();

    final tightened = FTelemetryQueue(file: file, maxEntries: 4);
    await tightened.load();
    await tightened.flushToDisk();

    expect(tightened.length, 4);
    expect(tightened.events.first.sessionId, 's6');
    expect(file.readAsLinesSync().where((l) => l.trim().isNotEmpty), hasLength(4));
  });

  test('removing a delivered batch leaves the rest', () async {
    final queue = FTelemetryQueue(file: file);
    await queue.load();
    for (var i = 0; i < 5; i++) {
      queue.add(event('s$i'));
    }

    expect(queue.peek(2).map((e) => e.sessionId), ['s0', 's1']);
    queue.removeThrough(queue.cursorAfter(2));
    await queue.flushToDisk();

    expect(queue.events.map((e) => e.sessionId), ['s2', 's3', 's4']);

    final reloaded = FTelemetryQueue(file: file);
    await reloaded.load();
    expect(reloaded.events.map((e) => e.sessionId), ['s2', 's3', 's4']);
  });

  test('a batch on the wire is not shifted by eviction behind it', () async {
    // The recovery path this queue exists for: offline for a while, queue at its cap, a slow
    // POST in flight while new events keep arriving and evicting the oldest.
    final queue = FTelemetryQueue(file: file, maxEntries: 5);
    await queue.load();
    for (var i = 0; i < 5; i++) {
      queue.add(event('s$i'));
    }

    final batch = queue.peek(2);
    final cursor = queue.cursorAfter(batch.length);

    // Two more arrive while the batch is being delivered, pushing s0 and s1 out.
    queue.add(event('s5'));
    queue.add(event('s6'));

    // Delivery succeeds. The two it delivered are already gone; nothing else may be dropped.
    queue.removeThrough(cursor);

    expect(queue.events.map((e) => e.sessionId), ['s2', 's3', 's4', 's5', 's6']);
  });

  test('skips a corrupt line instead of losing the file', () async {
    file.createSync(recursive: true);
    file.writeAsStringSync(
      '${'{"sessionId":"a","kind":"progress","occurredAt":"2026-01-01T12:00:00.000Z",'
          '"positionMs":0}'}\n'
      'not json at all\n'
      '{"sessionId":"b","kind":"end","occurredAt":"2026-01-01T12:00:00.000Z","positionMs":0}\n',
    );

    final queue = FTelemetryQueue(file: file);
    await queue.load();

    expect(queue.events.map((e) => e.sessionId), ['a', 'b']);
    expect(queue.events.last.kind, FTelemetryEventKind.end);
  });

  test('clearing empties both memory and disk', () async {
    final queue = FTelemetryQueue(file: file);
    await queue.load();
    queue.add(event('a'));
    await queue.clear();

    expect(queue.isEmpty, isTrue);
    expect(file.readAsStringSync().trim(), isEmpty);
  });

  test('metadata that is not JSON-safe is stringified rather than thrown away', () {
    final sanitized = sanitizeMetadata({
      'contentId': 42,
      'tags': ['a', 'b'],
      'when': DateTime.utc(2026),
    });

    expect(sanitized!['contentId'], 42);
    expect(sanitized['tags'], ['a', 'b']);
    expect(sanitized['when'], isA<String>());
  });
}
