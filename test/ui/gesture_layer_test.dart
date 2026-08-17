import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  Future<void> ready(
    WidgetTester tester, {
    FUiConfig config = const FUiConfig(),
  }) async {
    await pumpPlayer(tester, controller: controller, config: config);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();
    // Start from a position with room to move in both directions.
    await controller.seekTo(const Duration(minutes: 5));
    // The chrome sits above the gesture layer and the play button occupies the exact centre, so
    // gestures are exercised in the state they are actually used in: with the controls faded out.
    uiOf(tester).hideControls();
    engine.calls.clear();
    await tester.pump();
  }

  /// Two taps at the same place, close enough in time to read as a double tap.
  Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(position);
    await tester.pump();
  }

  testWidgets('double tap on the left rewinds', (tester) async {
    await ready(tester);
    await doubleTapAt(tester, const Offset(60, 225));

    expect(controller.position, const Duration(minutes: 4, seconds: 50));
    await settlePlayer(tester);
  });

  testWidgets('double tap on the right skips forward', (tester) async {
    await ready(tester);
    await doubleTapAt(tester, const Offset(740, 225));

    expect(controller.position, const Duration(minutes: 5, seconds: 10));
    await settlePlayer(tester);
  });

  testWidgets('taps pile onto the ripple while it is up', (tester) async {
    await ready(tester);
    await doubleTapAt(tester, const Offset(740, 225));

    // Single taps, not double ones: once the ripple is up the side is already known, and nobody
    // double-taps four times to skip forty seconds.
    await tester.tapAt(const Offset(740, 225));
    await tester.pump(kDoubleTapTimeout);

    expect(controller.position, const Duration(minutes: 5, seconds: 20));
    expect(find.text('20 ${const FPlayerLocalizations().seconds}'), findsOneWidget);
    // The controls stay away: that tap was a seek, not a request for chrome.
    expect(uiOf(tester).areControlsVisible, isFalse);

    await settlePlayer(tester);
  });

  testWidgets('the count starts over on the other side', (tester) async {
    await ready(tester);
    await doubleTapAt(tester, const Offset(740, 225));
    await doubleTapAt(tester, const Offset(60, 225));
    // Past the cross-fade, so the ripple leaving the other side is gone.
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.position, const Duration(minutes: 5));
    expect(find.text('10 ${const FPlayerLocalizations().seconds}'), findsOneWidget);
    await settlePlayer(tester);
  });

  testWidgets('a tap once the ripple has faded shows the controls again', (tester) async {
    await ready(tester);
    await doubleTapAt(tester, const Offset(740, 225));
    await tester.pump(const Duration(seconds: 2));

    await tester.tapAt(const Offset(740, 225));
    await tester.pump(kDoubleTapTimeout);

    expect(uiOf(tester).areControlsVisible, isTrue);
    expect(controller.position, const Duration(minutes: 5, seconds: 10));
    await settlePlayer(tester);
  });

  testWidgets('double tap in the middle toggles playback', (tester) async {
    await ready(tester);
    await doubleTapAt(tester, const Offset(400, 225));

    expect(engine.calls, contains('pause'));
    // The middle third is for play/pause, not for seeking.
    expect(controller.position, const Duration(minutes: 5));
    await settlePlayer(tester);
  });

  testWidgets('a single tap toggles the controls', (tester) async {
    await ready(tester);
    expect(uiOf(tester).areControlsVisible, isFalse);

    await tester.tapAt(const Offset(400, 225));
    await tester.pump(kDoubleTapTimeout);
    expect(uiOf(tester).areControlsVisible, isTrue);

    await settlePlayer(tester);
  });

  testWidgets('dragging up on the right raises the volume', (tester) async {
    await ready(tester);
    expect(controller.volume, 1.0);
    await controller.setVolume(0.5);
    engine.calls.clear();

    // Up is louder, and a full-height drag spans the whole range.
    await tester.dragFrom(const Offset(700, 300), const Offset(0, -112));
    await tester.pump();

    expect(controller.volume, greaterThan(0.5));
    expect(engine.calls.any((c) => c.startsWith('setVolume')), isTrue);
    await settlePlayer(tester);
  });

  testWidgets('dragging down on the right lowers the volume', (tester) async {
    await ready(tester);
    await controller.setVolume(0.8);

    await tester.dragFrom(const Offset(700, 150), const Offset(0, 112));
    await tester.pump();

    expect(controller.volume, lessThan(0.8));
    await settlePlayer(tester);
  });

  testWidgets('dragging up on the left raises the brightness', (tester) async {
    await ready(tester);
    engine.windowBrightness = 0.4;

    await tester.dragFrom(const Offset(100, 300), const Offset(0, -112));
    await tester.pump();

    // The window is what dims, not the device setting, so it reverts when the app goes away.
    expect(engine.calls.any((c) => c.startsWith('setBrightness')), isTrue);
    expect(engine.windowBrightness, greaterThan(0.4));
    await settlePlayer(tester);
  });

  testWidgets('the left half is inert when brightness is switched off', (tester) async {
    await ready(
      tester,
      config: const FUiConfig(
        gestures: FGestureConfig(verticalDragAdjustsBrightness: false),
      ),
    );

    await tester.dragFrom(const Offset(100, 300), const Offset(0, -112));
    await tester.pump();

    expect(engine.calls.any((c) => c.startsWith('setBrightness')), isFalse);
    await settlePlayer(tester);
  });

  testWidgets('volume and brightness stay on their own halves', (tester) async {
    await ready(tester);
    await controller.setVolume(0.5);
    engine.calls.clear();

    await tester.dragFrom(const Offset(100, 300), const Offset(0, -112));
    await tester.pump();

    // Touching the left half must not move the volume, or the two gestures would fight.
    expect(controller.volume, 0.5);
    expect(engine.calls.any((c) => c.startsWith('setBrightness')), isTrue);
    await settlePlayer(tester);
  });

  testWidgets('dragging sideways scrubs and commits on release', (tester) async {
    await ready(tester);

    final gesture = await tester.startGesture(const Offset(400, 225));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(uiOf(tester).isScrubbing, isTrue);
    expect(uiOf(tester).displayPosition, greaterThan(const Duration(minutes: 5)));
    // Nothing reaches the engine until the finger lifts.
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);

    await gesture.up();
    await tester.pump();

    expect(uiOf(tester).isScrubbing, isFalse);
    expect(engine.calls.where((c) => c.startsWith('seekTo')).length, 1);
    await settlePlayer(tester);
  });

  testWidgets('gestures are inert while locked', (tester) async {
    await ready(tester);
    uiOf(tester).setLocked(locked: true);
    await tester.pump();

    await doubleTapAt(tester, const Offset(740, 225));

    expect(controller.position, const Duration(minutes: 5));
    await settlePlayer(tester);
  });

  testWidgets('the none preset leaves only the tap that shows the controls', (tester) async {
    await ready(tester, config: const FUiConfig(gestures: FGestureConfig.none()));

    await doubleTapAt(tester, const Offset(740, 225));
    expect(controller.position, const Duration(minutes: 5));

    await tester.dragFrom(const Offset(700, 300), const Offset(0, -112));
    await tester.pump();
    expect(controller.volume, 1.0);
    await settlePlayer(tester);
  });
}
