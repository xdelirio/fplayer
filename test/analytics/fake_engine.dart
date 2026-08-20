import 'dart:async';

import 'package:fplayer/fplayer.dart';

/// A playback engine that plays nothing and reports whatever a test tells it to.
///
/// Uses `noSuchMethod` for the parts no test drives, so adding a method to `FPlaybackEngine` does
/// not break every analytics test that only cares about the signal stream.
class FakeEngine implements FPlaybackEngine {
  final StreamController<FEngineSignal> _signals = StreamController<FEngineSignal>.broadcast();

  bool isDisposed = false;
  FPlayerSource? lastSource;

  /// Pushes a signal as if the platform had reported it.
  void emit(FEngineSignal signal) => _signals.add(signal);

  @override
  Stream<FEngineSignal> get signals => _signals.stream;

  @override
  int get textureId => 1;

  @override
  int? get platformViewId => null;

  @override
  Future<void> create(FPlayerConfig config, {Map<String, Object?> extra = const {}}) async {}

  @override
  Future<void> setSource(FPlayerSource source) async => lastSource = source;

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _signals.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}
