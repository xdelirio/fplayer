import 'package:flutter/widgets.dart';

import '../core/player_controller.dart';
import 'video_fit.dart';

/// The raw video output: a texture, correctly sized and rotated, and nothing else.
///
/// Use it when the app brings its own controls. The batteries-included widget is `FPlayerView`,
/// which stacks controls, subtitles and overlays on top of this.
class FVideoSurface extends StatelessWidget {
  const FVideoSurface({
    required this.controller,
    this.fit = FVideoFit.contain,
    this.backgroundColor = const Color(0xFF000000),
    super.key,
  });

  final FPlayerController controller;

  /// How the frame is sized inside the available space.
  final FVideoFit fit;

  /// Painted behind the video, and visible in the letterbox bars.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final textureId = controller.textureId;
          if (textureId == null) return const SizedBox.expand();

          final value = controller.value;
          final quarterTurns = (value.rotationDegrees ~/ 90) % 4;

          return FittedBox(
            fit: fit.boxFit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              // Only the ratio matters here — FittedBox scales it to the real box.
              width: value.aspectRatio,
              height: 1,
              // RotatedBox swaps the constraints it hands down, so the texture receives the
              // pre-rotation geometry and lands upright.
              child: RotatedBox(
                quarterTurns: quarterTurns,
                child: Texture(textureId: textureId),
              ),
            ),
          );
        },
      ),
    );
  }
}
