import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/player_error.dart';
import '../models/player_source.dart';
import 'download_state.dart';

/// One entry in the download queue.
///
/// Self-describing on purpose: [metadata] is round-tripped through the platform's own download
/// index, so an app can rebuild a "My downloads" screen — titles, posters, episode ids — from
/// [FDownloadManager.list] alone, without keeping a parallel database in sync with it.
@immutable
class FDownloadItem {
  const FDownloadItem({
    required this.id,
    required this.uri,
    required this.state,
    required this.bytesDownloaded,
    required this.startedAt,
    required this.updatedAt,
    this.progress = 0,
    this.contentLength,
    this.error,
    this.metadata = const {},
  });

  factory FDownloadItem.fromMap(Map<Object?, Object?> map) {
    final length = (map['contentLength'] as num?)?.toInt();

    return FDownloadItem(
      id: map['id']! as String,
      uri: map['uri'] as String? ?? '',
      state: _stateByName[map['state']] ?? FDownloadState.queued,
      // Media3 reports a fraction from 0 to 100, and -1 before the size is known.
      progress: (((map['percent'] as num?)?.toDouble() ?? 0) / 100).clamp(0.0, 1.0),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      contentLength: length != null && length > 0 ? length : null,
      startedAt: _time(map['startedAtMs']),
      updatedAt: _time(map['updatedAtMs']),
      error: map['error'] == null
          ? null
          : FPlayerError.fromMap((map['error']! as Map).cast<String, Object?>()),
      metadata: _decodeMetadata(map['metadata'] as String?),
    );
  }

  /// Stable handle for this download. Defaults to the source URI when the caller does not supply
  /// one, which makes "is this episode downloaded?" a lookup rather than a scan.
  final String id;

  /// What was downloaded.
  final String uri;

  final FDownloadState state;

  /// Fraction from 0 to 1. Stays at 0 until the platform knows the total size.
  final double progress;

  final int bytesDownloaded;

  /// Total size in bytes, or null while it is still unknown.
  ///
  /// Adaptive streams often cannot report one until the manifest and every segment list have been
  /// read, so treat a null here as "still counting", not as an error.
  final int? contentLength;

  final DateTime startedAt;
  final DateTime updatedAt;

  /// Why it failed, when [state] is `FDownloadState.failed`.
  final FPlayerError? error;

  /// The payload handed to [FDownloadManager.enqueue], stored alongside the bytes.
  final Map<String, Object?> metadata;

  /// Whether the media can be played without a network.
  bool get isPlayableOffline => state == FDownloadState.completed;

  /// A source that plays this download from disk.
  ///
  /// The same URI as the original: the cache is keyed by it, so the engine reads local bytes and
  /// never touches the network. That is also why re-downloading the same URL resumes rather than
  /// starting over.
  FPlayerSource toSource({
    String? title,
    String? subtitle,
    Duration? startAt,
    List<FSubtitleSource> subtitles = const [],
  }) =>
      FPlayerSource.network(
        uri,
        title: title ?? _text('title'),
        subtitle: subtitle ?? _text('subtitle'),
        startAt: startAt,
        subtitles: subtitles,
        metadata: metadata.isEmpty ? null : metadata,
      );

  /// Metadata read defensively: the payload is JSON that round-tripped through the platform, so
  /// a title that comes back as a number is a wrong value rather than a reason to throw inside
  /// whatever list builder is drawing the downloads screen.
  String? _text(String key) {
    final value = metadata[key];
    return value is String ? value : value?.toString();
  }

  static const Map<Object?, FDownloadState> _stateByName = {
    'queued': FDownloadState.queued,
    'downloading': FDownloadState.downloading,
    'paused': FDownloadState.paused,
    'completed': FDownloadState.completed,
    'failed': FDownloadState.failed,
    'removing': FDownloadState.removing,
    'restarting': FDownloadState.restarting,
  };

  static DateTime _time(Object? milliseconds) => DateTime.fromMillisecondsSinceEpoch(
        (milliseconds as num?)?.toInt() ?? 0,
        isUtc: true,
      );

  /// Metadata travels as a JSON string because the platform stores it as opaque bytes.
  ///
  /// Anything unreadable is dropped rather than thrown: a queue entry written by an older build
  /// of the app should still list, just without its labels.
  static Map<String, Object?> _decodeMetadata(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const {};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FDownloadItem &&
          other.id == id &&
          other.state == state &&
          other.progress == progress &&
          other.bytesDownloaded == bytesDownloaded &&
          other.contentLength == contentLength &&
          other.error == error;

  @override
  int get hashCode =>
      Object.hash(id, state, progress, bytesDownloaded, contentLength, error);

  @override
  String toString() =>
      'FDownloadItem($id, ${state.name}, ${(progress * 100).toStringAsFixed(0)}%)';
}
