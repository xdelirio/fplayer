import 'package:fplayer/fplayer.dart';
import 'package:fvp/mdk.dart' as mdk;

/// Turns libmdk's stream list into the track model the rest of the package speaks.
///
/// Track ids are `type:index`, where the index is libmdk's own stream index — which is what
/// `Player.activeAudioTracks` and friends take. That keeps selection a lookup rather than a
/// search, and the id stays valid for as long as the media is loaded.
FTracks decodeFvpTracks(
  mdk.MediaInfo info, {
  required List<int> activeAudio,
  required List<int> activeVideo,
  required List<int> activeText,
  required bool isTextDisabled,
}) {
  final audio = <FAudioTrack>[];
  final text = <FTextTrack>[];
  final video = <FVideoTrack>[];

  info.audio?.forEachIndexed((index, stream) {
    final isSelected = activeAudio.contains(stream.index);
    audio.add(
      FAudioTrack(
        id: 'audio:${stream.index}',
        index: index,
        label: stream.metadata['title'],
        language: _language(stream.metadata),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: index == 0,
        codecs: stream.codec.codec,
        bitrate: stream.codec.bitRate.orNull(),
        sampleRate: stream.codec.sampleRate.orNull(),
        channelCount: stream.codec.channels.orNull(),
      ),
    );
  });

  info.subtitle?.forEachIndexed((index, stream) {
    final isSelected = !isTextDisabled && activeText.contains(stream.index);
    text.add(
      FTextTrack(
        id: 'text:${stream.index}',
        index: index,
        label: stream.metadata['title'],
        language: _language(stream.metadata),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: index == 0,
        mimeType: stream.codec.codec,
      ),
    );
  });

  info.video?.forEachIndexed((index, stream) {
    final isSelected = activeVideo.contains(stream.index);
    video.add(
      FVideoTrack(
        id: 'video:${stream.index}',
        index: index,
        label: stream.metadata['title'],
        language: _language(stream.metadata),
        isSelected: isSelected,
        isActive: isSelected,
        isSupported: true,
        isDefault: index == 0,
        codecs: stream.codec.codec,
        bitrate: stream.codec.bitRate.orNull(),
        width: stream.codec.width.orNull(),
        height: stream.codec.height.orNull(),
        frameRate: stream.codec.frameRate > 0 ? stream.codec.frameRate : null,
      ),
    );
  });

  return FTracks(
    audio: audio,
    text: text,
    video: video,
    isTextDisabled: isTextDisabled,
    // libmdk plays the streams a container holds; there is no ladder to adapt between, so the
    // video "tracks" are alternate streams, never bitrate rungs. Calling that auto would promise
    // an adaptation that never happens.
    isVideoAuto: false,
  );
}

/// Stream index of the track [id] refers to, or null when it names nothing here.
int? fvpStreamIndexOf(String? id) {
  if (id == null) return null;
  final parts = id.split(':');
  if (parts.length != 2) return null;
  return int.tryParse(parts[1]);
}

/// Container metadata spells the language key either way depending on the muxer.
String? _language(Map<String, String> metadata) {
  final value = metadata['language'] ?? metadata['LANGUAGE'] ?? metadata['lang'];
  if (value == null || value.isEmpty || value == 'und') return null;
  return value;
}

extension on int {
  int? orNull() => this > 0 ? this : null;
}

extension<T> on List<T> {
  void forEachIndexed(void Function(int index, T value) action) {
    for (var i = 0; i < length; i++) {
      action(i, this[i]);
    }
  }
}
