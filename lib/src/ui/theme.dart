import 'package:flutter/widgets.dart';

/// Colours and metrics for the player chrome.
///
/// Deliberately independent of `ThemeData`: a video player is usually a dark surface floating in
/// an app of any colour scheme, and inheriting the app's theme tends to produce controls that are
/// invisible over the picture. Set [accent] to your brand colour and the rest follows.
@immutable
class FPlayerTheme {
  const FPlayerTheme({
    this.accent = const Color(0xFFE50914),
    this.foreground = const Color(0xFFFFFFFF),
    this.mutedForeground = const Color(0xB3FFFFFF),
    this.disabledForeground = const Color(0x61FFFFFF),
    this.surface = const Color(0xF21A1A1A),
    this.scrim = const Color(0x99000000),
    this.trackColor = const Color(0x4DFFFFFF),
    this.bufferedColor = const Color(0x80FFFFFF),
    this.iconSize = 22,
    this.primaryIconSize = 40,
    this.trackHeight = 3,
    this.thumbRadius = 7,
    this.spacing = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.titleStyle = const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    this.subtitleStyle = const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    this.timestampStyle = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    this.labelStyle = const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
  });

  /// Larger touch targets and text, for a screen watched from across the room.
  const FPlayerTheme.tv({Color accent = const Color(0xFFE50914)})
      : this(
          accent: accent,
          iconSize: 30,
          primaryIconSize: 56,
          trackHeight: 5,
          thumbRadius: 10,
          spacing: 14,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          titleStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          subtitleStyle: const TextStyle(fontSize: 16),
          timestampStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        );

  /// Progress fill, active states, focus ring.
  final Color accent;

  /// Icons and primary text.
  final Color foreground;

  /// Secondary text: timestamps, subtitles of the title, hints.
  final Color mutedForeground;

  /// Controls that exist but cannot be used right now.
  final Color disabledForeground;

  /// Background of panels and menus that sit over the video.
  final Color surface;

  /// Veil drawn over the picture while the controls are up, so white icons stay readable over a
  /// bright scene.
  final Color scrim;

  /// Unplayed part of the seek bar.
  final Color trackColor;

  /// Buffered-but-unplayed part of the seek bar.
  final Color bufferedColor;

  final double iconSize;

  /// Size of the play/pause glyph in the centre.
  final double primaryIconSize;

  final double trackHeight;
  final double thumbRadius;
  final double spacing;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  /// Uses tabular figures so the clock does not jitter as the digits change.
  final TextStyle timestampStyle;

  final TextStyle labelStyle;

  FPlayerTheme copyWith({
    Color? accent,
    Color? foreground,
    Color? mutedForeground,
    Color? disabledForeground,
    Color? surface,
    Color? scrim,
    Color? trackColor,
    Color? bufferedColor,
    double? iconSize,
    double? primaryIconSize,
    double? trackHeight,
    double? thumbRadius,
    double? spacing,
    EdgeInsets? padding,
    BorderRadius? borderRadius,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
    TextStyle? timestampStyle,
    TextStyle? labelStyle,
  }) =>
      FPlayerTheme(
        accent: accent ?? this.accent,
        foreground: foreground ?? this.foreground,
        mutedForeground: mutedForeground ?? this.mutedForeground,
        disabledForeground: disabledForeground ?? this.disabledForeground,
        surface: surface ?? this.surface,
        scrim: scrim ?? this.scrim,
        trackColor: trackColor ?? this.trackColor,
        bufferedColor: bufferedColor ?? this.bufferedColor,
        iconSize: iconSize ?? this.iconSize,
        primaryIconSize: primaryIconSize ?? this.primaryIconSize,
        trackHeight: trackHeight ?? this.trackHeight,
        thumbRadius: thumbRadius ?? this.thumbRadius,
        spacing: spacing ?? this.spacing,
        padding: padding ?? this.padding,
        borderRadius: borderRadius ?? this.borderRadius,
        titleStyle: titleStyle ?? this.titleStyle,
        subtitleStyle: subtitleStyle ?? this.subtitleStyle,
        timestampStyle: timestampStyle ?? this.timestampStyle,
        labelStyle: labelStyle ?? this.labelStyle,
      );
}
