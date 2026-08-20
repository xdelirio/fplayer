import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

FVideoTrack track({
  required String id,
  int? width,
  int? height,
  int? bitrate,
}) =>
    FVideoTrack(
      id: id,
      index: 0,
      label: null,
      language: null,
      width: width,
      height: height,
      bitrate: bitrate,
      isSelected: false,
      isActive: false,
      isSupported: true,
      isDefault: false,
    );

void main() {
  test('one row per size, keeping the best rendition of each', () {
    // Two ladders in one manifest, which is what a real HLS master often looks like.
    final rungs = distinctQualityRungs([
      track(id: 'a', width: 1920, height: 1080, bitrate: 199000),
      track(id: 'b', width: 854, height: 480, bitrate: 133000),
      track(id: 'c', width: 1920, height: 1080, bitrate: 2400000),
      track(id: 'd', width: 854, height: 480, bitrate: 1129000),
    ]);

    expect(rungs.map((t) => t.id), ['c', 'd']);
  });

  test('highest first, because that is what the menu is opened for', () {
    final rungs = distinctQualityRungs([
      track(id: 'low', width: 426, height: 240, bitrate: 300000),
      track(id: 'high', width: 1920, height: 1080, bitrate: 4000000),
      track(id: 'mid', width: 1280, height: 720, bitrate: 1500000),
    ]);

    expect(rungs.map((t) => t.id), ['high', 'mid', 'low']);
  });

  test('renditions with no readable size are kept apart, not merged', () {
    final rungs = distinctQualityRungs([
      track(id: 'x'),
      track(id: 'y'),
    ]);

    expect(rungs.length, 2);
  });

  group('the bitrate beside each rung', () {
    late FakeEngine engine;
    late FPlayerController controller;

    final tracks = FTracks(
      video: [
        track(id: 'v1080', width: 1920, height: 1080, bitrate: 2400000),
        track(id: 'v720', width: 1280, height: 720, bitrate: 1232000),
      ],
    );

    setUp(() {
      engine = FakeEngine();
      controller = quietController(engine);
    });

    tearDown(() => controller.dispose());

    Future<void> openQuality(WidgetTester tester, FUiConfig config) async {
      await pumpPlayer(tester, controller: controller, config: config);
      await controller.open(const FPlayerSource.network('https://example.com/a.m3u8'));
      engine.becomeReady();
      engine.emit(FEngineTracksChanged(tracks));
      await tester.pump();

      uiOf(tester).openPanel(FPlayerPanel.quality);
      await tester.pumpAndSettle();
    }

    testWidgets('is there by default', (tester) async {
      await openQuality(tester, const FUiConfig(showControlsOnStart: true));

      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('2400 kbps'), findsOneWidget);
      expect(find.text('1232 kbps'), findsOneWidget);

      await settlePlayer(tester);
    });

    testWidgets('goes away when the config says so, leaving the rungs', (tester) async {
      await openQuality(
        tester,
        const FUiConfig(showControlsOnStart: true, showQualityBitrate: false),
      );

      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.textContaining('kbps'), findsNothing);

      await settlePlayer(tester);
    });
  });
}
