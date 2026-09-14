import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart' show tracksButton;

void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  setUp(() {
    engine = FakeEngine();
    controller = FPlayerController(
      // These tests are about the chrome, so the controller's own timers are switched off: an
      // armed loading timeout or a pending retry would outlive the widget tree and fail the
      // test for a reason that has nothing to do with the UI.
      config: const FPlayerConfig(
        network: FNetworkConfig(
          loadingTimeout: Duration.zero,
          retry: FRetryPolicy.none(),
        ),
      ),
      engine: engine,
    );
  });

  tearDown(() => controller.dispose());

  /// The view needs a Navigator for the fullscreen route and a Directionality for text.
  Future<void> pumpPlayer(
    WidgetTester tester, {
    // Most of what is asserted here is the chrome, so it starts on screen. The default is the
    // opposite; that is covered by its own test.
    FUiConfig config = const FUiConfig(showControlsOnStart: true),
    Size size = const Size(800, 450),
    VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Navigator(
            onGenerateRoute: (settings) => PageRouteBuilder<void>(
              pageBuilder: (context, _, _) =>
                  FPlayerView(controller: controller, config: config, onBack: onBack),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the texture once the engine exists', (tester) async {
    await pumpPlayer(tester);
    expect(find.byType(FVideoSurface), findsOneWidget);

    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    await tester.pump();

    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('shows a spinner while loading and hides it once ready', (tester) async {
    await pumpPlayer(tester);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    await tester.pump();

    // Loading: the transport steps aside so the spinner is not stacked on the play button. It
    // keeps its place in the tree while it does, or every rebuffer would take a remote's focus
    // down with it — so it is invisible rather than gone.
    expect(
      tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.play_arrow),
          matching: find.byType(Opacity),
        ).first,
      ).opacity,
      0,
    );

    engine.becomeReady();
    await tester.pump();

    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('tapping the middle toggles playback', (tester) async {
    await pumpPlayer(tester);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(engine.calls, contains('pause'));
    expect(controller.isPlaying, isFalse);
  });

  testWidgets('controls fade out after the timeout while playing', (tester) async {
    await pumpPlayer(
      tester,
      config: const FUiConfig(showControlsOnStart: true, controlsTimeout: Duration(seconds: 2)),
    );
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    final ui = tester.state<State<FPlayerView>>(find.byType(FPlayerView)) as FPlayerUi;
    expect(ui.areControlsVisible, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(ui.areControlsVisible, isFalse);
  });

  testWidgets('controls stay up while paused', (tester) async {
    await pumpPlayer(
      tester,
      config: const FUiConfig(showControlsOnStart: true, controlsTimeout: Duration(seconds: 1)),
    );
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    engine.emit(const FEnginePlayingChanged(isPlaying: false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final ui = tester.state<State<FPlayerView>>(find.byType(FPlayerView)) as FPlayerUi;
    expect(ui.areControlsVisible, isTrue);
  });

  testWidgets('a fatal error replaces the chrome with a retry affordance', (tester) async {
    await pumpPlayer(tester);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    engine.emit(
      const FEngineFailed(
        FPlayerError(
          code: FPlayerErrorCode.notFound,
          message: 'gone',
        ),
      ),
    );
    // Two frames: the signal lands on a microtask after the first one has been built, so the
    // overlay it triggers is painted on the next. A real player shows it 16 ms later.
    await tester.pump();
    await tester.pump();

    expect(find.byType(FErrorView), findsOneWidget);
    expect(find.text(const FPlayerLocalizations().errorNotFound), findsOneWidget);
    // Not retryable, so no button to press.
    expect(find.text(const FPlayerLocalizations().retry), findsNothing);
  });

  testWidgets('a fatal error still offers a way out of the player', (tester) async {
    // The error view covers the chrome, so the top bar's back button goes with it. A video that
    // will never play and no way to leave it is an app the viewer has to kill.
    var backs = 0;
    await pumpPlayer(tester, onBack: () => backs++);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    engine.emit(
      const FEngineFailed(
        FPlayerError(code: FPlayerErrorCode.notFound, message: 'gone'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text(const FPlayerLocalizations().back));
    await tester.pump();
    expect(backs, 1);

    // And the arrow in the corner, where the chrome keeps it.
    await tester.tap(find.descendant(
      of: find.byType(FErrorView),
      matching: find.byIcon(Icons.arrow_back),
    ));
    await tester.pump();
    expect(backs, 2);
  });

  testWidgets('a retryable error offers a retry that reaches the engine', (tester) async {
    await pumpPlayer(tester);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    engine.emit(
      const FEngineFailed(
        FPlayerError(
          code: FPlayerErrorCode.network,
          message: 'offline',
          isRetryable: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text(const FPlayerLocalizations().retry));
    await tester.pump();

    expect(engine.calls, contains('retry'));
  });

  testWidgets('the track dialog lists the subtitles and selects one', (tester) async {
    await pumpPlayer(tester);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();

    engine.emit(
      const FEngineTracksChanged(
        FTracks(
          text: [
            FTextTrack(
              id: 'text:0:0',
              index: 0,
              label: 'Spanish',
              language: 'es',
              isSelected: false,
              isActive: false,
              isSupported: true,
              isDefault: false,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    // One control for both kinds of track, and no menu to walk: the list is right there.
    await tester.tap(tracksButton);
    await tester.pump();
    expect(find.byType(FTrackDialog), findsOneWidget);

    await tester.tap(find.text('Spanish'));
    await tester.pump();

    // Chosen, not yet applied: the dialog exists to pick audio *and* subtitles, so it waits.
    expect(engine.calls, isNot(contains('selectTrack:text:text:0:0')));

    await tester.tap(find.text(const FPlayerLocalizations().apply));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:text:text:0:0'));
  });

  testWidgets('the settings panel still walks to a track when it is turned on', (tester) async {
    await pumpPlayer(
      tester,
      config: const FUiConfig(showControlsOnStart: true, showSettingsButton: true),
    );
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();

    engine.emit(
      const FEngineTracksChanged(
        FTracks(
          text: [
            FTextTrack(
              id: 'text:0:0',
              index: 0,
              label: 'Spanish',
              language: 'es',
              isSelected: false,
              isActive: false,
              isSupported: true,
              isDefault: false,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    expect(find.byType(FSettingsPanel), findsOneWidget);

    await tester.tap(find.text(const FPlayerLocalizations().subtitles));
    await tester.pump();

    await tester.tap(find.text('Spanish'));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:text:text:0:0'));
  });

  testWidgets('the chrome carries its own text baseline', (tester) async {
    // No Material anywhere above — which is the fullscreen route, and any host that does not use
    // Material. Without a default style of its own the whole chrome inherits Flutter's error
    // style: yellow, underlined, monospaced.
    await pumpPlayer(tester);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();

    final paragraph = tester.renderObject<RenderParagraph>(find.text('0:00'));
    expect(paragraph.text.style?.decoration ?? TextDecoration.none, TextDecoration.none);
    expect(paragraph.text.style?.color, const FPlayerTheme().foreground);
  });

  testWidgets('the chrome starts away, with a hairline of progress in its place', (tester) async {
    await pumpPlayer(tester, config: const FUiConfig());
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();

    final ui = tester.state<State<FPlayerView>>(find.byType(FPlayerView)) as FPlayerUi;
    expect(ui.areControlsVisible, isFalse);
    expect(find.byKey(const Key('fplayer.idle-progress')), findsOneWidget);

    await tester.tapAt(const Offset(400, 225));
    await tester.pump(kDoubleTapTimeout);

    expect(ui.areControlsVisible, isTrue);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('bare config renders the video without any chrome', (tester) async {
    await pumpPlayer(tester, config: const FUiConfig.bare());
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    expect(find.byType(FVideoSurface), findsOneWidget);
    expect(find.byType(FControlsOverlay), findsNothing);
  });

  testWidgets('a custom bottom bar replaces the built-in one and keeps the scope', (tester) async {
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
                config: const FUiConfig(showControlsOnStart: true),
                bottomBarBuilder: (context, ui) => GestureDetector(
                  onTap: ui.showControls,
                  child: const Text('custom'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady();
    await tester.pump();

    expect(find.text('custom'), findsOneWidget);
    // The rest of the chrome is untouched.
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
  });
}
