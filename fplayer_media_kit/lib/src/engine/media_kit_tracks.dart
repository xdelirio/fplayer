import 'package:fplayer/fplayer.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Turns mpv's track list into the track model the rest of the package speaks.
///
/// Track ids are mpv's own — `"1"`, `"2"` — which is what `vid`, `aid` and `sid` take and report,
/// so selection is a lookup and the id stays valid for as long as the media is loaded. The
/// `auto` and `no` placeholders media_kit prepends to every list are not tracks and are dropped.
FTracks decodeMediaKitTracks(
  mk.Tracks tracks, {
  required String? activeVideo,
  required String? activeAudio,
  required String? activeText,
  required bool isTextDisabled,
}) {
  final audio = <FAudioTrack>[];
  final text = <FTextTrack>[];
  final video = <FVideoTrack>[];

  for (final stream in tracks.audio.where((s) => isRealTrackId(s.id))) {
    final isSelected = stream.id == activeAudio;
    audio.add(
      FAudioTrack(
        id: stream.id,
        index: audio.length,
        label: stream.title,
        language: _language(stream.language),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: stream.isDefault ?? audio.isEmpty,
        codecs: stream.codec,
        bitrate: stream.bitrate.orNull(),
        sampleRate: stream.samplerate.orNull(),
        channelCount: stream.channelscount.orNull(),
      ),
    );
  }

  for (final stream in tracks.subtitle.where((s) => isRealTrackId(s.id))) {
    final isSelected = !isTextDisabled && stream.id == activeText;
    text.add(
      FTextTrack(
        id: stream.id,
        index: text.length,
        label: stream.title,
        language: _language(stream.language),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: stream.isDefault ?? text.isEmpty,
        mimeType: stream.codec,
      ),
    );
  }

  // Cover art rides along as a video stream of one still frame. Listing it as a rung of the
  // quality menu would offer the viewer a picture of the album.
  for (final stream in tracks.video.where((s) => isRealTrackId(s.id) && s.albumart != true)) {
    final isSelected = stream.id == activeVideo;
    video.add(
      FVideoTrack(
        id: stream.id,
        index: video.length,
        label: stream.title,
        language: _language(stream.language),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: stream.isDefault ?? video.isEmpty,
        codecs: stream.codec,
        bitrate: stream.bitrate.orNull(),
        width: stream.w.orNull(),
        height: stream.h.orNull(),
        frameRate: (stream.fps ?? 0) > 0 ? stream.fps : null,
      ),
    );
  }

  return FTracks(
    audio: audio,
    text: text,
    video: video,
    isTextDisabled: isTextDisabled,
    // mpv plays the variant it picked at load time and stays on it; the video "tracks" are
    // alternate streams, never a ladder it adapts between. Calling that auto would promise an
    // adaptation that never happens.
    isVideoAuto: false,
  );
}

/// Whether [id] names a stream in the media, rather than one of mpv's selection keywords.
bool isRealTrackId(String id) => id != 'auto' && id != 'no';

/// mpv reports the language as it appears in the container, `und` included.
String? _language(String? value) => value == null || value.isEmpty || value == 'und' ? null : value;

extension on int? {
  int? orNull() => this == null || this! <= 0 ? null : this;
}
