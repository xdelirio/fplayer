import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';

import '../config/background_config.dart';
import '../config/player_config.dart';
import '../engine/engine_signal.dart';
import '../engine/media3/media3_engine.dart';
import '../engine/playback_engine.dart';
import '../models/player_error.dart';
import '../models/player_source.dart';
import '../models/track.dart';
import 'player_event.dart';
import 'player_status.dart';
import 'player_value.dart';

/// Drives one player and exposes its state.
///
/// A `ChangeNotifier`, so `ListenableBuilder` / `AnimatedBuilder` is all a widget needs. The
/// controller owns the engine's lifetime: create it, [open] sources on it, and [dispose] it when
/// the screen goes away.
///
/// ```dart
/// final controller = FPlayerController(
///   config: const FPlayerConfig(playback: FPlaybackConfig(autoPlay: true)),
/// );
/// await controller.open(FPlayerSource.network('https://…/master.m3u8'));
/// ```
class FPlayerController extends ChangeNotifier with WidgetsBindingObserver {
  /// [engine] replaces the Media3 backend with another implementation of [FPlaybackEngine] —
  /// `fplayer_fvp`'s libmdk engine, the fallback that composes the two, or a fake in a test.
  ///
  /// Deliberately not `@visibleForTesting`: installing an engine is the documented way to use a
  /// different backend, and that annotation made every consumer doing it fail their own
  /// analysis. It is an advanced seam, not a private one.
  FPlayerController({
    this.config = const FPlayerConfig(),
    FPlaybackEngine? engine,
  }) : _engine = engine ?? FMedia3Engine();

  final FPlayerConfig config;

  final FPlaybackEngine _engine;

  final StreamController<FPlayerEvent> _events = StreamController<FPlayerEvent>.broadcast();

  StreamSubscription<FEngineSignal>? _signals;
  Timer? _loadingTimeout;
  Timer? _retryTimer;

  /// The creation in flight, shared by every concurrent [initialize].
  Future<void>? _initializing;

  /// Where a seek asked the engine to go, until a progress tick arrives from around there.
  Duration? _pendingSeek;

  /// Ticks ignored so far while waiting for that seek to land.
  int _staleProgressTicks = 0;

  /// How far a progress tick may sit from the seek target and still count as having landed.
  static const _seekSettleWindow = Duration(seconds: 2);

  /// How many ticks to wait before believing the engine over the seek that was asked for.
  ///
  /// A seek the engine silently refuses must not freeze the position readout for the session;
  /// counting ticks rather than running a timer keeps that bound tied to the thing being
  /// guarded against, and leaves nothing pending when playback is idle.
  static const _maxStaleProgressTicks = 12;

  FPlayerValue _value = const FPlayerValue.idle();
  bool _isCreated = false;
  bool _isDisposed = false;
  bool _hasInitialized = false;
  int _retryAttempt = 0;
  double _volumeBeforeMute = 1;

  /// Current state. Read this from `build`.
  FPlayerValue get value => _value;

  /// Discrete transitions, for analytics and for reacting to specific moments.
  Stream<FPlayerEvent> get events => _events.stream;

  /// Texture to render. Null until the engine has been created.
  int? get textureId => _isCreated ? _engine.textureId : null;

  /// Whether the native player exists. The video surface cannot be built before this is true.
  bool get isEngineReady => _isCreated;

  // Conveniences that read better at call sites than reaching through `value`.
  FPlayerStatus get status => _value.status;
  bool get isPlaying => _value.isPlaying;
  bool get isPaused => _value.isPaused;
  bool get isBuffering => _value.isBuffering;
  bool get isCompleted => _value.isCompleted;
  bool get hasError => _value.hasError;
  Duration get position => _value.position;
  Duration get buffered => _value.buffered;
  Duration? get duration => _value.duration;
  double get speed => _value.speed;
  double get volume => _value.volume;
  bool get isMuted => _value.isMuted;
  FTracks get tracks => _value.tracks;
  List<FAudioTrack> get audioTracks => _value.tracks.audio;
  List<FTextTrack> get textTracks => _value.tracks.text;
  List<FVideoTrack> get videoTracks => _value.tracks.video;
  bool get isPipSupported => _value.isPipSupported;
  bool get isPipActive => _value.isPipActive;
  bool get hasMediaSession => _value.hasMediaSession;
  bool get isOnline => _value.isOnline;
  bool get isWaitingForNetwork => _value.isWaitingForNetwork;

  /// Creates the native player without loading anything.
  ///
  /// Idempotent, and called automatically by [open]. Call it explicitly to have the texture ready
  /// before the source is known — it avoids a frame of empty layout.
  ///
  /// Concurrent calls share one creation: the documented `initialize(); open(src);` pattern from
  /// a `State.initState`, where neither call can be awaited, would otherwise build two native
  /// players and register this controller with the binding twice — and the binding only ever
  /// removes one observer, which pins the controller for the life of the process.
  Future<void> initialize() {
    if (_isCreated || _isDisposed) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _engine.create(config);
    } on Object catch (error, stack) {
      // A player that cannot be created is a playback failure like any other. Left to propagate,
      // it escapes into whatever called `open` — routinely a fire-and-forget from `initState` —
      // and the UI sits on a spinner until the loading timeout invents a different reason.
      _failWith(error, stack);
      return;
    } finally {
      _initializing = null;
    }

    if (_isDisposed) {
      await _engine.dispose();
      return;
    }

    _isCreated = true;
    _signals = _engine.signals.listen(_onSignal, onError: _failWith);
    WidgetsBinding.instance.addObserver(this);
    _update(
      _value.copyWith(
        volume: config.playback.volume,
        speed: config.playback.speed,
        isLooping: config.playback.loop,
      ),
    );
  }

  /// Turns a thrown platform failure into the error state the UI already knows how to render.
  void _failWith(Object error, [StackTrace? stack]) {
    if (_isDisposed) return;
    _onFailure(
      error is FPlayerError
          ? error
          : FPlayerError(
              code: FPlayerErrorCode.unknown,
              message: error is PlatformException
                  ? (error.message ?? error.code)
                  : error.toString(),
              nativeCode: error is PlatformException ? error.code : null,
              isRetryable: true,
            ),
    );
  }

  /// Loads [source] and, unless `autoPlay` is off, starts playing it.
  ///
  /// Replaces whatever was loaded before. Safe to call repeatedly.
  Future<void> open(FPlayerSource source) =>
      _open(source, playlist: const [], index: -1);

  // region Playlist

  /// Plays through [sources] in order, starting at [startIndex].
  ///
  /// Replaces any queue already loaded. Calling [open] afterwards clears the queue again: opening
  /// a single source means "play this one thing", not "append to what was playing".
  Future<void> setPlaylist(
    List<FPlayerSource> sources, {
    int startIndex = 0,
  }) async {
    if (sources.isEmpty) {
      await stop();
      // `stop` unloads the media but keeps the queue, so that `jumpTo` still works afterwards.
      // Being handed an empty list is the one case that means "there is no queue".
      _update(_value.copyWith(playlist: const [], currentIndex: -1));
      _emit(const FPlaylistChanged([], -1));
      return;
    }

    final queue = List<FPlayerSource>.unmodifiable(sources);
    final index = startIndex.clamp(0, queue.length - 1);
    _emit(FPlaylistChanged(queue, index));
    await _open(queue[index], playlist: queue, index: index);
  }

  /// Plays the item at [index]. Out-of-range values are ignored.
  Future<void> jumpTo(int index) async {
    final queue = _value.playlist;
    if (index < 0 || index >= queue.length) return;
    await _open(queue[index], playlist: queue, index: index);
  }

  /// Advances to the next item. No-op at the end unless `repeatPlaylist` is on.
  Future<void> next() async {
    if (_value.hasNext) {
      await jumpTo(_value.currentIndex + 1);
    } else if (config.playback.repeatPlaylist && _value.hasPlaylist) {
      await jumpTo(0);
    }
  }

  /// Goes back one item.
  ///
  /// Within the first few seconds of an item it steps to the previous one; after that it restarts
  /// the current one, which is what a "previous" control does everywhere else.
  Future<void> previous() async {
    if (_value.position > const Duration(seconds: 3) || !_value.hasPrevious) {
      await seekTo(Duration.zero);
      return;
    }
    await jumpTo(_value.currentIndex - 1);
  }

  // endregion

  Future<void> _open(
    FPlayerSource source, {
    required List<FPlayerSource> playlist,
    required int index,
  }) async {
    await initialize();
    // `initialize` turns a failed creation into the error state rather than throwing, so this
    // also covers "there is no engine to load anything into".
    if (_isDisposed || !_isCreated) return;

    _cancelTimers();
    _hasInitialized = false;
    _retryAttempt = 0;

    _update(
      FPlayerValue(
        status: FPlayerStatus.loading,
        source: source,
        position: source.startAt ?? Duration.zero,
        speed: _value.speed,
        volume: _value.volume,
        isMuted: _value.isMuted,
        isLive: source.isLive,
        isLooping: _value.isLooping,
        playlist: playlist,
        currentIndex: index,
        // Platform facts, not media facts: they outlive the source being swapped.
        isOnline: _value.isOnline,
        isWaitingForNetwork: _value.isWaitingForNetwork,
        isPipSupported: _value.isPipSupported,
        isPipActive: _value.isPipActive,
        hasMediaSession: _value.hasMediaSession,
      ),
    );
    _emit(FSourceOpened(source));
    _startLoadingTimeout();

    try {
      await _engine.setSource(source);
    } on Object catch (error, stack) {
      // The native side answers a load it cannot even start with a platform error rather than an
      // error event. Without this the player waits out the whole loading timeout and then blames
      // a timeout for something it was told about immediately.
      _failWith(error, stack);
    }
  }

  Future<void> play() async {
    if (!_isCreated) return;
    // Replaying after the end should start over rather than sit at the last frame.
    if (_value.isCompleted && !_value.isLooping) {
      await _engine.seekTo(Duration.zero);
    }
    await _engine.play();
  }

  Future<void> pause() async {
    if (!_isCreated) return;
    await _engine.pause();
  }

  Future<void> togglePlayPause() => _value.isPlaying ? pause() : play();

  /// Stops playback and unloads the media, keeping the engine alive for the next [open].
  Future<void> stop() async {
    if (!_isCreated) return;
    _cancelTimers();
    _hasInitialized = false;
    // The next failure on this source deserves the whole retry ladder, not what a previous run
    // left of it.
    _retryAttempt = 0;
    await _engine.stop();
    _update(
      _value.copyWith(
        status: FPlayerStatus.idle,
        isPlaying: false,
        position: Duration.zero,
        buffered: Duration.zero,
        tracks: FTracks.empty,
        cues: const [],
        clearDuration: true,
        clearError: true,
      ),
    );
  }

  Future<void> seekTo(Duration position) async {
    if (!_isCreated || !_value.isSeekable) return;

    final from = _value.position;
    final clamped = _clampToMedia(position);
    // Move the playhead in local state first so the UI reacts on the same frame as the gesture;
    // the engine confirms it a moment later.
    _update(
      _value.copyWith(
        position: clamped,
        status: _value.isCompleted ? FPlayerStatus.ready : null,
      ),
    );
    _emit(FSeeked(from: from, to: clamped));

    // Held until the engine's own progress catches up, so a tick that was already in flight
    // cannot drag the playhead back to where the viewer just left.
    _pendingSeek = clamped;
    _staleProgressTicks = 0;

    await _engine.seekTo(clamped);
  }

  /// Seeks [delta] relative to the current position. Negative goes backwards.
  Future<void> seekBy(Duration delta) => seekTo(_value.position + delta);

  /// Skips forward by `FPlaybackConfig.seekStep`.
  Future<void> skipForward() => seekBy(config.playback.seekStep);

  /// Skips backward by `FPlaybackConfig.seekStep`.
  Future<void> skipBackward() => seekBy(-config.playback.seekStep);

  /// Jumps to the live edge. No-op for on-demand media.
  Future<void> seekToLive() async {
    if (!_isCreated || !_value.isLive) return;
    await _engine.seekToDefaultPosition();
  }

  Future<void> setSpeed(double speed) async {
    if (!_isCreated) return;
    final clamped = speed.clamp(0.25, 4.0);
    _update(_value.copyWith(speed: clamped));
    _emit(FSpeedChanged(clamped));
    await _engine.setSpeed(clamped);
  }

  /// Sets the player's own gain, `0.0` to `1.0`. Does not touch device volume.
  Future<void> setVolume(double volume) async {
    if (!_isCreated) return;
    final clamped = volume.clamp(0.0, 1.0);
    // Every road to silence is a mute, not just the mute button: a volume gesture dragged to the
    // bottom has to be what unmuting restores from, or the sound comes back at full blast.
    if (clamped == 0 && _value.volume > 0) _volumeBeforeMute = _value.volume;
    _update(_value.copyWith(volume: clamped, isMuted: clamped == 0));
    _emit(FVolumeChanged(clamped));
    await _engine.setVolume(clamped);
  }

  /// Mutes without losing the previous level, so unmuting restores it.
  Future<void> toggleMute() async {
    if (_value.isMuted) {
      await setVolume(_volumeBeforeMute == 0 ? 1 : _volumeBeforeMute);
    } else {
      await setVolume(0);
    }
  }

  Future<void> setLooping({required bool looping}) async {
    if (!_isCreated) return;
    _update(_value.copyWith(isLooping: looping));
    await _engine.setLooping(looping: looping);
  }

  // region Tracks

  /// Switches the audio rendition. Passing null returns the choice to the engine, which then
  /// follows `FPlaybackConfig.preferredAudioLanguages`.
  Future<void> selectAudioTrack(FAudioTrack? track) =>
      _selectTrack(FTrackType.audio, track?.id);

  /// Shows a subtitle track, or passes null to turn subtitles off.
  Future<void> selectTextTrack(FTextTrack? track) =>
      _selectTrack(FTrackType.text, track?.id);

  /// Turns subtitles off. Same as `selectTextTrack(null)`, spelled for readability.
  Future<void> disableSubtitles() => selectTextTrack(null);

  /// Pins the video quality. Passing null restores bandwidth-adaptive selection.
  Future<void> selectVideoTrack(FVideoTrack? track) =>
      _selectTrack(FTrackType.video, track?.id);

  /// Restores automatic quality selection.
  Future<void> enableAutoQuality() => selectVideoTrack(null);

  /// Changes the languages the engine prefers when choosing tracks on its own.
  ///
  /// Applies to the media already loaded as well as to later sources.
  Future<void> setPreferredLanguages({
    List<String>? audio,
    List<String>? text,
  }) async {
    if (!_isCreated) return;
    await _engine.setPreferredLanguages(audio: audio, text: text);
  }

  /// Attaches a subtitle file to the media already playing.
  ///
  /// The subtitle set belongs to the media item, so this reloads the source at the current
  /// position — expect a brief rebuffer. When the subtitles are known before playback, declare
  /// them on `FPlayerSource.subtitles` instead and this cost disappears.
  Future<void> addSubtitle(FSubtitleSource subtitle) async {
    if (!_isCreated || _value.source == null) return;
    await _engine.addSubtitle(subtitle);
  }

  Future<void> _selectTrack(FTrackType type, String? id) async {
    if (!_isCreated) return;
    await _engine.selectTrack(type, id);
  }

  // endregion

  // region Picture-in-Picture and lifecycle

  /// Shrinks the app into a Picture-in-Picture window.
  ///
  /// Returns whether the system accepted. It refuses when PiP is unsupported, when the host
  /// Activity does not declare `android:supportsPictureInPicture`, or when the user has revoked
  /// the permission for this app — so treat false as "offer the user something else", not as an
  /// error.
  Future<bool> enterPip() async {
    if (!_isCreated || !config.pip.enabled || !_value.isPipSupported) return false;
    return _engine.enterPip();
  }

  /// Brings the app back to full screen from Picture-in-Picture.
  Future<void> exitPip() async {
    if (!_isCreated || !_value.isPipActive) return;
    await _engine.exitPip();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isCreated || _isDisposed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        // Progress events stop while the app is away, so the seek bar would show a stale
        // position for one interval without this.
        _fireAndForget(syncFromEngine());

      case AppLifecycleState.paused:
        _applyBackgroundPolicy();

      // `inactive` also fires for a notification shade pull or a permission dialog, and it is
      // what Picture-in-Picture reports — pausing there would defeat the feature.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _applyBackgroundPolicy() {
    if (_value.isPipActive) return;

    switch (config.background.mode) {
      case FBackgroundMode.stop:
        _fireAndForget(stop());
      case FBackgroundMode.pause:
        _fireAndForget(pause());
      case FBackgroundMode.continueAudio:
        break;
    }
  }

  /// Runs a call nobody is waiting for, without letting a platform failure escape into the zone.
  ///
  /// Every one of these is triggered by something other than a user action — a lifecycle change,
  /// a timer, a signal — so there is no call site to hand the error back to. Uncaught, it becomes
  /// an app-level crash for a player that could simply have shown its error state.
  void _fireAndForget(Future<void> call) {
    unawaited(call.catchError(_failWith));
  }

  // endregion

  /// Retries the current source after a failure.
  Future<void> retry() async {
    if (!_isCreated || _isDisposed || _value.source == null) return;
    _cancelTimers();
    _retryAttempt = 0;
    _update(_value.copyWith(status: FPlayerStatus.loading, clearError: true));
    _startLoadingTimeout();
    await _engine.retry();
  }

  /// Sets the screen brightness while the player is on screen.
  ///
  /// Applies to the app's window only, so it reverts on its own when the app goes away. Pass null
  /// to hand control back to the system.
  Future<void> setBrightness(double? brightness) async {
    if (!_isCreated) return;
    await _engine.setBrightness(brightness?.clamp(0.0, 1.0));
  }

  /// Brightness a gesture should start from.
  Future<double> brightness() async {
    if (!_isCreated) return 0.5;
    return _engine.brightness();
  }

  /// Pulls fresh state from the engine.
  ///
  /// Progress events are pushed, but they stop while the app is backgrounded. Call this on resume
  /// so the seek bar does not show a stale position for one interval.
  Future<void> syncFromEngine() async {
    if (!_isCreated) return;
    final snapshot = await _engine.snapshot();
    if (_isDisposed) return;
    _update(
      _value.copyWith(
        position: snapshot.position,
        buffered: snapshot.buffered,
        bufferedAhead: snapshot.bufferedAhead,
        duration: snapshot.duration,
        isPlaying: snapshot.isPlaying,
        speed: snapshot.speed,
        volume: snapshot.volume,
      ),
    );
  }

  // region Engine signals

  void _onSignal(FEngineSignal signal) {
    if (_isDisposed) return;

    switch (signal) {
      case FEngineInitialized():
        _hasInitialized = true;
        _retryAttempt = 0;
        _loadingTimeout?.cancel();
        _update(
          _value.copyWith(
            duration: signal.duration,
            clearDuration: signal.duration == null,
            size: signal.size,
            rotationDegrees: signal.rotationDegrees,
            pixelAspectRatio: signal.pixelAspectRatio,
            isLive: signal.isLive,
            isSeekable: signal.isSeekable,
            clearError: true,
          ),
        );
        _emit(
          FInitialized(
            duration: signal.duration,
            size: signal.size,
            isLive: signal.isLive,
            isSeekable: signal.isSeekable,
          ),
        );

      case FEnginePlaybackStateChanged():
        _applyPlaybackState(signal.state);

      case FEnginePlayingChanged():
        _update(_value.copyWith(isPlaying: signal.isPlaying));
        _emit(FPlayingChanged(isPlaying: signal.isPlaying));

      case FEngineProgress():
        // A progress tick sent before the engine acted on a seek still carries the old position.
        // Applied verbatim it drags the playhead back to where the viewer just left, and the
        // scrubber rubber-bands for a tick or two. The buffered ranges are current either way.
        final isStale = _pendingSeek != null &&
            (signal.position - _pendingSeek!).abs() > _seekSettleWindow &&
            _staleProgressTicks < _maxStaleProgressTicks;
        if (isStale) {
          _staleProgressTicks++;
        } else {
          _pendingSeek = null;
          _staleProgressTicks = 0;
        }

        _update(
          _value.copyWith(
            position: isStale ? null : signal.position,
            buffered: signal.buffered,
            bufferedAhead: signal.bufferedAhead,
          ),
        );
        _emit(FPositionChanged(position: _value.position, buffered: signal.buffered));

      case FEngineVideoSizeChanged():
        _update(
          _value.copyWith(
            size: signal.size,
            rotationDegrees: signal.rotationDegrees,
            pixelAspectRatio: signal.pixelAspectRatio,
          ),
        );

      case FEngineDurationChanged():
        _update(
          _value.copyWith(
            duration: signal.duration,
            clearDuration: signal.duration == null,
            isSeekable: signal.isSeekable,
          ),
        );

      case FEngineSpeedChanged():
        if (_value.speed != signal.speed) {
          _update(_value.copyWith(speed: signal.speed));
          _emit(FSpeedChanged(signal.speed));
        }

      case FEngineVolumeChanged():
        _update(_value.copyWith(volume: signal.volume, isMuted: signal.volume == 0));

      case FEngineTracksChanged():
        final previous = _value.tracks;
        _update(_value.copyWith(tracks: signal.tracks));
        if (previous != signal.tracks) _emit(FTracksChanged(signal.tracks));

      case FEngineCuesChanged():
        // Cues arrive several times a second; skip the notify when nothing actually changed.
        if (!listEquals(_value.cues, signal.cues)) {
          _update(_value.copyWith(cues: signal.cues));
        }

      case FEnginePipChanged():
        final wasActive = _value.isPipActive;
        _update(
          _value.copyWith(
            isPipActive: signal.isActive,
            isPipSupported: signal.isSupported,
          ),
        );
        if (wasActive != signal.isActive) {
          _emit(FPipChanged(isActive: signal.isActive));
        }

      case FEngineMediaSessionChanged():
        _update(_value.copyWith(hasMediaSession: signal.isActive));

      case FEngineConnectivityChanged():
        final wasOnline = _value.isOnline;
        _update(
          _value.copyWith(
            isOnline: signal.isOnline,
            isWaitingForNetwork: signal.isWaitingForNetwork,
          ),
        );

        if (!signal.isOnline) {
          // The engine parks the failed load until the signal returns. A countdown running
          // against a network that is not there would only manufacture a timeout and spend the
          // retry budget before it is needed.
          _loadingTimeout?.cancel();
          _retryTimer?.cancel();
        } else if (!wasOnline && !_hasInitialized) {
          _startLoadingTimeout();
        }

        if (wasOnline != signal.isOnline) {
          _emit(FConnectivityChanged(isOnline: signal.isOnline));
        }

      case FEngineFailed():
        _onFailure(signal.error);
    }
  }

  void _applyPlaybackState(FEnginePlaybackState state) {
    final next = switch (state) {
      // Before the media is described, a stall is the initial load; after, it is a rebuffer.
      FEnginePlaybackState.buffering =>
        _hasInitialized ? FPlayerStatus.buffering : FPlayerStatus.loading,
      FEnginePlaybackState.ready => FPlayerStatus.ready,
      FEnginePlaybackState.ended => FPlayerStatus.completed,
      // The engine goes idle after `stop()` and after a fatal error; do not clobber the error.
      FEnginePlaybackState.idle =>
        _value.hasError ? FPlayerStatus.error : FPlayerStatus.idle,
    };

    final previous = _value.status;
    if (previous == next) return;

    _update(_value.copyWith(status: next));
    _emit(FStatusChanged(previous, next));

    if (next == FPlayerStatus.completed) {
      _emit(const FCompleted());
      // Advance after the event, so a listener that wants to do something else on completion
      // still sees the item that just ended rather than the one replacing it.
      if (config.playback.autoAdvance && _value.hasPlaylist) {
        _fireAndForget(this.next());
      }
    }
  }

  void _onFailure(FPlayerError error) {
    _loadingTimeout?.cancel();

    if (_value.isOffline) {
      // Hold rather than fail: the device has no network, so no number of attempts helps, and
      // burning them now leaves none for the moment the signal comes back.
      _update(_value.copyWith(status: FPlayerStatus.loading, clearError: true));
      return;
    }

    final policy = config.network.retry;
    if (error.isRetryable && _retryAttempt < policy.maxAttempts) {
      final delay = policy.delayFor(_retryAttempt);
      _retryAttempt++;
      _emit(FRetryScheduled(attempt: _retryAttempt, delay: delay, error: error));
      // Stay in `loading`: from the user's point of view the player is still trying, and flashing
      // an error overlay that disappears two seconds later is worse than a spinner.
      _update(_value.copyWith(status: FPlayerStatus.loading, clearError: true));

      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        if (_isDisposed || !_isCreated) return;
        _fireAndForget(_engine.retry());
        _startLoadingTimeout();
      });
      return;
    }

    _update(
      _value.copyWith(status: FPlayerStatus.error, isPlaying: false, error: error),
    );
    _emit(FErrorOccurred(error));
  }

  // endregion

  void _startLoadingTimeout() {
    _loadingTimeout?.cancel();
    final timeout = config.network.loadingTimeout;
    if (timeout <= Duration.zero) return;

    _loadingTimeout = Timer(timeout, () {
      if (_isDisposed || _hasInitialized) return;
      _onFailure(
        FPlayerError(
          code: FPlayerErrorCode.timeout,
          message: 'The source did not become playable within '
              '${timeout.inSeconds}s',
          isRetryable: true,
        ),
      );
    });
  }

  Duration _clampToMedia(Duration position) {
    if (position.isNegative) return Duration.zero;
    final total = _value.duration;
    if (total != null && position > total) return total;
    return position;
  }

  void _update(FPlayerValue next) {
    if (_isDisposed || identical(_value, next)) return;
    _value = next;
    notifyListeners();
  }

  void _emit(FPlayerEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _cancelTimers() {
    _loadingTimeout?.cancel();
    _loadingTimeout = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingSeek = null;
    _staleProgressTicks = 0;
  }

  /// Releases the engine, the timers and the streams.
  ///
  /// Every step runs even if an earlier one throws. Disposal is routinely called from a
  /// `State.dispose` that cannot await it, and a platform call failing on the way out — which is
  /// ordinary while the Flutter engine detaches — must not leave the notifier and its two stream
  /// controllers behind for the life of the process.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _cancelTimers();
    if (_isCreated) WidgetsBinding.instance.removeObserver(this);
    _isCreated = false;

    try {
      await _signals?.cancel();
    } on Object {
      // Nothing left to hear from.
    }
    _signals = null;

    try {
      await _engine.dispose();
    } finally {
      await _events.close();
      super.dispose();
    }
  }
}
