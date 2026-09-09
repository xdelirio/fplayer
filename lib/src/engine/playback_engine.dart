import '../config/player_config.dart';
import '../models/player_source.dart';
import '../models/track.dart';
import 'engine_signal.dart';

/// Point-in-time readout pulled from the engine on demand.
///
/// Used to resync after the app returns to the foreground, where pushed progress events may have
/// been missed.
class FEngineSnapshot {
  const FEngineSnapshot({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.isPlaying,
    required this.speed,
    required this.volume,
    this.bufferedAhead = Duration.zero,
  });

  final Duration position;
  final Duration buffered;

  /// Media buffered beyond the playhead. See `FEngineProgress.bufferedAhead`.
  final Duration bufferedAhead;
  final Duration? duration;
  final bool isPlaying;
  final double speed;
  final double volume;
}

/// The playback backend behind a controller.
///
/// Everything above this interface — state, UI, TV handling, storyboard — is pure Dart and works
/// with any implementation. Today the only one is Media3; a libmdk/FFmpeg engine can be added for
/// codecs Android's own decoders do not cover.
abstract interface class FPlaybackEngine {
  /// Texture to render, or null while there is nothing to render into.
  ///
  /// Nullable because engines differ on when it exists: Media3 allocates one at [create] and
  /// keeps it for the player's life, while libmdk sizes its texture from the decoded frame, so
  /// there is none until a source is prepared and a fresh one per source.
  int? get textureId;

  /// Native player id an Android platform view binds to, or null when this engine renders into a
  /// texture instead.
  ///
  /// At most one of this and [textureId] is non-null: they are two ways of naming the same
  /// output, and which one an engine uses is decided when it is created.
  int? get platformViewId;

  /// Normalised notifications from the backend.
  Stream<FEngineSignal> get signals;

  /// Allocates the backing player and its texture.
  Future<void> create(FPlayerConfig config);

  /// Loads [source], replacing whatever was playing.
  Future<void> setSource(FPlayerSource source);

  Future<void> play();

  Future<void> pause();

  /// Stops playback and releases the loaded media, keeping the player alive.
  Future<void> stop();

  Future<void> seekTo(Duration position);

  /// Jumps to the default position — the live edge for live streams, the start otherwise.
  Future<void> seekToDefaultPosition();

  Future<void> setSpeed(double speed);

  Future<void> setVolume(double volume);

  Future<void> setLooping({required bool looping});

  /// Re-prepares the current source after a failure.
  Future<void> retry();

  /// Pins a track of [type] by id.
  ///
  /// A null [id] means "no override": subtitles turn off, audio and video fall back to the
  /// engine's own choice — which for video is bandwidth-adaptive selection.
  Future<void> selectTrack(FTrackType type, String? id);

  /// Sets the languages the engine should prefer when picking tracks automatically.
  Future<void> setPreferredLanguages({
    List<String>? audio,
    List<String>? text,
  });

  /// Attaches a subtitle file to the media that is already loaded.
  ///
  /// Reloads the source at the current position, because the subtitle set is part of the media
  /// item. Prefer declaring subtitles on the source when you know them up front.
  Future<void> addSubtitle(FSubtitleSource subtitle);

  /// Shrinks the host Activity into a Picture-in-Picture window.
  ///
  /// Returns whether the platform accepted the request. Failing is normal — the OS refuses when
  /// the Activity is not declared for PiP, when the user disabled it, or when the app is already
  /// in the background.
  Future<bool> enterPip();

  /// Restores the Activity to full screen from Picture-in-Picture.
  Future<void> exitPip();

  /// Puts the host window into the platform's fullscreen mode, or takes it out of it.
  ///
  /// A desktop concern. On Android the fullscreen route and the system bars are the whole
  /// story and the engine does nothing; an engine that owns a window is what makes it fill the
  /// screen when the viewer asks, and give the screen back when they leave.
  Future<void> setWindowFullscreen({required bool fullscreen});

  /// Sets the host window's brightness, `0.0` to `1.0`, or restores the system value with null.
  ///
  /// Scoped to the window rather than the device setting, so leaving the app puts the screen back
  /// to normal without the player having to remember to undo anything.
  Future<void> setBrightness(double? brightness);

  /// Brightness a gesture should start from: the current override, or the device setting when
  /// none is in force.
  Future<double> brightness();

  Future<FEngineSnapshot> snapshot();

  Future<void> dispose();
}
