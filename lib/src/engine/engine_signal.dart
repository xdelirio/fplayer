import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/player_error.dart';
import '../models/subtitle_cue.dart';
import '../models/track.dart';

/// The engine's own view of playback state, before it is folded into `FPlayerStatus`.
///
/// It mirrors what every serious playback engine reports, which is why the enum is here rather
/// than being ExoPlayer-specific.
enum FEnginePlaybackState { idle, buffering, ready, ended }

/// Normalised notifications produced by an [FPlaybackEngine].
///
/// This is the seam that keeps `FPlayerController` engine-agnostic: a second engine only has to
/// produce these signals, not match a wire format.
@immutable
sealed class FEngineSignal {
  const FEngineSignal();
}

final class FEngineInitialized extends FEngineSignal {
  const FEngineInitialized({
    required this.duration,
    required this.size,
    required this.rotationDegrees,
    required this.pixelAspectRatio,
    required this.isLive,
    required this.isSeekable,
  });

  final Duration? duration;
  final Size size;
  final int rotationDegrees;
  final double pixelAspectRatio;
  final bool isLive;
  final bool isSeekable;
}

final class FEnginePlaybackStateChanged extends FEngineSignal {
  const FEnginePlaybackStateChanged(this.state);

  final FEnginePlaybackState state;
}

final class FEnginePlayingChanged extends FEngineSignal {
  const FEnginePlayingChanged({required this.isPlaying});

  final bool isPlaying;
}

final class FEngineProgress extends FEngineSignal {
  const FEngineProgress({
    required this.position,
    required this.buffered,
    this.bufferedAhead = Duration.zero,
  });

  final Duration position;

  /// How far into the media the buffer reaches, measured from the start.
  final Duration buffered;

  /// How much media is buffered *beyond the playhead*.
  ///
  /// The number that decides whether playback is about to stall. [buffered] is absolute and says
  /// nothing about that right after a seek, when a large value can sit entirely behind the
  /// playhead.
  final Duration bufferedAhead;
}

final class FEngineVideoSizeChanged extends FEngineSignal {
  const FEngineVideoSizeChanged({
    required this.size,
    required this.rotationDegrees,
    required this.pixelAspectRatio,
  });

  final Size size;
  final int rotationDegrees;
  final double pixelAspectRatio;
}

final class FEngineDurationChanged extends FEngineSignal {
  const FEngineDurationChanged({required this.duration, required this.isSeekable, this.isLive});

  final Duration? duration;
  final bool isSeekable;

  /// Whether the media turned out to be live, when the engine learns that with the duration.
  ///
  /// Null leaves the controller's answer alone. Set by engines that only find out after
  /// describing the media: mpv lists the tracks first and reports a duration once the demuxer
  /// has one, so a stream initialised as live becomes on-demand a moment later.
  final bool? isLive;
}

final class FEngineSpeedChanged extends FEngineSignal {
  const FEngineSpeedChanged(this.speed);

  final double speed;
}

final class FEngineVolumeChanged extends FEngineSignal {
  const FEngineVolumeChanged(this.volume);

  final double volume;
}

final class FEngineTracksChanged extends FEngineSignal {
  const FEngineTracksChanged(this.tracks);

  final FTracks tracks;
}

/// The set of cues that should be on screen right now. An empty list clears them.
final class FEngineCuesChanged extends FEngineSignal {
  const FEngineCuesChanged(this.cues);

  final List<FSubtitleCue> cues;
}

/// Picture-in-Picture availability or state moved.
///
/// Support is not a constant: it depends on the OS version, on the device (Android Go and some
/// TVs omit it), on the host Activity declaring it, and on the user not having revoked the
/// per-app permission — so it is reported rather than assumed.
final class FEnginePipChanged extends FEngineSignal {
  const FEnginePipChanged({required this.isActive, required this.isSupported});

  final bool isActive;
  final bool isSupported;
}

/// Whether a media session is published for this player.
final class FEngineMediaSessionChanged extends FEngineSignal {
  const FEngineMediaSessionChanged({required this.isActive});

  final bool isActive;
}

/// The device's network came or went, and whether playback is parked waiting for it.
///
/// Reported rather than inferred from errors: "the CDN refused us" and "this phone is in a
/// tunnel" both surface as I/O failures, and only one of them is worth waiting out.
final class FEngineConnectivityChanged extends FEngineSignal {
  const FEngineConnectivityChanged({
    required this.isOnline,
    required this.isWaitingForNetwork,
  });

  final bool isOnline;

  /// A load already failed and the engine is holding it until the network returns, rather than
  /// spending the retry budget against a network that is not there.
  final bool isWaitingForNetwork;
}

final class FEngineFailed extends FEngineSignal {
  const FEngineFailed(this.error);

  final FPlayerError error;
}
