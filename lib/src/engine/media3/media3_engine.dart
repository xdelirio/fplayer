import 'dart:async';

import 'package:flutter/services.dart';

import '../../config/player_config.dart';
import '../../models/player_error.dart';
import '../../models/player_source.dart';
import '../../models/subtitle_cue.dart';
import '../../models/track.dart';
import '../engine_signal.dart';
import '../playback_engine.dart';
import 'media3_tracks.dart';

/// Media3/ExoPlayer backend.
///
/// Each instance owns one native player, identified by [_playerId], with its own method channel
/// and event channel. Nothing is shared between instances, so several players can run at once.
class FMedia3Engine implements FPlaybackEngine {
  FMedia3Engine();

  static const MethodChannel _main = MethodChannel('dev.chikenare.fplayer');

  final StreamController<FEngineSignal> _signals = StreamController<FEngineSignal>.broadcast();

  int? _playerId;
  int? _textureId;
  MethodChannel? _channel;
  StreamSubscription<Object?>? _eventSubscription;
  bool _isDisposed = false;

  /// The `create` round-trip while it is in flight, so a disposal that lands during it can wait
  /// for the player it has to release rather than leave it running native-side.
  Future<void>? _creating;

  @override
  int? get textureId => _textureId;

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  @override
  Future<void> create(FPlayerConfig config) {
    if (_playerId != null || _creating != null) {
      throw StateError('FMedia3Engine has already been created');
    }
    if (_isDisposed) {
      throw StateError('FMedia3Engine cannot be created after being disposed');
    }

    // Held so `dispose` can await it: the native player exists from the moment this returns,
    // whether or not anyone is still waiting for it.
    return _creating = _create(config);
  }

  Future<void> _create(FPlayerConfig config) async {
    try {
      final result = await _main.invokeMapMethod<String, Object?>('create', {
        'config': config.toMap(),
      });
      if (result == null) {
        throw PlatformException(code: 'create_failed', message: 'Native player was not created');
      }

      final playerId = (result['playerId']! as num).toInt();

      // Disposal arrived while the native side was building the player. It is alive now and
      // nobody holds it, so release it here — the caller's `dispose` could not, having had no id
      // to release when it ran.
      if (_isDisposed) {
        await _main.invokeMethod<void>('dispose', {'playerId': playerId});
        return;
      }

      _playerId = playerId;
      _textureId = (result['textureId']! as num).toInt();
      _channel = MethodChannel('dev.chikenare.fplayer/player/$playerId');

      _eventSubscription = EventChannel('dev.chikenare.fplayer/player/$playerId/events')
          .receiveBroadcastStream()
          .listen(_onNativeEvent, onError: _onNativeStreamError);
    } finally {
      _creating = null;
    }
  }

  @override
  Future<void> setSource(FPlayerSource source) => _invoke('setSource', {
        'source': source.toMap(),
        // Sent alongside rather than inside the source map: `FPlayerSource.toMap` only carries
        // what the engine needs to fetch bytes, while these fields exist to label the media on
        // the lock screen and in the notification.
        'metadata': {
          'title': source.title,
          'subtitle': source.subtitle,
          'artworkUri': source.posterUrl,
        },
      });

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> seekTo(Duration position) => _invoke('seekTo', {
        'positionMs': position.isNegative ? 0 : position.inMilliseconds,
      });

  @override
  Future<void> seekToDefaultPosition() => _invoke('seekToDefaultPosition');

  @override
  Future<void> setSpeed(double speed) => _invoke('setSpeed', {'speed': speed});

  @override
  Future<void> setVolume(double volume) => _invoke('setVolume', {'volume': volume});

  @override
  Future<void> setLooping({required bool looping}) => _invoke('setLooping', {'looping': looping});

  @override
  Future<void> retry() => _invoke('retry');

  @override
  Future<void> selectTrack(FTrackType type, String? id) =>
      _invoke('selectTrack', {'type': type.name, 'id': id});

  @override
  Future<void> setPreferredLanguages({List<String>? audio, List<String>? text}) =>
      _invoke('setPreferredLanguages', {'audio': audio, 'text': text});

  @override
  Future<void> addSubtitle(FSubtitleSource subtitle) =>
      _invoke('addSubtitle', {'subtitle': subtitle.toMap()});

  @override
  Future<bool> enterPip() async {
    final channel = _channel;
    if (channel == null || _isDisposed) return false;
    return await channel.invokeMethod<bool>('enterPip') ?? false;
  }

  @override
  Future<void> exitPip() => _invoke('exitPip');

  @override
  Future<void> setBrightness(double? brightness) =>
      _invoke('setBrightness', {'brightness': brightness});

  @override
  Future<double> brightness() async {
    final channel = _channel;
    if (channel == null || _isDisposed) return 0.5;
    return await channel.invokeMethod<double>('getBrightness') ?? 0.5;
  }

  @override
  Future<FEngineSnapshot> snapshot() async {
    final channel = _channel;
    if (channel == null || _isDisposed) {
      return const FEngineSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
        duration: null,
        isPlaying: false,
        speed: 1,
        volume: 1,
      );
    }

    final map = await channel.invokeMapMethod<String, Object?>('getSnapshot') ?? const {};
    return FEngineSnapshot(
      position: _duration(map['positionMs']) ?? Duration.zero,
      buffered: _duration(map['bufferedMs']) ?? Duration.zero,
      bufferedAhead: _duration(map['bufferedAheadMs']) ?? Duration.zero,
      duration: _duration(map['durationMs']),
      isPlaying: map['isPlaying'] as bool? ?? false,
      speed: (map['speed'] as num?)?.toDouble() ?? 1,
      volume: (map['volume'] as num?)?.toDouble() ?? 1,
    );
  }

  /// Releases the native player, its texture and both channels.
  ///
  /// Every step runs even if an earlier one throws: a `MissingPluginException` on the way out —
  /// routine when the Flutter engine is detaching — must not be the reason a stream controller
  /// stays open for the life of the process.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // A create in flight owns a player that does not exist yet. Waiting for it is what makes the
    // release below reach that player instead of missing it by a few milliseconds.
    final creating = _creating;
    if (creating != null) {
      try {
        await creating;
      } on Object {
        // A failed create has nothing to release.
      }
    }

    try {
      await _eventSubscription?.cancel();
    } on Object {
      // Already gone; the release below is what matters.
    }
    _eventSubscription = null;

    final playerId = _playerId;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _playerId = null;
    _textureId = null;

    try {
      if (playerId != null) {
        await _main.invokeMethod<void>('dispose', {'playerId': playerId});
      }
    } finally {
      await _signals.close();
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    final channel = _channel;
    if (channel == null || _isDisposed) return;
    await channel.invokeMethod<void>(method, arguments);
  }

  void _onNativeEvent(Object? event) {
    if (event is! Map) return;
    final map = event.cast<Object?, Object?>();
    final signal = _decode(map);
    if (signal != null && !_signals.isClosed) {
      _signals.add(signal);
    }
  }

  /// A failure of the event channel itself, rather than one the player reported through it.
  ///
  /// The native side classifies what it can and sends it as the error payload; anything arriving
  /// here is the channel breaking. The details it does carry are kept — flattening a classified
  /// `PlatformException` into `unknown` throws away the one thing the UI branches on, and
  /// marking a setup failure retryable spends the whole retry ladder before saying anything.
  void _onNativeStreamError(Object error) {
    if (_signals.isClosed) return;

    if (error is PlatformException) {
      final details = error.details;
      _signals.add(
        FEngineFailed(
          details is Map
              ? FPlayerError.fromMap(details.cast<String, Object?>())
              : FPlayerError(
                  code: FPlayerError.codeByName(error.code) ?? FPlayerErrorCode.unknown,
                  message: error.message ?? error.code,
                  nativeCode: error.code,
                  isRetryable: false,
                ),
        ),
      );
      return;
    }

    _signals.add(
      FEngineFailed(
        FPlayerError(
          code: FPlayerErrorCode.unknown,
          message: error.toString(),
        ),
      ),
    );
  }

  FEngineSignal? _decode(Map<Object?, Object?> map) {
    switch (map['event']) {
      case 'initialized':
        return FEngineInitialized(
          duration: _duration(map['durationMs']),
          size: _size(map),
          rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
          pixelAspectRatio: (map['pixelAspectRatio'] as num?)?.toDouble() ?? 1,
          isLive: map['isLive'] as bool? ?? false,
          isSeekable: map['isSeekable'] as bool? ?? true,
        );

      case 'playbackState':
        return FEnginePlaybackStateChanged(_playbackState(map['state']));

      case 'isPlayingChanged':
        return FEnginePlayingChanged(isPlaying: map['isPlaying'] as bool? ?? false);

      case 'progress':
        return FEngineProgress(
          position: _duration(map['positionMs']) ?? Duration.zero,
          buffered: _duration(map['bufferedMs']) ?? Duration.zero,
          bufferedAhead: _duration(map['bufferedAheadMs']) ?? Duration.zero,
        );

      case 'videoSize':
        return FEngineVideoSizeChanged(
          size: _size(map),
          rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
          pixelAspectRatio: (map['pixelAspectRatio'] as num?)?.toDouble() ?? 1,
        );

      case 'durationChanged':
        return FEngineDurationChanged(
          duration: _duration(map['durationMs']),
          isSeekable: map['isSeekable'] as bool? ?? true,
        );

      case 'speedChanged':
        return FEngineSpeedChanged((map['speed'] as num?)?.toDouble() ?? 1);

      case 'volumeChanged':
        return FEngineVolumeChanged((map['volume'] as num?)?.toDouble() ?? 1);

      case 'tracks':
        return FEngineTracksChanged(decodeTracks(map));

      case 'cues':
        final raw = map['cues'] as List<Object?>? ?? const [];
        return FEngineCuesChanged([
          for (final cue in raw)
            if (cue is Map) FSubtitleCue.fromMap(cue.cast<Object?, Object?>()),
        ]);

      case 'pip':
        return FEnginePipChanged(
          isActive: map['isActive'] as bool? ?? false,
          isSupported: map['isSupported'] as bool? ?? false,
        );

      case 'connectivity':
        return FEngineConnectivityChanged(
          isOnline: map['isOnline'] as bool? ?? true,
          isWaitingForNetwork: map['isWaitingForNetwork'] as bool? ?? false,
        );

      case 'mediaSession':
        return FEngineMediaSessionChanged(isActive: map['isActive'] as bool? ?? false);

      case 'error':
        return FEngineFailed(FPlayerError.fromMap(map.cast<String, Object?>()));

      default:
        return null;
    }
  }

  static FEnginePlaybackState _playbackState(Object? raw) => switch (raw) {
        'buffering' => FEnginePlaybackState.buffering,
        'ready' => FEnginePlaybackState.ready,
        'ended' => FEnginePlaybackState.ended,
        _ => FEnginePlaybackState.idle,
      };

  static Size _size(Map<Object?, Object?> map) => Size(
        ((map['width'] as num?) ?? 0).toDouble(),
        ((map['height'] as num?) ?? 0).toDouble(),
      );

  static Duration? _duration(Object? milliseconds) {
    final value = (milliseconds as num?)?.toInt();
    if (value == null || value < 0) return null;
    return Duration(milliseconds: value);
  }
}
