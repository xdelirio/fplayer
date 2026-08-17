import 'dart:math';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';

/// Records every observation so a test can assert on the sequence, not just the totals.
class RecordingObserver extends FPlayerObserver {
  final List<String> calls = <String>[];
  final List<FPlaybackMetrics> snapshots = <FPlaybackMetrics>[];
  final List<Duration> stalls = <Duration>[];
  final List<(Duration, Duration)> seeks = <(Duration, Duration)>[];
  final List<(FVideoTrack?, FVideoTrack?)> qualityChanges = <(FVideoTrack?, FVideoTrack?)>[];
  final List<bool> errorFatality = <bool>[];
  FSessionEndReason? endReason;

  FPlaybackMetrics get last => snapshots.last;

  void _record(String name, FPlaybackMetrics metrics) {
    calls.add(name);
    snapshots.add(metrics);
  }

  @override
  void onSessionStart(FPlaybackMetrics metrics) => _record('start', metrics);

  @override
  void onFirstFrame(FPlaybackMetrics metrics) => _record('firstFrame', metrics);

  @override
  void onProgress(FPlaybackMetrics metrics) => _record('progress', metrics);

  @override
  void onRebufferStart(FPlaybackMetrics metrics) => _record('rebufferStart', metrics);

  @override
  void onRebufferEnd(FPlaybackMetrics metrics, Duration stallDuration) {
    _record('rebufferEnd', metrics);
    stalls.add(stallDuration);
  }

  @override
  void onQualityChanged(FPlaybackMetrics metrics, {FVideoTrack? from, FVideoTrack? to}) {
    _record('quality', metrics);
    qualityChanges.add((from, to));
  }

  @override
  void onSeek(FPlaybackMetrics metrics, {required Duration from, required Duration to}) {
    _record('seek', metrics);
    seeks.add((from, to));
  }

  @override
  void onError(FPlaybackMetrics metrics, FPlayerError error, {required bool isFatal}) {
    _record('error', metrics);
    errorFatality.add(isFatal);
  }

  @override
  void onSessionEnd(FPlaybackMetrics metrics, FSessionEndReason reason) {
    _record('end', metrics);
    endReason = reason;
  }
}

/// A clock the test moves by hand, so measurements are exact instead of approximately right.
class FakeClock {
  DateTime now = DateTime.utc(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration amount) => now = now.add(amount);
}

FVideoTrack videoTrack(String id, {int? height, int? bitrate, bool isActive = true}) =>
    FVideoTrack(
      id: id,
      index: 0,
      label: null,
      language: null,
      isSelected: true,
      isActive: isActive,
      isSupported: true,
      isDefault: false,
      height: height,
      width: height == null ? null : (height * 16 / 9).round(),
      bitrate: bitrate,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEngine engine;
  late FPlayerController controller;
  late FakeClock clock;
  late RecordingObserver observer;
  late FPlaybackSessionTracker tracker;

  setUp(() {
    engine = FakeEngine();
    controller = FPlayerController(engine: engine);
    clock = FakeClock();
    observer = RecordingObserver();
    tracker = FPlaybackSessionTracker(
      controller: controller,
      observers: [observer],
      clock: clock.call,
      progressInterval: const Duration(seconds: 30),
      random: Random(7),
    );
  });

  tearDown(() {
    tracker.dispose();
    controller.dispose();
  });

  /// Lets stream deliveries land before the test looks at the result.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> openAndStart({Duration total = const Duration(minutes: 10)}) async {
    await controller.open(
      const FPlayerSource.network(
        'https://example.com/a.m3u8',
        title: 'Episode 1',
        metadata: {'contentId': 42},
      ),
    );
    await settle();

    engine.emit(
      FEngineInitialized(
        duration: total,
        size: const Size(1920, 1080),
        rotationDegrees: 0,
        pixelAspectRatio: 1,
        isLive: false,
        isSeekable: true,
      ),
    );
    engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ready));
    engine.emit(const FEnginePlayingChanged(isPlaying: true));
    await settle();
  }

  group('session lifecycle', () {
    test('starts on a source being opened and carries its metadata', () async {
      await controller.open(
        const FPlayerSource.network(
          'https://example.com/a.m3u8',
          title: 'Episode 1',
          metadata: {'contentId': 42},
        ),
      );
      await settle();

      expect(observer.calls, ['start']);
      expect(observer.last.contentTitle, 'Episode 1');
      expect(observer.last.sourceMetadata, {'contentId': 42});
      expect(tracker.hasSession, isTrue);
    });

    test('session ids sort by creation time', () {
      final earlier = FSessionId.generate(at: DateTime.utc(2026), random: Random(1));
      final later = FSessionId.generate(at: DateTime.utc(2027), random: Random(1));

      expect(earlier.length, 26);
      expect(earlier.compareTo(later), lessThan(0));
      expect(FSessionId.timestampOf(earlier), DateTime.utc(2026));
      expect(FSessionId.timestampOf('not-an-id'), isNull);
    });

    test('opening a second source closes the first session', () async {
      await openAndStart();
      await controller.open(const FPlayerSource.network('https://example.com/b.m3u8'));
      await settle();

      expect(observer.endReason, FSessionEndReason.sourceChanged);
      expect(observer.calls.where((c) => c == 'start').length, 2);
    });

    test('completing ends the session', () async {
      await openAndStart();
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
      await settle();

      expect(observer.endReason, FSessionEndReason.completed);
      expect(tracker.hasSession, isFalse);
    });

    test('disposing ends the session', () async {
      await openAndStart();
      tracker.dispose();

      expect(observer.endReason, FSessionEndReason.disposed);
    });
  });

  group('watch time', () {
    test('counts only time spent playing', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 10));
      engine.emit(const FEnginePlayingChanged(isPlaying: false));
      await settle();

      // Paused: this stretch must not count.
      clock.advance(const Duration(seconds: 30));
      engine.emit(const FEnginePlayingChanged(isPlaying: true));
      await settle();

      clock.advance(const Duration(seconds: 5));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
      await settle();

      expect(observer.last.watchedTime, const Duration(seconds: 15));
      expect(observer.last.wallClockTime, const Duration(seconds: 45));
    });

    test('scales with playback speed', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 10));
      engine.emit(const FEngineSpeedChanged(2));
      await settle();

      clock.advance(const Duration(seconds: 10));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
      await settle();

      // Ten seconds at 1x plus ten at 2x is thirty seconds of programme consumed.
      expect(observer.last.watchedTime, const Duration(seconds: 30));
    });
  });

  group('startup and rebuffering', () {
    test('measures time to first frame', () async {
      await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
      await settle();

      clock.advance(const Duration(milliseconds: 1800));
      engine.emit(
        const FEngineInitialized(
          duration: Duration(minutes: 5),
          size: Size(1280, 720),
          rotationDegrees: 0,
          pixelAspectRatio: 1,
          isLive: false,
          isSeekable: true,
        ),
      );
      await settle();

      expect(observer.calls, contains('firstFrame'));
      expect(observer.last.timeToFirstFrame, const Duration(milliseconds: 1800));
    });

    test('waiting before the first frame is startup, not a rebuffer', () async {
      await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
      await settle();

      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
      await settle();

      expect(observer.calls, isNot(contains('rebufferStart')));
      expect(tracker.metrics!.rebufferCount, 0);
    });

    test('counts stalls after playback started and measures them', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 5));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
      await settle();

      clock.advance(const Duration(seconds: 3));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ready));
      await settle();

      expect(observer.calls, containsAllInOrder(['rebufferStart', 'rebufferEnd']));
      expect(observer.stalls.single, const Duration(seconds: 3));
      expect(observer.last.rebufferCount, 1);
      expect(observer.last.rebufferTime, const Duration(seconds: 3));
      // The stall must not be counted as watch time.
      expect(observer.last.watchedTime, const Duration(seconds: 5));
    });

    test('reports the share of the session spent stalled', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 9));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
      await settle();
      clock.advance(const Duration(seconds: 1));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ready));
      await settle();

      expect(observer.last.rebufferRatio, closeTo(0.1, 0.001));
    });
  });

  group('seeks', () {
    test('a seek is reported with where it came from and went to', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 1));
      engine.emit(
        const FEngineProgress(position: Duration(seconds: 1), buffered: Duration(seconds: 30)),
      );
      await settle();

      await controller.seekTo(const Duration(minutes: 4));
      await settle();

      expect(observer.seeks.single.$1, const Duration(seconds: 1));
      expect(observer.seeks.single.$2, const Duration(minutes: 4));
      expect(tracker.metrics!.seekCount, 1);
    });

    test('a seek of a second is still counted', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 10));
      engine.emit(
        const FEngineProgress(position: Duration(seconds: 10), buffered: Duration(minutes: 1)),
      );
      await settle();

      // Short corrections used to be indistinguishable from timing drift; the event makes them
      // exact.
      await controller.seekTo(const Duration(seconds: 11));
      await settle();

      expect(tracker.metrics!.seekCount, 1);
    });

    test('ordinary progress is not mistaken for a seek', () async {
      await openAndStart();

      var position = Duration.zero;
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(milliseconds: 250));
        position += const Duration(milliseconds: 250);
        engine.emit(FEngineProgress(position: position, buffered: const Duration(minutes: 1)));
        await settle();
      }

      expect(tracker.metrics!.seekCount, 0);
    });
  });

  group('quality', () {
    test('weights bitrate and height by time on screen', () async {
      await openAndStart();

      engine.emit(
        FEngineTracksChanged(
          FTracks(video: [videoTrack('a', height: 1080, bitrate: 6000000)]),
        ),
      );
      await settle();

      clock.advance(const Duration(seconds: 90));
      engine.emit(
        FEngineTracksChanged(
          FTracks(video: [videoTrack('b', height: 480, bitrate: 1000000)]),
        ),
      );
      await settle();

      clock.advance(const Duration(seconds: 30));
      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
      await settle();

      // 90 s at 1080p/6 Mbps and 30 s at 480p/1 Mbps.
      expect(observer.last.averageBitrate, closeTo(4750000, 1000));
      expect(observer.last.averageVideoHeight, closeTo(930, 1));
      expect(observer.last.peakVideoHeight, 1080);
      expect(observer.last.qualityChangeCount, 1);
    });

    test('the first rendition is a selection, not a change', () async {
      await openAndStart();

      engine.emit(
        FEngineTracksChanged(FTracks(video: [videoTrack('a', height: 720)])),
      );
      await settle();

      expect(observer.calls, isNot(contains('quality')));
      expect(tracker.metrics!.qualityChangeCount, 0);
    });
  });

  group('progress heartbeat', () {
    test('fires on the interval while playing and stays silent while paused', () async {
      await openAndStart();

      clock.advance(const Duration(seconds: 10));
      engine.emit(
        const FEngineProgress(position: Duration(seconds: 10), buffered: Duration(minutes: 1)),
      );
      await settle();
      expect(observer.calls.where((c) => c == 'progress').length, 1);

      // Too soon for another heartbeat.
      clock.advance(const Duration(seconds: 5));
      engine.emit(
        const FEngineProgress(position: Duration(seconds: 15), buffered: Duration(minutes: 1)),
      );
      await settle();
      expect(observer.calls.where((c) => c == 'progress').length, 1);

      clock.advance(const Duration(seconds: 31));
      engine.emit(
        const FEngineProgress(position: Duration(seconds: 46), buffered: Duration(minutes: 1)),
      );
      await settle();
      expect(observer.calls.where((c) => c == 'progress').length, 2);

      engine.emit(const FEnginePlayingChanged(isPlaying: false));
      await settle();
      clock.advance(const Duration(minutes: 5));
      engine.emit(
        const FEngineProgress(position: Duration(seconds: 46), buffered: Duration(minutes: 1)),
      );
      await settle();
      expect(observer.calls.where((c) => c == 'progress').length, 2);
    });
  });

  group('errors', () {
    test('separates a retry from a failure the viewer sees', () async {
      await openAndStart();

      engine.emit(
        const FEngineFailed(
          FPlayerError(
            code: FPlayerErrorCode.network,
            message: 'connection reset',
            isRetryable: true,
          ),
        ),
      );
      await settle();

      expect(observer.errorFatality, [false]);
      expect(tracker.metrics!.retryCount, 1);
      expect(tracker.metrics!.errorCount, 0);
    });

    test('an unrecovered failure ends the session as an error', () async {
      await openAndStart();

      engine.emit(
        const FEngineFailed(
          FPlayerError(
            code: FPlayerErrorCode.notFound,
            message: 'gone',
          ),
        ),
      );
      await settle();

      expect(observer.errorFatality, [true]);
      expect(tracker.metrics!.errorCount, 1);

      tracker.dispose();
      expect(observer.endReason, FSessionEndReason.error);
    });
  });

  group('composite observer', () {
    test('one failing observer does not stop the others', () {
      final good = RecordingObserver();
      final errors = <Object>[];
      final composite = FCompositeObserver(
        [_ThrowingObserver(), good],
        onObserverError: (observer, error, stackTrace) => errors.add(error),
      );

      composite.onSessionStart(
        FPlaybackMetrics(
          sessionId: 'x',
          startedAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      expect(errors, hasLength(1));
      expect(good.calls, ['start']);
    });
  });
}

class _ThrowingObserver extends FPlayerObserver {
  @override
  void onSessionStart(FPlaybackMetrics metrics) => throw StateError('boom');
}
