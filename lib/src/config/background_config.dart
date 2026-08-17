import 'package:flutter/foundation.dart';

/// What happens to playback when the app stops being visible.
enum FBackgroundMode {
  /// Unload the media. The next return to the app starts from scratch.
  stop,

  /// Pause and keep everything loaded, so resuming is instant. The safe default.
  pause,

  /// Keep playing with the screen off or the app in the background.
  ///
  /// Audio-only continuation needs a foreground service, so this mode turns the media session on
  /// whether or not [FBackgroundConfig.mediaSession] is set — without it Android would kill
  /// playback within seconds.
  continueAudio,
}

/// Appearance of the playback notification that backs the media session.
@immutable
class FNotificationConfig {
  const FNotificationConfig({
    this.channelId = 'fplayer_playback',
    this.channelName = 'Playback',
    this.smallIconResource,
  });

  /// Notification channel the playback notification is posted to.
  final String channelId;

  /// Name the user sees for that channel in system settings.
  final String channelName;

  /// Drawable resource name for the status-bar icon, e.g. `ic_stat_play`.
  ///
  /// Falls back to the app icon when null, which is legible but not what a polished app ships:
  /// status-bar icons are expected to be a flat white silhouette.
  final String? smallIconResource;

  Map<String, Object?> toMap() => {
        'channelId': channelId,
        'channelName': channelName,
        'smallIconResource': smallIconResource,
      };
}

/// Behaviour while the app is not on screen, and the media session that goes with it.
///
/// The media session is what puts the player on the lock screen, in the notification shade and
/// under the headset buttons. It is off by default because it posts a persistent notification,
/// which is wrong for a player embedded in a feed.
///
/// Enabling it requires the host app to declare `FplayerMediaService` and the foreground-service
/// permissions; see the README. When the declaration is missing the session is skipped rather
/// than crashing, and [FPlayerValue.hasMediaSession] stays false.
@immutable
class FBackgroundConfig {
  const FBackgroundConfig({
    this.mode = FBackgroundMode.pause,
    this.mediaSession = false,
    this.notification = const FNotificationConfig(),
  });

  /// Keeps audio going in the background, with the session and notification that requires.
  const FBackgroundConfig.audioInBackground({
    this.notification = const FNotificationConfig(),
  })  : mode = FBackgroundMode.continueAudio,
        mediaSession = true;

  final FBackgroundMode mode;

  /// Publish a media session: lock-screen controls, notification, headset buttons.
  final bool mediaSession;

  final FNotificationConfig notification;

  /// Whether a session is actually needed, accounting for [FBackgroundMode.continueAudio].
  bool get needsMediaSession => mediaSession || mode == FBackgroundMode.continueAudio;

  FBackgroundConfig copyWith({
    FBackgroundMode? mode,
    bool? mediaSession,
    FNotificationConfig? notification,
  }) =>
      FBackgroundConfig(
        mode: mode ?? this.mode,
        mediaSession: mediaSession ?? this.mediaSession,
        notification: notification ?? this.notification,
      );

  Map<String, Object?> toMap() => {
        'mode': mode.name,
        'mediaSession': needsMediaSession,
        'notification': notification.toMap(),
      };
}
