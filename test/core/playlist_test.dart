import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import '../ui/fake_engine.dart';

void main() {
  // The controller observes the app lifecycle, so it needs a binding even in a plain test.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEngine engine;
  late FPlayerController controller;

  const queue = [
    FPlayerSource.network('https://example.com/1.mp4', title: 'Uno'),
    FPlayerSource.network('https://example.com/2.mp4', title: 'Dos'),
    FPlayerSource.network('https://example.com/3.mp4', title: 'Tres'),
  ];

  FPlayerController build({FPlaybackConfig playback = const FPlaybackConfig()}) {
    engine = FakeEngine();
    return FPlayerController(
      config: FPlayerConfig(
        playback: playback,
        network: const FNetworkConfig(
          loadingTimeout: Duration.zero,
          retry: FRetryPolicy.none(),
        ),
      ),
      engine: engine,
    );
  }

  setUp(() {
    controller = build();
  });

  tearDown(() => controller.dispose());

  test('setPlaylist opens the item at the start index', () async {
    await controller.setPlaylist(queue, startIndex: 1);

    expect(controller.value.currentIndex, 1);
    expect(controller.value.source?.title, 'Dos');
    expect(controller.value.playlist, hasLength(3));
    expect(controller.value.hasNext, isTrue);
    expect(controller.value.hasPrevious, isTrue);
  });

  test('an out-of-range start index is clamped rather than throwing', () async {
    await controller.setPlaylist(queue, startIndex: 99);

    expect(controller.value.currentIndex, 2);
    expect(controller.value.hasNext, isFalse);
  });

  test('an empty queue stops instead of loading nothing', () async {
    await controller.setPlaylist(queue);
    await controller.setPlaylist(const []);

    expect(controller.status, FPlayerStatus.idle);
    expect(controller.value.playlist, isEmpty);
  });

  test('next and jumpTo move through the queue', () async {
    await controller.setPlaylist(queue);

    await controller.next();
    expect(controller.value.source?.title, 'Dos');

    await controller.jumpTo(2);
    expect(controller.value.source?.title, 'Tres');

    // At the end, with repeat off, next does nothing.
    await controller.next();
    expect(controller.value.currentIndex, 2);
  });

  test('jumping outside the queue is ignored', () async {
    await controller.setPlaylist(queue);
    await controller.jumpTo(9);

    expect(controller.value.currentIndex, 0);
  });

  test('previous restarts the item once past the first seconds', () async {
    await controller.setPlaylist(queue, startIndex: 1);
    engine.becomeReady();
    await controller.seekTo(const Duration(seconds: 30));

    await controller.previous();

    // Still on the same item, back at the start — what a "previous" control does everywhere.
    expect(controller.value.currentIndex, 1);
    expect(controller.position, Duration.zero);
  });

  test('previous steps back when barely into the item', () async {
    await controller.setPlaylist(queue, startIndex: 1);
    engine.becomeReady();
    await controller.seekTo(const Duration(seconds: 1));

    await controller.previous();

    expect(controller.value.source?.title, 'Uno');
  });

  test('reaching the end advances to the next item', () async {
    await controller.setPlaylist(queue);
    engine.becomeReady();

    engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.source?.title, 'Dos');
  });

  test('autoAdvance off leaves the player at the end', () async {
    await controller.dispose();
    controller = build(playback: const FPlaybackConfig(autoAdvance: false));
    await controller.setPlaylist(queue);
    engine.becomeReady();

    engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.source?.title, 'Uno');
    expect(controller.isCompleted, isTrue);
  });

  test('repeatPlaylist wraps around after the last item', () async {
    await controller.dispose();
    controller = build(playback: const FPlaybackConfig(repeatPlaylist: true));
    await controller.setPlaylist(queue, startIndex: 2);
    engine.becomeReady();

    engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.currentIndex, 0);
  });

  test('opening a single source clears the queue', () async {
    await controller.setPlaylist(queue);
    await controller.open(const FPlayerSource.network('https://example.com/solo.mp4'));

    expect(controller.value.playlist, isEmpty);
    expect(controller.value.currentIndex, -1);
    expect(controller.value.hasNext, isFalse);
  });

  test('the queue change is announced once, not per item', () async {
    final events = <FPlayerEvent>[];
    final subscription = controller.events.listen(events.add);

    await controller.setPlaylist(queue);
    await controller.next();
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<FPlaylistChanged>(), hasLength(1));
    // Each item still announces itself.
    expect(events.whereType<FSourceOpened>(), hasLength(2));

    await subscription.cancel();
  });

  test('nextInPlaylist names what comes after', () async {
    await controller.setPlaylist(queue);

    expect(controller.value.nextInPlaylist?.title, 'Dos');

    await controller.jumpTo(2);
    expect(controller.value.nextInPlaylist, isNull);
  });
}
