import 'package:flutter/foundation.dart';

import '../models/track.dart';

/// One rendition a download could include.
///
/// Deliberately not `FTrack`: that model carries `isSelected` and `isActive`, which describe a
/// player that is running. Nothing is playing here — this is a menu.
@immutable
class FDownloadTrack {
  const FDownloadTrack({
    required this.type,
    required this.groupIndex,
    required this.trackIndex,
    this.label,
    this.language,
    this.codecs,
    this.bitrate,
    this.width,
    this.height,
    this.estimatedBytes,
  });

  factory FDownloadTrack.fromMap(Map<Object?, Object?> map) => FDownloadTrack(
        type: _typeByName[map['type']] ?? FTrackType.video,
        groupIndex: (map['groupIndex'] as num?)?.toInt() ?? 0,
        trackIndex: (map['trackIndex'] as num?)?.toInt() ?? 0,
        label: map['label'] as String?,
        language: map['language'] as String?,
        codecs: map['codecs'] as String?,
        bitrate: _positive(map['bitrate']),
        width: _positive(map['width']),
        height: _positive(map['height']),
        estimatedBytes: _positive(map['estimatedBytes']),
      );

  final FTrackType type;

  /// Where this rendition sits in the manifest. Together the two indices identify it.
  final int groupIndex;
  final int trackIndex;

  final String? label;
  final String? language;
  final String? codecs;
  final int? bitrate;
  final int? width;
  final int? height;

  /// Rough size on disk, from bitrate times duration.
  ///
  /// An estimate, not a promise: variable-bitrate content lands within a few percent, and live or
  /// unbounded media reports null. Good enough to label a menu, not to reserve storage.
  final int? estimatedBytes;

  /// `1080p`, `720p`… for video renditions.
  String? get qualityLabel {
    final h = height;
    if (h == null) return null;
    final w = width;
    // Cinematic content is wider than 16:9, so its pixel height under-reports the detail level.
    final equivalent = (w != null && w * 9 / 16 > h) ? (w * 9 / 16).round() : h;
    const ladder = [144, 240, 360, 480, 720, 1080, 1440, 2160, 4320];
    final nearest = ladder.reduce(
      (a, b) => (a - equivalent).abs() <= (b - equivalent).abs() ? a : b,
    );
    return '${nearest}p';
  }

  /// Best available name for a menu row.
  String get displayName => label ?? qualityLabel ?? language ?? 'Track ${trackIndex + 1}';

  static const Map<Object?, FTrackType> _typeByName = {
    'audio': FTrackType.audio,
    'text': FTrackType.text,
    'video': FTrackType.video,
  };

  static int? _positive(Object? value) {
    final number = (value as num?)?.toInt();
    return number != null && number > 0 ? number : null;
  }

  @override
  String toString() => 'FDownloadTrack(${type.name}, $displayName)';
}

/// What a source offers to a download, read from its manifest.
///
/// Produced by [FDownloadManager.inspect]. Use it to build a quality picker; skip it entirely and
/// pass an [FDownloadSelection] straight to `enqueue` if the app chooses on the user's behalf.
@immutable
class FDownloadOptions {
  const FDownloadOptions({
    this.video = const [],
    this.audio = const [],
    this.text = const [],
    this.duration,
  });

  factory FDownloadOptions.fromMap(Map<Object?, Object?> map) {
    List<FDownloadTrack> read(Object? raw) => [
          for (final entry in (raw as List<Object?>? ?? const []))
            if (entry is Map) FDownloadTrack.fromMap(entry.cast<Object?, Object?>()),
        ];

    final durationMs = (map['durationMs'] as num?)?.toInt();

    return FDownloadOptions(
      video: read(map['video']),
      audio: read(map['audio']),
      text: read(map['text']),
      duration: durationMs != null && durationMs > 0
          ? Duration(milliseconds: durationMs)
          : null,
    );
  }

  /// Video renditions, lowest quality first.
  final List<FDownloadTrack> video;
  final List<FDownloadTrack> audio;
  final List<FDownloadTrack> text;

  /// Length of the media, when the manifest declares one.
  final Duration? duration;

  /// Whether there is a real choice to put in front of the user.
  bool get hasChoice => video.length > 1 || audio.length > 1 || text.isNotEmpty;

  /// Distinct audio languages on offer.
  List<String> get audioLanguages =>
      audio.map((t) => t.language).whereType<String>().toSet().toList();

  /// Distinct subtitle languages on offer.
  List<String> get textLanguages =>
      text.map((t) => t.language).whereType<String>().toSet().toList();

  @override
  String toString() =>
      'FDownloadOptions(video: ${video.length}, audio: ${audio.length}, text: ${text.length})';
}
