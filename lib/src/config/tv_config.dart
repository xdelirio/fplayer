import 'package:flutter/foundation.dart';

/// When the player behaves like a TV app.
enum FTvMode {
  /// Touch until the first directional key arrives, then remote-first.
  ///
  /// The right default for an app that ships to both phones and TVs: nothing changes for a
  /// touch user, and a remote user gets a focus ring from their first press.
  auto,

  /// Remote-first from the first frame. Use it in a build that only ships to TV.
  enabled,

  /// Touch only. Directional keys fall back to Flutter's own focus traversal.
  disabled,
}

/// Remote-control behaviour.
@immutable
class FTvConfig {
  const FTvConfig({
    this.mode = FTvMode.auto,
    this.seekAcceleration = true,
    this.maxSeekMultiplier = 6,
    this.seekCommitDelay = const Duration(milliseconds: 500),
    this.handleMediaKeys = true,
    this.backHidesControls = true,
  });

  final FTvMode mode;

  /// Holding left or right seeks further per press the longer it is held.
  ///
  /// Without it, crossing an hour of video means a few hundred presses.
  final bool seekAcceleration;

  /// Ceiling on that acceleration, as a multiple of `FPlaybackConfig.seekStep`.
  final int maxSeekMultiplier;

  /// Quiet time after the last directional press before the seek is committed.
  ///
  /// Seeking on every press would make the engine re-buffer dozens of times while the viewer is
  /// still travelling; the preview moves immediately and the engine is told once, at the end.
  final Duration seekCommitDelay;

  /// Act on play/pause/stop/next/previous/fast-forward/rewind keys.
  final bool handleMediaKeys;

  /// Back closes the controls first, and only leaves the player on a second press.
  final bool backHidesControls;

  FTvConfig copyWith({
    FTvMode? mode,
    bool? seekAcceleration,
    int? maxSeekMultiplier,
    Duration? seekCommitDelay,
    bool? handleMediaKeys,
    bool? backHidesControls,
  }) =>
      FTvConfig(
        mode: mode ?? this.mode,
        seekAcceleration: seekAcceleration ?? this.seekAcceleration,
        maxSeekMultiplier: maxSeekMultiplier ?? this.maxSeekMultiplier,
        seekCommitDelay: seekCommitDelay ?? this.seekCommitDelay,
        handleMediaKeys: handleMediaKeys ?? this.handleMediaKeys,
        backHidesControls: backHidesControls ?? this.backHidesControls,
      );
}
