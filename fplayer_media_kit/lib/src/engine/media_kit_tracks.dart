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
  Map<String, List<String>> audioNames = const {},
  Map<String, List<String>> textNames = const {},
  Map<String, ({bool isForced, bool isClosedCaption})> textRoles = const {},
}) {
  // How many tracks of each language have been seen, so the nth one takes the nth name the
  // manifest gives that language. See [manifestNameFor].
  final seenAudio = <String?, int>{};
  final seenText = <String?, int>{};
  String? labelOf(
    String? title,
    String? language,
    Map<String, List<String>> names,
    Map<String?, int> seen,
  ) {
    final occurrence = seen[language] = (seen[language] ?? -1) + 1;
    if (title != null && title.isNotEmpty) return title;
    return manifestNameFor(names, language, occurrence);
  }

  final audio = <FAudioTrack>[];
  final text = <FTextTrack>[];
  final video = <FVideoTrack>[];

  for (final stream in tracks.audio.where((s) => isRealTrackId(s.id))) {
    final isSelected = stream.id == activeAudio;
    audio.add(
      FAudioTrack(
        id: stream.id,
        index: audio.length,
        label: labelOf(stream.title, stream.language, audioNames, seenAudio),
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
        label: labelOf(stream.title, stream.language, textNames, seenText),
        language: _language(stream.language),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: stream.isDefault ?? text.isEmpty,
        mimeType: stream.codec,
        isForced: textRoles[stream.id]?.isForced ?? false,
        isClosedCaption: textRoles[stream.id]?.isClosedCaption ?? false,
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

/// The name a manifest gives the [occurrence]th track in [language], counting from zero.
///
/// FFmpeg opens renditions in manifest order, so the nth track in a language is the nth one the
/// manifest lists in it. Past the end — one rendition listed once per HLS group but opened once
/// per variant — the last name is the right one.
String? manifestNameFor(Map<String, List<String>> names, String? language, int occurrence) {
  final candidates = names[language];
  if (candidates == null || candidates.isEmpty) return null;
  return candidates[occurrence < candidates.length ? occurrence : candidates.length - 1];
}

/// Whether [id] names a stream in the media, rather than one of mpv's selection keywords.
bool isRealTrackId(String id) => id != 'auto' && id != 'no';

/// mpv reports the language as it appears in the container, `und` included.
String? _language(String? value) => value == null || value.isEmpty || value == 'und' ? null : value;

extension on int? {
  int? orNull() => this == null || this! <= 0 ? null : this;
}
