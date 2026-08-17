import 'package:flutter/foundation.dart';

/// How playback behaves once a source is loaded.
@immutable
class FPlaybackConfig {
  const FPlaybackConfig({
    this.autoPlay = true,
    this.loop = false,
    this.speed = 1.0,
    this.volume = 1.0,
    this.seekStep = const Duration(seconds: 10),
    this.progressInterval = const Duration(milliseconds: 250),
    this.keepScreenOn = true,
    this.handleAudioFocus = true,
    this.pauseOnBecomingNoisy = true,
    this.preferredAudioLanguages = const [],
    this.preferredTextLanguages = const [],
    this.autoSelectSubtitles = false,
    this.autoAdvance = true,
    this.repeatPlaylist = false,
  });

  /// Start playing as soon as the source is ready.
  final bool autoPlay;

  /// Repeat indefinitely when playback reaches the end.
  final bool loop;

  /// Initial playback rate. `1.0` is normal speed.
  final double speed;

  /// Initial volume, `0.0` to `1.0`. This is the player's own gain, not the device volume.
  final double volume;

  /// How far a single skip-forward / skip-back jumps.
  final Duration seekStep;

  /// How often the engine reports position while playing.
  ///
  /// Lower is smoother on the seek bar but crosses the platform channel more often. 250 ms keeps
  /// a progress bar visually continuous at 60 fps without measurable cost.
  final Duration progressInterval;

  /// Hold the screen awake while frames are advancing.
  ///
  /// Tied to actual playback, not to having a source loaded: a player left paused overnight has
  /// no business keeping the display on.
  final bool keepScreenOn;

  /// Request audio focus, so playback ducks or pauses when another app takes over the speaker.
  final bool handleAudioFocus;

  /// Pause when the audio route becomes "noisy" — headphones unplugged, Bluetooth disconnected.
  final bool pauseOnBecomingNoisy;

  /// Preferred audio languages, most preferred first. BCP-47 tags.
  final List<String> preferredAudioLanguages;

  /// Preferred subtitle languages, most preferred first. BCP-47 tags.
  final List<String> preferredTextLanguages;

  /// Turn subtitles on automatically when a track matching [preferredTextLanguages] exists.
  final bool autoSelectSubtitles;

  /// Play the next queue item when one finishes.
  ///
  /// Only applies to a queue set with `setPlaylist`; a lone source opened with `open` always
  /// stops at its end.
  final bool autoAdvance;

  /// Start the queue over after the last item instead of stopping.
  final bool repeatPlaylist;

  FPlaybackConfig copyWith({
    bool? autoPlay,
    bool? loop,
    double? speed,
    double? volume,
    Duration? seekStep,
    Duration? progressInterval,
    bool? keepScreenOn,
    bool? handleAudioFocus,
    bool? pauseOnBecomingNoisy,
    List<String>? preferredAudioLanguages,
    List<String>? preferredTextLanguages,
    bool? autoSelectSubtitles,
    bool? autoAdvance,
    bool? repeatPlaylist,
  }) =>
      FPlaybackConfig(
        autoPlay: autoPlay ?? this.autoPlay,
        loop: loop ?? this.loop,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        seekStep: seekStep ?? this.seekStep,
        progressInterval: progressInterval ?? this.progressInterval,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        handleAudioFocus: handleAudioFocus ?? this.handleAudioFocus,
        pauseOnBecomingNoisy: pauseOnBecomingNoisy ?? this.pauseOnBecomingNoisy,
        preferredAudioLanguages: preferredAudioLanguages ?? this.preferredAudioLanguages,
        preferredTextLanguages: preferredTextLanguages ?? this.preferredTextLanguages,
        autoSelectSubtitles: autoSelectSubtitles ?? this.autoSelectSubtitles,
        autoAdvance: autoAdvance ?? this.autoAdvance,
        repeatPlaylist: repeatPlaylist ?? this.repeatPlaylist,
      );

  Map<String, Object?> toMap() => {
        'autoPlay': autoPlay,
        'loop': loop,
        'speed': speed,
        'volume': volume,
        'seekStepMs': seekStep.inMilliseconds,
        'progressIntervalMs': progressInterval.inMilliseconds,
        'keepScreenOn': keepScreenOn,
        'handleAudioFocus': handleAudioFocus,
        'pauseOnBecomingNoisy': pauseOnBecomingNoisy,
        'preferredAudioLanguages': preferredAudioLanguages,
        'preferredTextLanguages': preferredTextLanguages,
        'autoSelectSubtitles': autoSelectSubtitles,
      };
}
