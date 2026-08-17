import 'package:flutter/widgets.dart';

import '../config/ui_config.dart';
import '../core/player_controller.dart';
import 'localizations.dart';
import 'theme.dart';
import 'video_fit.dart';

/// The chrome's own state and the commands that change it.
///
/// Separate from `FPlayerController`, which owns playback. Whether the controls are on screen or
/// the picture is locked is a property of *this view*, not of the media — two views of the same
/// controller (inline and fullscreen) each have their own.
abstract interface class FPlayerUi {
  FPlayerController get controller;
  FUiConfig get config;
  FPlayerTheme get theme;
  FPlayerLocalizations get localizations;

  bool get areControlsVisible;

  /// Everything except the unlock affordance is ignoring input.
  bool get isLocked;

  bool get isScrubbing;

  /// Position the UI should display: the scrub preview while dragging, the real position
  /// otherwise. Read this instead of `controller.position` so the seek bar does not fight the
  /// finger.
  Duration get displayPosition;

  FVideoFit get fit;

  bool get isFullscreen;

  bool get isSettingsOpen;

  /// Shows the controls and restarts the auto-hide countdown. Call it from any custom control so
  /// interacting with your own UI does not let the chrome fade out underneath.
  void showControls();

  void hideControls();

  void toggleControls();

  void setLocked({required bool locked});

  void setFit(FVideoFit fit);

  void cycleFit();

  void openSettings();

  void closeSettings();

  void beginScrub();

  void updateScrub(Duration position);

  void endScrub();

  Future<void> toggleFullscreen();

  /// Runs the view's back action: leaves fullscreen if in it, otherwise pops the route.
  void back();
}

/// Makes the surrounding [FPlayerUi] reachable from anywhere under an `FPlayerView`.
///
/// Custom builders get it through [FPlayerScope.of] instead of having half a dozen parameters
/// threaded into them.
class FPlayerScope extends InheritedWidget {
  const FPlayerScope({
    required this.ui,
    required super.child,
    super.key,
  });

  final FPlayerUi ui;

  /// The nearest player UI. Throws when called outside an `FPlayerView`, which is a programming
  /// error rather than a state to handle.
  static FPlayerUi of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FPlayerScope>();
    assert(scope != null, 'FPlayerScope.of() called outside an FPlayerView');
    return scope!.ui;
  }

  static FPlayerUi? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FPlayerScope>()?.ui;

  @override
  bool updateShouldNotify(FPlayerScope oldWidget) => oldWidget.ui != ui;
}
