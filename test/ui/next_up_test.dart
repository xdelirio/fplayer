import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  const queue = [
    FPlayerSource.network('https://example.com/1.mp4', title: 'Uno'),
    FPlayerSource.network('https://example.com/2.mp4', title: 'Dos'),
  ];

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  /// Puts the playhead [remaining] before the end of a ten-minute item.
  void positionNearEnd(Duration remaining) {
    engine.emit(
      FEngineProgress(
        position: const Duration(minutes: 10) - remaining,
        buffered: const Duration(minutes: 10),
      ),
    );
  }

  Future<void> ready(WidgetTester tester, {FUiConfig config = const FUiConfig()}) async {
    await pumpPlayer(tester, controller: controller, config: config);
    await controller.setPlaylist(queue);
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();
  }

  testWidgets('the offer appears only near the end', (tester) async {
    await ready(tester);

    positionNearEnd(const Duration(minutes: 5));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FNextUpCard), findsOneWidget);
    expect(find.text('Dos'), findsNothing);

    positionNearEnd(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dos'), findsOneWidget);

    await settlePlayer(tester);
  });

  testWidgets('tapping it advances the queue', (tester) async {
    await ready(tester);
    positionNearEnd(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Dos'));
    await tester.pump();

    expect(controller.value.currentIndex, 1);
    await settlePlayer(tester);
  });

  testWidgets('nothing is offered on the last item', (tester) async {
    await ready(tester);
    await controller.jumpTo(1);
    engine.becomeReady(duration: const Duration(minutes: 10));
    positionNearEnd(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Uno'), findsNothing);
    await settlePlayer(tester);
  });

  testWidgets('track controls appear only with a queue', (tester) async {
    await pumpPlayer(tester, controller: controller);
    await controller.open(const FPlayerSource.network('https://example.com/solo.mp4'));
    engine.becomeReady();
    await tester.pump();

    expect(find.bySemanticsLabel(const FPlayerLocalizations().next), findsNothing);

    await controller.setPlaylist(queue);
    engine.becomeReady();
    await tester.pump();

    expect(find.bySemanticsLabel(const FPlayerLocalizations().next), findsOneWidget);
    await settlePlayer(tester);
  });

  testWidgets('the spinner explains itself while waiting for a network', (tester) async {
    await pumpPlayer(tester, controller: controller);
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    await tester.pump();

    // Loading with no explanation is indistinguishable from a hang.
    expect(find.text(const FPlayerLocalizations().waitingForNetwork), findsNothing);

    engine.emit(
      const FEngineConnectivityChanged(isOnline: false, isWaitingForNetwork: true),
    );
    await tester.pump();

    expect(find.text(const FPlayerLocalizations().waitingForNetwork), findsOneWidget);
    await settlePlayer(tester);
  });
}
