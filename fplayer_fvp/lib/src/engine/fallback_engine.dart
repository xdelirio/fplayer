import 'dart:async';

import 'package:fplayer/fplayer.dart';

import '../engine_config.dart';

import 'fvp_engine.dart';

/// Plays through Media3, and hands a source to libmdk when Media3 cannot decode it.
///
/// Wrapping both engines rather than teaching the controller about them keeps the choice out of
/// the state layer: everything above this sees one engine that happens to recover from a class of
/// failure. Pass it explicitly when you want the fallback:
///
/// ```dart
/// FPlayerController(
///   engine: FFallbackEngine(config: const FEngineConfig(mode: FEngineMode.automatic)),
/// )
/// ```
///
/// The swap costs a reload — the media restarts from the position it had reached — and the
/// player it lands on is plainer: see [FFvpEngine] for what libmdk does not do. It happens only
/// for `unsupportedFormat` and `decoder` failures, because those are the only ones a different
/// decoder can fix. A 404 or an expired token fails the same way on both.
class FFallbackEngine implements FPlaybackEngine {
  /// [primaryFactory] and [fallbackFactory] replace either side of the pair — a fake in a test,
  /// or a third engine of your own. Advanced, but public: they are the only way to compose
  /// something other than Media3 and libmdk.
  FFallbackEngine({
    FEngineConfig config = const FEngineConfig(),
    FPlaybackEngine Function()? primaryFactory,
    FPlaybackEngine Function()? fallbackFactory,
  })  : _config = config,
        _primaryFactory = primaryFactory ?? FMedia3Engine.new,
        _fallbackFactory = fallbackFactory ?? (() => FFvpEngine(config: config));

  /// Failures a different decoder could plausibly fix. Everything else fails on both engines.
  static const Set<FPlayerErrorCode> _recoverable = {
    FPlayerErrorCode.unsupportedFormat,
    FPlayerErrorCode.decoder,
  };

  final FEngineConfig _config;
  final FPlaybackEngine Function() _primaryFactory;
  final FPlaybackEngine Function() _fallbackFactory;

  final StreamController<FEngineSignal> _signals = StreamController<FEngineSignal>.broadcast();

  FPlaybackEngine? _active;
  StreamSubscription<FEngineSignal>? _subscription;
  FPlayerConfig? _config0;
  FPlayerSource? _source;
  Duration _position = Duration.zero;
  bool _hasFallenBack = false;
  bool _isSwapping = false;
  bool _isDisposed = false;

  // What the viewer had set, so the engine they land on is the one they were watching rather
  // than a fresh one with the defaults. Without this, a swap silently reset the speed, the
  // volume, the loop and every track choice, and whether it resumed playing was decided by
  // `autoPlay` rather than by what was happening a second earlier.
  double? _speed;
  double? _volume;
  bool? _isLooping;
  bool _wasPlaying = false;
  final Map<FTrackType, String?> _selectedTracks = <FTrackType, String?>{};
  List<String>? _audioLanguages;
  List<String>? _textLanguages;
  final List<FSubtitleSource> _sideLoadedSubtitles = <FSubtitleSource>[];

  /// Commands issued while the engines are being exchanged, replayed onto the new one.
  ///
  /// The swap takes seconds — a create, a prepare, a first frame — and `_active` is null for
  /// part of it. A play or a seek in that window used to reach nothing at all, with no error and
  /// no retry: the viewer pressed a button and the player ignored it.
  final List<Future<void> Function(FPlaybackEngine engine)> _deferred =
      <Future<void> Function(FPlaybackEngine engine)>[];

  /// Whether playback is currently running on libmdk rather than Media3.
  bool get isUsingFallback => _hasFallenBack;

  /// Null while there is nothing to render — before creation, and during a swap.
  ///
  /// `FPlaybackEngine` says null means "nothing to render", and the video surface only checks for
  /// null: handing out libmdk's internal `-1` had it building a `Texture(textureId: -1)` before
  /// the first frame and throughout every swap.
  @override
  int? get textureId {
    final id = _active?.textureId;
    return id == null || id == FFvpEngine.noTexture ? null : id;
  }

  /// Whichever engine is live decides this, and only Media3 ever answers with an id: the swap
  /// to libmdk is also a swap back to a texture.
  @override
  int? get platformViewId => _active?.platformViewId;

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  @override
  Future<void> create(FPlayerConfig config) async {
    if (_active != null) {
      throw StateError('FFallbackEngine has already been created');
    }

    _config0 = config;
    _hasFallenBack = _config.mode == FEngineMode.fvpOnly;
    await _activate(_hasFallenBack ? _fallbackFactory() : _primaryFactory(), config);
  }

  @override
  Future<void> setSource(FPlayerSource source) async {
    _source = source;
    _position = source.startAt ?? Duration.zero;
    // A new source starts from a clean slate: the selections belonged to the old media.
    _selectedTracks.clear();
    _sideLoadedSubtitles.clear();
    await _run((engine) => engine.setSource(source));
  }

  @override
  Future<void> play() async {
    _wasPlaying = true;
    await _run((engine) => engine.play());
  }

  @override
  Future<void> pause() async {
    _wasPlaying = false;
    await _run((engine) => engine.pause());
  }

  @override
  Future<void> stop() async {
    _wasPlaying = false;
    await _run((engine) => engine.stop());
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
    await _run((engine) => engine.seekTo(position));
  }

  @override
  Future<void> seekToDefaultPosition() async =>
      _run((engine) => engine.seekToDefaultPosition());

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _run((engine) => engine.setSpeed(speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _run((engine) => engine.setVolume(volume));
  }

  @override
  Future<void> setLooping({required bool looping}) async {
    _isLooping = looping;
    await _run((engine) => engine.setLooping(looping: looping));
  }

  @override
  Future<void> retry() async => _run((engine) => engine.retry());

  @override
  Future<void> selectTrack(FTrackType type, String? id) async {
    _selectedTracks[type] = id;
    await _run((engine) => engine.selectTrack(type, id));
  }

  @override
  Future<void> setPreferredLanguages({List<String>? audio, List<String>? text}) async {
    _audioLanguages = audio;
    _textLanguages = text;
    await _run((engine) => engine.setPreferredLanguages(audio: audio, text: text));
  }

  @override
  Future<void> addSubtitle(FSubtitleSource subtitle) async {
    _sideLoadedSubtitles.add(subtitle);
    await _run((engine) => engine.addSubtitle(subtitle));
  }

  /// Runs [command] on the active engine, or queues it when there is none.
  Future<void> _run(Future<void> Function(FPlaybackEngine engine) command) async {
    final engine = _active;
    if (engine != null) {
      await command(engine);
      return;
    }
    if (_isDisposed) return;
    if (_isSwapping) _deferred.add(command);
  }

  @override
  Future<bool> enterPip() async => await _active?.enterPip() ?? false;

  @override
  Future<void> exitPip() async => _active?.exitPip();

  @override
  Future<void> setWindowFullscreen({required bool fullscreen}) async =>
      _active?.setWindowFullscreen(fullscreen: fullscreen);

  // Delegated rather than held here: brightness is the host window's, and only the engine that
  // owns a channel to the Activity can set it. After a fallback that is nobody, so the gesture
  // goes inert — one more thing libmdk gives up, listed on [FFvpEngine].
  @override
  Future<void> setBrightness(double? brightness) async => _active?.setBrightness(brightness);

  @override
  Future<double> brightness() async => await _active?.brightness() ?? 0.5;

  @override
  Future<FEngineSnapshot> snapshot() async =>
      await _active?.snapshot() ??
      const FEngineSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
        duration: null,
        isPlaying: false,
        speed: 1,
        volume: 1,
      );

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await _subscription?.cancel();
    _subscription = null;
    _deferred.clear();
    await _active?.dispose();
    _active = null;
    await _signals.close();
  }

  Future<void> _activate(FPlaybackEngine engine, FPlayerConfig config) async {
    // Listening first, so nothing the creation reports is missed — but published as `_active`
    // only once it is built. Assigning up front meant commands were dispatched into a
    // half-constructed engine with no source, and the queue meant to hold them was unreachable.
    _subscription = engine.signals.listen(_onSignal);
    await engine.create(config);
    _active = engine;
  }

  void _onSignal(FEngineSignal signal) {
    if (_isDisposed) return;

    // Track the playhead so the fallback can resume where the primary stopped rather than
    // restarting the media from zero.
    if (signal is FEngineProgress) _position = signal.position;

    // And whether it was playing — which the composite's own `play`/`pause` cannot tell it,
    // because a pause from the lock screen, the notification or a headset button never passes
    // through here. Without this a swap resumed a video the viewer had paused.
    if (signal is FEnginePlayingChanged) _wasPlaying = signal.isPlaying;
    if (signal is FEnginePlaybackStateChanged &&
        signal.state == FEnginePlaybackState.ended) {
      _wasPlaying = false;
    }

    if (signal is FEngineFailed && _shouldFallBack(signal.error)) {
      // Swallowed on purpose: the controller would otherwise show an error and start its retry
      // ladder against an engine that is about to be replaced.
      unawaited(_swap());
      return;
    }

    if (!_signals.isClosed) _signals.add(signal);
  }

  bool _shouldFallBack(FPlayerError error) =>
      _config.mode == FEngineMode.automatic &&
      !_hasFallenBack &&
      !_isSwapping &&
      _source != null &&
      _recoverable.contains(error.code);

  /// Replaces the primary engine with libmdk and reloads the current source.
  Future<void> _swap() async {
    final config = _config0;
    final source = _source;
    if (config == null || source == null) return;

    _isSwapping = true;
    _hasFallenBack = true;

    // Keep the viewer on a spinner instead of an error: from their side this is still the same
    // video loading, just the long way round.
    if (!_signals.isClosed) {
      _signals.add(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
    }

    await _subscription?.cancel();
    _subscription = null;
    await _active?.dispose();
    _active = null;

    if (_isDisposed) return;

    try {
      await _activate(_fallbackFactory(), config);
      // Disposal can land while the new engine is being built, exactly as it can during the
      // first create. Releasing it here is what keeps a live player — and its own progress
      // timer — from outliving the owner that asked for all this.
      if (_isDisposed) {
        final orphan = _active;
        _active = null;
        await orphan?.dispose();
        return;
      }
      await _active?.setSource(source.copyWith(startAt: _position));
      await _replayState();
    } on Object catch (error) {
      // Whatever was half-built is released rather than left as the active engine: it has no
      // source, nothing will ever give it one, and every later command would be dispatched into
      // it and disappear.
      final orphan = _active;
      _active = null;
      await orphan?.dispose();

      if (!_signals.isClosed) {
        _signals.add(
          FEngineFailed(
            FPlayerError(
              code: FPlayerErrorCode.unsupportedFormat,
              message: 'Neither engine could play this media: $error',
            ),
          ),
        );
      }
    } finally {
      _isSwapping = false;
      _deferred.clear();
    }
  }

  /// Puts the new engine back into the state the viewer had the old one in.
  Future<void> _replayState() async {
    final engine = _active;
    if (engine == null) return;

    final speed = _speed;
    if (speed != null) await engine.setSpeed(speed);

    final volume = _volume;
    if (volume != null) await engine.setVolume(volume);

    final isLooping = _isLooping;
    if (isLooping != null) await engine.setLooping(looping: isLooping);

    if (_audioLanguages != null || _textLanguages != null) {
      await engine.setPreferredLanguages(audio: _audioLanguages, text: _textLanguages);
    }

    for (final subtitle in _sideLoadedSubtitles) {
      await engine.addSubtitle(subtitle);
    }

    for (final entry in _selectedTracks.entries) {
      await engine.selectTrack(entry.key, entry.value);
    }

    // Whether playback resumes is what the viewer was doing a second ago, not what `autoPlay`
    // says: a paused player must not start playing because it changed engines.
    if (_wasPlaying) {
      await engine.play();
    } else {
      await engine.pause();
    }

    // Anything pressed while the swap was running, in the order it was pressed.
    final pending = List.of(_deferred);
    _deferred.clear();
    for (final command in pending) {
      await command(engine);
    }
  }
}
