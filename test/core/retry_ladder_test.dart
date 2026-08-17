import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import '../ui/fake_engine.dart';

/// The retry ladder, which decides whether a viewer sees a spinner that resolves or one that
/// never does — and what analytics is told while it runs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const a = FPlayerSource.network('https://example.com/a.m3u8');
  const b = FPlayerSource.network('https://example.com/b.m3u8');

  FPlayerController controllerWith(FPlaybackEngine engine) => FPlayerController(
        config: const FPlayerConfig(
          network: FNetworkConfig(
            loadingTimeout: Duration(milliseconds: 40),
            retry: FRetryPolicy(
              maxAttempts: 2,
              baseDelay: Duration(milliseconds: 10),
              maxDelay: Duration(milliseconds: 20),
            ),
          ),
        ),
        engine: engine,
      );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 300));

  test('a spent ladder does not follow the viewer to the next source', () async {
    final engine = _FailingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(a);
    await settle();
    expect(controller.status, FPlayerStatus.error);

    // A different URL is a different attempt at a different thing. Its budget is its own.
    engine.creates = 0;
    await controller.open(b);
    await settle();

    expect(engine.creates, greaterThan(1), reason: 'the second source got no ladder at all');
  });

  test('Try again after an exhausted ladder tries again more than once', () async {
    final engine = _FailingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    await controller.open(a);
    await settle();

    engine.creates = 0;
    await controller.retry();
    await settle();

    expect(engine.creates, greaterThan(1));
  });

  test('one play is one session, however many attempts it takes', () async {
    final engine = _FailingEngine();
    final controller = controllerWith(engine);
    addTearDown(controller.dispose);

    final opened = <FPlayerSource>[];
    final sub = controller.events
        .where((e) => e is FSourceOpened)
        .cast<FSourceOpened>()
        .listen((e) => opened.add(e.source));
    addTearDown(sub.cancel);

    await controller.open(a);
    await settle();

    // Every FSourceOpened starts a fresh analytics session, so a ladder that announced each of
    // its own attempts reported one play as several — each with the counters zeroed.
    expect(opened, [a]);
  });
}

/// Never manages to build a player.
class _FailingEngine extends FakeEngine {
  int creates = 0;

  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) async {
    creates++;
    throw PlatformException(code: 'create_failed', message: 'no player');
  }
}
