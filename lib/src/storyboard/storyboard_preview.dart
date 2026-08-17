import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'storyboard.dart';
import 'storyboard_controller.dart';

/// The thumbnail for a position, ready to float above a seek bar.
///
/// Crops its frame straight out of the cached sprite sheet on the canvas, so moving along the
/// timeline costs a repaint and nothing else — no image widgets built and torn down per pointer
/// move, no re-decoding.
///
/// It renders a placeholder rather than disappearing when there is no storyboard, no frame for
/// the position, or the sheet is still loading: a preview that pops in and out under the finger
/// is worse than one that stays put.
class FStoryboardPreview extends StatefulWidget {
  const FStoryboardPreview({
    required this.controller,
    required this.position,
    this.width = 160,
    this.height,
    this.fallbackAspectRatio = 16 / 9,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.backgroundColor = const Color(0xE6101010),
    this.border,
    this.placeholder,
    this.filterQuality = FilterQuality.medium,
    super.key,
  });

  final FStoryboardController controller;

  /// Timeline position to preview — usually where the finger is, not where playback is.
  final Duration position;

  final double width;

  /// Fixed height. When null it follows from [width] and the thumbnail's own shape.
  final double? height;

  /// Shape used until the frame's real proportions are known.
  ///
  /// Sprite indexes declare the crop size up front, so this only shows for storyboards of
  /// one-file-per-thumbnail, and only until the first decode.
  final double fallbackAspectRatio;

  final BorderRadius borderRadius;

  /// Painted behind the thumbnail, and shown alone while there is nothing to draw.
  final Color backgroundColor;

  final BoxBorder? border;

  /// Shown in place of the thumbnail while loading or when no frame covers the position.
  final Widget? placeholder;

  final FilterQuality filterQuality;

  @override
  State<FStoryboardPreview> createState() => _FStoryboardPreviewState();
}

class _FStoryboardPreviewState extends State<FStoryboardPreview> {
  FStoryboardFrame? _frame;

  /// Clone owned by this widget. Disposed on replacement and on unmount.
  ui.Image? _image;

  /// Sheet [_image] came from, so a stale image is never cropped with a new frame's region.
  String? _imageUrl;

  /// Invalidates in-flight loads whose result is no longer wanted.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _resolve();
  }

  @override
  void didUpdateWidget(FStoryboardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.controller != widget.controller || oldWidget.position != widget.position) {
      _resolve();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _onControllerChanged() => _resolve();

  /// Points the widget at the frame for the current position, fetching its sheet if needed.
  void _resolve() {
    final frame = widget.controller.frameAt(widget.position);

    if (frame == null) {
      if (_frame != null || _image != null) {
        _releaseImage();
        _frame = null;
        _rebuild();
      }
      return;
    }

    final sameSheet = _imageUrl == frame.url;
    if (frame == _frame && (sameSheet || _image == null)) return;

    _frame = frame;

    // Frames from the sheet already in hand only change the crop, which is a repaint.
    if (sameSheet) {
      _rebuild();
      return;
    }

    _releaseImage();

    final cached = widget.controller.peekImage(frame);
    if (cached != null) {
      _image = cached;
      _imageUrl = frame.url;
      _rebuild();
      return;
    }

    _rebuild();

    final token = ++_request;
    unawaited(
      widget.controller.imageFor(frame).then((image) {
        if (!mounted || token != _request) {
          image?.dispose();
          return;
        }
        _releaseImage();
        _image = image;
        _imageUrl = image == null ? null : frame.url;
        _rebuild();
      }),
    );
  }

  void _releaseImage() {
    _image?.dispose();
    _image = null;
    _imageUrl = null;
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  double get _aspectRatio {
    final declared = _frame?.aspectRatio;
    if (declared != null && declared > 0) return declared;

    final image = _image;
    if (image != null && image.height > 0) return image.width / image.height;

    return widget.fallbackAspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final frame = _frame;
    final hasThumbnail = image != null && frame != null && _imageUrl == frame.url;

    return SizedBox(
      width: widget.width,
      height: widget.height ?? widget.width / _aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: widget.borderRadius,
          border: widget.border,
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: hasThumbnail
              ? CustomPaint(
                  painter: _FramePainter(
                    image: image,
                    region: frame.region,
                    filterQuality: widget.filterQuality,
                  ),
                  size: Size.infinite,
                )
              : widget.placeholder ?? const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.image,
    required this.region,
    required this.filterQuality,
  });

  final ui.Image image;
  final Rect? region;
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // A region that overruns the sheet — an off-by-one in a packaging tool, or a sheet served at
    // a different scale than the index assumed — would otherwise sample undefined pixels.
    final source = region == null ? bounds : region!.intersect(bounds);
    if (source.isEmpty) return;

    canvas.drawImageRect(
      image,
      source,
      Offset.zero & size,
      Paint()..filterQuality = filterQuality,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.region != region ||
      oldDelegate.filterQuality != filterQuality;
}
