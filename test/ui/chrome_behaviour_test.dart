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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(engine.calls.where((c) => c.startsWith('selectTrack')), isNotEmpty);
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
