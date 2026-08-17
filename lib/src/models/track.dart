import 'package:flutter/foundation.dart';

/// Kind of media a track carries.
enum FTrackType { audio, text, video }

/// One selectable track exposed by the media.
///
/// Tracks come from the manifest (HLS renditions, DASH adaptation sets) or from container
/// metadata, plus any external subtitle files attached to the source. They are re-read every time
/// the engine reports a change, so hold the [id], not the object.
@immutable
sealed class FTrack {
  const FTrack({
    required this.id,
    required this.index,
    required this.label,
    required this.language,
    required this.isSelected,
    required this.isActive,
    required this.isSupported,
    required this.isDefault,
  });

  /// Opaque handle used to select this track. Stable only until the track list changes.
  ///
  /// Never show it to a user — it is an engine detail.
  final String id;

  /// Position among the tracks of the same type, from zero. Used to name unlabelled tracks.
  final int index;

  /// Human-readable name from the manifest, when the packager set one.
  final String? label;

  /// BCP-47 language tag.
  final String? language;

  /// Whether this track is part of the engine's current selection.
  ///
  /// For audio and subtitles that means exactly one track. For video in adaptive mode it means
  /// the whole quality ladder is eligible, so this is true for several tracks at once — use
  /// [isActive] to find the one on screen.
  final bool isSelected;

  /// Whether this is the track being decoded right now.
  final bool isActive;

  /// Whether this device can decode it. Unsupported tracks are still listed so the UI can grey
  /// them out instead of silently hiding content the user expects to see.
  final bool isSupported;

  /// Whether the manifest marks this track as the default choice.
  final bool isDefault;

  FTrackType get type;

  /// Neutral name used when the manifest labels nothing. English by design: a package cannot
  /// know the app's locale, and apps that care should build their own labels from [language].
  String get defaultName;

  /// Best available name for a picker: the manifest's label, then the language tag, then a
  /// generic numbered name. Never the [id].
  String get displayName => label ?? language ?? defaultName;

  /// Compares everything a picker or a summary reads, not just identity and selection.
  ///
  /// A manifest refresh routinely re-sends the same track with a better label or a corrected
  /// bitrate. With those left out, the new list compared equal to the old one and the fresher
  /// metadata was thrown away — the quality summary and the track names stayed stale for the
  /// rest of the session.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FTrack &&
          other.runtimeType == runtimeType &&
          other.id == id &&
          other.index == index &&
          other.label == label &&
          other.language == language &&
          other.isSelected == isSelected &&
          other.isActive == isActive &&
          other.isSupported == isSupported &&
          other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        id,
        index,
        label,
        language,
        isSelected,
        isActive,
        isSupported,
        isDefault,
      );
}

/// An audio rendition: a language, a codec, a channel layout.
final class FAudioTrack extends FTrack {
  const FAudioTrack({
    required super.id,
    required super.index,
    required super.label,
    required super.language,
    required super.isSelected,
    required super.isActive,
    required super.isSupported,
    required super.isDefault,
    this.codecs,
    this.bitrate,
    this.sampleRate,
    this.channelCount,
    this.isDescriptive = false,
  });

  final String? codecs;

  /// Bits per second, when the manifest declares it.
  final int? bitrate;

  final int? sampleRate;

  /// 1 mono, 2 stereo, 6 for 5.1, and so on.
  final int? channelCount;

  /// Audio description for viewers with low vision.
  final bool isDescriptive;

  @override
  FTrackType get type => FTrackType.audio;

  @override
  String get defaultName => 'Audio ${index + 1}';

  /// Short channel layout label, e.g. `5.1`. Null when the count is unknown.
  String? get channelLabel => switch (channelCount) {
        1 => 'Mono',
        2 => 'Stereo',
        6 => '5.1',
        8 => '7.1',
        null => null,
        _ => '$channelCount ch',
      };
}

/// A subtitle or caption track, whether muxed in the media or attached as a separate file.
final class FTextTrack extends FTrack {
  const FTextTrack({
    required super.id,
    required super.index,
    required super.label,
    required super.language,
    required super.isSelected,
    required super.isActive,
    required super.isSupported,
    required super.isDefault,
    this.mimeType,
    this.isForced = false,
    this.isClosedCaption = false,
  });

  final String? mimeType;

  /// Forced narrative: meant to be shown even when subtitles are off, for foreign dialogue.
  final bool isForced;

  /// Captions for deaf and hard-of-hearing viewers, including sound descriptions.
  final bool isClosedCaption;

  @override
  FTrackType get type => FTrackType.text;

  @override
  String get defaultName => 'Subtitle ${index + 1}';
}

/// One quality level of the video. Selecting one pins the quality; leaving it unset lets the
/// engine adapt to bandwidth.
final class FVideoTrack extends FTrack {
  const FVideoTrack({
    required super.id,
    required super.index,
    required super.label,
    required super.language,
    required super.isSelected,
    required super.isActive,
    required super.isSupported,
    required super.isDefault,
    this.codecs,
    this.bitrate,
    this.width,
    this.height,
    this.frameRate,
  });

  final String? codecs;
  final int? bitrate;
  final int? width;
  final int? height;
  final double? frameRate;

  @override
  FTrackType get type => FTrackType.video;

  /// Standard rungs a quality menu is expected to show.
  static const List<int> _ladder = [144, 240, 360, 480, 720, 1080, 1440, 2160, 4320];

  /// Conventional quality name: `1080p`, `720p`…
  ///
  /// Not simply the pixel height. Cinematic content is wider than 16:9, so a 1680×750 rendition
  /// has the detail of 1080p while its height would call it "750p" — a label no viewer
  /// recognises. Wide frames are normalised to their 16:9 equivalent height and snapped to the
  /// nearest standard rung. Use [width] and [height] directly if you need the raw numbers.
  String? get qualityLabel {
    final h = height;
    if (h == null) return null;

    final w = width;
    final equivalent = (w != null && w * 9 / 16 > h) ? (w * 9 / 16).round() : h;

    final nearest = _ladder.reduce(
      (a, b) => (a - equivalent).abs() <= (b - equivalent).abs() ? a : b,
    );
    return '${nearest}p';
  }

  @override
  String get defaultName => 'Quality ${index + 1}';

  @override
  String get displayName => label ?? qualityLabel ?? defaultName;
}

/// Every track the current media exposes, grouped by type.
@immutable
class FTracks {
  const FTracks({
    this.audio = const [],
    this.text = const [],
    this.video = const [],
    this.isTextDisabled = true,
    this.isVideoAuto = true,
  });

  static const FTracks empty = FTracks();

  final List<FAudioTrack> audio;
  final List<FTextTrack> text;
  final List<FVideoTrack> video;

  /// Whether subtitles are switched off entirely, as opposed to no text track being available.
  final bool isTextDisabled;

  /// Whether video quality is left to the adaptive selector rather than pinned.
  final bool isVideoAuto;

  /// The audio track being heard.
  FAudioTrack? get selectedAudio =>
      audio.where((t) => t.isActive).firstOrNull ??
      audio.where((t) => t.isSelected).firstOrNull;

  /// The subtitle track being displayed, or null when subtitles are off.
  FTextTrack? get selectedText =>
      isTextDisabled ? null : text.where((t) => t.isSelected).firstOrNull;

  /// The quality on screen right now. In adaptive mode this changes as bandwidth changes.
  ///
  /// Show it next to "Auto" so viewers can see what they are actually getting.
  FVideoTrack? get activeVideo => video.where((t) => t.isActive).firstOrNull;

  /// The quality the user pinned, or null when the engine is choosing.
  ///
  /// Use it to tick the right row in a quality menu; use [activeVideo] to label what is playing.
  FVideoTrack? get selectedVideo =>
      isVideoAuto ? null : video.where((t) => t.isSelected).firstOrNull;

  bool get hasSubtitles => text.isNotEmpty;

  bool get hasMultipleAudioTracks => audio.length > 1;

  /// Whether there is a real quality choice to offer the user.
  bool get hasMultipleQualities => video.length > 1;

  bool get isEmpty => audio.isEmpty && text.isEmpty && video.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FTracks &&
          other.isTextDisabled == isTextDisabled &&
          other.isVideoAuto == isVideoAuto &&
          listEquals(other.audio, audio) &&
          listEquals(other.text, text) &&
          listEquals(other.video, video);

  @override
  int get hashCode => Object.hash(
        isTextDisabled,
        isVideoAuto,
        Object.hashAll(audio),
        Object.hashAll(text),
        Object.hashAll(video),
      );

  @override
  String toString() =>
      'FTracks(audio: ${audio.length}, text: ${text.length}, video: ${video.length})';
}
