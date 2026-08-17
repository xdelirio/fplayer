import 'package:flutter/foundation.dart';

/// Conditions that must hold before a download will run.
///
/// Enforced by the platform, not by the app: a download waiting on Wi-Fi resumes on its own when
/// Wi-Fi returns, even if the app is not running.
@immutable
class FDownloadRequirements {
  const FDownloadRequirements({
    this.network = true,
    this.unmeteredNetwork = false,
    this.charging = false,
    this.deviceIdle = false,
    this.storageNotLow = true,
  });

  /// What most video apps offer as a "download over Wi-Fi only" switch.
  const FDownloadRequirements.unmeteredOnly()
      : network = true,
        unmeteredNetwork = true,
        charging = false,
        deviceIdle = false,
        storageNotLow = true;

  /// Any network at all.
  final bool network;

  /// Wi-Fi or another connection the system does not consider metered.
  final bool unmeteredNetwork;

  final bool charging;

  /// Only while the device is idle. Suits a large library sync; too aggressive for a single
  /// episode someone is waiting on.
  final bool deviceIdle;

  /// Pause rather than fill the last of the user's storage.
  final bool storageNotLow;

  Map<String, Object?> toMap() => {
        'network': network,
        'unmeteredNetwork': unmeteredNetwork,
        'charging': charging,
        'deviceIdle': deviceIdle,
        'storageNotLow': storageNotLow,
      };
}

/// The notification the download service shows while it works.
///
/// Android requires a foreground service — and therefore a visible notification — for work that
/// should survive the app going to the background.
@immutable
class FDownloadNotificationConfig {
  const FDownloadNotificationConfig({
    this.channelId = 'fplayer_downloads',
    this.channelName = 'Downloads',
    this.smallIconResource,
  });

  final String channelId;
  final String channelName;

  /// Name of a drawable in the host app, without extension. Falls back to the app icon.
  final String? smallIconResource;

  Map<String, Object?> toMap() => {
        'channelId': channelId,
        'channelName': channelName,
        'smallIconResource': smallIconResource,
      };
}

/// How offline downloads behave.
///
/// Passed once to [FDownloadManager.initialize]; the settings are process-wide because the cache
/// and the queue are.
@immutable
class FDownloadConfig {
  const FDownloadConfig({
    this.maxParallelDownloads = 3,
    this.minRetryCount = 5,
    this.requirements = const FDownloadRequirements(),
    this.notification = const FDownloadNotificationConfig(),
    this.directoryName = 'fplayer_downloads',
    this.progressInterval = const Duration(seconds: 1),
  });

  /// How many downloads transfer at once.
  ///
  /// More is not faster on a phone: the segments share one connection budget, and running six at
  /// once mostly means six half-finished episodes instead of three whole ones.
  final int maxParallelDownloads;

  /// Attempts per segment before the whole download is marked failed.
  final int minRetryCount;

  final FDownloadRequirements requirements;
  final FDownloadNotificationConfig notification;

  /// Folder under the app's own files directory where the bytes live.
  ///
  /// Inside app storage, so uninstalling the app reclaims the space and no storage permission is
  /// involved. It is not visible to the gallery or to other apps, which is usually what a
  /// licensed-content app wants.
  final String directoryName;

  /// How often the queue is re-published while something is transferring.
  ///
  /// The platform reports state changes but not byte-by-byte progress, so a percentage needs
  /// polling. One second is smooth enough for a progress bar and cheap.
  final Duration progressInterval;

  FDownloadConfig copyWith({
    int? maxParallelDownloads,
    int? minRetryCount,
    FDownloadRequirements? requirements,
    FDownloadNotificationConfig? notification,
    String? directoryName,
    Duration? progressInterval,
  }) =>
      FDownloadConfig(
        maxParallelDownloads: maxParallelDownloads ?? this.maxParallelDownloads,
        minRetryCount: minRetryCount ?? this.minRetryCount,
        requirements: requirements ?? this.requirements,
        notification: notification ?? this.notification,
        directoryName: directoryName ?? this.directoryName,
        progressInterval: progressInterval ?? this.progressInterval,
      );

  Map<String, Object?> toMap() => {
        'maxParallelDownloads': maxParallelDownloads,
        'minRetryCount': minRetryCount,
        'requirements': requirements.toMap(),
        'notification': notification.toMap(),
        'directoryName': directoryName,
        'progressIntervalMs': progressInterval.inMilliseconds,
      };
}
