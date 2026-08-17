/// Where a download is in its life.
enum FDownloadState {
  /// Accepted and waiting: for a free slot, or for the network and power conditions the config
  /// asks for.
  queued,

  /// Actively transferring.
  downloading,

  /// Stopped by the app. Survives restarts — a paused download stays paused until resumed.
  paused,

  /// Fully on disk and playable offline.
  completed,

  /// Gave up after exhausting retries. Re-enqueueing the same id resumes from what it already has.
  failed,

  /// Being deleted from disk.
  removing,

  /// Queued again after being removed, because the request changed.
  ///
  /// Media3 models "download this differently" as remove-then-download rather than as an edit, so
  /// a selection change surfaces here rather than looking like a fresh download.
  restarting,
}

extension FDownloadStateX on FDownloadState {
  /// Whether the bytes are on disk and the media can play without a network.
  bool get isComplete => this == FDownloadState.completed;

  /// Whether work is happening or about to.
  bool get isActive =>
      this == FDownloadState.queued ||
      this == FDownloadState.downloading ||
      this == FDownloadState.restarting;

  /// Whether nothing more will happen without the app asking.
  bool get isStopped => this == FDownloadState.paused || this == FDownloadState.failed;
}
