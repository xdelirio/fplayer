import 'dart:async';

import 'package:fplayer/fplayer.dart';

/// An [FDownloadPlatform] that keeps the queue in memory.
///
/// Lets the manager's own behaviour — ordering, aggregate progress, the guard against using an
/// uninitialised queue — be tested without a device.
class FakeDownloadPlatform implements FDownloadPlatform {
  final StreamController<List<FDownloadItem>> _queue =
      StreamController<List<FDownloadItem>>.broadcast();

  final List<String> calls = <String>[];
  final Map<String, FDownloadItem> items = <String, FDownloadItem>{};

  FDownloadOptions options = const FDownloadOptions();
  FDownloadConfig? config;
  bool isDisposed = false;

  @override
  Stream<List<FDownloadItem>> get queue => _queue.stream;

  /// Pushes the current queue to listeners, as the platform would after a change.
  ///
  /// Silent once disposed, the way a closed platform channel is.
  void emit() {
    if (_queue.isClosed) return;
    _queue.add(items.values.toList());
  }

  /// Adds or replaces an entry and publishes it.
  void put(FDownloadItem item) {
    items[item.id] = item;
    emit();
  }

  @override
  Future<void> initialize(FDownloadConfig config) async {
    calls.add('initialize');
    this.config = config;
  }

  @override
  Future<List<FDownloadItem>> list() async {
    calls.add('list');
    return items.values.toList();
  }

  @override
  Future<FDownloadOptions> inspect(FPlayerSource source) async {
    calls.add('inspect:${source.uri}');
    return options;
  }

  @override
  Future<void> enqueue({
    required String id,
    required FPlayerSource source,
    required FDownloadSelection selection,
    required String? metadata,
  }) async {
    calls.add('enqueue:$id');
    put(
      FDownloadItem(
        id: id,
        uri: source.uri,
        state: FDownloadState.queued,
        bytesDownloaded: 0,
        startedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  Future<void> setPaused({required String id, required bool paused}) async {
    calls.add('setPaused:$id:$paused');
    final item = items[id];
    if (item == null) return;
    put(_withState(item, paused ? FDownloadState.paused : FDownloadState.queued));
  }

  @override
  Future<void> setAllPaused({required bool paused}) async {
    calls.add('setAllPaused:$paused');
    for (final item in items.values.toList()) {
      items[item.id] =
          _withState(item, paused ? FDownloadState.paused : FDownloadState.queued);
    }
    emit();
  }

  @override
  Future<void> remove(String id) async {
    calls.add('remove:$id');
    items.remove(id);
    emit();
  }

  @override
  Future<void> removeAll() async {
    calls.add('removeAll');
    items.clear();
    emit();
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    isDisposed = true;
    await _queue.close();
  }

  static FDownloadItem _withState(FDownloadItem item, FDownloadState state) => FDownloadItem(
        id: item.id,
        uri: item.uri,
        state: state,
        progress: item.progress,
        bytesDownloaded: item.bytesDownloaded,
        contentLength: item.contentLength,
        startedAt: item.startedAt,
        updatedAt: item.updatedAt,
        metadata: item.metadata,
      );
}
