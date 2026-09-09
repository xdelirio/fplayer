import 'package:flutter/foundation.dart';

/// Whether the mouse-and-keyboard layout is in force.
enum FDesktopMode {
  /// On when the app runs on macOS, Windows or Linux; off everywhere else.
  auto,

  /// Always on. For a mouse-driven build on a platform the automatic choice would not pick.
  enabled,

  /// Never. The touch chrome and gestures stay in force on a desktop too.
  disabled,
}

/// How the player behaves under a mouse and a keyboard.
///
/// The desktop chrome is a different set of widgets from the touch one — `FDesktopControls`
/// instead of `FControlsOverlay` — and this decides when it is used and what the pointer and the
/// keys do over it. See `FUiConfig.desktop()` for the preset that turns it on.
@immutable
class FDesktopConfig {
  const FDesktopConfig({
    this.mode = FDesktopMode.auto,
    this.keyboardShortcuts = true,
    this.autofocus = true,
    this.clickTogglesPlayback = true,
    this.doubleClickTogglesFullscreen = true,
    this.scrollAdjustsVolume = true,
    this.hideCursorWithControls = true,
    this.volumeStep = 0.05,
  });

  final FDesktopMode mode;

  /// Space and K play or pause, left and right seek by `FPlaybackConfig.seekStep`, up and down
  /// change the volume by [volumeStep], M mutes, F toggles fullscreen and Escape leaves it. The
  /// media keys work regardless.
  final bool keyboardShortcuts;

  /// Take keyboard focus when the player appears, so the shortcuts work before the first click.
  ///
  /// Off for a player embedded beside something that needs the keyboard, such as a comment box.
  /// A click on the picture focuses it either way.
  final bool autofocus;

  /// A click on the picture plays or pauses, the way every desktop player does.
  final bool clickTogglesPlayback;

  final bool doubleClickTogglesFullscreen;

  /// The scroll wheel over the picture changes the volume.
  final bool scrollAdjustsVolume;

  /// Hide the pointer along with the controls while playing, so an idle mouse does not sit on
  /// the picture.
  final bool hideCursorWithControls;

  /// How much the volume keys and the scroll wheel move it, `0.0` to `1.0`.
  final double volumeStep;

  FDesktopConfig copyWith({
    FDesktopMode? mode,
    bool? keyboardShortcuts,
    bool? autofocus,
    bool? clickTogglesPlayback,
    bool? doubleClickTogglesFullscreen,
    bool? scrollAdjustsVolume,
    bool? hideCursorWithControls,
    double? volumeStep,
  }) =>
      FDesktopConfig(
        mode: mode ?? this.mode,
        keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
        autofocus: autofocus ?? this.autofocus,
        clickTogglesPlayback: clickTogglesPlayback ?? this.clickTogglesPlayback,
        doubleClickTogglesFullscreen:
            doubleClickTogglesFullscreen ?? this.doubleClickTogglesFullscreen,
        scrollAdjustsVolume: scrollAdjustsVolume ?? this.scrollAdjustsVolume,
        hideCursorWithControls: hideCursorWithControls ?? this.hideCursorWithControls,
        volumeStep: volumeStep ?? this.volumeStep,
      );
}
