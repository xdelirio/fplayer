import 'package:flutter/material.dart' show Icons;
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

    await tester.tap(find.byIcon(Icons.closed_caption_off_outlined));
    await tester.pump();
  }

  testWidgets('both kinds of track are on screen at once', (tester) async {
    await ready(tester);

    expect(find.byType(FTrackDialog), findsOneWidget);
    // The point of the dialog: no menu to walk, both lists visible together.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Italian'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);
    expect(find.text(const FPlayerLocalizations().off), findsOneWidget);

    await settlePlayer(tester);
  });

  testWidgets('picking an audio track reaches the engine and closes the dialog', (tester) async {
    await ready(tester);
    engine.calls.clear();

    await tester.tap(find.text('Italian'));
    await tester.pump();

    expect(engine.calls, contains('selectTrack:audio:audio:0:1'));
    expect(find.byType(FTrackDialog), findsNothing);
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
