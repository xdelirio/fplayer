import 'package:flutter/foundation.dart';

/// Which renditions of an adaptive stream to put on disk.
///
/// Downloading is not streaming: there is no bandwidth to adapt to once the file is local, so
/// pulling the whole quality ladder spends the user's data and storage on renditions that will
/// never be played. The defaults take one video rendition and only the languages asked for.
///
/// Ignored for progressive media, which has nothing to choose between.
@immutable
class FDownloadSelection {
  const FDownloadSelection({
    this.maxHeight,
    this.maxBitrate,
    this.audioLanguages = const [],
    this.textLanguages = const [],
    this.allAudioLanguages = false,
    this.allTextLanguages = false,
  });

  /// A sensible offline copy: up to 720p, plus whichever languages the caller names.
  ///
  /// 720p is the point where a phone screen stops showing the difference and the file size stops
  /// being polite about it.
  const FDownloadSelection.standard({
    List<String> audioLanguages = const [],
    List<String> textLanguages = const [],
  }) : this(
          maxHeight: 720,
          audioLanguages: audioLanguages,
          textLanguages: textLanguages,
        );

  /// The best video the stream offers, and every audio and subtitle track with it.
  const FDownloadSelection.everything()
      : maxHeight = null,
        maxBitrate = null,
        audioLanguages = const [],
        textLanguages = const [],
        allAudioLanguages = true,
        allTextLanguages = true;

  /// Ceiling on the video rendition's height, in pixels. Null takes the highest available.
  final int? maxHeight;

  /// Ceiling on the video rendition's bitrate, in bits per second.
  final int? maxBitrate;

  /// Audio languages to include, as BCP-47 tags. Empty takes the stream's default track.
  final List<String> audioLanguages;

  /// Subtitle languages to include, as BCP-47 tags. Empty takes no subtitles.
  ///
  /// Subtitles are cheap in bytes but are not downloaded by accident: an app that never shows a
  /// picker should not ship six languages the user cannot reach.
  final List<String> textLanguages;

  /// Take every audio language, ignoring [audioLanguages].
  final bool allAudioLanguages;

  /// Take every subtitle language, ignoring [textLanguages].
  final bool allTextLanguages;

  FDownloadSelection copyWith({
    int? maxHeight,
    int? maxBitrate,
    List<String>? audioLanguages,
    List<String>? textLanguages,
    bool? allAudioLanguages,
    bool? allTextLanguages,
  }) =>
      FDownloadSelection(
        maxHeight: maxHeight ?? this.maxHeight,
        maxBitrate: maxBitrate ?? this.maxBitrate,
        audioLanguages: audioLanguages ?? this.audioLanguages,
        textLanguages: textLanguages ?? this.textLanguages,
        allAudioLanguages: allAudioLanguages ?? this.allAudioLanguages,
        allTextLanguages: allTextLanguages ?? this.allTextLanguages,
      );

  Map<String, Object?> toMap() => {
        'maxHeight': maxHeight,
        'maxBitrate': maxBitrate,
        'audioLanguages': audioLanguages,
        'textLanguages': textLanguages,
        'allAudioLanguages': allAudioLanguages,
        'allTextLanguages': allTextLanguages,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FDownloadSelection &&
          other.maxHeight == maxHeight &&
          other.maxBitrate == maxBitrate &&
          other.allAudioLanguages == allAudioLanguages &&
          other.allTextLanguages == allTextLanguages &&
          listEquals(other.audioLanguages, audioLanguages) &&
          listEquals(other.textLanguages, textLanguages);

  @override
  int get hashCode => Object.hash(
        maxHeight,
        maxBitrate,
        allAudioLanguages,
        allTextLanguages,
        Object.hashAll(audioLanguages),
        Object.hashAll(textLanguages),
      );
}
