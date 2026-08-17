import 'package:flutter/painting.dart';

/// How the edge of subtitle glyphs is drawn, so text stays readable over any picture.
enum FSubtitleEdge {
  /// No edge treatment. Only legible with a solid [FSubtitleStyle.backgroundColor].
  none,

  /// A stroke around each glyph. The most reliable over arbitrary video.
  outline,

  /// A soft shadow below and to the right.
  dropShadow,

  /// Shadow that makes the text look lifted off the picture.
  raised,

  /// Shadow that makes the text look pressed into the picture.
  depressed,
}

/// Appearance of rendered subtitles.
///
/// Defaults follow the broadcast convention that survives any background: white text with a dark
/// outline, no box. [scale] is the knob to expose to users — it multiplies the size without
/// touching the rest of the design.
class FSubtitleStyle {
  const FSubtitleStyle({
    this.fontSize = 18,
    this.scale = 1.0,
    this.textColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0x00000000),
    this.windowColor = const Color(0x00000000),
    this.edge = FSubtitleEdge.outline,
    this.edgeColor = const Color(0xFF000000),
    this.edgeWidth = 2.0,
    this.fontFamily,
    this.fontWeight = FontWeight.w500,
    this.height = 1.25,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.bottomMargin = 0.06,
    this.maxWidthFraction = 0.9,
  });

  /// Readable over bright scenes without an outline: white on a translucent black box.
  const FSubtitleStyle.boxed()
      : fontSize = 18,
        scale = 1.0,
        textColor = const Color(0xFFFFFFFF),
        backgroundColor = const Color(0xCC000000),
        windowColor = const Color(0x00000000),
        edge = FSubtitleEdge.none,
        edgeColor = const Color(0xFF000000),
        edgeWidth = 0,
        fontFamily = null,
        fontWeight = FontWeight.w500,
        height = 1.25,
        padding = const EdgeInsets.symmetric(horizontal: 24),
        bottomMargin = 0.06,
        maxWidthFraction = 0.9;

  /// Base size in logical pixels, before [scale].
  final double fontSize;

  /// User-facing size multiplier. 1.0 is the designed size.
  final double scale;

  final Color textColor;

  /// Painted directly behind the glyphs, per line.
  final Color backgroundColor;

  /// Painted behind the whole cue box, including the padding.
  final Color windowColor;

  final FSubtitleEdge edge;
  final Color edgeColor;
  final double edgeWidth;

  final String? fontFamily;
  final FontWeight fontWeight;

  /// Line height multiplier.
  final double height;

  /// Inset from the video edges, so text never touches the frame.
  final EdgeInsets padding;

  /// Distance from the bottom of the video, as a fraction of its height.
  ///
  /// Raise it when controls are on screen so subtitles are not hidden behind them.
  final double bottomMargin;

  /// Widest a cue may get, as a fraction of the video width.
  final double maxWidthFraction;

  /// Size actually used for painting.
  double get effectiveFontSize => fontSize * scale;

  FSubtitleStyle copyWith({
    double? fontSize,
    double? scale,
    Color? textColor,
    Color? backgroundColor,
    Color? windowColor,
    FSubtitleEdge? edge,
    Color? edgeColor,
    double? edgeWidth,
    String? fontFamily,
    FontWeight? fontWeight,
    double? height,
    EdgeInsets? padding,
    double? bottomMargin,
    double? maxWidthFraction,
  }) =>
      FSubtitleStyle(
        fontSize: fontSize ?? this.fontSize,
        scale: scale ?? this.scale,
        textColor: textColor ?? this.textColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        windowColor: windowColor ?? this.windowColor,
        edge: edge ?? this.edge,
        edgeColor: edgeColor ?? this.edgeColor,
        edgeWidth: edgeWidth ?? this.edgeWidth,
        fontFamily: fontFamily ?? this.fontFamily,
        fontWeight: fontWeight ?? this.fontWeight,
        height: height ?? this.height,
        padding: padding ?? this.padding,
        bottomMargin: bottomMargin ?? this.bottomMargin,
        maxWidthFraction: maxWidthFraction ?? this.maxWidthFraction,
      );
}
