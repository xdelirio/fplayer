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
  FFallbackEngine({
    FEngineConfig config = const FEngineConfig(),
    @Deprecated('Testing seam') FPlaybackEngine Function()? primaryFactory,
    @Deprecated('Testing seam') FPlaybackEngine Function()? fallbackFactory,
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

  /// Whether playback is currently running on libmdk rather than Media3.
  bool get isUsingFallback => _hasFallenBack;

  @override
  int get textureId => _active?.textureId ?? FFvpEngine.noTexture;

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
    await _active?.setSource(source);
  }

  @override
  Future<void> play() async => _active?.play();

  @override
  Future<void> pause() async => _active?.pause();

  @override
  Future<void> stop() async => _active?.stop();

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
    await _active?.seekTo(position);
  }

  @override
  Future<void> seekToDefaultPosition() async => _active?.seekToDefaultPosition();

  @override
  Future<void> setSpeed(double speed) async => _active?.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) async => _active?.setVolume(volume);

  @override
  Future<void> setLooping({required bool looping}) async =>
      _active?.setLooping(looping: looping);

  @override
  Future<void> retry() async => _active?.retry();

  @override
  Future<void> selectTrack(FTrackType type, String? id) async =>
      _active?.selectTrack(type, id);

  @override
  Future<void> setPreferredLanguages({List<String>? audio, List<String>? text}) async =>
      _active?.setPreferredLanguages(audio: audio, text: text);

  @override
  Future<void> addSubtitle(FSubtitleSource subtitle) async => _active?.addSubtitle(subtitle);

  @override
  Future<bool> enterPip() async => await _active?.enterPip() ?? false;

  @override
  Future<void> exitPip() async => _active?.exitPip();

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
    await _active?.dispose();
    _active = null;
    await _signals.close();
  }

  Future<void> _activate(FPlaybackEngine engine, FPlayerConfig config) async {
    _active = engine;
    _subscription = engine.signals.listen(_onSignal);
    await engine.create(config);
  }

  void _onSignal(FEngineSignal signal) {
    if (_isDisposed) return;

    // Track the playhead so the fallback can resume where the primary stopped rather than
    // restarting the media from zero.
    if (signal is FEngineProgress) _position = signal.position;

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
      await _active?.setSource(source.copyWith(startAt: _position));
    } on Object catch (error) {
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
    }
  }
}
