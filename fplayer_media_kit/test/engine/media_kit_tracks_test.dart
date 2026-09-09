import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';
import 'package:fplayer_media_kit/src/engine/media_kit_tracks.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// What media_kit hands over for a file with two audio languages, one subtitle and a cover.
final mk.Tracks _sample = mk.Tracks(
  video: [
    mk.VideoTrack.auto(),
    mk.VideoTrack.no(),
    const mk.VideoTrack('1', null, null, codec: 'h264', w: 1920, h: 1080, fps: 23.976),
    const mk.VideoTrack('2', 'cover', null, albumart: true, w: 600, h: 600),
  ],
  audio: [
    mk.AudioTrack.auto(),
    mk.AudioTrack.no(),
    const mk.AudioTrack('1', 'Español', 'spa', isDefault: true, codec: 'aac', channelscount: 2),
    const mk.AudioTrack('2', null, 'und', codec: 'ac3', channelscount: 6, bitrate: 0),
  ],
  subtitle: [
    mk.SubtitleTrack.auto(),
    mk.SubtitleTrack.no(),
    const mk.SubtitleTrack('1', 'Forced', 'eng', codec: 'subrip'),
  ],
);

void main() {
  group('decodeMediaKitTracks', () {
    test('drops the auto and no placeholders and keeps mpv ids', () {
      final tracks = decodeMediaKitTracks(
        _sample,
        activeVideo: '1',
        activeAudio: '1',
        activeText: null,
        isTextDisabled: true,
      );

      expect(tracks.audio.map((t) => t.id), ['1', '2']);
      expect(tracks.audio.map((t) => t.index), [0, 1]);
      expect(tracks.text.map((t) => t.id), ['1']);
    });

    test('leaves cover art out of the video list', () {
      final tracks = decodeMediaKitTracks(
        _sample,
        activeVideo: '1',
        activeAudio: '1',
        activeText: null,
        isTextDisabled: true,
      );

      expect(tracks.video.map((t) => t.id), ['1']);
      expect(tracks.video.single.width, 1920);
      expect(tracks.video.single.frameRate, closeTo(23.976, 0.001));
      expect(tracks.isVideoAuto, isFalse);
    });

    test('marks what mpv reports as selected', () {
      final tracks = decodeMediaKitTracks(
        _sample,
        activeVideo: '1',
        activeAudio: '2',
        activeText: '1',
        isTextDisabled: false,
      );

      expect(tracks.audio.map((t) => t.isSelected), [false, true]);
      expect(tracks.audio.map((t) => t.isActive), [false, true]);
      expect(tracks.text.single.isSelected, isTrue);
      expect(tracks.isTextDisabled, isFalse);
    });

    test('a subtitle mpv has selected still reads as off while subtitles are disabled', () {
      final tracks = decodeMediaKitTracks(
        _sample,
        activeVideo: '1',
        activeAudio: '1',
        activeText: '1',
        isTextDisabled: true,
      );

      expect(tracks.text.single.isSelected, isFalse);
      expect(tracks.isTextDisabled, isTrue);
    });

    test('normalises metadata the container leaves blank', () {
      final tracks = decodeMediaKitTracks(
        _sample,
        activeVideo: null,
        activeAudio: null,
        activeText: null,
        isTextDisabled: true,
      );

      final surround = tracks.audio[1];
      expect(surround.language, isNull, reason: 'und is not a language');
      expect(surround.label, isNull);
      expect(surround.bitrate, isNull, reason: 'zero is unknown, not a bitrate');
      expect(surround.channelCount, 6);
      expect(tracks.audio.first.isDefault, isTrue);
      expect(tracks.audio.first.language, 'spa');
      expect(tracks.text.single, isA<FTextTrack>().having((t) => t.mimeType, 'mimeType', 'subrip'));
    });
  });

  test('isRealTrackId', () {
    expect(isRealTrackId('auto'), isFalse);
    expect(isRealTrackId('no'), isFalse);
    expect(isRealTrackId('1'), isTrue);
  });
}
