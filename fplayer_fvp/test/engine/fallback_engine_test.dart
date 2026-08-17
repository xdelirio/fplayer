import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';
import 'package:fplayer_fvp/fplayer_fvp.dart';
// Direct import until `fplayer.dart` exports the engine layer; see the phase 11 report.

/// A stand-in for either backend, so the composite's own logic can be exercised without a device.
class _StubEngine implements FPlaybackEngine {
  _StubEngine(this.name, {this.texture = 1});

  final String name;
  final int texture;
  final List<String> calls = <String>[];
  final StreamController<FEngineSignal> _signals =
      StreamController<FEngineSignal>.broadcast();

  FPlayerSource? source;
  bool isDisposed = false;

  void emit(FEngineSignal signal) => _signals.add(signal);

  @override
  int get textureId => texture;

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  @override
  Future<void> create(FPlayerConfig config) async => calls.add('create');

  @override
  Future<void> setSource(FPlayerSource value) async {
    source = value;
    calls.add('setSource:${value.uri}@${value.startAt?.inSeconds ?? 0}');
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seekTo(Duration position) async => calls.add('seekTo');

  @override
  Future<void> seekToDefaultPosition() async => calls.add('seekToDefault');

  @override
  Future<void> setSpeed(double speed) async => calls.add('setSpeed');

  @override
  Future<void> setVolume(double volume) async => calls.add('setVolume');

  @override
  Future<void> setLooping({required bool looping}) async => calls.add('setLooping');

  @override
  Future<void> retry() async => calls.add('retry');

  @override
  Future<void> selectTrack(FTrackType type, String? id) async => calls.add('selectTrack');

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

  @override
  Future<void> setBrightness(double? brightness) async => calls.add('setBrightness');

  @override
  Future<double> brightness() async => 0.5;

  @override
  Future<FEngineSnapshot> snapshot() async => const FEngineSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
        duration: null,
        isPlaying: false,
        speed: 1,
        volume: 1,
      );

  @override
  Future<void> dispose() async {
    isDisposed = true;
    calls.add('dispose');
    await _signals.close();
  }
}

void main() {
  late _StubEngine primary;
  late _StubEngine fallback;

  const source = FPlayerSource.network('https://example.com/av1.mp4');
  const decoderFailure = FEngineFailed(
    FPlayerError(code: FPlayerErrorCode.decoder, message: 'no decoder'),
  );
  const networkFailure = FEngineFailed(
    FPlayerError(code: FPlayerErrorCode.network, message: 'offline', isRetryable: true),
  );

  FFallbackEngine build(FEngineMode mode) => FFallbackEngine(
        config: FEngineConfig(mode: mode),
        primaryFactory: () => primary,
        fallbackFactory: () => fallback,
      );

  setUp(() {
    primary = _StubEngine('media3', texture: 7);
    fallback = _StubEngine('fvp', texture: 42);
  });

  test('media3Only never reaches for the fallback', () async {
    final engine = build(FEngineMode.media3Only);
    await engine.create(const FPlayerConfig());
    await engine.setSource(source);

    final seen = <FEngineSignal>[];
    engine.signals.listen(seen.add);

    primary.emit(decoderFailure);
    await Future<void>.delayed(Duration.zero);

    // The failure reaches the controller untouched, which is what makes an error screen appear.
    expect(seen.whereType<FEngineFailed>(), hasLength(1));
    expect(engine.isUsingFallback, isFalse);
    expect(fallback.calls, isEmpty);

    await engine.dispose();
  });

  test('fvpOnly starts on the fallback and never uses media3', () async {
    final engine = build(FEngineMode.fvpOnly);
    await engine.create(const FPlayerConfig());

    expect(fallback.calls, contains('create'));
    expect(primary.calls, isEmpty);
    expect(engine.textureId, 42);

    await engine.dispose();
  });

  test('automatic swaps on a decoder failure and resumes where it stopped', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());
    await engine.setSource(source);

    final seen = <FEngineSignal>[];
    engine.signals.listen(seen.add);

    primary.emit(const FEngineProgress(position: Duration(seconds: 30), buffered: Duration.zero));
    await Future<void>.delayed(Duration.zero);

    primary.emit(decoderFailure);
    await Future<void>.delayed(Duration.zero);

    expect(engine.isUsingFallback, isTrue);
    expect(primary.isDisposed, isTrue);
    // Reloaded at the position the primary had reached, not from the start.
    expect(fallback.calls, contains('setSource:https://example.com/av1.mp4@30'));
    // The failure never surfaced: from the viewer's side this is the same video still loading.
    expect(seen.whereType<FEngineFailed>(), isEmpty);
    expect(seen.whereType<FEnginePlaybackStateChanged>().last.state,
        FEnginePlaybackState.buffering);

    await engine.dispose();
  });

  test('the texture follows the engine that is playing', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());
    await engine.setSource(source);
    expect(engine.textureId, 7);

    primary.emit(decoderFailure);
    await Future<void>.delayed(Duration.zero);

    expect(engine.textureId, 42);
    await engine.dispose();
  });

  test('a failure a decoder cannot fix is passed straight through', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());
    await engine.setSource(source);

    final seen = <FEngineSignal>[];
    engine.signals.listen(seen.add);

    primary.emit(networkFailure);
    await Future<void>.delayed(Duration.zero);

    // Being offline fails the same way on both engines; swapping would only waste a reload.
    expect(seen.whereType<FEngineFailed>(), hasLength(1));
    expect(engine.isUsingFallback, isFalse);

    await engine.dispose();
  });

  test('it only falls back once', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());
    await engine.setSource(source);

    final seen = <FEngineSignal>[];
    engine.signals.listen(seen.add);

    primary.emit(decoderFailure);
    await Future<void>.delayed(Duration.zero);

    // libmdk cannot decode it either. There is nowhere left to go, so the error has to surface.
    fallback.emit(decoderFailure);
    await Future<void>.delayed(Duration.zero);

    expect(seen.whereType<FEngineFailed>(), hasLength(1));
    await engine.dispose();
  });

  test('signals from the active engine are forwarded', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());

    final seen = <FEngineSignal>[];
    engine.signals.listen(seen.add);

    primary.emit(const FEngineVolumeChanged(0.4));
    await Future<void>.delayed(Duration.zero);

    expect(seen.whereType<FEngineVolumeChanged>().single.volume, 0.4);
    await engine.dispose();
  });

  test('commands reach the active engine', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());
    await engine.setSource(source);

    await engine.play();
    await engine.setVolume(0.2);
    expect(primary.calls, containsAll(<String>['play', 'setVolume']));

    primary.emit(decoderFailure);
    await Future<void>.delayed(Duration.zero);

    await engine.pause();
    expect(fallback.calls, contains('pause'));

    await engine.dispose();
  });

  test('disposing tears down the engine in use', () async {
    final engine = build(FEngineMode.automatic);
    await engine.create(const FPlayerConfig());
    await engine.dispose();

    expect(primary.isDisposed, isTrue);
  });
}
