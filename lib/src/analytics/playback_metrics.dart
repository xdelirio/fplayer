import 'package:flutter/foundation.dart';

/// Why a playback session stopped being measured.
enum FSessionEndReason {
  /// Playback reached the end of the media.
  completed,

  /// A different source was opened on the same controller.
  sourceChanged,

  /// Playback failed and did not recover.
  error,

  /// The tracker, or the controller behind it, was torn down.
  disposed,
}

/// Everything measured about one playback session, accumulated from its start.
///
/// Cumulative rather than incremental: a snapshot is meaningful on its own, and a reporter that
/// needs deltas can diff two snapshots. The reverse — reconstructing totals from a stream of
/// deltas — breaks the moment one report is lost, which on a mobile network is routine.
@immutable
class FPlaybackMetrics {
  const FPlaybackMetrics({
    required this.sessionId,
    required this.startedAt,
    required this.updatedAt,
    this.contentTitle,
    this.sourceMetadata,
    this.watchedTime = Duration.zero,
    this.wallClockTime = Duration.zero,
    this.timeToFirstFrame,
    this.rebufferCount = 0,
    this.rebufferTime = Duration.zero,
    this.seekCount = 0,
    this.qualityChangeCount = 0,
    this.retryCount = 0,
    this.errorCount = 0,
    this.position = Duration.zero,
    this.duration,
    this.isLive = false,
    this.averageBitrate,
    this.averageVideoHeight,
    this.peakVideoHeight,
    this.bytesDownloaded,
    this.droppedFrames,
  });

  /// Time-sortable identifier, one per session. See `FSessionId`.
  final String sessionId;

  final DateTime startedAt;

  /// When these numbers were last recomputed.
  final DateTime updatedAt;

  final String? contentTitle;

  /// Whatever the app attached to `FPlayerSource.metadata` — content ids, campaign tags.
  ///
  /// The player never interprets it; it is carried here so a reporter can label the session
  /// without keeping its own map from controller to content.
  final Object? sourceMetadata;

  /// Content actually consumed, adjusted for playback speed.
  ///
  /// Ten wall-clock seconds at 2× count as twenty: the viewer got through twenty seconds of the
  /// programme. Pauses and stalls contribute nothing.
  final Duration watchedTime;

  /// Real time elapsed since the session started, including pauses.
  final Duration wallClockTime;

  /// How long the viewer waited before the picture appeared. Null until it does.
  final Duration? timeToFirstFrame;

  /// Stalls after playback had already started. The initial load is startup, not a rebuffer.
  final int rebufferCount;

  final Duration rebufferTime;

  final int seekCount;

  /// Adaptive switches plus manual quality picks.
  final int qualityChangeCount;

  /// Failures the player recovered from by retrying.
  final int retryCount;

  /// Failures surfaced to the viewer, after retries were exhausted.
  final int errorCount;

  /// Position when this snapshot was taken.
  final Duration position;

  final Duration? duration;

  final bool isLive;

  /// Mean video bitrate weighted by how long each rendition was on screen, in bits per second.
  ///
  /// Weighted rather than averaged over switches, because a ladder that spends fifty-nine minutes
  /// at 1080p and one at 240p is not "660p on average".
  final int? averageBitrate;

  /// Mean video height weighted the same way.
  final double? averageVideoHeight;

  /// Tallest rendition that actually played.
  final int? peakVideoHeight;

  /// Bytes pulled over the network for this session.
  ///
  /// Always null for now: the figure lives in the engine's own loader statistics and needs a
  /// native bridge that does not exist yet. Reported as absent rather than estimated, because a
  /// made-up byte count is worse than none for a data-usage feature.
  final int? bytesDownloaded;

  /// Frames the renderer had to drop to keep up.
  ///
  /// Null for the same reason as [bytesDownloaded].
  final int? droppedFrames;

  /// How far through the media the viewer got, 0 to 1. Null when there is nothing to divide by.
  double? get completionRatio {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0) return null;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Share of the session spent waiting for data, 0 to 1.
  ///
  /// The number a quality-of-experience dashboard actually plots: raw stall seconds mean nothing
  /// without knowing how long the session ran.
  double get rebufferRatio {
    final playing = watchedTime.inMilliseconds + rebufferTime.inMilliseconds;
    if (playing <= 0) return 0;
    return rebufferTime.inMilliseconds / playing;
  }

  FPlaybackMetrics copyWith({
    DateTime? updatedAt,
    Duration? watchedTime,
    Duration? wallClockTime,
    Duration? timeToFirstFrame,
    int? rebufferCount,
    Duration? rebufferTime,
    int? seekCount,
    int? qualityChangeCount,
    int? retryCount,
    int? errorCount,
    Duration? position,
    Duration? duration,
    bool? isLive,
    int? averageBitrate,
    double? averageVideoHeight,
    int? peakVideoHeight,
  }) =>
      FPlaybackMetrics(
        sessionId: sessionId,
        startedAt: startedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        contentTitle: contentTitle,
        sourceMetadata: sourceMetadata,
        watchedTime: watchedTime ?? this.watchedTime,
        wallClockTime: wallClockTime ?? this.wallClockTime,
        timeToFirstFrame: timeToFirstFrame ?? this.timeToFirstFrame,
        rebufferCount: rebufferCount ?? this.rebufferCount,
        rebufferTime: rebufferTime ?? this.rebufferTime,
        seekCount: seekCount ?? this.seekCount,
        qualityChangeCount: qualityChangeCount ?? this.qualityChangeCount,
        retryCount: retryCount ?? this.retryCount,
        errorCount: errorCount ?? this.errorCount,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        isLive: isLive ?? this.isLive,
        averageBitrate: averageBitrate ?? this.averageBitrate,
        averageVideoHeight: averageVideoHeight ?? this.averageVideoHeight,
        peakVideoHeight: peakVideoHeight ?? this.peakVideoHeight,
        bytesDownloaded: bytesDownloaded,
        droppedFrames: droppedFrames,
      );

  @override
  String toString() => 'FPlaybackMetrics($sessionId, watched: $watchedTime, '
      'stalls: $rebufferCount/$rebufferTime, startup: $timeToFirstFrame)';
}
