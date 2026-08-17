import '../models/player_error.dart';
import '../models/track.dart';
import 'playback_metrics.dart';

/// Receives the measurable moments of a playback session.
///
/// A class with no-op methods rather than an interface, so an implementation overrides only the
/// moments it cares about — a startup-time dashboard needs [onFirstFrame] and nothing else.
///
/// Every call carries the session's cumulative [FPlaybackMetrics], so an observer never has to
/// keep its own running totals; the shape of the snapshot is the same at every callback.
///
/// Observers run on the platform thread as playback events arrive. Keep the work short and hand
/// anything slow — disk, network — to a queue.
abstract class FPlayerObserver {
  const FPlayerObserver();

  /// A source was opened and measurement began. Nothing has loaded yet.
  void onSessionStart(FPlaybackMetrics metrics) {}

  /// The picture appeared. `metrics.timeToFirstFrame` is the number a startup dashboard wants.
  void onFirstFrame(FPlaybackMetrics metrics) {}

  /// Periodic heartbeat while playing, at the interval the tracker was built with.
  ///
  /// Silent while paused: a paused player generates no watch time, and reporting it anyway is how
  /// engagement numbers end up inflated.
  void onProgress(FPlaybackMetrics metrics) {}

  /// Playback stalled after it had already started.
  void onRebufferStart(FPlaybackMetrics metrics) {}

  /// Playback recovered from a stall that lasted [stallDuration].
  void onRebufferEnd(FPlaybackMetrics metrics, Duration stallDuration) {}

  /// The rendition on screen changed, whether the selector chose it or the viewer did.
  void onQualityChanged(FPlaybackMetrics metrics, {FVideoTrack? from, FVideoTrack? to}) {}

  /// The playhead jumped.
  ///
  /// Derived from position discontinuities rather than reported by the engine, so a jump smaller
  /// than a second or two will not register.
  void onSeek(FPlaybackMetrics metrics, {required Duration from, required Duration to}) {}

  /// Something failed.
  ///
  /// [isFatal] separates the two cases worth distinguishing: a transient failure the player is
  /// about to retry, and one the viewer is now looking at.
  void onError(FPlaybackMetrics metrics, FPlayerError error, {required bool isFatal}) {}

  /// Measurement stopped. The last chance to flush anything about this session.
  void onSessionEnd(FPlaybackMetrics metrics, FSessionEndReason reason) {}
}

/// Fans one stream of observations out to several observers.
///
/// A failing observer must not take down playback measurement for the others, so each call is
/// isolated and reported through [onObserverError] instead of propagating.
class FCompositeObserver extends FPlayerObserver {
  const FCompositeObserver(this.observers, {this.onObserverError});

  final List<FPlayerObserver> observers;

  /// Called when one observer throws. Defaults to swallowing, because analytics failing is never
  /// a reason to interrupt a video.
  final void Function(FPlayerObserver observer, Object error, StackTrace stackTrace)?
      onObserverError;

  void _each(void Function(FPlayerObserver observer) action) {
    for (final observer in observers) {
      try {
        action(observer);
      } catch (error, stackTrace) {
        onObserverError?.call(observer, error, stackTrace);
      }
    }
  }

  @override
  void onSessionStart(FPlaybackMetrics metrics) => _each((o) => o.onSessionStart(metrics));

  @override
  void onFirstFrame(FPlaybackMetrics metrics) => _each((o) => o.onFirstFrame(metrics));

  @override
  void onProgress(FPlaybackMetrics metrics) => _each((o) => o.onProgress(metrics));

  @override
  void onRebufferStart(FPlaybackMetrics metrics) => _each((o) => o.onRebufferStart(metrics));

  @override
  void onRebufferEnd(FPlaybackMetrics metrics, Duration stallDuration) =>
      _each((o) => o.onRebufferEnd(metrics, stallDuration));

  @override
  void onQualityChanged(FPlaybackMetrics metrics, {FVideoTrack? from, FVideoTrack? to}) =>
      _each((o) => o.onQualityChanged(metrics, from: from, to: to));

  @override
  void onSeek(FPlaybackMetrics metrics, {required Duration from, required Duration to}) =>
      _each((o) => o.onSeek(metrics, from: from, to: to));

  @override
  void onError(FPlaybackMetrics metrics, FPlayerError error, {required bool isFatal}) =>
      _each((o) => o.onError(metrics, error, isFatal: isFatal));

  @override
  void onSessionEnd(FPlaybackMetrics metrics, FSessionEndReason reason) =>
      _each((o) => o.onSessionEnd(metrics, reason));
}
