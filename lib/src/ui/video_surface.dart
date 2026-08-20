import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/player_controller.dart';
import 'video_fit.dart';

/// The raw video output: a texture or a platform view, correctly sized and rotated, and nothing
/// else.
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
          final value = controller.value;

          // Checked first: when the engine renders through a platform view there is no texture
          // to fall back to, and the two are never both live.
          final platformViewId = controller.platformViewId;
          if (platformViewId != null) {
            return _SurfaceViewOutput(
              playerId: platformViewId,
              aspectRatio: value.aspectRatio,
              fit: fit,
            );
          }

          final textureId = controller.textureId;
          if (textureId == null) return const SizedBox.expand();

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

/// The SurfaceView output, sized by hand.
///
/// The texture path can hand `FittedBox` a box one logical pixel tall and let it scale, because a
/// texture is just pixels. A platform view is a real Android view, and Flutter gives it a buffer
/// the size its *layout* asked for — a scale applied on top of that would blow a two-pixel
/// SurfaceView up across the screen. So the destination size is computed here and given to the
/// view as its constraints.
///
/// No rotation either: on this path the codec's rotation hint is applied before the frame reaches
/// the screen, so the native side reports zero degrees and already-swapped dimensions.
class _SurfaceViewOutput extends StatelessWidget {
  const _SurfaceViewOutput({
    required this.playerId,
    required this.aspectRatio,
    required this.fit,
  });

  final int playerId;
  final double aspectRatio;
  final FVideoFit fit;

  /// Matches `VideoPlatformViewFactory.VIEW_TYPE`.
  static const String _viewType = 'dev.chikenare.fplayer/video';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = _platformView(context);

        // Nothing to fit into. `AspectRatio` is what an unbounded box can still honour.
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return AspectRatio(aspectRatio: aspectRatio, child: view);
        }

        final size = _fittedSize(constraints.biggest);
        if (size == null) return AspectRatio(aspectRatio: aspectRatio, child: view);

        return ClipRect(
          child: OverflowBox(
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: view,
          ),
        );
      },
    );
  }

  /// The size the view has to be laid out at to look like `FittedBox` would have painted it.
  ///
  /// Not `applyBoxFit(...).destination`, which is the box the frame is painted *into*: for
  /// `cover` and `fitWidth` that is the output box itself, and the overflow is expressed by
  /// cropping the source rect instead. Rebuilding the scale from both halves is what turns that
  /// back into one size, and it is the same scale `FittedBox` puts in its transform.
  ///
  /// Null when the arithmetic has nothing to work with — a zero-sized box, or a frame whose
  /// dimensions have not arrived yet.
  Size? _fittedSize(Size box) {
    final source = Size(aspectRatio, 1);
    if (source.width <= 0 || box.isEmpty) return null;

    final fitted = applyBoxFit(fit.boxFit, source, box);
    if (fitted.source.width <= 0 || fitted.source.height <= 0) return null;

    final size = Size(
      source.width * fitted.destination.width / fitted.source.width,
      source.height * fitted.destination.height / fitted.source.height,
    );
    return size.isFinite ? size : null;
  }

  Widget _platformView(BuildContext context) {
    // The video is output, never a destination. `PlatformViewLink` puts a focus node around the
    // view, and on a remote that node joins the traversal ring: pressing down walked focus off
    // the chrome and into something invisible with nothing to activate, which reads as the
    // controls having seized up. Excluded rather than made unfocusable, so nothing inside the
    // platform view can claim focus either.
    return ExcludeFocus(
      child: PlatformViewLink(
        // A new player is a new view: without this the link would keep the old one and its
        // surface would stay wired to a player that no longer exists.
        key: ValueKey<int>(playerId),
        viewType: _viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          // The controls sit on top of this and have to keep receiving taps and D-pad presses.
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        ),
        onCreatePlatformView: (params) {
          // Hybrid composition, asked for by name. The cheaper texture-layer path draws the
          // platform view into a Flutter-owned surface, and a SurfaceView's buffer is not part
          // of what gets drawn: the video would come out as a black hole.
          //
          // No `onFocus`: that hands Flutter's focus to the platform view whenever Android
          // gives the view focus, which would take it off whatever control the viewer was on.
          final controller = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
            creationParams: <String, Object?>{'playerId': playerId},
            creationParamsCodec: const StandardMessageCodec(),
          );
          controller
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
          return controller;
        },
      ),
    );
  }
}
