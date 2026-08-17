import 'dart:async';
import 'dart:math';

import '../core/player_controller.dart';
import '../core/player_event.dart';
import '../core/player_status.dart';
import '../models/player_source.dart';
import '../models/track.dart';
import 'playback_metrics.dart';
import 'player_observer.dart';
import 'session_id.dart';

/// Turns a controller's event stream into playback measurements.
///
/// Attaches from the outside: it listens to `FPlayerController.events` and to the controller
/// itself, and never reaches into the engine. That keeps measurement optional — an app that does
/// not want analytics simply never builds one — and keeps the core free of reporting concerns.
///
/// ```dart
/// final tracker = FPlaybackSessionTracker(
///   controller: controller,
///   observers: [MyObserver()],
/// );
/// // ...
/// tracker.dispose();
/// ```
class FPlaybackSessionTracker {
  FPlaybackSessionTracker({
    required this.controller,
    List<FPlayerObserver> observers = const [],
    this.progressInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    Random? random,
  })  : _observer = FCompositeObserver(observers),
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure() {
    _events = controller.events.listen(_onEvent);
    controller.addListener(_onValueChanged);
  }

  final FPlayerController controller;

  /// How often [FPlayerObserver.onProgress] fires while playing.
  final Duration progressInterval;

  final FPlayerObserver _observer;
  final DateTime Function() _clock;
  final Random _random;

  StreamSubscription<FPlayerEvent>? _events;

  // Session identity.
  String? _sessionId;
  DateTime? _startedAt;
  String? _contentTitle;
  Object? _sourceMetadata;

  // Sampling state. Everything accumulates between these marks.
  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPlaying = false;

  /// The source of the session that ended, so replaying the same media can open a new one.
  FPlayerSource? _lastSource;
  double _speed = 1;
  FVideoTrack? _activeVideo;

  // Accumulators.
  double _watchedMs = 0;
  int _rebufferMs = 0;
  int _rebufferCount = 0;
  int _seekCount = 0;
  int _qualityChangeCount = 0;
  int _retryCount = 0;
  int _errorCount = 0;
  int _bitrateWeighted = 0;
  int _heightWeighted = 0;
  int _qualityWeightMs = 0;
  int? _peakVideoHeight;

  bool _isRebuffering = false;
  DateTime? _rebufferStartedAt;
  bool _hasFirstFrame = false;
  Duration? _timeToFirstFrame;
  bool _hasUnrecoveredError = false;

  DateTime? _lastProgressAt;

  /// The session in flight, or null when nothing is being measured.
  FPlaybackMetrics? get metrics => _sessionId == null ? null : _snapshot();

  bool get hasSession => _sessionId != null;

  /// Stops measuring and closes the open session, if any.
  void dispose() {
    _endSession(
      _hasUnrecoveredError ? FSessionEndReason.error : FSessionEndReason.disposed,
    );
    unawaited(_events?.cancel());
    _events = null;
    controller.removeListener(_onValueChanged);
  }

  // region Event handling

  void _onEvent(FPlayerEvent event) {
    switch (event) {
      case FSourceOpened():
        _endSession(FSessionEndReason.sourceChanged);
        _lastSource = event.source;
        _startSession(
          title: event.source.title,
          metadata: event.source.metadata,
        );

      case FSeeked():
        if (_sessionId == null) return;
        _accumulate();
        _seekCount++;
        _observer.onSeek(_snapshot(), from: event.from, to: event.to);

      case FInitialized():
        if (_sessionId == null || _hasFirstFrame) return;
        final now = _accumulate();
        _hasFirstFrame = true;
        _timeToFirstFrame = now.difference(_startedAt!);
        _observer.onFirstFrame(_snapshot());

      case FStatusChanged():
        _onStatusChanged(event);

      case FPositionChanged():
        _onPositionChanged(event);

      case FCompleted():
        _endSession(FSessionEndReason.completed);

      case FRetryScheduled():
        if (_sessionId == null) return;
        _accumulate();
        _retryCount++;
        _observer.onError(_snapshot(), event.error, isFatal: false);

      case FErrorOccurred():
        if (_sessionId == null) return;
        _accumulate();
        _errorCount++;
        _hasUnrecoveredError = true;
        _observer.onError(_snapshot(), event.error, isFatal: true);

      // Playing, speed and the active rendition are all read from `value` instead, because not
      // every change to them is announced as an event.
      // Replacing the queue is not a measurable moment on its own; each item announces itself
      // with FSourceOpened when it starts.
      case FConnectivityChanged():
      case FPlaylistChanged():
      case FPlayingChanged():
      case FSpeedChanged():
      case FTracksChanged():
      case FVolumeChanged():
      case FPipChanged():
        break;
    }
  }

  void _onStatusChanged(FStatusChanged event) {
    if (_sessionId == null) return;

    // Waiting before the first frame is startup, not a rebuffer. Conflating them makes every
    // session look like it stalled once, and buries the stalls that actually hurt.
    final isStalling = event.current == FPlayerStatus.buffering && _hasFirstFrame;

    if (isStalling && !_isRebuffering) {
      final now = _accumulate();
      _isRebuffering = true;
      _rebufferStartedAt = now;
      _rebufferCount++;
      _observer.onRebufferStart(_snapshot());
      return;
    }

    if (!isStalling && _isRebuffering) {
      final now = _accumulate();
      final stall = now.difference(_rebufferStartedAt ?? now);
      _isRebuffering = false;
      _rebufferStartedAt = null;
      _observer.onRebufferEnd(_snapshot(), stall);
    }

    if (event.current == FPlayerStatus.ready) _hasUnrecoveredError = false;
  }

  void _onPositionChanged(FPositionChanged event) {
    if (_sessionId == null) return;

    final now = _accumulate();

    final since = _lastProgressAt;
    if (_isPlaying && (since == null || now.difference(since) >= progressInterval)) {
      _lastProgressAt = now;
      _observer.onProgress(_snapshot());
    }
  }

  /// Picks up every property the accumulators weight time by.
  ///
  /// Read from `value` rather than from the event stream on purpose. The controller emits
  /// `FSpeedChanged` when the app calls `setSpeed`, but not when the engine reports a rate change
  /// on its own, and the adaptive selector moves between renditions with no event at all. `value`
  /// is the one place that is always right.
  void _onValueChanged() {
    final value = controller.value;

    // Watching the same video again is a second session, not nothing. Only `FSourceOpened`
    // started one, and replay does not re-open a source — so every replay was invisible: no
    // watch time, no stalls, no telemetry at all.
    if (_sessionId == null) {
      if (value.isPlaying && _lastSource != null) {
        _startSession(title: _lastSource!.title, metadata: _lastSource!.metadata);
        _isPlaying = true;
      }
      return;
    }

    final active = value.tracks.activeVideo;

    final hasPlayingChanged = value.isPlaying != _isPlaying;
    final hasSpeedChanged = value.speed != _speed;
    final hasQualityChanged = active?.id != _activeVideo?.id;
    if (!hasPlayingChanged && !hasSpeedChanged && !hasQualityChanged) return;

    // Close the current slice against the old values before adopting the new ones, so each stretch
    // of time is weighted by the state that was actually in force during it.
    _accumulate();

    _isPlaying = value.isPlaying;
    _speed = value.speed;

    if (!hasQualityChanged) return;

    final previous = _activeVideo;
    _activeVideo = active;

    final height = active?.height;
    if (height != null && (_peakVideoHeight == null || height > _peakVideoHeight!)) {
      _peakVideoHeight = height;
    }

    // The first rendition of a session is a selection, not a switch: counting it would report a
    // quality change on every video ever played.
    if (previous == null) return;

    _qualityChangeCount++;
    _observer.onQualityChanged(_snapshot(), from: previous, to: active);
  }

  // endregion

  // region Session lifecycle

  void _startSession({String? title, Object? metadata}) {
    final now = _clock();

    _sessionId = FSessionId.generate(at: now, random: _random);
    _startedAt = now;
    _lastSampleAt = now;
    _contentTitle = title;
    _sourceMetadata = metadata;

    _isPlaying = controller.value.isPlaying;
    _speed = controller.value.speed;
    _activeVideo = controller.value.tracks.activeVideo;

    _watchedMs = 0;
    _rebufferMs = 0;
    _rebufferCount = 0;
    _seekCount = 0;
    _qualityChangeCount = 0;
    _retryCount = 0;
    _errorCount = 0;
    _bitrateWeighted = 0;
    _heightWeighted = 0;
    _qualityWeightMs = 0;
    _peakVideoHeight = _activeVideo?.height;

    _isRebuffering = false;
    _rebufferStartedAt = null;
    _hasFirstFrame = false;
    _timeToFirstFrame = null;
    _hasUnrecoveredError = false;

    _lastProgressAt = null;

    _observer.onSessionStart(_snapshot());
  }

  void _endSession(FSessionEndReason reason) {
    if (_sessionId == null) return;

    _accumulate();
    _observer.onSessionEnd(_snapshot(), reason);

    _sessionId = null;
    _startedAt = null;
    _isRebuffering = false;
    _rebufferStartedAt = null;
  }

  // endregion

  /// Folds the time since the last mark into the accumulators, and returns the new mark.
  ///
  /// Called before every state change so each slice of time is attributed to the state that was
  /// actually in force during it.
  DateTime _accumulate() {
    final now = _clock();
    if (_sessionId == null) return now;

    final elapsedMs = now.difference(_lastSampleAt).inMilliseconds;
    _lastSampleAt = now;
    if (elapsedMs <= 0) return now;

    if (_isRebuffering) {
      _rebufferMs += elapsedMs;
      return now;
    }

    if (!_isPlaying) return now;

    _watchedMs += elapsedMs * _speed;

    final track = _activeVideo;
    if (track != null) {
      _qualityWeightMs += elapsedMs;
      final bitrate = track.bitrate;
      if (bitrate != null) _bitrateWeighted += bitrate * elapsedMs;
      final height = track.height;
      if (height != null) _heightWeighted += height * elapsedMs;
    }

    return now;
  }

  FPlaybackMetrics _snapshot() {
    final now = _lastSampleAt;
    final value = controller.value;

    return FPlaybackMetrics(
      sessionId: _sessionId!,
      startedAt: _startedAt!,
      updatedAt: now,
      contentTitle: _contentTitle,
      sourceMetadata: _sourceMetadata,
      watchedTime: Duration(milliseconds: _watchedMs.round()),
      wallClockTime: now.difference(_startedAt!),
      timeToFirstFrame: _timeToFirstFrame,
      rebufferCount: _rebufferCount,
      rebufferTime: Duration(milliseconds: _rebufferMs),
      seekCount: _seekCount,
      qualityChangeCount: _qualityChangeCount,
      retryCount: _retryCount,
      errorCount: _errorCount,
      position: value.position,
      duration: value.duration,
      isLive: value.isLive,
      averageBitrate: _qualityWeightMs == 0 ? null : _bitrateWeighted ~/ _qualityWeightMs,
      averageVideoHeight:
          _qualityWeightMs == 0 ? null : _heightWeighted / _qualityWeightMs,
      peakVideoHeight: _peakVideoHeight,
    );
  }
}
