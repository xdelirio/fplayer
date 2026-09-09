import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  Future<void> ready(WidgetTester tester, {FUiConfig config = const FUiConfig.desktop()}) async {
    await pumpPlayer(tester, controller: controller, config: config);
    await controller.open(const FPlayerSource.network('https://example.com/a.mp4'));
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();
  }

  /// A mouse that has entered the player and now sits at [at].
  Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    addTearDown(mouse.removePointer);
    await tester.pump();
    return mouse;
  }

  group('which chrome', () {
    testWidgets('the desktop preset swaps the overlay for the desktop controls', (tester) async {
      await ready(tester);
      expect(find.byType(FDesktopControls), findsOneWidget);
      expect(find.byType(FControlsOverlay), findsNothing);
      // The transport lives in the bar, not in the middle of the picture.
      expect(find.byType(FDesktopBottomBar), findsOneWidget);
      expect(find.byType(FVolumeSlider), findsOneWidget);
      await settlePlayer(tester);
    });

    testWidgets('the default config picks by platform, and the remote layout stays off', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await ready(tester, config: const FUiConfig(showControlsOnStart: true));
        expect(find.byType(FDesktopControls), findsOneWidget);

        // Enter is a key the desktop layer leaves alone. It used to reach the TV layer, whose
        // `auto` mode took it as a remote and armed itself for good: focus rings on, the speed
        // control gone, and the shortcuts dead after the next auto-hide.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.text('1×'), findsOneWidget, reason: 'the speed control is a phone/desktop one');

        uiOf(tester).hideControls();
        await tester.pump();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(controller.value.isPlaying, isFalse, reason: 'Space still reaches the player');
        await settlePlayer(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a leanback build keeps its layout on a desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await ready(tester, config: const FUiConfig.tv());
        expect(find.byType(FControlsOverlay), findsOneWidget);
        expect(find.byType(FDesktopControls), findsNothing);
        await settlePlayer(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a phone keeps the touch chrome', (tester) async {
      await ready(tester, config: const FUiConfig(showControlsOnStart: true));
      expect(find.byType(FControlsOverlay), findsOneWidget);
      expect(find.byType(FDesktopControls), findsNothing);
      await settlePlayer(tester);
    });
  });

  group('mouse', () {
    testWidgets('moving over the player reveals the controls, leaving hides them', (tester) async {
      await ready(tester);
      uiOf(tester).hideControls();
      await tester.pump();
      expect(uiOf(tester).areControlsVisible, isFalse);

      final mouse = await mouseAt(tester, const Offset(400, 225));
      expect(uiOf(tester).areControlsVisible, isTrue);

      // Hidden again, then a plain move inside the player — the path the feature lives on.
      uiOf(tester).hideControls();
      await tester.pump();
      await mouse.moveTo(const Offset(420, 230));
      await tester.pump();
      expect(uiOf(tester).areControlsVisible, isTrue);

      await mouse.moveTo(const Offset(1200, 225));
      await tester.pump(const Duration(seconds: 1));
      expect(uiOf(tester).areControlsVisible, isFalse);
      await settlePlayer(tester);
    });

    testWidgets('a click on the picture pauses, a double-click goes fullscreen', (tester) async {
      await ready(tester);
      expect(controller.value.isPlaying, isTrue);

      await tester.tapAt(const Offset(400, 225), kind: PointerDeviceKind.mouse);
      // A single click waits out the double-click window before it counts.
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.value.isPlaying, isFalse);

      await tester.tapAt(const Offset(400, 225), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(400, 225), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(uiOf(tester).isFullscreen, isTrue);
      await settlePlayer(tester);
    });

    testWidgets('a click on the bar between controls is not a click on the picture', (
      tester,
    ) async {
      await ready(tester);
      final bar = tester.getRect(find.byType(FDesktopBottomBar));
      // Just under the seek bar, in the gap above the transport row.
      await tester.tapAt(Offset(bar.center.dx, bar.top + 2), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.value.isPlaying, isTrue);
      await settlePlayer(tester);
    });

    testWidgets('a narrow player scrolls the pickers instead of overflowing', (tester) async {
      await pumpPlayer(
        tester,
        controller: controller,
        config: const FUiConfig.desktop().copyWith(showSettingsButton: true),
        size: const Size(360, 203),
      );
      await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
      engine.becomeReady(duration: const Duration(minutes: 10));
      engine.emit(
        const FEngineTracksChanged(
          FTracks(
            audio: [
              FAudioTrack(
                id: 'a1',
                index: 0,
                label: 'English',
                language: 'en',
                isSelected: true,
                isActive: true,
                isSupported: true,
                isDefault: true,
              ),
              FAudioTrack(
                id: 'a2',
                index: 1,
                label: 'Español',
                language: 'es',
                isSelected: false,
                isActive: false,
                isSupported: true,
                isDefault: false,
              ),
            ],
            video: [
              FVideoTrack(
                id: 'v1',
                index: 0,
                label: null,
                language: null,
                isSelected: false,
                isActive: true,
                isSupported: true,
                isDefault: true,
                height: 1080,
              ),
              FVideoTrack(
                id: 'v2',
                index: 1,
                label: null,
                language: null,
                isSelected: false,
                isActive: false,
                isSupported: true,
                isDefault: false,
                height: 720,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(FDesktopBottomBar), findsOneWidget);
      await settlePlayer(tester);
    });

    testWidgets('the wheel changes the volume', (tester) async {
      await ready(tester);
      await controller.setVolume(0.5);
      await mouseAt(tester, const Offset(400, 225));

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(400, 225),
          scrollDelta: Offset(0, -20),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(controller.value.volume, closeTo(0.55, 0.001));
      await settlePlayer(tester);
    });

    testWidgets('the cursor hides with the controls while playing', (tester) async {
      await ready(tester);
      MouseRegion region() => tester.widget<MouseRegion>(
        find.descendant(of: find.byType(FDesktopLayer), matching: find.byType(MouseRegion)).first,
      );
      expect(region().cursor, MouseCursor.defer);

      uiOf(tester).hideControls();
      await tester.pump();
      expect(region().cursor, SystemMouseCursors.none);

      await controller.pause();
      await tester.pump();
      expect(region().cursor, MouseCursor.defer, reason: 'a paused picture is not idle');
      await settlePlayer(tester);
    });
  });

  group('keyboard', () {
    testWidgets('space, arrows, M and F do what desktop players do', (tester) async {
      await ready(tester);
      await controller.setVolume(0.5);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(engine.position, controller.config.playback.seekStep);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controller.value.volume, closeTo(0.55, 0.001));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(controller.value.isMuted, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(uiOf(tester).isFullscreen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(uiOf(tester).isFullscreen, isFalse);
      await settlePlayer(tester);
    });

    testWidgets('a key press brings the controls back', (tester) async {
      await ready(tester);
      uiOf(tester).hideControls();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(uiOf(tester).areControlsVisible, isTrue);
      await settlePlayer(tester);
    });

    testWidgets('the shortcuts can be turned off, the media keys cannot', (tester) async {
      await ready(
        tester,
        config: const FUiConfig.desktop().copyWith(
          desktop: const FDesktopConfig(mode: FDesktopMode.enabled, keyboardShortcuts: false),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.value.isPlaying, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse);
      await settlePlayer(tester);
    });
  });

  group('window', () {
    testWidgets('fullscreen asks the engine for the window, and gives it back', (tester) async {
      await ready(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(engine.calls, contains('setWindowFullscreen:true'));
      expect(engine.calls, isNot(contains('setWindowFullscreen:false')));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(engine.calls, contains('setWindowFullscreen:false'));
      await settlePlayer(tester);
    });

    testWidgets(
      'the floating PiP window keeps the pointer, and leaves on Escape or a double-click',
      (tester) async {
        await ready(tester);
        engine.emit(const FEnginePipChanged(isActive: true, isSupported: true));
        await tester.pump();
        expect(controller.value.isPipActive, isTrue);
        // Nothing but the picture and the pointer layer: no bar, no title.
        expect(find.byType(FDesktopControls), findsNothing);
        expect(find.byType(FDesktopPointerLayer), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(engine.calls, contains('exitPip'));
        engine.calls.clear();

        await tester.tapAt(const Offset(400, 225));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(const Offset(400, 225));
        await tester.pump(const Duration(milliseconds: 400));
        expect(engine.calls, contains('exitPip'));
        expect(
          uiOf(tester).isFullscreen,
          isFalse,
          reason: 'a double-click in PiP is not fullscreen',
        );
        await settlePlayer(tester);
      },
    );
  });

  group('a host-owned full-window player', () {
    testWidgets('F fills the window instead of closing the player', (tester) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Navigator(
              onGenerateRoute: (settings) => PageRouteBuilder<void>(
                pageBuilder: (context, _, _) => FPlayerView(
                  controller: controller,
                  config: const FUiConfig.desktop(),
                  isFullscreen: true,
                ),
              ),
            ),
          ),
        ),
      );
      await controller.open(const FPlayerSource.network('https://example.com/a.mp4'));
      engine.becomeReady(duration: const Duration(minutes: 10));
      await tester.pump();
      expect(uiOf(tester).isFullscreen, isFalse, reason: 'the window is not fullscreen yet');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(find.byType(FPlayerView), findsOneWidget, reason: 'the route stays');
      expect(engine.calls, contains('setWindowFullscreen:true'));
      expect(uiOf(tester).isFullscreen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(FPlayerView), findsOneWidget);
      expect(engine.calls, contains('setWindowFullscreen:false'));
      expect(uiOf(tester).isFullscreen, isFalse);
      await settlePlayer(tester);
    });
  });

  group('volume slider', () {
    testWidgets('a click sets the level, a drag follows the pointer', (tester) async {
      await ready(tester);
      final slider = find.byType(FVolumeSlider);
      final left = tester.getTopLeft(slider);
      final size = tester.getSize(slider);

      await tester.tapAt(left + Offset(size.width * 0.25, size.height / 2));
      await tester.pump();
      expect(controller.value.volume, closeTo(0.25, 0.02));

      await tester.dragFrom(
        left + Offset(size.width * 0.25, size.height / 2),
        Offset(size.width * 0.5, 0),
      );
      await tester.pump();
      expect(controller.value.volume, closeTo(0.75, 0.02));
      await settlePlayer(tester);
    });
  });
}
