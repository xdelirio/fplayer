import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Remote OK, keyboard Enter and Space all mean "activate this".
///
/// Shared so every control in the chrome — and any control an app builds alongside them — agrees
/// on what counts as a press.
bool isSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.space ||
    key == LogicalKeyboardKey.gameButtonA;

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
  ///
  /// The TV layer is the second signal, for the case Flutter's own cannot cover: a leanback
  /// build starts in `touch` mode — Android with no mouse connected — and would show no focus at
  /// all until the first key arrives, which is one press too late on a screen that is only ever
  /// driven by a remote.
  ///
  /// Read from `build`, like any inherited value.
  bool get showsFocusRing =>
      _isFocused && (_isHighlightVisible || FTvFocusMode.of(context));

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
    if (!mounted || _isFocused == value) return;
    setState(() => _isFocused = value);
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    final isVisible = mode == FocusHighlightMode.traditional;
    if (_isHighlightVisible == isVisible || !mounted) return;
    setState(() => _isHighlightVisible = isVisible);
  }

  /// The focus wiring every control in the chrome shares.
  ///
  /// A control that takes focus but does nothing with OK is worse than one that cannot be
  /// reached at all: on a remote it looks like the target the viewer wanted and then swallows
  /// the press. Building the `Focus` here rather than at each call site is what keeps that from
  /// being re-decided — and re-forgotten — control by control.
  Widget focusable({
    required VoidCallback? onActivate,
    required Widget child,
    bool autofocus = false,
    FocusNode? focusNode,
    bool? canRequestFocus,
  }) =>
      Focus(
        focusNode: focusNode,
        autofocus: autofocus,
        canRequestFocus: canRequestFocus ?? onActivate != null,
        onFocusChange: onFocusChanged,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && isSelectKey(event.logicalKey)) {
            if (onActivate == null) return KeyEventResult.ignored;
            onActivate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      );
}

/// Whether the chrome should behave as though a remote is driving it.
///
/// Published by the TV layer and read by [FFocusHighlight]. It lives here rather than in the TV
/// layer so that the controls do not have to import it — and so a custom control can opt into
/// the same behaviour with one line.
class FTvFocusMode extends InheritedWidget {
  const FTvFocusMode({
    required this.isRemoteDriven,
    required super.child,
    super.key,
  });

  final bool isRemoteDriven;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FTvFocusMode>()?.isRemoteDriven ?? false;

  @override
  bool updateShouldNotify(FTvFocusMode oldWidget) =>
      oldWidget.isRemoteDriven != isRemoteDriven;
}
