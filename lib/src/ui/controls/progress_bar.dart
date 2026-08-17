import 'package:flutter/widgets.dart';

import '../../models/player_source.dart';
import '../player_scope.dart';
import '../theme.dart';

/// Seek bar with buffered range, drag-to-scrub and an optional preview above the thumb.
///
/// Painted rather than assembled from a `Slider` because it has to show three overlapping ranges,
/// keep a preview pinned to the thumb, and later carry chapter marks — none of which a stock
/// slider does without fighting it.
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

class _FProgressBarState extends State<FProgressBar> {
  /// Horizontal position of the thumb in logical pixels, tracked so the preview can follow it.
  double _thumbX = 0;
  double _trackWidth = 0;

  FPlayerUi get _ui => widget.ui;

  bool get _isSeekable {
    final value = _ui.controller.value;
    return value.isSeekable && value.duration != null && value.duration! > Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _ui.theme;

    return LayoutBuilder(
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
                    showThumb: _isSeekable,
                  ),
                ),
              ),
            ),
            if (_ui.isScrubbing && widget.previewBuilder != null)
              _Preview(
                thumbX: _thumbX,
                trackWidth: _trackWidth,
                child: widget.previewBuilder!(context, _ui.displayPosition),
              ),
          ],
        );
      },
    );
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

    final fraction = (dx / _trackWidth).clamp(0.0, 1.0);
    setState(() => _thumbX = fraction * _trackWidth);
    _ui.updateScrub(total * fraction);
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
    required this.showThumb,
  });

  final double progress;
  final double buffered;
  final List<double> chapterMarks;
  final FPlayerTheme theme;
  final bool isScrubbing;
  final bool showThumb;

  @override
  void paint(Canvas canvas, Size size) {
    final height = theme.trackHeight;
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
    final thumbRadius = isScrubbing ? theme.thumbRadius * 1.4 : theme.thumbRadius;
    canvas.drawCircle(
      Offset(size.width * progress, size.height / 2),
      thumbRadius,
      Paint()..color = theme.accent,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.isScrubbing != isScrubbing ||
      old.showThumb != showThumb ||
      old.chapterMarks.length != chapterMarks.length ||
      old.theme != theme;
}
