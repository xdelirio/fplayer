import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import '../ui/fake_engine.dart';

/// The lifetime of a controller, rather than its behaviour: what happens when disposal lands in
/// the middle of creation, when two callers initialise at once, and when the platform refuses.
///
/// These are the paths that leak rather than fail — nothing on screen goes wrong, and a native
/// player keeps running for the life of the process.
void main() {
  // The controller registers with the binding, so there has to be one.
  TestWidgetsFlutterBinding.ensureInitialized();

  const source = FPlayerSource.network('https://example.com/a.m3u8');

  /// Signals reach the controller through a broadcast stream, so they land a microtask later.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  FPlayerController controllerWith(FPlaybackEngine engine) => FPlayerController(
        config: const FPlayerConfig(
          network: FNetworkConfig(
            loadingTimeout: Duration.zero,
            retry: FRetryPolicy.none(),
          ),
        ),
        engine: engine,
      );

  test('creating once is enough, however many callers ask at the same time', () async {
    final engine = _SlowEngine();
    final controller = controllerWith(engine);

    // The documented pattern from an initState: neither call can be awaited.
    final first = controller.initialize();
    final second = controller.initialize();
    engine.finishCreate();
    await Future.wait([first, second]);

    expect(engine.calls.where((c) => c == 'create').length, 1);

    await controller.dispose();
    // `removeObserver` answers whether it found one. A second registration would still be in the
    // binding's list after disposal removed the first — and would pin the controller, its engine
    // and its whole value graph for the life of the process.
    expect(
      WidgetsBinding.instance.removeObserver(controller),
      isFalse,
      reason: 'the controller registered with the binding more than once',
    );
  });

  test('disposing during creation still releases the player that arrives after', () async {
    final engine = _SlowEngine();
    final controller = controllerWith(engine);

    final opening = controller.open(source);
    // The screen is popped while the platform is still building the player.
    final disposing = controller.dispose();
    engine.finishCreate();
    await Future.wait([opening, disposing]);

    expect(engine.isDisposed, isTrue, reason: 'the engine must be released, not orphaned');
    expect(engine.calls, isNot(contains('setSource')));
  });

  test('a player that cannot be created becomes an error, not a spinner', () async {
    final engine = _FailingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);

    expect(controller.status, FPlayerStatus.error);
    expect(controller.value.error, isNotNull);
    // And the failure did not escape into whatever called `open`.
  });

  test('a source the platform refuses becomes an error, not a spinner', () async {
    final engine = _RefusingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);

    expect(controller.status, FPlayerStatus.error);
    expect(controller.value.error?.message, contains('no'));
  });

  test('disposal finishes even when the engine throws on the way out', () async {
    final engine = _ThrowingOnDisposeEngine();
    final controller = controllerWith(engine);
    await controller.initialize();

    await expectLater(controller.dispose(), throwsA(isA<Exception>()));

    // The notifier and its streams are released regardless: a failing platform call on the way
    // out must not keep the whole object graph alive.
    expect(controller.isEngineReady, isFalse);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });

  test('nothing acts on a disposed controller', () async {
    final engine = FakeEngine();
    final controller = controllerWith(engine);
    await controller.open(source);
    engine.calls.clear();

    await controller.dispose();
    await controller.retry();
    await controller.play();
    await controller.seekTo(const Duration(seconds: 5));

    expect(engine.calls, isEmpty);
    expect(controller.textureId, isNull);
  });

  test('a progress tick from before a seek does not drag the playhead back', () async {
    final engine = FakeEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    engine.becomeReady(duration: const Duration(minutes: 10));
    await settle();
    await controller.seekTo(const Duration(minutes: 5));
    expect(controller.position, const Duration(minutes: 5));

    // The tick the engine had already sent, still carrying the old position.
    engine.emit(
      const FEngineProgress(
        position: Duration(seconds: 2),
        buffered: Duration(seconds: 30),
        bufferedAhead: Duration(seconds: 28),
      ),
    );
    await settle();
    expect(controller.position, const Duration(minutes: 5));
    // The ranges around it are current either way.
    expect(controller.buffered, const Duration(seconds: 30));

    // And once the engine has actually landed, it drives the position again.
    engine.emit(
      const FEngineProgress(
        position: Duration(minutes: 5, seconds: 1),
        buffered: Duration(minutes: 5, seconds: 30),
        bufferedAhead: Duration(seconds: 29),
      ),
    );
    await settle();
    expect(controller.position, const Duration(minutes: 5, seconds: 1));
  });

  test('the playhead is not held hostage by a seek the engine ignored', () async {
    final engine = FakeEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    engine.becomeReady();
    await settle();
    await controller.seekTo(const Duration(minutes: 5));

    for (var i = 0; i < 20; i++) {
      engine.emit(
        FEngineProgress(
          position: Duration(seconds: i),
          buffered: Duration(seconds: i + 10),
          bufferedAhead: const Duration(seconds: 10),
        ),
      );
    }
    await settle();

    // The engine won the argument rather than the readout freezing for the session.
    expect(controller.position.inSeconds, greaterThan(0));
    expect(controller.position, lessThan(const Duration(minutes: 1)));
  });

  test('unmuting restores the level the viewer was listening at, however it got to zero',
      () async {
    final engine = FakeEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(source);
    await controller.setVolume(0.3);
    // Dragged to silence with the volume gesture rather than the mute button.
    await controller.setVolume(0);
    expect(controller.isMuted, isTrue);

    await controller.toggleMute();

    expect(controller.volume, closeTo(0.3, 0.001));
  });
}

/// A create that does not return until the test says so.
class _SlowEngine extends FakeEngine {
  final Completer<void> _create = Completer<void>();

  void finishCreate() => _create.complete();

  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) async {
    calls.add('create');
    await _create.future;
  }
}

class _FailingEngine extends FakeEngine {
  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) async {
    calls.add('create');
    throw Exception('no player for you');
  }
}

class _RefusingEngine extends FakeEngine {
  @override
  Future<void> setSource(FPlayerSource source) async {
    calls.add('setSource');
    throw Exception('no such media');
  }
}

class _ThrowingOnDisposeEngine extends FakeEngine {
  @override
  Future<void> dispose() async {
    isDisposed = true;
    throw Exception('the engine was already detaching');
  }
}
