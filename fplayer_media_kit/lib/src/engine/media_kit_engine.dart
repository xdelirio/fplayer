import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Rect, Size;

import 'package:flutter/painting.dart' show Alignment;
import 'package:fplayer/fplayer.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:window_manager/window_manager.dart' show windowManager;

import 'media_kit_tracks.dart';
import 'mpv_error.dart';

/// libmpv backend, for every platform the Media3 engine does not reach.
///
/// This is the engine for iOS, macOS, Windows and Linux. On Android the Media3 engine stays the
/// default — it is the one with adaptive bitrate, DRM, Picture-in-Picture, a media session and a
/// SurfaceView for televisions — and nothing here is meant to replace it there. What this engine
/// does not do, it does not pretend to:
///
/// - **No adaptive bitrate.** mpv picks one HLS or DASH variant at load time and stays on it; the
///   variants are listed as video tracks the viewer can switch between by hand, and
///   `FTracks.isVideoAuto` is false.
/// - **Picture-in-Picture is a floating window.** On a desktop there is no system PiP to hand
///   the picture to, so [enterPip] shrinks the app's own window to a corner and keeps it above
///   the others, and [exitPip] puts it back. The whole Flutter tree is in that small window,
///   which is why `FPlayerView` shows nothing but the picture while PiP is active. Not on iOS,
///   where this engine has no window to move; there `isPipSupported` stays false.
/// - **Fullscreen is the window's.** [setWindowFullscreen] uses the platform's own mode — the
///   green button on macOS, the borderless window on Windows and Linux.
/// - **No media session, no screen brightness.** Those are OS features the Android plugin
///   reaches through the Activity; no session signal is ever emitted, and the brightness
///   gesture goes inert.
/// - **No DRM.** libmpv has neither Widevine nor FairPlay, so protected content simply fails.
/// - **Subtitles are text.** mpv hands over the text of the active cue and the package renders
///   it, in the same style as on Android. Positioned cues lose their placement, and bitmap
///   subtitles (PGS, VobSub) show nothing.
/// - **Language preferences apply to the next load.** mpv resolves `alang` and `slang` when a
///   file opens, so [setPreferredLanguages] takes effect from the next [setSource].
///
/// Its texture appears once the first frame is rendered, so [textureId] is null until then; it
/// then outlives source changes, and can change when the picture changes size.
class FMediaKitEngine implements FPlaybackEngine {
  FMediaKitEngine();

  final StreamController<FEngineSignal> _signals = StreamController<FEngineSignal>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  mk.Player? _player;
  mkv.VideoController? _video;
  Timer? _ticker;
  Duration _progressInterval = const Duration(milliseconds: 250);

  FPlayerSource? _source;

  /// Bumped by every load, so a slower one cannot finish on top of a newer one.
  int _sourceGeneration = 0;
  int? _textureId;
  bool _isDisposed = false;
  bool _isTextDisabled = true;
  bool _autoPlay = true;
  bool _hasReportedInitialized = false;
  bool _hasCompleted = false;

  /// True from a load's start until the media is described, which is when mpv giving up on the
  /// file is the load failing. Trouble after that is mpv recovering on its own — a bad frame, a
  /// segment refetched — and failing the session over it would be worse than the glitch.
  bool _isOpening = false;

  /// The last reason mpv logged for the load in flight, reported if the load then fails.
  FPlayerError? _loadReason;

  /// Set by [_fail] and cleared by the next load: mpv keeps reporting — a start-file, a
  /// buffering flag — after it has given up on a file, and none of that is news once the failure
  /// is out.
  bool _hasFailed = false;
  Duration? _duration;
  Size _size = Size.zero;
  int _rotationDegrees = 0;
  double _pixelAspectRatio = 1;
  bool _isLive = false;

  mk.Tracks _tracks = const mk.Tracks();

  /// What mpv reports as selected, by property name: `vid`, `aid`, `sid`.
  final Map<String, String?> _selected = {'vid': null, 'aid': null, 'sid': null};

  /// Where the window was before Picture-in-Picture shrank it, so leaving puts it back.
  Rect? _windowBeforePip;

  /// Whether this process owns a window that can be moved and made fullscreen.
  ///
  /// True on the three desktops. iOS plays through this engine too, and has neither.
  static final bool _hasWindow = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  mk.NativePlayer get _native => _player!.platform! as mk.NativePlayer;

  /// Null until mpv has rendered a frame into a texture of real size, which is what
  /// `FPlaybackEngine` promises and what the video surface checks.
  @override
  int? get textureId => _textureId;

  /// Always null: libmpv renders into a texture and has no platform view path.
  @override
  int? get platformViewId => null;

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  @override
  Future<void> create(FPlayerConfig config) async {
    if (_player != null) {
      throw StateError('FMediaKitEngine has already been created');
    }

    mk.MediaKit.ensureInitialized();

    _progressInterval = config.playback.progressInterval;
    _autoPlay = config.playback.autoPlay;
    _isTextDisabled = !config.playback.autoSelectSubtitles;

    // libass stays off: with it, mpv would paint the subtitles into the video and the package's
    // own subtitle view — the one the style config and the Android engine feed — would draw
    // nothing. Without it, mpv exposes the active cue as text, which is what the view renders.
    //
    // Warnings are asked for because that is where ffmpeg puts the reason a load failed — the
    // HTTP status, the DNS miss — before mpv reports the failure itself at error level.
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(logLevel: mk.MPVLogLevel.warn),
    );
    _player = player;

    final decoding = config.decoding;
    _video = mkv.VideoController(
      player,
      configuration: mkv.VideoControllerConfiguration(
        enableHardwareAcceleration: decoding.mode != FDecoderMode.softwareOnly,
      ),
    );
    _video!.id.addListener(_onTextureChanged);
    _video!.rect.addListener(_onTextureChanged);

    final stream = player.stream;
    _subscriptions.addAll([
      stream.playing.listen(_onPlayingChanged),
      stream.buffering.listen(_onBufferingChanged),
      stream.completed.listen(_onCompletedChanged),
      stream.duration.listen(_onDurationChanged),
      stream.tracks.listen(_onTracksChanged),
      stream.videoParams.listen((_) => _emitVideoSize()),
      stream.subtitle.listen(_onSubtitleText),
      stream.log.listen(_onLog),
    ]);

    await player.setVolume(config.playback.volume * 100);
    await player.setRate(config.playback.speed);
    await setLooping(looping: config.playback.loop);
    await setPreferredLanguages(
      audio: config.playback.preferredAudioLanguages,
      text: config.playback.preferredTextLanguages,
    );
    // `sid` set before a load is the option mpv applies to it: off means no subtitle track is
    // picked on its own, the same as `autoSelectSubtitles: false` means on Android.
    if (_isTextDisabled) await _native.setProperty('sid', 'no');

    for (final property in _selected.keys) {
      await _native.observeProperty(property, (value) async => _onSelectedChanged(property, value));
    }

    // Binds the plugin to the main window; it refuses every other call until this has run.
    if (_hasWindow) await windowManager.ensureInitialized();
  }

  @override
  Future<void> setSource(FPlayerSource source) async {
    final player = _player;
    if (player == null || _isDisposed) return;

    // Two loads in quick succession — a retry landing on top of a source change — otherwise
    // interleave, and the loser's tracks and duration land on the winner's picture.
    final generation = ++_sourceGeneration;

    _source = source;
    _isOpening = true;
    _hasFailed = false;
    _loadReason = null;
    _hasReportedInitialized = false;
    _hasCompleted = false;
    _releaseMediaState();
    _stopTicker();

    _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
    // With every load rather than once at creation: the controller only listens once the engine
    // exists, so anything said during [create] is said to nobody.
    if (_hasWindow) _emit(FEnginePipChanged(isActive: _windowBeforePip != null, isSupported: true));

    await player.open(
      mk.Media(
        _mediaUriOf(source),
        httpHeaders: source.headers.isEmpty ? null : source.headers,
        start: source.startAt,
      ),
      play: _autoPlay,
    );
    if (_isDisposed || generation != _sourceGeneration) return;

    for (final subtitle in source.subtitles) {
      await addSubtitle(subtitle);
    }
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> stop() async {
    _isOpening = false;
    _hasFailed = false;
    await _player?.stop();
    _stopTicker();
    _hasReportedInitialized = false;
    _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.idle));
  }

  @override
  Future<void> seekTo(Duration position) async {
    final player = _player;
    if (player == null) return;
    await player.seek(position.isNegative ? Duration.zero : position);
    _emitProgress();
  }

  /// The live edge for a live stream, the start otherwise.
  ///
  /// mpv has no "default position"; the closest it offers for a live stream is the end of what
  /// it knows about, which is the edge.
  @override
  Future<void> seekToDefaultPosition() async {
    if (!_isLive) return seekTo(Duration.zero);
    await _native.command(['seek', '100', 'absolute-percent']);
    _emitProgress();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player?.setRate(speed);
    _emit(FEngineSpeedChanged(speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player?.setVolume(volume * 100);
    _emit(FEngineVolumeChanged(volume));
  }

  @override
  Future<void> setLooping({required bool looping}) async {
    await _player?.setPlaylistMode(looping ? mk.PlaylistMode.single : mk.PlaylistMode.none);
  }

  /// Reloads the current source from where playback had reached, not from where it was opened.
  @override
  Future<void> retry() async {
    final source = _source;
    if (source == null) return;
    final resumeAt = _player?.state.position ?? Duration.zero;
    await setSource(source.copyWith(startAt: resumeAt));
  }

  @override
  Future<void> selectTrack(FTrackType type, String? id) async {
    final player = _player;
    if (player == null) return;

    // Looked up rather than rebuilt from the id: media_kit treats a track it added from a URI
    // differently from one the container holds, and only the listed instance knows which it is.
    switch (type) {
      case FTrackType.audio:
        await player.setAudioTrack(
          id == null
              ? mk.AudioTrack.auto()
              : _tracks.audio.firstWhere(
                  (t) => t.id == id,
                  orElse: () => mk.AudioTrack(id, null, null),
                ),
        );
      case FTrackType.video:
        await player.setVideoTrack(
          id == null
              ? mk.VideoTrack.auto()
              : _tracks.video.firstWhere(
                  (t) => t.id == id,
                  orElse: () => mk.VideoTrack(id, null, null),
                ),
        );
      case FTrackType.text:
        _isTextDisabled = id == null;
        await player.setSubtitleTrack(
          id == null
              ? mk.SubtitleTrack.no()
              : _tracks.subtitle.firstWhere(
                  (t) => t.id == id,
                  orElse: () => mk.SubtitleTrack(id, null, null),
                ),
        );
    }
    // The `vid`/`aid`/`sid` observers report the outcome; nothing to describe here.
  }

  @override
  Future<void> setPreferredLanguages({List<String>? audio, List<String>? text}) async {
    if (_player == null) return;
    if (audio != null) await _native.setProperty('alang', audio.join(','));
    if (text != null) await _native.setProperty('slang', text.join(','));
  }

  /// Side-loads a subtitle file into the loaded media.
  ///
  /// No reload: mpv attaches external subtitles to the running file. Headers on the subtitle
  /// source are not carried — mpv fetches it with the player's own request options.
  @override
  Future<void> addSubtitle(FSubtitleSource subtitle) async {
    if (_player == null) return;
    await _native.command([
      'sub-add',
      mk.Media.normalizeURI(_uriOf(subtitle.kind, subtitle.uri, package: null)),
      subtitle.selectedByDefault ? 'select' : 'auto',
      subtitle.label ?? 'external',
      subtitle.language ?? 'auto',
    ]);
  }

  /// Shrinks the window to a corner of the screen and keeps it above the others.
  ///
  /// The size follows the picture's shape, at a width that reads as a thumbnail rather than a
  /// second player. Fullscreen is left first: a window cannot be both.
  @override
  Future<bool> enterPip() async {
    if (!_hasWindow || _windowBeforePip != null) return false;

    await windowManager.setFullScreen(false);
    _windowBeforePip = await windowManager.getBounds();

    final aspect = _size.isEmpty ? 16 / 9 : _size.width * _pixelAspectRatio / _size.height;
    const width = 400.0;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(Size(width, width / aspect));
    await windowManager.setAlignment(Alignment.bottomRight);

    _emit(const FEnginePipChanged(isActive: true, isSupported: true));
    return true;
  }

  @override
  Future<void> exitPip() async {
    final bounds = _windowBeforePip;
    if (bounds == null) return;
    _windowBeforePip = null;

    await windowManager.setAlwaysOnTop(false);
    await windowManager.setBounds(bounds);
    await windowManager.focus();

    _emit(const FEnginePipChanged(isActive: false, isSupported: true));
  }

  @override
  Future<void> setWindowFullscreen({required bool fullscreen}) async {
    if (!_hasWindow) return;
    await windowManager.setFullScreen(fullscreen);
  }

  /// No-op: window brightness belongs to the host, and this engine has no channel to it.
  @override
  Future<void> setBrightness(double? brightness) async {}

  /// Reports the neutral midpoint, which is what a gesture should start from when the real value
  /// cannot be read. Guessing the device setting would make the first drag jump.
  @override
  Future<double> brightness() async => 0.5;

  @override
  Future<FEngineSnapshot> snapshot() async {
    final state = _player?.state;
    if (state == null) {
      return const FEngineSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
        duration: null,
        isPlaying: false,
        speed: 1,
        volume: 1,
      );
    }
    return FEngineSnapshot(
      position: state.position,
      buffered: state.buffer,
      bufferedAhead: _ahead(state),
      duration: _duration,
      isPlaying: state.playing,
      speed: state.rate,
      volume: state.volume / 100,
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
    _video?.id.removeListener(_onTextureChanged);
    _video?.rect.removeListener(_onTextureChanged);
    _video = null;
    // Releases the video output with it; `VideoController` has no dispose of its own.
    await _player?.dispose();
    _player = null;
    await _signals.close();
  }

  // region Media

  String _mediaUriOf(FPlayerSource source) =>
      _uriOf(source.kind, source.uri, package: source.package);

  /// The URI mpv should open. Flutter assets go through media_kit's own `asset://` scheme, which
  /// resolves them to the bundle on every desktop and mobile platform.
  String _uriOf(FSourceKind kind, String uri, {required String? package}) => switch (kind) {
    FSourceKind.asset => 'asset:///${package == null ? '' : 'packages/$package/'}$uri',
    FSourceKind.file || FSourceKind.network => uri,
  };

  /// Forgets the media, not the texture: media_kit keeps one texture per player and resizes it,
  /// so the id survives a source change, and a source of the same size as the last one never
  /// changes the rect that would otherwise announce it.
  void _releaseMediaState() {
    _size = Size.zero;
    _duration = null;
    _tracks = const mk.Tracks();
    _selected.updateAll((_, _) => null);
  }

  /// Announces the media once mpv has read it: the moment the track list arrives.
  ///
  /// Not tied to the first frame, which an audio-only source never produces. The size reported
  /// here is whatever the texture has shown so far — zero, usually — and [_emitVideoSize] fills
  /// it in when the picture arrives.
  void _reportInitialized() {
    if (_hasReportedInitialized) return;
    _hasReportedInitialized = true;
    _isOpening = false;
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

  /// Reports the picture's geometry, but only once there is a texture to show it in.
  ///
  /// The size the controller holds stays zero until then, so that its change from zero is what
  /// wakes the video surface to pick the texture up: a signal carrying a size it already has
  /// is deduplicated upstream and would leave the surface blank.
  void _emitVideoSize() {
    final player = _player;
    if (player == null || _textureId == null) return;

    final params = player.state.videoParams;
    // Cleared between files; a texture with nothing described behind it is not a picture yet.
    if (params.w == null || params.h == null) return;
    _size = Size(params.w!.toDouble(), params.h!.toDouble());
    _rotationDegrees = params.rotate ?? 0;
    _pixelAspectRatio = params.par ?? 1;

    _emit(
      FEngineVideoSizeChanged(
        size: _size,
        rotationDegrees: _rotationDegrees,
        pixelAspectRatio: _pixelAspectRatio,
      ),
    );
  }

  void _describeTracks() {
    _emit(
      FEngineTracksChanged(
        decodeMediaKitTracks(
          _tracks,
          activeVideo: _selected['vid'],
          activeAudio: _selected['aid'],
          activeText: _selected['sid'],
          isTextDisabled: _isTextDisabled,
        ),
      ),
    );
  }

  // endregion

  // region Callbacks

  /// The texture media_kit starts with is one pixel, there to probe the render context; it is
  /// replaced by one of the video's size on the first frame. Only the second one is worth showing.
  void _onTextureChanged() {
    final video = _video;
    if (video == null || _isDisposed) return;
    final id = video.id.value;
    final rect = video.rect.value;
    final next = id != null && rect != null && rect.width > 1 && rect.height > 1 ? id : null;
    if (next == _textureId) return;
    _textureId = next;
    _emitVideoSize();
  }

  void _onPlayingChanged(bool isPlaying) {
    _emit(FEnginePlayingChanged(isPlaying: isPlaying));
    if (isPlaying) {
      _startTicker();
    } else {
      _stopTicker();
    }
    _emitProgress();
  }

  void _onBufferingChanged(bool isBuffering) {
    if (_hasCompleted && !isBuffering) return;
    _emit(
      FEnginePlaybackStateChanged(
        isBuffering ? FEnginePlaybackState.buffering : FEnginePlaybackState.ready,
      ),
    );
  }

  void _onCompletedChanged(bool isCompleted) {
    _hasCompleted = isCompleted;
    if (!isCompleted) return;
    _stopTicker();
    _emitProgress();
    _emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ended));
  }

  void _onDurationChanged(Duration duration) {
    _duration = duration > Duration.zero ? duration : null;
    _isLive = (_source?.isLive ?? false) || _duration == null;
    if (!_hasReportedInitialized) return;
    _emit(
      FEngineDurationChanged(
        duration: _duration,
        isSeekable: !_isLive && _duration != null,
        isLive: _isLive,
      ),
    );
  }

  void _onTracksChanged(mk.Tracks tracks) {
    _tracks = tracks;
    // An empty list is mpv between files, not a description of one.
    final hasAny =
        tracks.video.any((t) => isRealTrackId(t.id)) ||
        tracks.audio.any((t) => isRealTrackId(t.id)) ||
        tracks.subtitle.any((t) => isRealTrackId(t.id));
    if (!hasAny) return;
    if (!_hasReportedInitialized) {
      _onDurationChanged(_player?.state.duration ?? Duration.zero);
      _reportInitialized();
    }
    _describeTracks();
  }

  void _onSelectedChanged(String property, String value) {
    _selected[property] = isRealTrackId(value) ? value : null;
    if (_hasReportedInitialized) _describeTracks();
  }

  /// Subtitle text as mpv would render it.
  ///
  /// No geometry comes with it, so every cue takes the default bottom-centre placement. A cue
  /// that positioned itself on screen — a sign translation in a corner — loses that here.
  void _onSubtitleText(List<String> lines) {
    final text = lines.where((line) => line.trim().isNotEmpty).join('\n');
    _emit(FEngineCuesChanged([if (text.isNotEmpty) FSubtitleCue(text: text)]));
  }

  /// mpv has no failure event a client can see; what it has is the log, where the component
  /// that met the trouble says why and the player then says it gave up. The why comes first,
  /// so it is kept until the giving up arrives and reported with it.
  void _onLog(mk.PlayerLog log) {
    if (!_isOpening) return;
    final reason = classifyMpvLog(log);
    if (isMpvLoadFailure(log)) {
      _fail(_loadReason ?? reason!);
    } else if (reason != null) {
      _loadReason = reason;
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

  Duration _ahead(mk.PlayerState state) {
    final ahead = state.buffer - state.position;
    return ahead.isNegative ? Duration.zero : ahead;
  }

  void _emitProgress() {
    final state = _player?.state;
    if (state == null || _isDisposed) return;
    _emit(
      FEngineProgress(
        position: state.position,
        buffered: state.buffer,
        bufferedAhead: _ahead(state),
      ),
    );
  }

  void _fail(FPlayerError error) {
    _isOpening = false;
    _hasFailed = true;
    _stopTicker();
    _emit(FEngineFailed(error));
  }

  void _emit(FEngineSignal signal) {
    if (_isDisposed || _signals.isClosed) return;
    // Nothing follows a failure until the next load: the controller has an error to show, and a
    // buffering flag from mpv's aftermath would put a spinner over it.
    if (_hasFailed && signal is! FEngineFailed) return;
    _signals.add(signal);
  }
}
