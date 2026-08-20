import 'dart:async';
import 'dart:ui' show Size;

import 'package:fplayer/fplayer.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../engine_config.dart';

import 'fvp_tracks.dart';

/// libmdk/FFmpeg backend, for media the device's own decoders cannot handle.
///
/// This is a **fallback, not a peer** of the Media3 engine. It exists for one job: playing a local
/// or progressive file whose codec Android has no decoder for — AV1 on Android below 12, mostly,
/// plus the occasional exotic container. On anything else it is a downgrade, and the parts of the
/// player it cannot serve are honest no-ops rather than silent lies:
///
/// - **No adaptive bitrate.** FFmpeg's HLS and DASH demuxers pick one variant and stay there, so
///   an adaptive stream played here loses the quality ladder entirely. Do not route streaming at
///   it on purpose.
/// - **No Picture-in-Picture, no media session, no offline downloads.** Those live in the Android
///   plugin around ExoPlayer; there is nothing here to attach them to. [enterPip] returns false
///   and no PiP or session signal is ever emitted, so `FPlayerValue.isPipSupported` stays false.
/// - **No DRM.** libmdk has no Widevine, so protected content simply fails.
/// - **No screen brightness control.** That is a property of the host Activity's window, reached
///   through the Android plugin that wraps ExoPlayer; there is no channel to it from here, so the
///   brightness gesture goes inert while a source is on the fallback.
/// - **Its texture appears late and changes per source.** libmdk allocates the texture from the
///   decoded frame size, which is unknown until the media is prepared, and releases it on every
///   new source. [textureId] is `-1` until the first frame is described.
class FFvpEngine implements FPlaybackEngine {
  FFvpEngine({this.config = const FEngineConfig()});


  /// Reported until libmdk has a frame to size a texture from.
  static const int noTexture = -1;

  /// Decoder preferences and texture caps this engine was built with.
  final FEngineConfig config;
  final StreamController<FEngineSignal> _signals = StreamController<FEngineSignal>.broadcast();

  mdk.Player? _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _ticker;
  Duration _progressInterval = const Duration(milliseconds: 250);

  FPlayerSource? _source;

  /// Bumped by every load, so a slower one cannot finish on top of a newer one.
  int _sourceGeneration = 0;
  int _textureId = noTexture;
  bool _isDisposed = false;
  bool _isTextDisabled = true;
  bool _autoPlay = true;
  Duration? _duration;
  Size _size = Size.zero;
  int _rotationDegrees = 0;
  double _pixelAspectRatio = 1;
  bool _isLive = false;
  bool _hasReportedInitialized = false;
  bool _wasPlaying = false;

  @override
  /// Null while there is nothing to render, which is what `FPlaybackEngine` promises and what
  /// the video surface checks: `-1` is libmdk's own sentinel and stays inside this class.
  int? get textureId => _textureId == noTexture ? null : _textureId;

  /// Always null: libmdk renders into a texture and has no platform view path.
  @override
  int? get platformViewId => null;

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  @override
  Future<void> create(FPlayerConfig playerConfig) async {
    if (_player != null) {
      throw StateError('FFvpEngine has already been created');
    }

    _progressInterval = playerConfig.playback.progressInterval;
    _autoPlay = playerConfig.playback.autoPlay;

    final player = mdk.Player()
      ..videoDecoders = config.fvpVideoDecoders
      ..audioDecoders = config.fvpAudioDecoders
      ..volume = playerConfig.playback.volume
      ..playbackRate = playerConfig.playback.speed
      ..loop = playerConfig.playback.loop ? -1 : 0;

    _subscriptions.addAll([
      player.onStateChanged.listen((e) => _onStateChanged(e.oldValue, e.newValue)),
      player.onMediaStatus.listen((e) => _onMediaStatus(e.newValue)),
      player.onEvent.listen(_onEvent),
    ]);
    // libmdk hands subtitle text straight to Dart, so cues cross no platform channel here.
    player.onSubtitleText(_onSubtitleText);

    _player = player;
    _isTextDisabled = !playerConfig.playback.autoSelectSubtitles;
  }

  @override
  Future<void> setSource(FPlayerSource source) async {
    final player = _player;
    if (player == null || _isDisposed) return;

    // Two loads in quick succession — a retry landing on top of a source change — otherwise
    // interleave their prepare and their texture update, and the loser overwrites the winner's
    // texture and duration.
    final generation = ++_sourceGeneration;

    _source = source;
    _hasReportedInitialized = false;
    _releaseTextureState();
    _stopTicker();

    // Stop before re-pointing: libmdk keeps decoding the old media otherwise, and the first
    // progress tick of the new one would report the old position.
    player.state = mdk.PlaybackState.stopped;

    switch (source.kind) {
      case FSourceKind.asset:
        player.setAsset(source.uri, package: source.package);
      case FSourceKind.file:
      case FSourceKind.network:
        player.media = _mediaUriOf(source);
    }

    _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));

    final startAt = source.startAt ?? Duration.zero;
    final result = await player.prepare(position: startAt.inMilliseconds);
    if (_isDisposed || generation != _sourceGeneration) return;

    if (result < 0) {
      _fail(
        FPlayerError(
          code: FPlayerErrorCode.malformedContent,
          message: 'libmdk could not prepare the media (code $result)',
        ),
      );
      return;
    }

    await _attachTexture(player);
    if (_isDisposed) return;

    _describe(player);
    if (_autoPlay) {
      player.state = mdk.PlaybackState.playing;
    }
  }

  @override
  Future<void> play() async {
    _player?.state = mdk.PlaybackState.playing;
  }

  @override
  Future<void> pause() async {
    _player?.state = mdk.PlaybackState.paused;
  }

  @override
  Future<void> stop() async {
    _player?.state = mdk.PlaybackState.stopped;
    _stopTicker();
    _hasReportedInitialized = false;
    _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.idle));
  }

  @override
  Future<void> seekTo(Duration position) async {
    final player = _player;
    if (player == null) return;
    await player.seek(position: position.isNegative ? 0 : position.inMilliseconds);
    _emitProgress();
  }

  @override
  Future<void> seekToDefaultPosition() => seekTo(Duration.zero);

  @override
  Future<void> setSpeed(double speed) async {
    _player?.playbackRate = speed;
    _emit(FEngineSpeedChanged(speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    _player?.volume = volume;
    _emit(FEngineVolumeChanged(volume));
  }

  @override
  Future<void> setLooping({required bool looping}) async {
    _player?.loop = looping ? -1 : 0;
  }

  /// Reloads the current source from where playback had reached.
  ///
  /// Not from `source.startAt`: that is where this media was *opened*, so a retry forty minutes
  /// in used to throw the viewer back to minute twelve.
  @override
  Future<void> retry() async {
    final source = _source;
    if (source == null) return;
    final resumeAt = _player?.position ?? 0;
    await setSource(source.copyWith(startAt: Duration(milliseconds: resumeAt)));
  }

  @override
  Future<void> selectTrack(FTrackType type, String? id) async {
    final player = _player;
    if (player == null) return;

    final index = fvpStreamIndexOf(id);

    switch (type) {
      case FTrackType.audio:
        // libmdk takes an explicit stream list; an empty one means "no audio", which is not what
        // "let the engine choose" means, so a null id falls back to the first stream.
        player.activeAudioTracks = [index ?? 0];
      case FTrackType.video:
        player.activeVideoTracks = [index ?? 0];
      case FTrackType.text:
        _isTextDisabled = index == null;
        player.activeSubtitleTracks = index == null ? const [] : [index];
    }

    _describeTracks(player);
  }

  /// No-op: libmdk selects streams by index, not by language preference.
  ///
  /// Left silent rather than approximated — picking a stream here would override a choice the app
  /// made explicitly through [selectTrack].
  @override
  Future<void> setPreferredLanguages({List<String>? audio, List<String>? text}) async {}

  /// No-op: libmdk has no side-loaded subtitle API on this path.
  ///
  /// External subtitles are a reason to stay on the Media3 engine, which does support them.
  @override
  Future<void> addSubtitle(FSubtitleSource subtitle) async {}

  /// Always false: Picture-in-Picture is an Activity mode driven by the Android plugin, and
  /// nothing in this engine is wired to it.
  @override
  Future<bool> enterPip() async => false;

  @override
  Future<void> exitPip() async {}

  /// No-op: window brightness belongs to the Activity, and this engine has no channel to it.
  @override
  Future<void> setBrightness(double? brightness) async {}

  /// Reports the neutral midpoint, which is what a gesture should start from when the real value
  /// cannot be read. Guessing the device setting would make the first drag jump.
  @override
  Future<double> brightness() async => 0.5;

  @override
  Future<FEngineSnapshot> snapshot() async {
    final player = _player;
    if (player == null) {
      return const FEngineSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
        duration: null,
        isPlaying: false,
        speed: 1,
        volume: 1,
      );
    }

    final position = Duration(milliseconds: player.position);
    return FEngineSnapshot(
      position: position,
      buffered: position + Duration(milliseconds: player.buffered()),
      bufferedAhead: Duration(milliseconds: player.buffered()),
      duration: _duration,
      isPlaying: player.state == mdk.PlaybackState.playing,
      speed: player.playbackRate,
      volume: player.volume,
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _stopTicker();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
    await _signals.close();
  }

  // region Media

  /// The URI libmdk should open.
  ///
  /// Headers ride along as an FFmpeg option on the URL, which is the only way to carry them on
  /// this backend. It covers the common `Authorization` case; anything relying on per-request
  /// headers, such as a signed segment scheme, belongs on the Media3 engine.
  String _mediaUriOf(FPlayerSource source) {
    if (source.kind == FSourceKind.file || source.headers.isEmpty) return source.uri;

    final headers = source.headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join();
    return '${source.uri}|headers=$headers';
  }

  Future<void> _attachTexture(mdk.Player player) async {
    final generation = _sourceGeneration;
    final id = await player.updateTexture(
      width: config.fvpMaxTextureWidth,
      height: config.fvpMaxTextureHeight,
    );
    // A texture for media nobody is playing any more: the load that asked for it has been
    // overtaken, and installing it now would point the surface at the wrong picture.
    if (_isDisposed || generation != _sourceGeneration) return;
    _textureId = id;
  }

  void _releaseTextureState() {
    _textureId = noTexture;
    _size = Size.zero;
    _duration = null;
  }

  /// Reads everything the media says about itself and announces it once.
  void _describe(mdk.Player player) {
    final info = player.mediaInfo;
    final video = info.video?.firstOrNull;

    _duration = info.duration > 0 ? Duration(milliseconds: info.duration) : null;
    _isLive = player.isLive;
    _size = video == null
        ? Size.zero
        : Size(video.codec.width.toDouble(), video.codec.height.toDouble());
    _rotationDegrees = video?.rotation ?? 0;
    _pixelAspectRatio = video?.codec.par ?? 1;

    if (!_hasReportedInitialized) {
      _hasReportedInitialized = true;
      _emit(
        FEngineInitialized(
          duration: _duration,
          size: _size,
          rotationDegrees: _rotationDegrees,
          pixelAspectRatio: _pixelAspectRatio,
          isLive: _isLive,
          isSeekable: !_isLive && _duration != null,
        ),
      );
    }

    _emit(
      FEngineVideoSizeChanged(
        size: _size,
        rotationDegrees: _rotationDegrees,
        pixelAspectRatio: _pixelAspectRatio,
      ),
    );
    _describeTracks(player);
  }

  void _describeTracks(mdk.Player player) {
    _emit(
      FEngineTracksChanged(
        decodeFvpTracks(
          player.mediaInfo,
          activeAudio: player.activeAudioTracks,
          activeVideo: player.activeVideoTracks,
          activeText: player.activeSubtitleTracks,
          isTextDisabled: _isTextDisabled,
        ),
      ),
    );
  }

  // endregion

  // region Callbacks

  void _onStateChanged(mdk.PlaybackState oldValue, mdk.PlaybackState newValue) {
    final isPlaying = newValue == mdk.PlaybackState.playing;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      _emit(FEnginePlayingChanged(isPlaying: isPlaying));
    }

    if (isPlaying) {
      _startTicker();
    } else {
      _stopTicker();
    }
    _emitProgress();
  }

  void _onMediaStatus(mdk.MediaStatus newValue) {
    if (newValue.test(mdk.MediaStatus.invalid)) {
      _fail(
        const FPlayerError(
          code: FPlayerErrorCode.unsupportedFormat,
          message: 'libmdk reported the media as invalid',
        ),
      );
      return;
    }

    if (newValue.test(mdk.MediaStatus.end)) {
      _stopTicker();
      _emitProgress();
      _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
      return;
    }

    // Stalled and buffering both mean "waiting for data"; prepared and buffered both mean
    // "playable". Everything else is still on its way in.
    if (newValue.test(mdk.MediaStatus.stalled) || newValue.test(mdk.MediaStatus.buffering)) {
      _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
    } else if (newValue.test(mdk.MediaStatus.prepared) ||
        newValue.test(mdk.MediaStatus.buffered)) {
      _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ready));
    }
  }

  /// Subtitle text as libmdk renders it.
  ///
  /// No geometry comes with it, so every cue takes the default bottom-centre placement. A cue
  /// that positioned itself on screen — a sign translation in a corner — loses that here.
  void _onSubtitleText(double start, double end, List<String> text) {
    final lines = text.where((line) => line.trim().isNotEmpty).toList();
    _emit(
      FEngineCuesChanged([
        if (lines.isNotEmpty) FSubtitleCue(text: lines.join('\n')),
      ]),
    );
  }

  void _onEvent(mdk.MediaEvent event) {
    // libmdk reports decoder selection through events rather than a result code, so a decoder
    // that failed to open is the one event worth turning into an error: it is exactly the case
    // this engine exists to survive, and silently playing audio over a black screen is worse.
    if (event.category == 'decoder.video' && event.detail.contains('failed')) {
      _fail(
        FPlayerError(
          code: FPlayerErrorCode.decoder,
          message: 'libmdk could not open a video decoder: ${event.detail}',
        ),
      );
    }
  }

  // endregion

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_progressInterval, (_) => _emitProgress());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emitProgress() {
    final player = _player;
    if (player == null || _isDisposed) return;

    final position = Duration(milliseconds: player.position);
    final ahead = Duration(milliseconds: player.buffered());
    _emit(
      FEngineProgress(
        position: position,
        buffered: position + ahead,
        bufferedAhead: ahead,
      ),
    );
  }

  void _fail(FPlayerError error) {
    _stopTicker();
    _emit(FEngineFailed(error));
  }

  void _emit(FEngineSignal signal) {
    if (_isDisposed || _signals.isClosed) return;
    _signals.add(signal);
  }
}
