import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';

/// A controller whose own timers are disarmed.
///
/// The loading timeout and the retry backoff would otherwise outlive the widget tree and fail
/// tests for a reason unrelated to what they assert.
FPlayerController quietController(FakeEngine engine) => FPlayerController(
      config: const FPlayerConfig(
        network: FNetworkConfig(
          loadingTimeout: Duration.zero,
          retry: FRetryPolicy.none(),
        ),
      ),
      engine: engine,
    );

/// Mounts a player at a known size, inside the Navigator and Directionality it needs.
Future<void> pumpPlayer(
  WidgetTester tester, {
  required FPlayerController controller,
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

/// The view's own state, for asserting on chrome behaviour.
FPlayerUi uiOf(WidgetTester tester) =>
    tester.state<State<FPlayerView>>(find.byType(FPlayerView)) as FPlayerUi;

/// Lets the view's own timers expire before the tree is torn down.
///
/// The auto-hide countdown and the gesture feedback badge both outlive a single pump, and a
/// pending timer fails the test for a reason unrelated to what it asserts.
Future<void> settlePlayer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
}
