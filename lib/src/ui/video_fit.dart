import 'package:flutter/widgets.dart';

/// How the video is sized inside the space the player is given.
enum FVideoFit {
  /// Whole frame visible, letterboxed. The default, and what people expect from a video player.
  contain,

  /// Fills the box, cropping whatever overflows. What "zoom to fill" does on a TV.
  cover,

  /// Stretches to the box, ignoring aspect ratio. Distorts the picture.
  fill,

  /// Matches the box width; may overflow vertically.
  fitWidth,

  /// Matches the box height; may overflow horizontally.
  fitHeight,
}

extension FVideoFitX on FVideoFit {
  BoxFit get boxFit => switch (this) {
        FVideoFit.contain => BoxFit.contain,
        FVideoFit.cover => BoxFit.cover,
        FVideoFit.fill => BoxFit.fill,
        FVideoFit.fitWidth => BoxFit.fitWidth,
        FVideoFit.fitHeight => BoxFit.fitHeight,
      };

  /// Next mode in the cycle a "resize" button walks through.
  FVideoFit get next => switch (this) {
        FVideoFit.contain => FVideoFit.cover,
        FVideoFit.cover => FVideoFit.fill,
        FVideoFit.fill => FVideoFit.contain,
        FVideoFit.fitWidth => FVideoFit.fitHeight,
        FVideoFit.fitHeight => FVideoFit.contain,
      };
}
