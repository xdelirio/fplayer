import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  const tvConfig = FUiConfig(
    showControlsOnStart: true,
    tv: FTvConfig(
      mode: FTvMode.enabled,
      seekCommitDelay: Duration(milliseconds: 300),
    ),
  );

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  /// Puts focus on the seek bar, which is what makes left and right mean *scrub*: everywhere
  /// else on the chrome they walk the controls.
  Future<void> focusSeekBar(WidgetTester tester) async {
    final bar = tester.widget<Focus>(
      find
          .descendant(of: find.byType(FProgressBar), matching: find.byType(Focus))
          .first,
    );
    bar.focusNode!.requestFocus();
    await tester.pump();
  }

  Future<void> ready(
    WidgetTester tester, {
    FUiConfig config = tvConfig,
    bool onSeekBar = true,
  }) async {
    await pumpPlayer(tester, controller: controller, config: config);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();
    if (onSeekBar) await focusSeekBar(tester);
  }

  testWidgets('the first directional press only reveals the controls', (tester) async {
    await ready(tester);
    uiOf(tester).hideControls();
    await tester.pump();
    expect(uiOf(tester).areControlsVisible, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(uiOf(tester).areControlsVisible, isTrue);
    // Revealing is the whole action: nothing was seeked.
    expect(uiOf(tester).isScrubbing, isFalse);
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);
  });

  testWidgets('left and right leave the buttons alone', (tester) async {
    // The play button holds focus from its autofocus, and a viewer pressing right there is
    // reaching for the next control — not asking to jump ten seconds into the film.
    await ready(tester, onSeekBar: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(uiOf(tester).isScrubbing, isFalse);
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);
  });

  testWidgets('OK commits the pending seek without waiting', (tester) async {
    await ready(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(engine.calls.where((c) => c.startsWith('seekTo')).length, 1);
    expect(uiOf(tester).isScrubbing, isFalse);
  });

  testWidgets('right seeks forward once the controls are up', (tester) async {
    await ready(tester);
    expect(uiOf(tester).areControlsVisible, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    final ui = uiOf(tester);
    expect(ui.isScrubbing, isTrue);
    expect(ui.displayPosition, const Duration(seconds: 10));
    // Nothing has reached the engine yet — the preview moves first.
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);
  });

  testWidgets('the seek is committed once after the presses stop', (tester) async {
    await ready(tester);

    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);

    await tester.pump(const Duration(milliseconds: 400));

    // One seek for the whole run, not one per press.
    expect(engine.calls.where((c) => c.startsWith('seekTo')).length, 1);
    expect(uiOf(tester).isScrubbing, isFalse);
  });

  testWidgets('a run of presses accelerates', (tester) async {
    await ready(tester);

    Future<Duration> press() async {
      final before = uiOf(tester).displayPosition;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      return uiOf(tester).displayPosition - before;
    }

    final first = await press();
    expect(first, const Duration(seconds: 10));

    Duration last = first;
    for (var i = 0; i < 5; i++) {
      last = await press();
    }

    // Same key, further each time — that is what makes a long film crossable with a remote.
    expect(last, greaterThan(first));

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the run resets once the presses stop', (tester) async {
    await ready(tester);

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));

    final before = uiOf(tester).displayPosition;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    // Back to the base step: the acceleration belongs to the run, not to the session.
    expect(uiOf(tester).displayPosition - before, const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('acceleration can be switched off', (tester) async {
    await ready(
      tester,
      config: const FUiConfig(
        showControlsOnStart: true,
        tv: FTvConfig(
          mode: FTvMode.enabled,
          seekAcceleration: false,
          seekCommitDelay: Duration(milliseconds: 300),
        ),
      ),
    );

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }

    expect(uiOf(tester).displayPosition, const Duration(seconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('seeking is clamped to the media', (tester) async {
    await ready(tester);

    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }

    expect(uiOf(tester).displayPosition, Duration.zero);
    await tester.pump(const Duration(milliseconds: 400));
  });

  final speedButton = find.byWidgetPredicate(
    (widget) =>
        widget is FPlayerTextButton &&
        widget.semanticLabel == const FPlayerLocalizations().speed,
  );

  testWidgets('the speed control is there on touch', (tester) async {
    await ready(
      tester,
      config: const FUiConfig(showControlsOnStart: true),
      onSeekBar: false,
    );

    expect(speedButton, findsOneWidget);
  });

  testWidgets('the speed control steps aside for a remote', (tester) async {
    await ready(tester, onSeekBar: false);

    // One less stop for the D-pad to walk through, for a setting nobody changes from a sofa.
    expect(speedButton, findsNothing);
  });

  testWidgets('media keys act immediately, without revealing first', (tester) async {
    await ready(tester);
    uiOf(tester).hideControls();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();

    expect(engine.calls, contains('pause'));
  });

  testWidgets('disabled mode leaves the keys to Flutter', (tester) async {
    await ready(
      tester,
      config: const FUiConfig(tv: FTvConfig(mode: FTvMode.disabled)),
      onSeekBar: false,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(uiOf(tester).isScrubbing, isFalse);
    expect(engine.calls.where((c) => c.startsWith('seekTo')), isEmpty);
  });

  testWidgets('directional keys do not seek while the settings panel is open',
      (tester) async {
    await ready(tester);
    uiOf(tester).openSettings();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(uiOf(tester).isScrubbing, isFalse);
  });
}
