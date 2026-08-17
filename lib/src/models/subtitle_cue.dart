import 'package:flutter/foundation.dart';

/// Horizontal alignment of a cue's text.
enum FCueAlign { start, center, end }

/// Which part of the cue box the [FSubtitleCue.line] / [FSubtitleCue.position] value refers to.
enum FCueAnchor { start, middle, end }

/// One line of subtitle text with the positioning the format asked for.
///
/// WebVTT, TTML and ASS can place a cue anywhere on screen — a sign translation in the top-left,
/// a speaker label off to one side. The geometry is carried through so a renderer can honour it;
/// when the fields are null the cue takes the default bottom-centre position.
@immutable
class FSubtitleCue {
  const FSubtitleCue({
    required this.text,
    this.align = FCueAlign.center,
    this.line,
    this.lineAnchor = FCueAnchor.start,
    this.position,
    this.positionAnchor = FCueAnchor.middle,
    this.size,
    this.isVertical = false,
  });

  factory FSubtitleCue.fromMap(Map<Object?, Object?> map) => FSubtitleCue(
        text: map['text'] as String? ?? '',
        align: switch (map['align']) {
          'start' => FCueAlign.start,
          'end' => FCueAlign.end,
          _ => FCueAlign.center,
        },
        line: (map['line'] as num?)?.toDouble(),
        lineAnchor: _anchor(map['lineAnchor']),
        position: (map['position'] as num?)?.toDouble(),
        positionAnchor: _anchor(map['positionAnchor']),
        size: (map['size'] as num?)?.toDouble(),
        isVertical: map['isVertical'] as bool? ?? false,
      );

  /// The text to draw. Line breaks are meaningful.
  final String text;

  final FCueAlign align;

  /// Vertical placement as a fraction of the video height, 0 at the top. Null means default.
  ///
  /// Line values expressed in text rows rather than fractions are converted before they get here.
  final double? line;

  final FCueAnchor lineAnchor;

  /// Horizontal placement as a fraction of the video width. Null means default (centred).
  final double? position;

  final FCueAnchor positionAnchor;

  /// Maximum width of the cue box as a fraction of the video width.
  final double? size;

  /// Vertical writing mode, used by some CJK subtitles. Renderers may ignore it.
  final bool isVertical;

  static FCueAnchor _anchor(Object? raw) => switch (raw) {
        'middle' => FCueAnchor.middle,
        'end' => FCueAnchor.end,
        _ => FCueAnchor.start,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FSubtitleCue &&
          other.text == text &&
          other.align == align &&
          other.line == line &&
          other.lineAnchor == lineAnchor &&
          other.position == position &&
          other.positionAnchor == positionAnchor &&
          other.size == size &&
          other.isVertical == isVertical;

  @override
  int get hashCode => Object.hash(
        text,
        align,
        line,
        lineAnchor,
        position,
        positionAnchor,
        size,
        isVertical,
      );

  @override
  String toString() {
    final geometry = [
      if (line != null) 'line: ${line!.toStringAsFixed(2)} ${lineAnchor.name}',
      if (position != null) 'pos: ${position!.toStringAsFixed(2)} ${positionAnchor.name}',
      if (size != null) 'size: ${size!.toStringAsFixed(2)}',
      align.name,
    ].join(', ');
    return 'FSubtitleCue("${text.replaceAll('\n', ' / ')}", $geometry)';
  }
}
