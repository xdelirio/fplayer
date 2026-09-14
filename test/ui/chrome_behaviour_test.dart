import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

/// The behaviours a viewer meets in the first minute, and that the other suites could not see:
/// the chrome going away on its own while playback ticks, leaving fullscreen with the control
/// that says so, and a remote actually operating a panel.
void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  const source = FPlayerSource.network('https://example.com/a.m3u8');

  const tracks = FTracks(
    audio: [
      FAudioTrack(
        id: 'audio:0:0',
        index: 0,
        label: 'English',
        language: 'en',
        isSelected: true,
        isActive: true,
        isSupported: true,
        isDefault: true,
      ),
      FAudioTrack(
        id: 'audio:0:1',
        index: 1,
        label: 'Italian',
        language: 'it',
        isSelected: false,
        isActive: false,
        isSupported: true,
        isDefault: false,
      ),
    ],
  );

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  /// Playback as the engine really reports it: a position tick four times a second.
  void tick(Duration position) => engine.emit(
        FEngineProgress(
          position: position,
          buffered: position + const Duration(seconds: 20),
          bufferedAhead: const Duration(seconds: 20),
        ),
      );

  testWidgets('the chrome goes away on its own while the position keeps ticking',
      (tester) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(
        showControlsOnStart: true,
        controlsTimeout: Duration(seconds: 2),
      ),
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();
    expect(uiOf(tester).areControlsVisible, isTrue);

    // Four seconds of playback, reported the way the engine reports it. The countdown used to be
    // cancelled and re-armed by every one of these, so it could never fire and the chrome sat
    // over the picture for the length of the film.
    for (var i = 1; i <= 16; i++) {
      tick(Duration(milliseconds: 250 * i));
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(uiOf(tester).areControlsVisible, isFalse);
  });

  testWidgets('the chrome is not rebuilt while it is off screen', (tester) async {
    var builds = 0;
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(
        showControlsOnStart: true,
        controlsTimeout: Duration(seconds: 2),
      ),
      bottomBarBuilder: (context, ui) {
        builds++;
        return const SizedBox(height: 40);
      },
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();
    expect(builds, greaterThan(0));

    // Let it fade out, then play on. Every tick used to rebuild the whole chrome — seek bar,
    // volume slider, a dozen buttons — behind an opacity of zero.
    for (var i = 1; i <= 12; i++) {
      tick(Duration(milliseconds: 250 * i));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(uiOf(tester).areControlsVisible, isFalse);

    final whileHidden = builds;
    for (var i = 13; i <= 24; i++) {
      tick(Duration(milliseconds: 250 * i));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(builds, whileHidden, reason: 'nothing rebuilds a chrome nobody can see');

    // And it is up to date again the moment it is asked for.
    uiOf(tester).showControls();
    await tester.pump();
    expect(builds, greaterThan(whileHidden));
    await settlePlayer(tester);
  });

  testWidgets('a host rebuilding on every tick does not rebuild the hidden chrome',
      (tester) async {
    var builds = 0;
    tester.view.physicalSize = const Size(800, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The shape of an ordinary player page: the whole view inside a builder on the same
    // controller, with a config that is not const.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Navigator(
            onGenerateRoute: (settings) => PageRouteBuilder<void>(
              pageBuilder: (context, _, _) => ListenableBuilder(
                listenable: controller,
                builder: (context, _) => FPlayerView(
                  controller: controller,
                  // ignore: prefer_const_constructors
                  config: FUiConfig(controlsTimeout: const Duration(seconds: 2)),
                  bottomBarBuilder: (context, ui) {
                    builds++;
                    return const SizedBox(height: 40);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();
    uiOf(tester).showControls();
    await tester.pump();

    for (var i = 1; i <= 12; i++) {
      tick(Duration(milliseconds: 250 * i));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(uiOf(tester).areControlsVisible, isFalse);

    final whileHidden = builds;
    for (var i = 13; i <= 24; i++) {
      tick(Duration(milliseconds: 250 * i));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(builds, whileHidden, reason: 'a new widget is not a reason to rebuild what is hidden');
    await settlePlayer(tester);
  });

  testWidgets('an episode ending in a queue does not close fullscreen', (tester) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(showControlsOnStart: true),
    );
    await controller.setPlaylist(const [
      FPlayerSource.network('https://example.com/1.m3u8'),
      FPlayerSource.network('https://example.com/2.m3u8'),
    ]);
    engine.becomeReady();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    // The next item loads behind a spinner that never settles, so the frames are counted out.
    engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(
      find.byIcon(Icons.fullscreen_exit),
      findsOneWidget,
      reason: 'the next episode is about to start; the viewer is still watching',
    );

    // The last one ending is the end of watching, and fullscreen goes as it always did.
    engine.becomeReady();
    await tester.pump();
    engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
  });

  group('a host-owned full-screen page on a television', () {
    Future<void> hostPage(WidgetTester tester, {VoidCallback? onBack}) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            // The player page on top of the host's home, the way an app reaches it: a pop here
            // would have somewhere to go.
            child: Navigator(
              initialRoute: '/player',
              onGenerateRoute: (settings) => PageRouteBuilder<void>(
                settings: settings,
                pageBuilder: (context, _, _) => settings.name == '/player'
                    ? FPlayerView(
                        controller: controller,
                        config: const FUiConfig.tv(),
                        isFullscreen: true,
                        onBack: onBack,
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await controller.open(source);
      engine.becomeReady(duration: const Duration(minutes: 10));
      await tester.pump();
    }

    testWidgets('a video reaching its end leaves the page standing', (tester) async {
      await hostPage(tester);

      engine.emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.byType(FPlayerView), findsOneWidget, reason: 'the page is the host’s to close');
      await settlePlayer(tester);
    });

    testWidgets('back runs the host callback', (tester) async {
      var backs = 0;
      await hostPage(tester, onBack: () => backs++);

      uiOf(tester).back();
      await tester.pump();

      expect(backs, 1);
      expect(find.byType(FPlayerView), findsOneWidget);
      await settlePlayer(tester);
    });
  });

  Future<void> openSettingsPanel(WidgetTester tester, FUiConfig config) async {
    await pumpPlayer(tester, controller: controller, config: config);
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();
    uiOf(tester).openPanel(FPlayerPanel.settings);
    await tester.pump();
  }

  testWidgets('a panel under touch keeps its frosted plate', (tester) async {
    await openSettingsPanel(tester, const FUiConfig(showControlsOnStart: true));
    expect(find.byType(BackdropFilter), findsOneWidget);
    await settlePlayer(tester);
  });

  testWidgets('a panel under a remote is a plain plate, not a blur', (tester) async {
    // On a television the picture is a SurfaceView the blur cannot sample, and every frame of it
    // was rasterised on the thread the decoder's callbacks share.
    await openSettingsPanel(
      tester,
      const FUiConfig(showControlsOnStart: true, tv: FTvConfig(mode: FTvMode.enabled)),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await settlePlayer(tester);
  });

  testWidgets('the exit-fullscreen control leaves fullscreen', (tester) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(showControlsOnStart: true),
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    // The rule that back closes the chrome before it closes the player is expressed as a
    // `PopScope` veto — and this control is only reachable *with* the chrome open, so it used to
    // trip over that rule every time and merely fade the controls out.
    await tester.tap(find.byIcon(Icons.fullscreen_exit));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
  });

  testWidgets('fullscreen with the chrome away shows nothing at all', (tester) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(showControlsOnStart: true, controlsTimeout: Duration(seconds: 2)),
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    // Let the chrome time out with playback reporting position, the way it really does.
    for (var i = 1; i <= 16; i++) {
      tick(Duration(milliseconds: 250 * i));
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The idle hairline is worth having over an inline player; over a film filling the screen it
    // is the one thing still burning along the bottom edge after the viewer put the chrome away.
    expect(find.byKey(const Key('fplayer.idle-progress')), findsNothing);
  });

  testWidgets('a remote can open a panel, walk it and pick a track', (tester) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(
        showControlsOnStart: true,
        tv: FTvConfig(mode: FTvMode.enabled),
      ),
    );
    await controller.open(source);
    engine.becomeReady();
    engine.emit(const FEngineTracksChanged(tracks));
    await tester.pump();

    uiOf(tester).openPanel(FPlayerPanel.tracks);
    await tester.pumpAndSettle();

    // The panel takes focus rather than leaving it on the chrome behind the scrim.
    expect(
      find.byType(FPanelOptionRow).evaluate().any(
            (element) => Focus.maybeOf(element)?.hasFocus ?? false,
          ),
      isTrue,
      reason: 'the panel did not take focus when it opened',
    );

    // Walk to the second audio track and press OK. Rows used to be focusable but inert: a bare
    // `Focus` answers no key at all, so the panel was decorative on a remote.
    await walk(tester, LogicalKeyboardKey.arrowDown, until: (c) => rowLabel(c) == 'Italian');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    // Nothing has reached the engine yet: the dialog holds the choice until it is confirmed, so
    // the remote has to be able to walk to Apply as well.
    expect(engine.calls.where((c) => c.startsWith('selectTrack')), isEmpty);

    await walk(tester, LogicalKeyboardKey.arrowDown, until: (c) => footerButton(c) != null);
    await walk(
      tester,
      LogicalKeyboardKey.arrowRight,
      until: (c) => footerButton(c)?.isPrimary ?? false,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(engine.calls, contains('selectTrack:audio:audio:0:1'));
  });

  testWidgets('hidden controls answer no key', (tester) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(
        showControlsOnStart: true,
        tv: FTvConfig(mode: FTvMode.enabled),
      ),
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();

    uiOf(tester).hideControls();
    await tester.pump();
    await tester.pump();
    engine.calls.clear();

    // The play button holds focus from its autofocus. Invisible, it used to take the press and
    // toggle playback with nothing on screen to explain it.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(engine.calls, isEmpty);
    expect(uiOf(tester).areControlsVisible, isTrue);
  });
}
