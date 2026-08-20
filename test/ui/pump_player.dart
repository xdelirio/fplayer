import 'package:flutter/services.dart';
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
        // The shortcuts and actions a `WidgetsApp` installs, because a player without them is
        // not the player anyone ships: arrow keys only move focus because the app above binds
        // them to `DirectionalFocusIntent`, and half of what a remote does is focus movement.
        child: Shortcuts(
          shortcuts: WidgetsApp.defaultShortcuts,
          child: Actions(
            actions: WidgetsApp.defaultActions,
            child: FocusTraversalGroup(
              child: Navigator(
                onGenerateRoute: (settings) => PageRouteBuilder<void>(
                  pageBuilder: (context, _, _) =>
                      FPlayerView(controller: controller, config: config),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The control that opens the audio and subtitles dialog.
///
/// Found by what it does rather than by its text: the label shortens on a narrow player, and the
/// tests that care about that are not the ones tapping it.
final Finder tracksButton = find.byWidgetPredicate(
  (widget) =>
      widget is FPlayerTextButton &&
      widget.semanticLabel == const FPlayerLocalizations().audioAndSubtitles,
);

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

/// Label of the panel row that holds focus, or null when focus is elsewhere.
String? rowLabel(BuildContext context) =>
    context.findAncestorWidgetOfExactType<FPanelOptionRow>()?.label;

/// The panel footer button that holds focus, or null when focus is elsewhere.
FPanelFooterButton? footerButton(BuildContext context) =>
    context.findAncestorWidgetOfExactType<FPanelFooterButton>();

/// Presses [key] until [until] holds for whatever has focus.
///
/// Written as a search rather than a fixed number of presses because the answer depends on
/// geometry — how many rows the media offers, and whether the dialog is one column or two — and a
/// test that hard-codes the count asserts the layout instead of the behaviour.
Future<void> walk(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  required bool Function(BuildContext context) until,
  int maxSteps = 12,
}) async {
  for (var step = 0; step <= maxSteps; step++) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null && until(context)) return;
    await tester.sendKeyEvent(key);
    await tester.pump();
  }
  fail('the D-pad never reached the target in $maxSteps presses of ${key.keyLabel}');
}
