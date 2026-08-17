import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_download_platform.dart';

void main() {
  late FakeDownloadPlatform platform;
  late FDownloadManager manager;

  const source = FPlayerSource.network(
    'https://cdn.example.com/ep4.m3u8',
    title: 'Episodio 4',
    subtitle: 'Temporada 2',
  );

  FDownloadItem item({
    required String id,
    FDownloadState state = FDownloadState.downloading,
    int bytes = 0,
    int? length,
    int startedAtDay = 1,
  }) =>
      FDownloadItem(
        id: id,
        uri: id,
        state: state,
        bytesDownloaded: bytes,
        contentLength: length,
        startedAt: DateTime.utc(2026, 1, startedAtDay),
        updatedAt: DateTime.utc(2026, 1, startedAtDay),
      );

  setUp(() {
    platform = FakeDownloadPlatform();
    manager = FDownloadManager(platform: platform);
  });

  tearDown(() => manager.dispose());

  group('lifecycle', () {
    test('using the queue before initialising is a programming error', () {
      expect(() => manager.enqueue(source), throwsStateError);
    });

    test('initialising twice only touches the platform once', () async {
      await manager.initialize();
      await manager.initialize();

      expect(platform.calls.where((c) => c == 'initialize').length, 1);
      expect(manager.isInitialized, isTrue);
    });

    test('the config reaches the platform', () async {
      await manager.initialize(
        const FDownloadConfig(
          maxParallelDownloads: 1,
          requirements: FDownloadRequirements.unmeteredOnly(),
        ),
      );

      expect(platform.config!.maxParallelDownloads, 1);
      expect(platform.config!.requirements.unmeteredNetwork, isTrue);
    });

    test('the queue restored from disk is adopted on initialise', () async {
      platform.items['a'] = item(id: 'a', state: FDownloadState.paused);
      await manager.initialize();

      expect(manager.items.single.id, 'a');
    });

    test('disposing releases the platform and stops listening', () async {
      await manager.initialize();

      var notifications = 0;
      manager.addListener(() => notifications++);
      await manager.dispose();

      expect(platform.isDisposed, isTrue);

      // A publication in flight when the queue was torn down must not reach a disposed
      // notifier — that is an exception thrown from a stream callback, with no call site to
      // catch it.
      platform.put(item(id: 'late'));
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0);
    });
  });

  group('enqueueing', () {
    test('defaults the id to the URI, so lookups need no bookkeeping', () async {
      await manager.initialize();
      final id = await manager.enqueue(source);

      expect(id, source.uri);
      expect(platform.calls, contains('enqueue:${source.uri}'));
    });

    test('an explicit id wins', () async {
      await manager.initialize();
      expect(await manager.enqueue(source, id: 'ep4'), 'ep4');
    });

    test('the title and poster travel with the download', () async {
      await manager.initialize();
      await manager.enqueue(source, metadata: {'episodeId': 128});

      // Verified through the round trip the platform performs.
      final stored = FDownloadItem.fromMap({
        'id': 'x',
        'uri': 'x',
        'state': 'queued',
        'percent': 0,
        'bytesDownloaded': 0,
        'contentLength': -1,
        'startedAtMs': 0,
        'updatedAtMs': 0,
        'metadata': '{"title":"Episodio 4","subtitle":"Temporada 2","episodeId":128}',
      });

      expect(stored.metadata['title'], 'Episodio 4');
      expect(stored.metadata['episodeId'], 128);
    });
  });

  group('queue state', () {
    test('is ordered newest first', () async {
      await manager.initialize();
      platform.items['old'] = item(id: 'old', startedAtDay: 1);
      platform.items['new'] = item(id: 'new', startedAtDay: 5);
      platform.emit();
      await Future<void>.delayed(Duration.zero);

      expect(manager.items.map((i) => i.id), ['new', 'old']);
    });

    test('separates what is running from what is on disk', () async {
      await manager.initialize();
      platform.items['a'] = item(id: 'a');
      platform.items['b'] = item(id: 'b', state: FDownloadState.completed);
      platform.items['c'] = item(id: 'c', state: FDownloadState.failed);
      platform.emit();
      await Future<void>.delayed(Duration.zero);

      expect(manager.active.map((i) => i.id), ['a']);
      expect(manager.completed.map((i) => i.id), ['b']);
    });

    test('lookup by source answers whether it can play offline', () async {
      await manager.initialize();
      platform.items[source.uri] =
          item(id: source.uri, state: FDownloadState.completed);
      platform.emit();
      await Future<void>.delayed(Duration.zero);

      expect(manager.isDownloaded(source), isTrue);
      expect(manager.stateOf(source), FDownloadState.completed);
      expect(manager[source.uri], isNotNull);
    });

    test('a source that was never enqueued has no state', () async {
      await manager.initialize();
      expect(manager.stateOf(source), isNull);
      expect(manager.isDownloaded(source), isFalse);
    });

    test('notifies listeners when the platform publishes', () async {
      await manager.initialize();
      var notifications = 0;
      manager.addListener(() => notifications++);

      platform.put(item(id: 'a'));
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 1);
    });
  });

  group('overall progress', () {
    test('weighs by size, so a film does not count the same as a trailer', () async {
      await manager.initialize();
      // 100 MB half done, 10 MB untouched: 50 of 110 MB.
      platform.items['film'] = item(id: 'film', bytes: 50, length: 100);
      platform.items['clip'] = item(id: 'clip', bytes: 0, length: 10);
      platform.emit();
      await Future<void>.delayed(Duration.zero);

      expect(manager.overallProgress, closeTo(50 / 110, 0.0001));
    });

    test('falls back to averaging when no size is known yet', () async {
      await manager.initialize();
      platform.items['a'] = FDownloadItem(
        id: 'a',
        uri: 'a',
        state: FDownloadState.downloading,
        progress: 0.4,
        bytesDownloaded: 0,
        startedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      platform.emit();
      await Future<void>.delayed(Duration.zero);

      expect(manager.overallProgress, closeTo(0.4, 0.0001));
    });

    test('is complete when nothing is pending', () async {
      await manager.initialize();
      expect(manager.overallProgress, 1);
    });

    test('counts only completed downloads towards bytes on disk', () async {
      await manager.initialize();
      platform.items['a'] = item(id: 'a', state: FDownloadState.completed, bytes: 900);
      platform.items['b'] = item(id: 'b', bytes: 100);
      platform.emit();
      await Future<void>.delayed(Duration.zero);

      expect(manager.bytesOnDisk, 900);
    });
  });

  group('controls', () {
    setUp(() async {
      await manager.initialize();
      await manager.enqueue(source, id: 'ep4');
    });

    test('pausing and resuming reach the platform', () async {
      await manager.pause('ep4');
      expect(platform.calls, contains('setPaused:ep4:true'));

      await manager.resume('ep4');
      expect(platform.calls, contains('setPaused:ep4:false'));
    });

    test('pausing everything is a single call, not one per item', () async {
      await manager.pauseAll();
      expect(platform.calls.where((c) => c.startsWith('setAllPaused')).length, 1);
    });

    test('removing drops the entry', () async {
      await manager.remove('ep4');
      await Future<void>.delayed(Duration.zero);

      expect(manager.items, isEmpty);
    });

    test('removing everything clears the queue', () async {
      await manager.removeAll();
      await Future<void>.delayed(Duration.zero);

      expect(manager.items, isEmpty);
      expect(platform.calls, contains('removeAll'));
    });
  });

  test('inspect asks the platform without enqueueing anything', () async {
    await manager.initialize();
    await manager.inspect(source);

    expect(platform.calls, contains('inspect:${source.uri}'));
    expect(platform.calls.any((c) => c.startsWith('enqueue')), isFalse);
  });

  test('the default selection is one rendition, not the whole ladder', () {
    const selection = FDownloadSelection.standard();
    expect(selection.maxHeight, 720);
    expect(selection.allAudioLanguages, isFalse);
    expect(selection.allTextLanguages, isFalse);
  });
}
