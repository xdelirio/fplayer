import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/player_source.dart';
import '../player_scope.dart';
import '../theme.dart';
import '../tv/tv_layer.dart';
import 'focus_highlight.dart';
import 'player_button.dart' show isSelectKey;

/// Seek bar with buffered range, drag-to-scrub and an optional preview above the thumb.
///
/// Painted rather than assembled from a `Slider` because it has to show three overlapping ranges,
/// keep a preview pinned to the thumb, and later carry chapter marks — none of which a stock
/// slider does without fighting it.
///
/// It takes focus like any other control, and that is what makes left and right mean *scrub*:
/// they seek while this bar holds focus and walk the buttons everywhere else, so a remote is not
/// stuck scrubbing whenever it tries to reach the next control.
class FProgressBar extends StatefulWidget {
  const FProgressBar({
    required this.ui,
    this.previewBuilder,
    super.key,
  });

  final FPlayerUi ui;

  /// Shown above the thumb while scrubbing. This is where a storyboard thumbnail goes.
  final Widget Function(BuildContext context, Duration position)? previewBuilder;

  @override
  State<FProgressBar> createState() => _FProgressBarState();
}

class _FProgressBarState extends State<FProgressBar> with FFocusHighlight {
  /// Named so a test — and a custom layout wanting to hand the bar focus — can find it.
  final FocusNode _focusNode = FocusNode(debugLabel: 'fplayer.seek-bar');

  double _trackWidth = 0;

  FPlayerUi get _ui => widget.ui;

  bool get _isSeekable {
    final value = _ui.controller.value;
    return value.isSeekable && value.duration != null && value.duration! > Duration.zero;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _ui.theme;

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: _isSeekable,
      onFocusChange: onFocusChanged,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _trackWidth = constraints.maxWidth;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _isSeekable ? _onTapDown : null,
                onTapUp: _isSeekable ? (_) => _ui.endScrub() : null,
                onTapCancel: _isSeekable ? _ui.endScrub : null,
                onHorizontalDragStart: _isSeekable ? _onDragStart : null,
                onHorizontalDragUpdate: _isSeekable ? _onDragUpdate : null,
                onHorizontalDragEnd: _isSeekable ? (_) => _ui.endScrub() : null,
                onHorizontalDragCancel: _isSeekable ? _ui.endScrub : null,
                child: SizedBox(
                  height: theme.thumbRadius * 2 + 16,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _ProgressPainter(
                      progress: _progress,
                      buffered: _ui.controller.value.bufferedProgress,
                      chapterMarks: _chapterMarks,
                      theme: theme,
                      isScrubbing: _ui.isScrubbing,
                      isFocused: showsFocusRing,
                      showThumb: _isSeekable,
                    ),
                  ),
                ),
              ),
              if (_ui.isScrubbing && widget.previewBuilder != null)
                _Preview(
                  thumbX: _progress * _trackWidth,
                  trackWidth: _trackWidth,
                  child: widget.previewBuilder!(context, _ui.displayPosition),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Left and right scrub, OK commits. Anything else — up, down, back — is left alone, which is
  /// what lets focus travel out of the bar.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final direction = key == LogicalKeyboardKey.arrowLeft
        ? -1
        : key == LogicalKeyboardKey.arrowRight
            ? 1
            : 0;

    if (direction != 0) {
      if (!_isSeekable) return KeyEventResult.ignored;
      _seekStep(direction);
      return KeyEventResult.handled;
    }

    if (isSelectKey(key) && _ui.isScrubbing) {
      final tv = FTvScope.maybeOf(context);
      if (tv != null) {
        tv.commitSeek();
      } else {
        _ui.endScrub();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _seekStep(int direction) {
    final tv = FTvScope.maybeOf(context);
    if (tv != null) {
      tv.seek(direction);
      return;
    }

    // No TV layer, so no run to accelerate and nothing deferring the commit: a keyboard press on
    // a focused seek bar is one jump, the same as the skip buttons.
    final controller = _ui.controller;
    unawaited(direction > 0 ? controller.skipForward() : controller.skipBackward());
    _ui.showControls();
  }

  /// Chapter starts as fractions of the timeline, so the bar can show where the parts divide.
  ///
  /// The one at zero is dropped: a notch on the left edge is not a boundary between anything.
  List<double> get _chapterMarks {
    final value = _ui.controller.value;
    final chapters = value.source?.chapters ?? const <FChapter>[];
    final total = value.duration?.inMilliseconds ?? 0;
    if (chapters.length < 2 || total <= 0) return const [];

    return [
      for (final chapter in chapters)
        if (chapter.start > Duration.zero && chapter.start.inMilliseconds < total)
          chapter.start.inMilliseconds / total,
    ];
  }

  double get _progress {
    final value = _ui.controller.value;
    final total = value.duration?.inMilliseconds ?? 0;
    if (total <= 0) return 0;
    return (_ui.displayPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _onTapDown(TapDownDetails details) {
    _ui.beginScrub();
    _seekToLocal(details.localPosition.dx);
  }

  void _onDragStart(DragStartDetails details) {
    _ui.beginScrub();
    _seekToLocal(details.localPosition.dx);
  }

  void _onDragUpdate(DragUpdateDetails details) => _seekToLocal(details.localPosition.dx);

  void _seekToLocal(double dx) {
    final total = _ui.controller.value.duration;
    if (total == null || _trackWidth <= 0) return;

    _ui.updateScrub(total * (dx / _trackWidth).clamp(0.0, 1.0));
  }
}

/// Keeps the preview centred on the thumb without letting it hang off either edge.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.thumbX,
    required this.trackWidth,
    required this.child,
  });

  final double thumbX;
  final double trackWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 36,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment(
          trackWidth <= 0 ? 0 : ((thumbX / trackWidth) * 2 - 1).clamp(-1.0, 1.0),
          0,
        ),
        child: child,
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({
    required this.progress,
    required this.buffered,
    required this.chapterMarks,
    required this.theme,
    required this.isScrubbing,
    required this.isFocused,
    required this.showThumb,
  });

  final double progress;
  final double buffered;
  final List<double> chapterMarks;
  final FPlayerTheme theme;
  final bool isScrubbing;

  /// Whether a remote or a keyboard is on the bar. Without it the seek bar is the one control
  /// with no visible focus, and a viewer pressing left has no idea what is about to move.
  final bool isFocused;

  final bool showThumb;

  @override
  void paint(Canvas canvas, Size size) {
    final height = theme.trackHeight * (isFocused || isScrubbing ? 1.6 : 1);
    final top = (size.height - height) / 2;
    final radius = Radius.circular(height / 2);

    void bar(double fraction, Color color) {
      final width = size.width * fraction.clamp(0.0, 1.0);
      if (width <= 0) return;
      canvas.drawRRect(
        RRect.fromLTRBR(0, top, width, top + height, radius),
        Paint()..color = color,
      );
    }

    bar(1, theme.trackColor);
    bar(buffered, theme.bufferedColor);
    bar(progress, theme.accent);

    // Chapter boundaries are punched out of the bar rather than drawn on top, so the mark reads
    // the same over the played, buffered and empty parts.
    if (chapterMarks.isNotEmpty) {
      final notch = Paint()
        ..blendMode = BlendMode.clear
        ..color = const Color(0xFF000000);
      canvas.saveLayer(Offset.zero & size, Paint());
      bar(1, theme.trackColor);
      bar(buffered, theme.bufferedColor);
      bar(progress, theme.accent);
      for (final mark in chapterMarks) {
        canvas.drawRect(
          Rect.fromLTWH(size.width * mark - 1, top, 2, height),
          notch,
        );
      }
      canvas.restore();
    }

    if (!showThumb) return;

    // The thumb grows while dragging so the finger does not fully hide the target.
    final thumbRadius =
        isScrubbing || isFocused ? theme.thumbRadius * 1.4 : theme.thumbRadius;
    final centre = Offset(size.width * progress, size.height / 2);

    // A halo rather than a ring around the whole bar: the bar spans the screen, so an outline
    // says nothing about *where* on it the next press lands.
    if (isFocused) {
      canvas.drawCircle(
        centre,
        thumbRadius + theme.thumbRadius * 0.9,
        Paint()..color = theme.accent.withValues(alpha: 0.3),
      );
    }

    canvas.drawCircle(centre, thumbRadius, Paint()..color = theme.accent);
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.isScrubbing != isScrubbing ||
      old.isFocused != isFocused ||
      old.showThumb != showThumb ||
      old.chapterMarks.length != chapterMarks.length ||
      old.theme != theme;
}
