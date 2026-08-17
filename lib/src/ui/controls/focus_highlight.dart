import 'package:flutter/widgets.dart';

/// Tracks focus *and* whether showing it is appropriate.
///
/// Flutter moves focus on touch too, so a control that paints a ring whenever it holds focus
/// leaves a permanent highlight around whichever one was autofocused — which is exactly what the
/// play button is, so that a remote finds it on the first press. On a phone that reads as a
/// coloured button nobody asked for.
///
/// [FocusManager.highlightMode] is the signal: it says `touch` until a directional key or a
/// keyboard arrives, and flips to `traditional` from then on. Watching it means the same widget
/// is a plain icon under a thumb and a ringed target under a D-pad, with no separate TV build.
mixin FFocusHighlight<T extends StatefulWidget> on State<T> {
  bool _isFocused = false;
  late bool _isHighlightVisible =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// Whether this control should paint its focus ring right now.
  bool get showsFocusRing => _isFocused && _isHighlightVisible;

  /// Whether the control holds focus, regardless of whether that is worth drawing.
  bool get isFocused => _isFocused;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }

  /// Wire this to `Focus.onFocusChange`.
  void onFocusChanged(bool value) {
    if (_isFocused == value) return;
    setState(() => _isFocused = value);
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    final isVisible = mode == FocusHighlightMode.traditional;
    if (_isHighlightVisible == isVisible) return;
    if (mounted) setState(() => _isHighlightVisible = isVisible);
  }
}
