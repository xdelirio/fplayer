import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

void main() {
  late FakeEngine engine;
  late FPlayerController controller;

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
  );

  const l10n = FPlayerLocalizations();

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  Future<void> ready(WidgetTester tester, {Size size = const Size(800, 450)}) async {
    await pumpPlayer(
      tester,
      controller: controller,
      config: const FUiConfig(showControlsOnStart: true),
      size: size,
    );
    await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
    engine.becomeReady(duration: const Duration(minutes: 10));
    engine.emit(const FEngineTracksChanged(tracks));
    await tester.pump();

    await tester.tap(tracksButton);
    await tester.pump();
  }

  testWidgets('both kinds of track are on screen at once', (tester) async {
    await ready(tester);

    expect(find.byType(FTrackDialog), findsOneWidget);
    // The point of the dialog: no menu to walk, both lists visible together.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Italian'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);
    expect(find.text(l10n.off), findsOneWidget);

    await settlePlayer(tester);
  });

  testWidgets('a choice is held until it is applied', (tester) async {
    await ready(tester);
    engine.calls.clear();

    await tester.tap(find.text('Italian'));
    await tester.pump();

    // Still open, and the engine has heard nothing: the dialog is for choosing audio *and*
    // subtitles, and closing on the first row tapped meant a second trip for the second choice.
    expect(find.byType(FTrackDialog), findsOneWidget);
    expect(engine.calls, isEmpty);

    await tester.tap(find.text(l10n.apply));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:audio:audio:0:1'));
    expect(find.byType(FTrackDialog), findsNothing);
    await settlePlayer(tester);
  });

  testWidgets('both kinds of track are applied in one pass', (tester) async {
    await ready(tester);
    engine.calls.clear();

    await tester.tap(find.text('Italian'));
    await tester.pump();
    await tester.tap(find.text('Spanish'));
    await tester.pump();
    await tester.tap(find.text(l10n.apply));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:audio:audio:0:1'));
    expect(engine.calls, contains('selectTrack:text:text:0:0'));
    await settlePlayer(tester);
  });

  testWidgets('applying pushes only what the viewer moved', (tester) async {
    await ready(tester);
    engine.calls.clear();

    // Subtitles only. Re-selecting the audio track that is already playing is not free — it
    // goes to the engine and can rebuffer — so Apply must leave it alone.
    await tester.tap(find.text('Spanish'));
    await tester.pump();
    await tester.tap(find.text(l10n.apply));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:text:text:0:0'));
    expect(engine.calls.where((c) => c.startsWith('selectTrack:audio')), isEmpty);
    await settlePlayer(tester);
  });

  testWidgets('cancelling leaves the player alone', (tester) async {
    await ready(tester);
    engine.calls.clear();

    await tester.tap(find.text('Italian'));
    await tester.pump();
    await tester.tap(find.text(l10n.cancel));
    await tester.pump();

    expect(engine.calls, isEmpty);
    expect(find.byType(FTrackDialog), findsNothing);
    await settlePlayer(tester);
  });

  testWidgets('the tick follows the choice before it is applied', (tester) async {
    await ready(tester);

    FPanelOptionRow rowFor(String label) => tester.widget<FPanelOptionRow>(
          find.ancestor(of: find.text(label), matching: find.byType(FPanelOptionRow)),
        );

    expect(rowFor('English').isSelected, isTrue);
    expect(rowFor('Italian').isSelected, isFalse);

    await tester.tap(find.text('Italian'));
    await tester.pump();

    // Nothing has changed in the player, so the tick can only be coming from the staged choice.
    expect(rowFor('Italian').isSelected, isTrue);
    expect(rowFor('English').isSelected, isFalse);
    await settlePlayer(tester);
  });

  testWidgets('the columns stack when the player is narrow', (tester) async {
    // The same content either way; only the shape changes.
    await ready(tester, size: const Size(360, 640));

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);

    final audio = tester.getTopLeft(find.text('English'));
    final subtitle = tester.getTopLeft(find.text('Spanish'));
    expect(subtitle.dy, greaterThan(audio.dy));
    expect(subtitle.dx, audio.dx);

    await settlePlayer(tester);
  });

  testWidgets('the columns sit side by side when there is room', (tester) async {
    await ready(tester, size: const Size(1280, 720));

    final audio = tester.getTopLeft(find.text('English'));
    final subtitle = tester.getTopLeft(find.text('Spanish'));
    expect(subtitle.dx, greaterThan(audio.dx));

    await settlePlayer(tester);
  });

  testWidgets('a tap outside puts the picture back', (tester) async {
    await ready(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();

    expect(find.byType(FTrackDialog), findsNothing);
    await settlePlayer(tester);
  });
}
