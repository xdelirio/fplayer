import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/player_error.dart';
import '../models/player_source.dart';
import '../models/subtitle_cue.dart';
import '../models/track.dart';
import 'player_status.dart';

/// Immutable snapshot of a player.
///
/// `FPlayerController` rebuilds one of these on every change and notifies listeners, so widgets
/// can compare snapshots instead of reading mutable fields mid-frame.
@immutable
class FPlayerValue {
  const FPlayerValue({
    this.status = FPlayerStatus.idle,
    this.source,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.bufferedAhead = Duration.zero,
    this.duration,
    this.size = Size.zero,
    this.rotationDegrees = 0,
    this.pixelAspectRatio = 1.0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.isLive = false,
    this.isSeekable = true,
    this.isLooping = false,
    this.playlist = const [],
    this.currentIndex = -1,
    this.tracks = FTracks.empty,
    this.cues = const [],
    this.isOnline = true,
    this.isWaitingForNetwork = false,
    this.isPipSupported = false,
    this.isPipActive = false,
    this.hasMediaSession = false,
    this.error,
  });

  const FPlayerValue.idle() : this();

  final FPlayerStatus status;

  /// The source currently loaded, or null when idle.
  final FPlayerSource? source;

  /// Whether frames are actually advancing. False while paused, buffering, or before the first
  /// frame.
  final bool isPlaying;

  final Duration position;

  /// How far ahead of the start the media is buffered.
  final Duration buffered;

  /// Media buffered *ahead of the playhead*.
  ///
  /// This is the number that predicts a stall, and [buffered] is not: right after a seek the
  /// absolute figure can be large while there is nothing ahead to play.
  final Duration bufferedAhead;

  /// Total length, or null for live streams and before the media is initialised.
  final Duration? duration;

  /// Decoded frame size in pixels, before [rotationDegrees] is applied.
  final Size size;

  /// Rotation the UI must apply, in degrees. Zero on backends that rotate frames themselves.
  final int rotationDegrees;

  /// Ratio between pixel width and height for anamorphic content. Usually 1.
  final double pixelAspectRatio;

  final double speed;

  /// Player gain, `0.0` to `1.0`. Unaffected by [isMuted], so unmuting restores it.
  final double volume;

  final bool isMuted;

  final bool isLive;

  /// Whether seeking is allowed. False for some live streams.
  final bool isSeekable;

  final bool isLooping;

  /// The queue being played through, or empty when a single source was opened directly.
  final List<FPlayerSource> playlist;

  /// Position of [source] within [playlist], or `-1` when there is no queue.
  final int currentIndex;

  /// Every audio, subtitle and quality track the media exposes, and what is selected.
  final FTracks tracks;

  /// Subtitle lines that should be on screen right now. Empty when nothing is showing.
  final List<FSubtitleCue> cues;

  /// Whether the device has a usable network right now.
  ///
  /// Optimistic before the first report: a player that starts by claiming to be offline would
  /// flash a warning on every launch.
  final bool isOnline;

  /// Whether playback is parked waiting for the network to come back.
  ///
  /// Distinct from [isOffline]: the device can be offline while a fully buffered stretch keeps
  /// playing. This is true only once a load has actually failed and is being held.
  final bool isWaitingForNetwork;

  /// Whether this device and this Activity can enter Picture-in-Picture.
  ///
  /// Stays false until the first frame: the system needs a video aspect ratio to size the window,
  /// and offering a PiP button that does nothing is worse than showing it a moment late.
  final bool isPipSupported;

  /// Whether the app is currently shrunk into the Picture-in-Picture window.
  ///
  /// The window shows the whole Flutter tree, so hide controls and overlays while this is true
  /// and leave only the video.
  final bool isPipActive;

  /// Whether a media session is published — lock screen, notification, headset buttons.
  final bool hasMediaSession;

  /// Set when [status] is `FPlayerStatus.error`.
  final FPlayerError? error;

  /// Aspect ratio to render at, accounting for rotation and anamorphic pixels.
  ///
  /// Falls back to 16:9 before the first frame, which avoids a layout jump for the overwhelmingly
  /// common case.
  double get aspectRatio {
    if (size.isEmpty) return 16 / 9;
    final isQuarterTurned = rotationDegrees == 90 || rotationDegrees == 270;
    final width = isQuarterTurned ? size.height : size.width;
    final height = isQuarterTurned ? size.width : size.height;
    if (height == 0) return 16 / 9;
    return (width / height) * pixelAspectRatio;
  }

  /// Playback progress from 0 to 1. Zero when the duration is unknown.
  double get progress {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Fraction of the media that is buffered, 0 to 1.
  double get bufferedProgress {
    final total = duration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (buffered.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Time left, or null when the duration is unknown.
  Duration? get remaining {
    final total = duration;
    if (total == null) return null;
    final left = total - position;
    return left.isNegative ? Duration.zero : left;
  }

  bool get hasError => error != null;

  bool get isOffline => !isOnline;

  bool get hasPlaylist => playlist.isNotEmpty;

  bool get hasNext => currentIndex >= 0 && currentIndex < playlist.length - 1;

  bool get hasPrevious => currentIndex > 0;

  /// What plays after this one, or null at the end of the queue.
  FPlayerSource? get nextInPlaylist => hasNext ? playlist[currentIndex + 1] : null;

  /// Ready but not advancing, with a source loaded.
  bool get isPaused => !isPlaying && status.isActive;

  bool get isBuffering => status == FPlayerStatus.buffering;

  bool get isCompleted => status == FPlayerStatus.completed;

  /// Whether a first frame has been decoded and the media is described.
  bool get isInitialized => status.isActive;

  FPlayerValue copyWith({
    FPlayerStatus? status,
    FPlayerSource? source,
    bool? isPlaying,
    Duration? position,
    Duration? buffered,
    Duration? bufferedAhead,
    Duration? duration,
    Size? size,
    int? rotationDegrees,
    double? pixelAspectRatio,
    double? speed,
    double? volume,
    bool? isMuted,
    bool? isLive,
    bool? isSeekable,
    bool? isLooping,
    List<FPlayerSource>? playlist,
    int? currentIndex,
    FTracks? tracks,
    List<FSubtitleCue>? cues,
    bool? isOnline,
    bool? isWaitingForNetwork,
    bool? isPipSupported,
    bool? isPipActive,
    bool? hasMediaSession,
    FPlayerError? error,
    bool clearError = false,
    bool clearDuration = false,
  }) =>
      FPlayerValue(
        status: status ?? this.status,
        source: source ?? this.source,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        buffered: buffered ?? this.buffered,
        bufferedAhead: bufferedAhead ?? this.bufferedAhead,
        duration: clearDuration ? null : (duration ?? this.duration),
        size: size ?? this.size,
        rotationDegrees: rotationDegrees ?? this.rotationDegrees,
        pixelAspectRatio: pixelAspectRatio ?? this.pixelAspectRatio,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        isMuted: isMuted ?? this.isMuted,
        isLive: isLive ?? this.isLive,
        isSeekable: isSeekable ?? this.isSeekable,
        isLooping: isLooping ?? this.isLooping,
        playlist: playlist ?? this.playlist,
        currentIndex: currentIndex ?? this.currentIndex,
        tracks: tracks ?? this.tracks,
        cues: cues ?? this.cues,
        isOnline: isOnline ?? this.isOnline,
        isWaitingForNetwork: isWaitingForNetwork ?? this.isWaitingForNetwork,
        isPipSupported: isPipSupported ?? this.isPipSupported,
        isPipActive: isPipActive ?? this.isPipActive,
        hasMediaSession: hasMediaSession ?? this.hasMediaSession,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  String toString() => 'FPlayerValue(${status.name}, playing: $isPlaying, '
      'position: $position/${duration ?? '∞'})';
}
