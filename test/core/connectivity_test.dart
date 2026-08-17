import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import '../ui/fake_engine.dart';

/// Losing the network must not look like a broken video.
///
/// A tunnel and a dead CDN both surface as I/O failures, but only one of them is worth waiting
/// out — spending the retry budget against a network that is not there leaves nothing for the
/// moment the signal returns.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEngine engine;
  late FPlayerController controller;

  const source = FPlayerSource.network('https://example.com/a.m3u8');
  const retryable = FPlayerError(
    code: FPlayerErrorCode.network,
    message: 'offline',
    isRetryable: true,
  );

  setUp(() {
    engine = FakeEngine();
    controller = FPlayerController(
      config: const FPlayerConfig(
        network: FNetworkConfig(
          loadingTimeout: Duration(seconds: 5),
          retry: FRetryPolicy(maxAttempts: 3, baseDelay: Duration(seconds: 1)),
        ),
      ),
      engine: engine,
    );
  });

  tearDown(() => controller.dispose());

  test('starts optimistic rather than claiming to be offline', () {
    expect(controller.value.isOnline, isTrue);
    expect(controller.value.isOffline, isFalse);
    expect(controller.value.isWaitingForNetwork, isFalse);
  });

  test('a failure while offline holds instead of consuming the retry budget', () async {
    await controller.open(source);
    engine.becomeReady();

    engine.emit(const FEngineConnectivityChanged(isOnline: false, isWaitingForNetwork: true));
    await Future<void>.delayed(Duration.zero);

    engine.emit(const FEngineFailed(retryable));
    await Future<void>.delayed(Duration.zero);

    // No error surfaced, and no retry scheduled against a network that is not there.
    expect(controller.hasError, isFalse);
    expect(controller.status, FPlayerStatus.loading);
    expect(engine.calls, isNot(contains('retry')));
  });

  test('the same failure while online does surface a retry', () async {
    await controller.open(source);
    engine.becomeReady();

    engine.emit(const FEngineFailed(retryable));
    await Future<void>.delayed(Duration.zero);

    // Held in `loading` while the backoff runs, rather than flashing an error overlay that
    // disappears a second later.
    expect(controller.status, FPlayerStatus.loading);
    expect(controller.hasError, isFalse);
  });

  test('connectivity changes are announced once per transition', () async {
    final events = <FPlayerEvent>[];
    final subscription = controller.events.listen(events.add);
    await controller.open(source);

    engine.emit(const FEngineConnectivityChanged(isOnline: false, isWaitingForNetwork: true));
    engine.emit(const FEngineConnectivityChanged(isOnline: false, isWaitingForNetwork: true));
    engine.emit(const FEngineConnectivityChanged(isOnline: true, isWaitingForNetwork: false));
    await Future<void>.delayed(Duration.zero);

    final changes = events.whereType<FConnectivityChanged>().toList();
    expect(changes.map((e) => e.isOnline), [false, true]);

    await subscription.cancel();
  });

  test('state survives a source swap', () async {
    await controller.open(source);
    engine.emit(const FEngineConnectivityChanged(isOnline: false, isWaitingForNetwork: true));
    await Future<void>.delayed(Duration.zero);

    await controller.open(const FPlayerSource.network('https://example.com/b.m3u8'));

    // Being in a tunnel is a fact about the device, not about the media being swapped.
    expect(controller.value.isOffline, isTrue);
  });
}
