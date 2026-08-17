import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';

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
    FUiConfig config = const FUiConfig(),
    Size size = const Size(800, 450),
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
                  FPlayerView(controller: controller, config: config),
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

    // Loading: the transport steps aside so the spinner is not stacked on the play button.
    expect(find.byIcon(Icons.play_arrow), findsNothing);

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
      config: const FUiConfig(controlsTimeout: Duration(seconds: 2)),
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
      config: const FUiConfig(controlsTimeout: Duration(seconds: 1)),
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

  testWidgets('the settings panel lists the subtitle tracks and selects one', (tester) async {
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
              label: 'Español',
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

    await tester.tap(find.text('Español'));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:text:text:0:0'));
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
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
