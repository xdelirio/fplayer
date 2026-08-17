import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import '../ui/fake_engine.dart';

/// What happens when the platform says no — the paths that decide whether a viewer sees an error
/// they can act on or a spinner that never resolves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const source = FPlayerSource.network('https://example.com/a.m3u8');

  /// A controller with a real, short retry ladder rather than a disarmed one: the defects these
  /// cover only appear once the ladder actually runs.
  FPlayerController controllerWith(FPlaybackEngine engine) => FPlayerController(
        config: const FPlayerConfig(
          network: FNetworkConfig(
            loadingTimeout: Duration(milliseconds: 50),
            retry: FRetryPolicy(
              maxAttempts: 2,
              baseDelay: Duration(milliseconds: 10),
              maxDelay: Duration(milliseconds: 20),
            ),
          ),
        ),
        engine: engine,
      );

  test('a player that cannot be created ends up as an error, not a spinner', () async {
    final engine = _FailingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    // Long enough for the whole ladder: every attempt has to re-attempt the *creation*, since
    // re-preparing a player that does not exist can never succeed.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(controller.status, FPlayerStatus.error);
    expect(controller.value.error, isNotNull);
    // The source is on the value throughout, so the error screen has a title and Try again has
    // something to act on.
    expect(controller.value.source, source);
    expect(engine.creates, greaterThan(1), reason: 'the ladder re-attempted the creation');
  });

  test('Try again after a failed creation builds the player again', () async {
    final engine = _FailingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.status, FPlayerStatus.error);

    engine.failCreate = false;
    await controller.retry();

    expect(controller.isEngineReady, isTrue);
    expect(engine.calls, contains('setSource'));
  });

  test('an engine that refuses synchronously can still be retried', () async {
    // The guard that shares one in-flight creation must not pin itself when `create` throws
    // before its first suspension, or every later call is a silent no-op.
    final engine = _SynchronousThrowEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(engine.creates, 1);

    engine.shouldThrow = false;
    await controller.initialize();

    expect(engine.creates, 2);
    expect(controller.isEngineReady, isTrue);
  });

  test('a seek the platform refuses becomes an error rather than a crash', () async {
    final engine = _RefusingSeekEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    engine.becomeReady();
    await Future<void>.delayed(Duration.zero);

    // The UI fires seeks and walks away, so this must not escape into the zone. Awaiting it
    // here is the assertion: an uncaught PlatformException would fail the test.
    await controller.seekTo(const Duration(seconds: 30));

    // And it was handled as a playback failure — the retryable branch holds a spinner and tries
    // again rather than showing an error the viewer cannot act on.
    expect(controller.status, FPlayerStatus.loading);
  });

  test('fresher track metadata is never discarded', () async {
    final engine = FakeEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    engine.becomeReady();
    await Future<void>.delayed(Duration.zero);

    engine.emit(FEngineTracksChanged(_tracksLabelled('Auto')));
    await Future<void>.delayed(Duration.zero);
    expect(controller.tracks.video.single.label, 'Auto');

    // Same id, same selection, better label — a manifest refresh. Compared on identity alone it
    // looked like nothing had changed, and the value was thrown away.
    engine.emit(FEngineTracksChanged(_tracksLabelled('1080p HDR')));
    await Future<void>.delayed(Duration.zero);

    expect(controller.tracks.video.single.label, '1080p HDR');
  });
}

FTracks _tracksLabelled(String label) => FTracks(
      video: [
        FVideoTrack(
          id: 'video:0:0',
          index: 0,
          label: label,
          language: null,
          width: 1920,
          height: 1080,
          isSelected: false,
          isActive: true,
          isSupported: true,
          isDefault: false,
        ),
      ],
    );

/// Fails every creation until told otherwise.
class _FailingEngine extends FakeEngine {
  bool failCreate = true;
  int creates = 0;

  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) async {
    creates++;
    calls.add('create');
    if (failCreate) {
      throw PlatformException(code: 'create_failed', message: 'no player');
    }
  }
}

/// Throws before its first suspension, the way a state check does.
class _SynchronousThrowEngine extends FakeEngine {
  bool shouldThrow = true;
  int creates = 0;

  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) {
    creates++;
    calls.add('create');
    if (shouldThrow) throw StateError('already created');
    return Future<void>.value();
  }
}

class _RefusingSeekEngine extends FakeEngine {
  @override
  Future<void> seekTo(Duration position) async {
    throw PlatformException(code: 'seek_failed', message: 'the player is detaching');
  }
}
