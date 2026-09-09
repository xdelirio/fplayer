import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'focus_highlight.dart';

/// A control in the player chrome.
///
/// Not a Material `IconButton`: the player must render the same over any app theme, and it needs
/// a focus ring that reads from across a room for the TV layout. Focus is wired here rather than
/// bolted on later so every control is reachable with a D-pad by construction.
class FPlayerButton extends StatefulWidget {
  const FPlayerButton({
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.semanticLabel,
    this.size,
    this.isActive = false,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final IconData icon;

  /// Null renders the control greyed out and unfocusable — the affordance stays visible so the
  /// layout does not shift when it becomes available.
  final VoidCallback? onPressed;

  final FPlayerTheme theme;
  final String? semanticLabel;
  final double? size;

  /// Tints the icon with the accent colour, for toggles that are currently on.
  final bool isActive;

  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<FPlayerButton> createState() => _FPlayerButtonState();
}

class _FPlayerButtonState extends State<FPlayerButton> with FFocusHighlight {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isEnabled = widget.onPressed != null;
    final size = widget.size ?? theme.iconSize;

    final color = !isEnabled
        ? theme.disabledForeground
        : widget.isActive
            ? theme.accent
            : theme.foreground;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.semanticLabel,
      child: focusable(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onActivate: widget.onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(theme.spacing),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: showsFocusRing
                  ? theme.accent.withValues(alpha: 0.22)
                  : _isPressed
                      ? theme.foreground.withValues(alpha: 0.12)
                      : const Color(0x00000000),
              border: Border.all(
                color: showsFocusRing ? theme.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
            child: Icon(widget.icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}

/// A short text control, for things whose current value *is* the label: speed, fit mode.
class FPlayerTextButton extends StatefulWidget {
  const FPlayerTextButton({
    required this.label,
    required this.onPressed,
    required this.theme,
    this.semanticLabel,
    this.isActive = false,
    this.focusNode,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final FPlayerTheme theme;
  final String? semanticLabel;

  /// Tints the label with the accent colour, for a control whose setting is currently on.
  final bool isActive;

  final FocusNode? focusNode;

  @override
  State<FPlayerTextButton> createState() => _FPlayerTextButtonState();
}

class _FPlayerTextButtonState extends State<FPlayerTextButton> with FFocusHighlight {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isEnabled = widget.onPressed != null;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.semanticLabel ?? widget.label,
      child: focusable(
        focusNode: widget.focusNode,
        onActivate: widget.onPressed,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing * 1.5,
              vertical: theme.spacing * 0.75,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              // Active reads as a filled pill rather than a colour: the accent and the
              // foreground are both white by default, and a label that only changed hue would
              // change nothing.
              color: showsFocusRing
                  ? theme.accent.withValues(alpha: 0.22)
                  : widget.isActive
                      ? theme.foreground.withValues(alpha: 0.16)
                      : const Color(0x00000000),
              border: Border.all(
                color: showsFocusRing ? theme.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
            child: Text(
              widget.label,
              style: theme.labelStyle.copyWith(
                color: !isEnabled
                    ? theme.disabledForeground
                    : widget.isActive
                        ? theme.accent
                        : theme.foreground,
                fontWeight: widget.isActive ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
