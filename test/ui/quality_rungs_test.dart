import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

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
}
