import 'dart:async';
import 'dart:ui' show Size;

import 'package:fplayer/fplayer.dart';

/// An [FPlaybackEngine] that answers from memory.
///
/// Lets the widget tests drive a real `FPlayerController` through states the platform would
/// otherwise have to produce — buffering, a failure, a track list — without a device.
class FakeEngine implements FPlaybackEngine {
  final StreamController<FEngineSignal> _signals =
      StreamController<FEngineSignal>.broadcast();

  final List<String> calls = <String>[];

  Duration position = Duration.zero;
  bool isDisposed = false;

  @override
  int? get textureId => 42;

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  /// Pushes a signal as if the platform had sent it.
  void emit(FEngineSignal signal) => _signals.add(signal);

  /// Drives the controller to a playing, fully described state.
  void becomeReady({
    Duration duration = const Duration(minutes: 10),
    Size size = const Size(1920, 1080),
    bool isLive = false,
  }) {
    emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.buffering));
    emit(
      FEngineInitialized(
        duration: duration,
        size: size,
        rotationDegrees: 0,
        pixelAspectRatio: 1,
        isLive: isLive,
        isSeekable: true,
      ),
    );
    emit(const FEnginePlaybackStateChanged(FEnginePlaybackState.ready));
    emit(const FEnginePlayingChanged(isPlaying: true));
  }

  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) async {
    calls.add('create');
  }

  @override
  Future<void> setSource(FPlayerSource source) async => calls.add('setSource');

  @override
  Future<void> play() async {
    calls.add('play');
    emit(const FEnginePlayingChanged(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emit(const FEnginePlayingChanged(isPlaying: false));
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seekTo:${position.inMilliseconds}');
    this.position = position;
  }

  @override
  Future<void> seekToDefaultPosition() async => calls.add('seekToDefaultPosition');

  @override
  Future<void> setSpeed(double speed) async => calls.add('setSpeed:$speed');

  @override
  Future<void> setVolume(double volume) async => calls.add('setVolume:$volume');

  @override
  Future<void> setLooping({required bool looping}) async => calls.add('setLooping:$looping');

  @override
  Future<void> retry() async => calls.add('retry');

  @override
  Future<void> selectTrack(FTrackType type, String? id) async =>
      calls.add('selectTrack:${type.name}:$id');

  @override
  Future<void> setPreferredLanguages({List<String>? audio, List<String>? text}) async =>
      calls.add('setPreferredLanguages');

  @override
  Future<void> addSubtitle(FSubtitleSource subtitle) async => calls.add('addSubtitle');

  @override
  Future<bool> enterPip() async {
    calls.add('enterPip');
    return true;
  }

  @override
  Future<void> exitPip() async => calls.add('exitPip');

  double windowBrightness = 0.5;

  @override
  Future<void> setBrightness(double? brightness) async {
    calls.add('setBrightness:$brightness');
    windowBrightness = brightness ?? 0.5;
  }

  @override
  Future<double> brightness() async => windowBrightness;

  @override
  Future<FEngineSnapshot> snapshot() async => FEngineSnapshot(
        position: position,
        buffered: position,
        duration: const Duration(minutes: 10),
        isPlaying: false,
        speed: 1,
        volume: 1,
      );

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _signals.close();
  }
}
