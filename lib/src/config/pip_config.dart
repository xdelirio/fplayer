import 'package:flutter/foundation.dart';

/// A control the system draws inside the Picture-in-Picture window.
///
/// Android caps how many fit — usually three — and drops the extras from the end of the list.
enum FPipAction {
  /// Toggles playback. Its icon follows the player, so it is worth keeping in every layout.
  playPause,

  /// Jumps forward by `FPlaybackConfig.seekStep`.
  skipForward,

  /// Jumps backward by `FPlaybackConfig.seekStep`.
  skipBackward,
}

/// Picture-in-Picture behaviour.
///
/// PiP is a property of the whole Activity, not of a widget: the system shrinks the entire app
/// window. Because this player renders into a Flutter texture, the PiP window shows whatever the
/// Flutter tree is drawing — so watch `FPlayerValue.isPipActive` and strip the UI down to the
/// video while it is true.
///
/// Requires the host Activity to declare `android:supportsPictureInPicture="true"`; see the
/// README. Without it [FPlayerValue.isPipSupported] stays false and [FPlayerController.enterPip]
/// does nothing.
@immutable
class FPipConfig {
  const FPipConfig({
    this.enabled = true,
    this.autoEnterOnLeave = false,
    this.actions = const [
      FPipAction.skipBackward,
      FPipAction.playPause,
      FPipAction.skipForward,
    ],
  });

  /// Turns Picture-in-Picture off entirely, even where the platform supports it.
  const FPipConfig.disabled()
      : enabled = false,
        autoEnterOnLeave = false,
        actions = const [];

  /// Whether the player may enter Picture-in-Picture at all.
  final bool enabled;

  /// Slip into PiP when the user leaves the app while playing, instead of only on request.
  ///
  /// Off by default: it is a strong behaviour to impose, and an app that also plays audio-only
  /// content usually wants to decide per screen. On Android 12+ the system performs the
  /// transition itself, which animates far better than reacting to the home gesture.
  final bool autoEnterOnLeave;

  /// Controls drawn in the PiP window, in order.
  final List<FPipAction> actions;

  FPipConfig copyWith({
    bool? enabled,
    bool? autoEnterOnLeave,
    List<FPipAction>? actions,
  }) =>
      FPipConfig(
        enabled: enabled ?? this.enabled,
        autoEnterOnLeave: autoEnterOnLeave ?? this.autoEnterOnLeave,
        actions: actions ?? this.actions,
      );

  Map<String, Object?> toMap() => {
        'enabled': enabled,
        'autoEnterOnLeave': autoEnterOnLeave,
        'actions': actions.map((a) => a.name).toList(),
      };
}
