import 'package:flutter/widgets.dart';

import '../config/subtitle_style.dart';
import '../core/player_controller.dart';
import '../models/subtitle_cue.dart';

/// Draws the player's current subtitle cues.
///
/// Rendering happens in Flutter rather than in the platform view, so the same styling applies in
/// fullscreen, in Picture-in-Picture and on TV, and so the app can restyle subtitles without
/// touching native code.
///
/// Stack it over the video, sized to the *video rectangle* rather than the whole screen — cue
/// coordinates are relative to the picture, so a letterboxed player would otherwise place text
/// in the black bars.
class FSubtitleView extends StatelessWidget {
  const FSubtitleView({
    required this.controller,
    this.style = const FSubtitleStyle(),
    this.bottomInset = 0,
    super.key,
  });

  final FPlayerController controller;

  final FSubtitleStyle style;

  /// Extra space to keep clear at the bottom, in logical pixels.
  ///
  /// Raise it while the controls are on screen so subtitles slide up instead of hiding behind
  /// the seek bar.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final cues = controller.value.cues;
          if (cues.isEmpty) return const SizedBox.shrink();

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;

              // Cues without a real placement preference share one stack at the bottom; the
              // format expects them to sit on consecutive lines rather than on top of each other.
              final flowing = <FSubtitleCue>[];
              final placed = <FSubtitleCue>[];
              for (final cue in cues) {
                (_isDefaultPlacement(cue) ? flowing : placed).add(cue);
              }

              return Stack(
                children: [
                  if (flowing.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: height * style.bottomMargin + bottomInset,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (final cue in flowing)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: width * style.maxWidthFraction,
                              ),
                              child: _CueBox(cue: cue, style: style),
                            ),
                        ],
                      ),
                    ),
                  for (final cue in placed) _placed(cue, width, height),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Whether the cue asks for nothing beyond "put it where subtitles normally go".
  ///
  /// Parsers fill in the format's defaults rather than leaving fields empty — WebVTT reports
  /// `position: 0.5, size: 1.0` for a plain cue — so a null check alone would route ordinary
  /// subtitles through absolute placement and stop them from stacking.
  static bool _isDefaultPlacement(FSubtitleCue cue) {
    if (cue.line != null) return false;
    final position = cue.position;
    if (position == null) return true;
    return (position - 0.5).abs() < 0.001 && cue.positionAnchor == FCueAnchor.middle;
  }

  Widget _placed(FSubtitleCue cue, double width, double height) {
    final position = (cue.position ?? 0.5).clamp(0.0, 1.0);

    // WebVTT's own rule: the box may take at most the room between its anchor and the edge it
    // grows towards. Without it, `position:60% align:left` laid out a full-width box from 60%
    // and lost nearly half the line off the right edge.
    final available = switch (cue.positionAnchor) {
      FCueAnchor.start => 1 - position,
      FCueAnchor.end => position,
      FCueAnchor.middle => 2 * (position < 0.5 ? position : 1 - position),
    };
    final requested = cue.size ?? style.maxWidthFraction;
    final boxWidth = requested.clamp(0.0, available <= 0 ? requested : available) * width;
    final line = (cue.line ?? 1 - style.bottomMargin).clamp(0.0, 1.0);

    // A bottom-anchored cue is laid out from the bottom edge rather than translated up from a
    // top offset. Translation happens after layout, so a tall cue placed near the foot of the
    // picture would be measured off-screen and clipped before it could be shifted back.
    //
    // A cue with no line at all also anchors to the bottom: it wanted a horizontal position, not
    // a vertical one, and should still sit where subtitles belong.
    final isBottomAnchored = cue.line == null || cue.lineAnchor == FCueAnchor.end;

    return Positioned(
      left: position * width,
      top: isBottomAnchored ? null : line * height,
      bottom: isBottomAnchored ? (1 - line) * height + bottomInset : null,
      width: boxWidth,
      child: FractionalTranslation(
        translation: Offset(
          _shift(cue.positionAnchor),
          isBottomAnchored ? 0 : _shift(cue.lineAnchor),
        ),
        child: _CueBox(cue: cue, style: style),
      ),
    );
  }

  /// Fraction of its own size the cue box moves so the requested anchor lands on the coordinate.
  static double _shift(FCueAnchor anchor) => switch (anchor) {
        FCueAnchor.start => 0,
        FCueAnchor.middle => -0.5,
        FCueAnchor.end => -1,
      };
}

class _CueBox extends StatelessWidget {
  const _CueBox({required this.cue, required this.style});

  final FSubtitleCue cue;
  final FSubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    final textAlign = switch (cue.align) {
      FCueAlign.start => TextAlign.start,
      FCueAlign.center => TextAlign.center,
      FCueAlign.end => TextAlign.end,
    };

    final base = TextStyle(
      fontSize: style.effectiveFontSize,
      fontFamily: style.fontFamily,
      fontWeight: style.fontWeight,
      height: style.height,
      color: style.textColor,
      backgroundColor: style.backgroundColor,
      shadows: _shadows(),
    );

    final text = Text(cue.text, textAlign: textAlign, style: base);

    return Container(
      padding: style.padding,
      color: style.windowColor,
      child: style.edge == FSubtitleEdge.outline && style.edgeWidth > 0
          // The stroke is painted as a second copy underneath, because a single TextStyle cannot
          // both stroke and fill.
          //
          // `passthrough` matters: a loose Stack would shrink to the text's intrinsic width and
          // sit against the left edge of the cue box, silently defeating `textAlign`.
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                Text(
                  cue.text,
                  textAlign: textAlign,
                  style: base.copyWith(
                    backgroundColor: const Color(0x00000000),
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = style.edgeWidth
                      ..strokeJoin = StrokeJoin.round
                      ..color = style.edgeColor,
                  ),
                ),
                text,
              ],
            )
          : text,
    );
  }

  List<Shadow>? _shadows() => switch (style.edge) {
        FSubtitleEdge.none || FSubtitleEdge.outline => null,
        FSubtitleEdge.dropShadow => [
            Shadow(color: style.edgeColor, offset: const Offset(2, 2), blurRadius: 3),
          ],
        FSubtitleEdge.raised => [
            Shadow(color: style.edgeColor, offset: const Offset(1, 1)),
            Shadow(color: style.edgeColor, offset: const Offset(2, 2)),
          ],
        FSubtitleEdge.depressed => [
            Shadow(color: style.edgeColor, offset: const Offset(-1, -1)),
            Shadow(color: style.edgeColor, offset: const Offset(-2, -2)),
          ],
      };
}
