import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/player_error.dart';
import '../models/player_source.dart';
import '../models/track.dart';
import 'player_status.dart';

/// Discrete things that happen during playback.
///
/// `FPlayerController` is a `ChangeNotifier`, which is what UI should listen to. This stream is
/// for the cases where the *transition* matters rather than the current state: analytics, logging,
/// "play the next episode when this one ends".
@immutable
sealed class FPlayerEvent {
  const FPlayerEvent();
}

/// A new source was handed to the engine. Fired before it starts loading.
final class FSourceOpened extends FPlayerEvent {
  const FSourceOpened(this.source);

  final FPlayerSource source;
}

/// The media is loaded far enough that its duration and dimensions are known.
final class FInitialized extends FPlayerEvent {
  const FInitialized({
    required this.duration,
    required this.size,
    required this.isLive,
    required this.isSeekable,
  });

  /// Null for live streams with no fixed length.
  final Duration? duration;
  final Size size;
  final bool isLive;
  final bool isSeekable;
}

final class FStatusChanged extends FPlayerEvent {
  const FStatusChanged(this.previous, this.current);

  final FPlayerStatus previous;
  final FPlayerStatus current;
}

final class FPlayingChanged extends FPlayerEvent {
  const FPlayingChanged({required this.isPlaying});

  final bool isPlaying;
}

/// Position advanced. Emitted at `FPlaybackConfig.progressInterval` while playing, and once after
/// every seek.
final class FPositionChanged extends FPlayerEvent {
  const FPositionChanged({required this.position, required this.buffered});

  final Duration position;
  final Duration buffered;
}

/// The queue was replaced. Fires once per `setPlaylist`, not per item.
final class FPlaylistChanged extends FPlayerEvent {
  const FPlaylistChanged(this.playlist, this.index);

  final List<FPlayerSource> playlist;
  final int index;
}

/// The available tracks changed, or a different one became active.
///
/// Fires on load, on every adaptive quality switch, and after a manual selection.
final class FTracksChanged extends FPlayerEvent {
  const FTracksChanged(this.tracks);

  final FTracks tracks;
}

/// The playhead was moved deliberately, as opposed to advancing with playback.
///
/// Emitted for every seek the controller performs, so an observer never has to infer one from a
/// jump in position — a correction of a second or two is indistinguishable from drift.
final class FSeeked extends FPlayerEvent {
  const FSeeked({required this.from, required this.to});

  final Duration from;
  final Duration to;

  /// Signed distance travelled. Negative when seeking backwards.
  Duration get delta => to - from;
}

final class FSpeedChanged extends FPlayerEvent {
  const FSpeedChanged(this.speed);

  final double speed;
}

final class FVolumeChanged extends FPlayerEvent {
  const FVolumeChanged(this.volume);

  final double volume;
}

/// Playback reached the end of the media.
final class FCompleted extends FPlayerEvent {
  const FCompleted();
}

/// The app entered or left the Picture-in-Picture window.
final class FPipChanged extends FPlayerEvent {
  const FPipChanged({required this.isActive});

  final bool isActive;
}

/// The device gained or lost its network.
final class FConnectivityChanged extends FPlayerEvent {
  const FConnectivityChanged({required this.isOnline});

  final bool isOnline;
}

final class FErrorOccurred extends FPlayerEvent {
  const FErrorOccurred(this.error);

  final FPlayerError error;
}

/// An automatic retry is about to run. [attempt] counts from 1.
final class FRetryScheduled extends FPlayerEvent {
  const FRetryScheduled({required this.attempt, required this.delay, required this.error});

  final int attempt;
  final Duration delay;
  final FPlayerError error;
}
