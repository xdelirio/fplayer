/// The pieces every panel over the video is built from.
///
/// Shared so the settings sheet and the track picker cannot drift apart: one frosted surface, one
/// row, one badge, one way in and out.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../player_scope.dart';
import '../theme.dart';
import 'focus_highlight.dart';

/// The frosted plate a panel sits on, sized to what the space allows.
class FPanelSheet extends StatelessWidget {
  const FPanelSheet({
    required this.theme,
    required this.child,
    this.width,
    super.key,
  });

  final FPlayerTheme theme;
  final Widget child;

  /// Preferred width. Defaults to the theme's menu width; either way it is capped by the room
  /// actually available, so a small phone gets a narrower sheet rather than an overflow.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.all(
      Radius.circular(theme.borderRadius.topLeft.x + theme.spacing),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: math.min(width ?? theme.menuWidth, constraints.maxWidth),
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 16)),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              // The picture behind stays visible but unreadable, which is what tells the eye the
              // panel is over the video rather than replacing it.
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.surface.withValues(alpha: theme.surface.a * 0.82),
                  borderRadius: radius,
                  border: Border.all(color: theme.foreground.withValues(alpha: 0.10)),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title, an optional way back, and a way out.
class FPanelHeader extends StatelessWidget {
  const FPanelHeader({
    required this.theme,
    required this.title,
    required this.onClose,
    this.onBack,
    super.key,
  });

  final FPlayerTheme theme;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(theme.spacing),
        child: Row(
          children: [
            if (onBack != null) ...[
              FPanelGhostButton(theme: theme, icon: Icons.arrow_back, onTap: onBack!),
              SizedBox(width: theme.spacing / 2),
            ] else
              SizedBox(width: theme.spacing / 2),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.titleStyle.copyWith(
                  color: theme.foreground,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            FPanelGhostButton(theme: theme, icon: Icons.close, onTap: onClose),
          ],
        ),
      );
}

class FPanelGhostButton extends StatelessWidget {
  const FPanelGhostButton({
    required this.theme,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final FPlayerTheme theme;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = theme.iconSize * 1.7;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.foreground.withValues(alpha: 0.10),
        ),
        child: Icon(icon, size: theme.iconSize * 0.8, color: theme.foreground),
      ),
    );
  }
}

/// A hairline between bands of a panel.
class FPanelDivider extends StatelessWidget {
  const FPanelDivider({required this.theme, super.key});

  final FPlayerTheme theme;

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: theme.foreground.withValues(alpha: 0.08));
}

/// A section label inside a panel: small, quiet, spaced out.
class FPanelSectionLabel extends StatelessWidget {
  const FPanelSectionLabel({required this.theme, required this.label, super.key});

  final FPlayerTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          theme.spacing * 2,
          theme.spacing,
          theme.spacing * 2,
          theme.spacing * 0.5,
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.subtitleStyle.copyWith(
            color: theme.mutedForeground,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      );
}

/// One of the choices inside a panel.
class FPanelOptionRow extends StatefulWidget {
  const FPanelOptionRow({
    required this.ui,
    required this.label,
    required this.onTap,
    this.badge,
    this.detail = '',
    this.isSelected = false,
    this.isEnabled = true,
    super.key,
  });

  final FPlayerUi ui;
  final String label;

  /// Two or three characters that qualify the row: `HD`, `4K`, `CC`.
  final String? badge;

  /// Secondary text on the right: bitrate, channel layout. Empty means none.
  final String detail;

  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  State<FPanelOptionRow> createState() => _FPanelOptionRowState();
}

class _FPanelOptionRowState extends State<FPanelOptionRow> with FFocusHighlight {
  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;
    final color = widget.isEnabled
        ? (widget.isSelected ? theme.accent : theme.foreground)
        : theme.disabledForeground;

    return Focus(
      canRequestFocus: widget.isEnabled,
      onFocusChange: onFocusChanged,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.isEnabled ? widget.onTap : null,
        child: FPanelRowSurface(
          theme: theme,
          isHighlighted: showsFocusRing,
          isSelected: widget.isSelected,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelStyle.copyWith(
                          color: color,
                          fontWeight: widget.isSelected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    if (widget.badge != null) ...[
                      SizedBox(width: theme.spacing * 0.75),
                      FPanelBadge(
                        theme: theme,
                        label: widget.badge!,
                        isEnabled: widget.isEnabled,
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.detail.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(left: theme.spacing),
                  child: Text(
                    widget.detail,
                    style: theme.subtitleStyle.copyWith(color: theme.mutedForeground),
                  ),
                ),
              SizedBox(width: theme.spacing / 2),
              // The slot is always there, so labels do not shift as the selection moves.
              SizedBox(
                width: theme.iconSize,
                child: widget.isSelected
                    ? Icon(Icons.check, size: theme.iconSize, color: theme.accent)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FPanelBadge extends StatelessWidget {
  const FPanelBadge({
    required this.theme,
    required this.label,
    this.isEnabled = true,
    super.key,
  });

  final FPlayerTheme theme;
  final String label;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: theme.spacing * 0.6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(
            color: (isEnabled ? theme.mutedForeground : theme.disabledForeground)
                .withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.subtitleStyle.copyWith(
            color: isEnabled ? theme.mutedForeground : theme.disabledForeground,
            fontSize: (theme.subtitleStyle.fontSize ?? 12) * 0.85,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

/// The rounded plate a row paints on, so selection and focus read as one shape instead of a band
/// running edge to edge.
class FPanelRowSurface extends StatelessWidget {
  const FPanelRowSurface({
    required this.theme,
    required this.child,
    this.isHighlighted = false,
    this.isSelected = false,
    super.key,
  });

  final FPlayerTheme theme;
  final Widget child;
  final bool isHighlighted;
  final bool isSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing,
          vertical: theme.spacing * 0.25,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing,
            vertical: theme.spacing * 1.1,
          ),
          decoration: BoxDecoration(
            color: isHighlighted
                ? theme.accent.withValues(alpha: 0.28)
                : isSelected
                    ? theme.foreground.withValues(alpha: 0.08)
                    : const Color(0x00000000),
            borderRadius: BorderRadius.circular(theme.spacing * 1.5),
          ),
          child: child,
        ),
      );
}

/// Plays once when a panel mounts.
class FPanelEnterTransition extends StatelessWidget {
  const FPanelEnterTransition({
    required this.child,
    this.slideFrom = Offset.zero,
    this.scaleFrom = 1,
    super.key,
  });

  final Widget child;

  /// Where the panel travels from, in logical pixels.
  final Offset slideFrom;

  /// Scale it starts at, for panels that grow into place rather than slide.
  final double scaleFrom;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: slideFrom * (1 - t),
            child: Transform.scale(
              scale: scaleFrom + (1 - scaleFrom) * t,
              child: child,
            ),
          ),
        ),
        child: child,
      );
}

/// The veil behind a panel: it darkens the picture and takes the tap that dismisses.
class FPanelScrim extends StatelessWidget {
  const FPanelScrim({required this.theme, required this.onTap, super.key});

  final FPlayerTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: FPanelEnterTransition(child: ColoredBox(color: theme.scrim)),
      );
}
