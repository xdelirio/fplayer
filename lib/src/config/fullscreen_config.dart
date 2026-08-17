import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which way the device may turn while the player is fullscreen.
enum FFullscreenOrientation {
  /// Follow the video: landscape media locks to landscape, portrait media stays portrait.
  ///
  /// The right default — it is what makes a phone rotate into a film and stay upright for a
  /// vertical clip, without the app having to know which it is.
  followVideo,

  /// Always landscape.
  landscape,

  /// Always portrait.
  portrait,

  /// Leave orientation alone.
  free,
}

/// How the fullscreen route behaves.
@immutable
class FFullscreenConfig {
  const FFullscreenConfig({
    this.autoOnPlay = false,
    this.orientation = FFullscreenOrientation.followVideo,
    this.systemUiMode = SystemUiMode.immersiveSticky,
    this.exitOnComplete = true,
    this.restoreOrientations = DeviceOrientation.values,
  });

  /// Go fullscreen as soon as playback starts.
  final bool autoOnPlay;

  final FFullscreenOrientation orientation;

  /// How the status and navigation bars behave while fullscreen.
  ///
  /// `immersiveSticky` is the video convention: the bars stay hidden and a swipe brings them
  /// back briefly instead of permanently resizing the picture.
  final SystemUiMode systemUiMode;

  /// Leave fullscreen when the media ends.
  final bool exitOnComplete;

  /// Orientations allowed again on exit.
  ///
  /// Flutter has no way to read the app's previous preference, so the player restores this list
  /// rather than guessing. Narrow it if your app is portrait-only.
  final List<DeviceOrientation> restoreOrientations;

  /// Orientations to allow for a video of this shape.
  List<DeviceOrientation> orientationsFor(double aspectRatio) => switch (orientation) {
        FFullscreenOrientation.free => restoreOrientations,
        FFullscreenOrientation.landscape => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        FFullscreenOrientation.portrait => const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
        FFullscreenOrientation.followVideo => aspectRatio >= 1
            ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      };

  FFullscreenConfig copyWith({
    bool? autoOnPlay,
    FFullscreenOrientation? orientation,
    SystemUiMode? systemUiMode,
    bool? exitOnComplete,
    List<DeviceOrientation>? restoreOrientations,
  }) =>
      FFullscreenConfig(
        autoOnPlay: autoOnPlay ?? this.autoOnPlay,
        orientation: orientation ?? this.orientation,
        systemUiMode: systemUiMode ?? this.systemUiMode,
        exitOnComplete: exitOnComplete ?? this.exitOnComplete,
        restoreOrientations: restoreOrientations ?? this.restoreOrientations,
      );
}
