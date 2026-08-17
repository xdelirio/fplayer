import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../player_scope.dart';
import '../time_format.dart';
import '../video_fit.dart';

/// Transient thing to show in the middle of the picture after a gesture.
enum _FeedbackKind { volume, brightness, speed }

/// Touch handling over the video surface.
///
/// All of it goes through one `onScale*` family rather than separate drag callbacks: Flutter's
/// scale and pan recognisers cannot coexist on the same detector, and the player needs both a
/// pinch and directional drags. Pointer count and the dominant axis are worked out here instead.
class FGestureLayer extends StatefulWidget {
  const FGestureLayer({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  State<FGestureLayer> createState() => _FGestureLayerState();
}

class _FGestureLayerState extends State<FGestureLayer> {
  static const _axisThreshold = 12.0;

  _DragAxis _axis = _DragAxis.undecided;
  Offset _dragTotal = Offset.zero;
  Duration _seekOrigin = Duration.zero;
  double _volumeOrigin = 1;
  double _brightnessOrigin = 0.5;
  double? _speedBeforeHold;

  _FeedbackKind? _feedback;
  String _feedbackText = '';
  double _feedbackValue = 0;
  Timer? _feedbackTimer;

  /// Which side is currently rippling, and how many steps have piled up on it. Null means no
  /// ripple is on screen.
  bool? _isSeekingForward;
  int _seekSteps = 0;
  Timer? _seekTimer;
  double _lastTapX = 0;

  FPlayerUi get _ui => widget.ui;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _seekTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestures = _ui.config.gestures;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _lastTapX = details.localPosition.dx,
          onTap: gestures.tapTogglesControls || gestures.doubleTapSeeks
              ? () => _onTap(constraints.maxWidth)
              : null,
          onDoubleTapDown: gestures.doubleTapSeeks
              ? (details) => _onDoubleTap(details.localPosition, constraints.maxWidth)
              : null,
          // Present so the recogniser claims the gesture; the work happens on the down event,
          // where the tap position is known.
          onDoubleTap: gestures.doubleTapSeeks ? () {} : null,
          onLongPressStart: gestures.longPressSpeed == null ? null : _onHoldStart,
          onLongPressEnd: gestures.longPressSpeed == null ? null : (_) => _onHoldEnd(),
          onLongPressCancel: gestures.longPressSpeed == null ? null : _onHoldEnd,
          onScaleStart: (details) => _onScaleStart(details, constraints),
          onScaleUpdate: (details) => _onScaleUpdate(details, constraints),
          onScaleEnd: (_) => _onScaleEnd(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Feedback(
                ui: _ui,
                kind: _feedback,
                text: _feedbackText,
                value: _feedbackValue,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _isSeekingForward == null
                    ? const SizedBox.expand()
                    : _SeekRipple(
                        key: ValueKey(_isSeekingForward),
                        ui: _ui,
                        isForward: _isSeekingForward!,
                        seconds: _ui.controller.config.playback.seekStep.inSeconds * _seekSteps,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // region Double tap

  void _onDoubleTap(Offset position, double width) {
    if (_ui.isLocked) return;

    final side = _sideAt(position.dx, width);
    if (side == null) {
      _ui.controller.togglePlayPause();
      return;
    }
    _addSeekStep(forward: side);
  }

  /// A plain tap, once the double-tap recogniser has given up on a second one.
  ///
  /// While the ripple is up, a single tap on the same side adds another step — the same shortcut
  /// YouTube has, and the reason nobody double-taps four times to skip forty seconds.
  void _onTap(double width) {
    if (!_ui.isLocked && _isSeekingForward != null) {
      final side = _sideAt(_lastTapX, width);
      if (side == _isSeekingForward) {
        _addSeekStep(forward: side!);
        return;
      }
    }
    if (_ui.config.gestures.tapTogglesControls) _ui.toggleControls();
  }

  /// Which side of the picture [x] falls on, or null for the middle band that toggles playback.
  bool? _sideAt(double x, double width) {
    final third = width / 3;
    if (x < third) return false;
    if (x > width - third) return true;
    return null;
  }

  void _addSeekStep({required bool forward}) {
    forward ? _ui.controller.skipForward() : _ui.controller.skipBackward();

    _seekTimer?.cancel();
    setState(() {
      _seekSteps = _isSeekingForward == forward ? _seekSteps + 1 : 1;
      _isSeekingForward = forward;
    });

    // Long enough to catch the next tap, short enough that the ripple is gone by the time anyone
    // looks back at the picture.
    _seekTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isSeekingForward = null;
          _seekSteps = 0;
        });
      }
    });
  }

  // endregion

  // region Hold to speed up

  void _onHoldStart(LongPressStartDetails details) {
    final target = _ui.config.gestures.longPressSpeed;
    if (target == null || _ui.isLocked || !_ui.controller.isPlaying) return;

    _speedBeforeHold = _ui.controller.speed;
    _ui.controller.setSpeed(target);
    _showFeedback(_FeedbackKind.speed, text: formatPlaybackSpeed(target), sticky: true);
  }

  void _onHoldEnd() {
    final previous = _speedBeforeHold;
    if (previous == null) return;

    _speedBeforeHold = null;
    _ui.controller.setSpeed(previous);
    _hideFeedback();
  }

  // endregion

  // region Pan and pinch

  void _onScaleStart(ScaleStartDetails details, BoxConstraints constraints) {
    _axis = _DragAxis.undecided;
    _dragTotal = Offset.zero;
    _seekOrigin = _ui.controller.position;
    _volumeOrigin = _ui.controller.volume;
    // Read once per gesture: the starting point has to be whatever the window is at, or the first
    // drag jumps from the system's brightness to whatever the maths computed from zero.
    unawaited(_ui.controller.brightness().then((value) => _brightnessOrigin = value));
  }

  void _onScaleUpdate(ScaleUpdateDetails details, BoxConstraints constraints) {
    if (_ui.isLocked) return;

    if (details.pointerCount > 1) {
      if (_ui.config.gestures.pinchChangesFit) _onPinch(details.scale);
      return;
    }

    _dragTotal += details.focalPointDelta;

    if (_axis == _DragAxis.undecided) {
      if (_dragTotal.distance < _axisThreshold) return;
      _axis = _dragTotal.dx.abs() > _dragTotal.dy.abs()
          ? _DragAxis.horizontal
          : _DragAxis.vertical;
      if (_axis == _DragAxis.horizontal) _ui.beginScrub();
    }

    switch (_axis) {
      case _DragAxis.horizontal:
        _updateSeek(constraints.maxWidth);
      case _DragAxis.vertical:
        _updateVertical(details.localFocalPoint.dx, constraints);
      case _DragAxis.undecided:
        break;
    }
  }

  void _onScaleEnd() {
    if (_axis == _DragAxis.horizontal) _ui.endScrub();
    _axis = _DragAxis.undecided;
    _dragTotal = Offset.zero;
  }

  void _onPinch(double scale) {
    if (scale > 1.15 && _ui.fit != FVideoFit.cover) {
      _ui.setFit(FVideoFit.cover);
    } else if (scale < 0.85 && _ui.fit != FVideoFit.contain) {
      _ui.setFit(FVideoFit.contain);
    }
  }

  void _updateSeek(double width) {
    final gestures = _ui.config.gestures;
    if (!gestures.horizontalDragSeeks || width <= 0) return;

    final value = _ui.controller.value;
    final duration = value.duration;
    if (duration == null || !value.isSeekable) return;

    // Dragging the full width covers a tenth of the media, with a floor so short clips stay
    // controllable and a ceiling so a three-hour film does not fly past under one thumb.
    final span = Duration(
      milliseconds: (duration.inMilliseconds ~/ 10).clamp(
        const Duration(seconds: 60).inMilliseconds,
        const Duration(minutes: 10).inMilliseconds,
      ),
    );

    final delta = span * (_dragTotal.dx / width);
    final target = _seekOrigin + delta;
    _ui.updateScrub(target < Duration.zero
        ? Duration.zero
        : target > duration
            ? duration
            : target);
  }

  void _updateVertical(double x, BoxConstraints constraints) {
    final gestures = _ui.config.gestures;
    final isRightHalf = x > constraints.maxWidth / 2;

    if (isRightHalf && !gestures.verticalDragAdjustsVolume) return;
    if (!isRightHalf && !gestures.verticalDragAdjustsBrightness) return;
    if (constraints.maxHeight <= 0) return;

    // Up is more, and a full-height drag spans the whole range.
    final change = -_dragTotal.dy / constraints.maxHeight;

    if (isRightHalf) {
      final target = (_volumeOrigin + change).clamp(0.0, 1.0);
      _ui.controller.setVolume(target);
      _showFeedback(
        _FeedbackKind.volume,
        text: '${(target * 100).round()}%',
        value: target,
        sticky: true,
      );
      return;
    }

    final target = (_brightnessOrigin + change).clamp(0.0, 1.0);
    unawaited(_ui.controller.setBrightness(target));
    _showFeedback(
      _FeedbackKind.brightness,
      text: '${(target * 100).round()}%',
      value: target,
      sticky: true,
    );
  }

  // endregion

  void _showFeedback(
    _FeedbackKind kind, {
    required String text,
    double value = 0,
    bool sticky = false,
  }) {
    _feedbackTimer?.cancel();
    setState(() {
      _feedback = kind;
      _feedbackText = text;
      _feedbackValue = value;
    });

    if (sticky) return;
    _feedbackTimer = Timer(const Duration(milliseconds: 600), _hideFeedback);
  }

  void _hideFeedback() {
    _feedbackTimer?.cancel();
    if (mounted) setState(() => _feedback = null);
  }
}

enum _DragAxis { undecided, horizontal, vertical }

/// The badge that appears mid-picture while a gesture is doing something.
class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.ui,
    required this.kind,
    required this.text,
    required this.value,
  });

  final FPlayerUi ui;
  final _FeedbackKind? kind;
  final String text;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: kind == null
          ? const SizedBox.expand()
          : Center(
              key: ValueKey(kind),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: theme.spacing * 2,
                  vertical: theme.spacing * 1.5,
                ),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: theme.borderRadius,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconFor(kind!), color: theme.foreground, size: theme.iconSize * 1.3),
                    SizedBox(height: theme.spacing / 2),
                    Text(text, style: theme.labelStyle.copyWith(color: theme.foreground)),
                    if (kind == _FeedbackKind.volume || kind == _FeedbackKind.brightness) ...[
                      SizedBox(height: theme.spacing / 2),
                      SizedBox(
                        width: 90,
                        height: theme.trackHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(theme.trackHeight),
                          child: Row(
                            children: [
                              Expanded(
                                flex: (value * 1000).round().clamp(0, 1000),
                                child: ColoredBox(
                                  color: theme.accent,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              Expanded(
                                flex: 1000 - (value * 1000).round().clamp(0, 1000),
                                child: ColoredBox(
                                  color: theme.trackColor,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  static IconData _iconFor(_FeedbackKind kind) => switch (kind) {
        _FeedbackKind.volume => Icons.volume_up,
        _FeedbackKind.brightness => Icons.brightness_6,
        _FeedbackKind.speed => Icons.speed,
      };
}

/// The half-screen wash that answers a double tap.
///
/// The shape matters: a plain rectangle reads as a broken layout, while an edge that bows toward
/// the middle reads as a ripple spreading from where the finger landed. The count keeps climbing
/// as taps land, because the useful number is how far the tap took you in total, not per tap.
class _SeekRipple extends StatefulWidget {
  const _SeekRipple({
    required this.ui,
    required this.isForward,
    required this.seconds,
    super.key,
  });

  final FPlayerUi ui;
  final bool isForward;
  final int seconds;

  @override
  State<_SeekRipple> createState() => _SeekRippleState();
}

class _SeekRippleState extends State<_SeekRipple> with SingleTickerProviderStateMixin {
  late final AnimationController _chevrons = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _chevrons.dispose();
    super.dispose();
  }

  /// A pulse that travels along the three glyphs, in the direction of travel.
  double _opacityAt(double t, int index) {
    final phase = (t - index * 0.15) % 1.0;
    if (phase >= 0.35) return 0.3;
    return 0.3 + 0.7 * math.sin(phase / 0.35 * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;
    final l10n = widget.ui.localizations;

    return Align(
      alignment: widget.isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 1,
        child: ClipPath(
          clipper: _RippleClipper(isForward: widget.isForward),
          child: ColoredBox(
            // Enough to read as a wash over a dark scene, not so much that it whites out a bright
            // one — the picture is what someone is looking at.
            color: theme.foreground.withValues(alpha: 0.11),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scaleX: widget.isForward ? 1 : -1,
                    child: AnimatedBuilder(
                      animation: _chevrons,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Opacity(
                              opacity: _opacityAt(_chevrons.value, i),
                              child: Icon(
                                Icons.play_arrow,
                                size: theme.iconSize * 1.1,
                                color: theme.foreground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: theme.spacing / 2),
                  Text(
                    '${widget.seconds} ${l10n.seconds}',
                    style: theme.labelStyle.copyWith(color: theme.foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RippleClipper extends CustomClipper<Path> {
  const _RippleClipper({required this.isForward});

  final bool isForward;

  @override
  Path getClip(Size size) {
    final bulge = size.width * 0.42;
    final path = Path();

    if (isForward) {
      path
        ..moveTo(bulge, 0)
        ..quadraticBezierTo(0, size.height / 2, bulge, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0);
    } else {
      final inner = size.width - bulge;
      path
        ..moveTo(inner, 0)
        ..quadraticBezierTo(size.width, size.height / 2, inner, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, 0);
    }

    return path..close();
  }

  @override
  bool shouldReclip(_RippleClipper oldClipper) => oldClipper.isForward != isForward;
}
