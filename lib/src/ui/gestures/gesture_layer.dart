import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../player_scope.dart';
import '../time_format.dart';
import '../video_fit.dart';

/// Transient thing to show in the middle of the picture after a gesture.
enum _FeedbackKind { seekForward, seekBackward, volume, brightness, speed }

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

  FPlayerUi get _ui => widget.ui;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gestures = _ui.config.gestures;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: gestures.tapTogglesControls ? _ui.toggleControls : null,
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
          child: _Feedback(
            ui: _ui,
            kind: _feedback,
            text: _feedbackText,
            value: _feedbackValue,
          ),
        );
      },
    );
  }

  // region Double tap

  void _onDoubleTap(Offset position, double width) {
    if (_ui.isLocked) return;

    final third = width / 3;
    if (position.dx < third) {
      _ui.controller.skipBackward();
      _showFeedback(
        _FeedbackKind.seekBackward,
        text: '-${_ui.controller.config.playback.seekStep.inSeconds}s',
      );
    } else if (position.dx > width - third) {
      _ui.controller.skipForward();
      _showFeedback(
        _FeedbackKind.seekForward,
        text: '+${_ui.controller.config.playback.seekStep.inSeconds}s',
      );
    } else {
      _ui.controller.togglePlayPause();
    }
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
        _FeedbackKind.seekForward => Icons.fast_forward,
        _FeedbackKind.seekBackward => Icons.fast_rewind,
        _FeedbackKind.volume => Icons.volume_up,
        _FeedbackKind.brightness => Icons.brightness_6,
        _FeedbackKind.speed => Icons.speed,
      };
}
