import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

/// Where focus lives on a remote-driven player, which decides whether the remote does anything
/// at all.
void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  const source = FPlayerSource.network('https://example.com/a.m3u8');

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  testWidgets('a remote reaches a player whose chrome starts away', (tester) async {
    // The default is `showControlsOnStart: false`, so on the first frame nothing inside the
    // player has ever held focus. With nothing focusable and nothing parked, every press on the
    // remote went nowhere — the player was inert until it was touched.
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(tv: FTvConfig(mode: FTvMode.enabled)),
    );
    await controller.open(source);
    engine.becomeReady();
    await tester.pump();
    await tester.pump();

    expect(uiOf(tester).areControlsVisible, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(uiOf(tester).areControlsVisible, isTrue);
  });

  testWidgets('the player does not take focus from the app around it', (tester) async {
    // The same parking, running four times a second on a phone, used to pull focus out of
    // whatever the host app owned.
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Column(
            children: [
              Focus(focusNode: outside, child: const SizedBox(width: 10, height: 10)),
              Expanded(
                child: Navigator(
                  onGenerateRoute: (settings) => PageRouteBuilder<void>(
                    pageBuilder: (context, _, _) => FPlayerView(
                      controller: controller,
                      config: const FUiConfig(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await controller.open(source);
    engine.becomeReady();
    await tester.pump();

    outside.requestFocus();
    await tester.pump();
    expect(outside.hasPrimaryFocus, isTrue);

    // A few seconds of playback, reported the way the engine reports it.
    for (var i = 1; i <= 8; i++) {
      engine.emit(
        FEngineProgress(
          position: Duration(milliseconds: 250 * i),
          buffered: const Duration(seconds: 20),
          bufferedAhead: const Duration(seconds: 20),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(outside.hasPrimaryFocus, isTrue);
  });
}
