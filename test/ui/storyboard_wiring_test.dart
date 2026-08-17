import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

/// The `FPlayerView` side of the storyboard: does a source that declares one end up showing a
/// thumbnail while the seek bar is being dragged?
///
/// The parsing and cropping are covered in `test/storyboard`; what is asserted here is the wiring
/// between the two, which is the part that silently does nothing when it is wrong.
void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  const withStoryboard = FPlayerSource.network(
    'https://example.com/a.m3u8',
    storyboard: FStoryboardSource.vtt('https://example.com/sb.vtt'),
  );
  const withoutStoryboard = FPlayerSource.network('https://example.com/a.m3u8');

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  Future<void> ready(WidgetTester tester, FPlayerSource source) async {
    await pumpPlayer(tester, controller: controller);
    await controller.open(source);
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();
  }

  testWidgets('a source with a storyboard previews while scrubbing', (tester) async {
    await ready(tester, withStoryboard);

    expect(find.byType(FStoryboardPreview), findsNothing);

    uiOf(tester).beginScrub();
    uiOf(tester).updateScrub(const Duration(minutes: 3));
    await tester.pump();

    // Visible from the first frame of the drag, showing its placeholder until the index lands —
    // a thumbnail that pops in halfway through a scrub is worse than one that is simply there.
    expect(find.byType(FStoryboardPreview), findsOneWidget);

    uiOf(tester).endScrub();
    await settlePlayer(tester);
  });

  testWidgets('a source without one shows nothing', (tester) async {
    await ready(tester, withoutStoryboard);

    uiOf(tester).beginScrub();
    await tester.pump();

    expect(find.byType(FStoryboardPreview), findsNothing);

    uiOf(tester).endScrub();
    await settlePlayer(tester);
  });

  testWidgets('an explicit previewBuilder wins over the storyboard', (tester) async {
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
                previewBuilder: (context, position) => Text('at $position'),
              ),
            ),
          ),
        ),
      ),
    );
    await controller.open(withStoryboard);
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();

    uiOf(tester).beginScrub();
    uiOf(tester).updateScrub(const Duration(minutes: 3));
    await tester.pump();

    expect(find.text('at 0:03:00.000000'), findsOneWidget);
    expect(find.byType(FStoryboardPreview), findsNothing);

    uiOf(tester).endScrub();
    await settlePlayer(tester);
  });

  testWidgets('an injected controller is not disposed by the view', (tester) async {
    final shared = FStoryboardController();
    addTearDown(shared.dispose);

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
                storyboardController: shared,
              ),
            ),
          ),
        ),
      ),
    );
    await controller.open(withStoryboard);
    engine.becomeReady(duration: const Duration(minutes: 10));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());

    // Still usable after the view is gone: a shared cache outlives any one player.
    expect(shared.hasFrames, isFalse);
    expect(() => shared.frameAt(Duration.zero), returnsNormally);
  });
}
