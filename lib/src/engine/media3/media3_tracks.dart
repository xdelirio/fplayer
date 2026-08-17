import '../../models/track.dart';

/// Rebuilds the [FTracks] snapshot from the map the native side sends.
///
/// Kept out of the engine class so the wire decoding stays readable and testable on its own.
FTracks decodeTracks(Map<Object?, Object?> map) => FTracks(
      audio: _list(map['audio'], _audio),
      text: _list(map['text'], _text),
      video: _list(map['video'], _video),
      isTextDisabled: map['isTextDisabled'] as bool? ?? true,
      isVideoAuto: map['isVideoAuto'] as bool? ?? true,
    );

List<T> _list<T>(Object? raw, T Function(Map<Object?, Object?>) build) => [
      for (final entry in (raw as List<Object?>? ?? const []))
        if (entry is Map) build(entry.cast<Object?, Object?>()),
    ];

FAudioTrack _audio(Map<Object?, Object?> m) => FAudioTrack(
      id: m['id']! as String,
      index: (m['index'] as num?)?.toInt() ?? 0,
      label: m['label'] as String?,
      language: m['language'] as String?,
      isSelected: m['isSelected'] as bool? ?? false,
      isActive: m['isActive'] as bool? ?? false,
      isSupported: m['isSupported'] as bool? ?? true,
      isDefault: m['isDefault'] as bool? ?? false,
      codecs: m['codecs'] as String?,
      bitrate: _int(m['bitrate']),
      sampleRate: _int(m['sampleRate']),
      channelCount: _int(m['channelCount']),
      isDescriptive: m['isDescriptive'] as bool? ?? false,
    );

FTextTrack _text(Map<Object?, Object?> m) => FTextTrack(
      id: m['id']! as String,
      index: (m['index'] as num?)?.toInt() ?? 0,
      label: m['label'] as String?,
      language: m['language'] as String?,
      isSelected: m['isSelected'] as bool? ?? false,
      isActive: m['isActive'] as bool? ?? false,
      isSupported: m['isSupported'] as bool? ?? true,
      isDefault: m['isDefault'] as bool? ?? false,
      mimeType: m['mimeType'] as String?,
      isForced: m['isForced'] as bool? ?? false,
      isClosedCaption: m['isClosedCaption'] as bool? ?? false,
    );

FVideoTrack _video(Map<Object?, Object?> m) => FVideoTrack(
      id: m['id']! as String,
      index: (m['index'] as num?)?.toInt() ?? 0,
      label: m['label'] as String?,
      language: m['language'] as String?,
      isSelected: m['isSelected'] as bool? ?? false,
      isActive: m['isActive'] as bool? ?? false,
      isSupported: m['isSupported'] as bool? ?? true,
      isDefault: m['isDefault'] as bool? ?? false,
      codecs: m['codecs'] as String?,
      bitrate: _int(m['bitrate']),
      width: _int(m['width']),
      height: _int(m['height']),
      frameRate: (m['frameRate'] as num?)?.toDouble(),
    );

int? _int(Object? value) => (value as num?)?.toInt();
