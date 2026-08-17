/// Coarse lifecycle state of a player.
///
/// Deliberately does *not* include `playing` / `paused`: those are orthogonal to loading state
/// (a player can be paused while buffering) and live on `FPlayerValue.isPlaying`. Folding them
/// into one enum is what produces impossible states like "playing and buffering at once".
enum FPlayerStatus {
  /// No source loaded, or playback was stopped.
  idle,

  /// A source is loading for the first time. Nothing is playable yet.
  loading,

  /// Enough media is buffered to play. Whether it *is* playing depends on `isPlaying`.
  ready,

  /// Playback stalled mid-stream waiting for more data.
  buffering,

  /// Reached the end of the media.
  completed,

  /// Playback failed. See `FPlayerValue.error`.
  error,
}

extension FPlayerStatusX on FPlayerStatus {
  /// Whether a spinner is warranted: the player wants to play but cannot yet.
  bool get isWaiting => this == FPlayerStatus.loading || this == FPlayerStatus.buffering;

  /// Whether the media is loaded far enough to expose a duration and accept seeks.
  bool get isActive =>
      this == FPlayerStatus.ready ||
      this == FPlayerStatus.buffering ||
      this == FPlayerStatus.completed;
}
