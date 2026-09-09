import 'package:flutter/widgets.dart';

import '../controls/focus_highlight.dart';
import '../player_scope.dart';

/// A short horizontal volume slider, the kind that sits beside the mute button in a desktop bar.
///
/// Drawn by hand rather than borrowed from Material, like every other control here, so it
/// follows the player's theme and nothing else. The thumb shows on hover and while dragging; at
/// rest it is a plain bar, which is all a level needs to be read.
class FVolumeSlider extends StatefulWidget {
  const FVolumeSlider({required this.ui, this.width = 72, super.key});

  final FPlayerUi ui;
  final double width;

  @override
  State<FVolumeSlider> createState() => _FVolumeSliderState();
}

class _FVolumeSliderState extends State<FVolumeSlider> with FFocusHighlight {
  bool _isHovered = false;
  bool _isDragging = false;

  FPlayerUi get _ui => widget.ui;

  @override
  Widget build(BuildContext context) {
    final theme = _ui.theme;
    final value = _ui.controller.value;
    final level = value.isMuted ? 0.0 : value.volume;
    final showsThumb = _isHovered || _isDragging || showsFocusRing;
    final radius = theme.thumbRadius * 0.8;

    return Semantics(
      slider: true,
      label: _ui.localizations.volume,
      value: '${(level * 100).round()}%',
      child: focusable(
        onActivate: _ui.controller.toggleMute,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _setFrom(details.localPosition.dx),
            onHorizontalDragStart: (details) {
              setState(() => _isDragging = true);
              _setFrom(details.localPosition.dx);
            },
            onHorizontalDragUpdate: (details) => _setFrom(details.localPosition.dx),
            onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
            onHorizontalDragCancel: () => setState(() => _isDragging = false),
            child: SizedBox(
              width: widget.width,
              // Tall enough to hit with a pointer without aiming; the bar itself stays thin.
              height: theme.iconSize + theme.spacing,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  _bar(theme.trackColor, 1),
                  _bar(showsFocusRing ? theme.accent : theme.foreground, level),
                  Positioned(
                    left: level * widget.width - radius,
                    child: AnimatedOpacity(
                      opacity: showsThumb ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: radius * 2,
                        height: radius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: showsFocusRing ? theme.accent : theme.foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(Color color, double fraction) => FractionallySizedBox(
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          height: _ui.theme.trackHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_ui.theme.trackHeight),
          ),
        ),
      );

  void _setFrom(double dx) {
    _ui.controller.setVolume((dx / widget.width).clamp(0.0, 1.0));
    _ui.showControls();
  }
}
