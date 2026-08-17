import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/download_config.dart';
import '../models/player_source.dart';
import 'download_item.dart';
import 'download_options.dart';
import 'download_platform.dart';
import 'download_selection.dart';
import 'download_state.dart';

/// The offline download queue.
///
/// One per process, because the cache directory and the platform's download index are. Use
/// [FDownloadManager.instance] rather than building your own, unless you are writing a test.
///
/// A `ChangeNotifier` like the player controller, so a downloads screen is a `ListenableBuilder`
/// away:
///
/// ```dart
/// await FDownloadManager.instance.initialize();
/// await FDownloadManager.instance.enqueue(
///   source,
///   selection: const FDownloadSelection.standard(textLanguages: ['es']),
///   metadata: {'title': 'Episodio 4', 'episodeId': 128},
/// );
/// ```
///
/// Downloading requires the host app to declare the download service; see the README. Without it
/// the queue still runs, but only while the app is in the foreground.
class FDownloadManager extends ChangeNotifier {
  FDownloadManager({@visibleForTesting FDownloadPlatform? platform})
      : _platform = platform ?? FMedia3DownloadPlatform();

  /// The process-wide queue.
  static final FDownloadManager instance = FDownloadManager();

  final FDownloadPlatform _platform;

  StreamSubscription<List<FDownloadItem>>? _subscription;

  /// The initialisation in flight, shared by every concurrent caller.
  Future<void>? _initializing;
  List<FDownloadItem> _items = const [];
  bool _isInitialized = false;
  bool _isDisposed = false;

  /// Everything in the queue, newest first.
  List<FDownloadItem> get items => _items;

  /// Whether [initialize] has completed.
  bool get isInitialized => _isInitialized;

  /// Downloads that are transferring or waiting to.
  List<FDownloadItem> get active => _items.where((i) => i.state.isActive).toList();

  /// Downloads that are fully on disk.
  List<FDownloadItem> get completed => _items.where((i) => i.isPlayableOffline).toList();

  /// Combined progress of everything still in flight, from 0 to 1.
  ///
  /// Weighted by size where sizes are known, so a 2 GB film does not count the same as a 40 MB
  /// trailer. Returns 1 when nothing is pending.
  double get overallProgress {
    final pending = active;
    if (pending.isEmpty) return 1;

    final weighted = pending.where((i) => i.contentLength != null).toList();
    if (weighted.isEmpty) {
      return pending.map((i) => i.progress).reduce((a, b) => a + b) / pending.length;
    }

    var total = 0;
    var done = 0;
    for (final item in weighted) {
      total += item.contentLength!;
      done += item.bytesDownloaded;
    }
    return total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
  }

  /// Total bytes held by completed downloads.
  int get bytesOnDisk =>
      completed.fold(0, (sum, item) => sum + item.bytesDownloaded);

  /// Prepares the platform queue and starts listening to it.
  ///
  /// Safe to call more than once; only the first call does anything. Call it before the first
  /// downloads screen is built — the queue is restored from disk, so a download interrupted by a
  /// previous run reappears here.
  Future<void> initialize([FDownloadConfig config = const FDownloadConfig()]) {
    if (_isInitialized || _isDisposed) return Future<void>.value();
    // Shared rather than re-entered: `_isInitialized` is only true once the platform has
    // answered, so two unawaited calls both used to get past the guard, both subscribe, and the
    // second assignment orphaned the first subscription — every queue event handled twice,
    // forever, with only one of them cancelled on disposal.
    return _initializing ??= _initialize(config);
  }

  Future<void> _initialize(FDownloadConfig config) async {
    try {
      await _platform.initialize(config);
      if (_isDisposed) return;

      _isInitialized = true;
      // Listed before listening: an event arriving between the two used to be overwritten by the
      // older snapshot the list call was still fetching.
      _apply(await _platform.list());
      if (_isDisposed) return;
      _subscription = _platform.queue.listen(_onQueue, onError: _onQueueError);
      notifyListeners();
    } finally {
      _initializing = null;
    }
  }

  /// The entry with this id, or null.
  FDownloadItem? operator [](String id) =>
      _items.where((item) => item.id == id).firstOrNull;

  /// Whether this source is on disk and playable without a network.
  bool isDownloaded(FPlayerSource source) =>
      this[idFor(source)]?.isPlayableOffline ?? false;

  /// State of this source in the queue, or null if it was never enqueued.
  FDownloadState? stateOf(FPlayerSource source) => this[idFor(source)]?.state;

  /// Reads what a source offers before committing to a download.
  ///
  /// Fetches and parses the manifest, so it costs a round trip. Skip it when the app picks the
  /// quality itself; use it to build a picker.
  Future<FDownloadOptions> inspect(FPlayerSource source) => _platform.inspect(source);

  /// Adds [source] to the queue.
  ///
  /// Returns the id, which defaults to the source URI. Enqueueing an id that already exists
  /// resumes it rather than starting over — which is also how a failed download is retried.
  ///
  /// [metadata] is stored with the download and comes back on every [FDownloadItem], so a
  /// downloads screen can show titles and posters without a second database.
  Future<String> enqueue(
    FPlayerSource source, {
    String? id,
    FDownloadSelection selection = const FDownloadSelection.standard(),
    Map<String, Object?>? metadata,
  }) async {
    _requireInitialized();

    final resolved = id ?? idFor(source);
    await _platform.enqueue(
      id: resolved,
      source: source,
      selection: selection,
      metadata: encodeDownloadMetadata({
        if (source.title != null) 'title': source.title,
        if (source.subtitle != null) 'subtitle': source.subtitle,
        if (source.posterUrl != null) 'posterUrl': source.posterUrl,
        ...?metadata,
      }),
    );
    return resolved;
  }

  /// Stops a single download, keeping what it already has.
  Future<void> pause(String id) {
    _requireInitialized();
    return _platform.setPaused(id: id, paused: true);
  }

  /// Resumes a paused or failed download from where it stopped.
  Future<void> resume(String id) {
    _requireInitialized();
    return _platform.setPaused(id: id, paused: false);
  }

  /// Stops every download.
  Future<void> pauseAll() {
    _requireInitialized();
    return _platform.setAllPaused(paused: true);
  }

  Future<void> resumeAll() {
    _requireInitialized();
    return _platform.setAllPaused(paused: false);
  }

  /// Deletes a download and its bytes.
  Future<void> remove(String id) {
    _requireInitialized();
    return _platform.remove(id);
  }

  /// Deletes everything, including partial transfers.
  Future<void> removeAll() {
    _requireInitialized();
    return _platform.removeAll();
  }

  /// Default id for a source: its URI.
  ///
  /// The cache is keyed by URI too, which is what makes a downloaded source play offline with no
  /// change at the call site.
  static String idFor(FPlayerSource source) => source.uri;

  void _onQueue(List<FDownloadItem> items) {
    if (_isDisposed) return;
    _apply(items);
    notifyListeners();
  }

  /// Newest first: a downloads screen is a list of what the user just asked for. Applied to the
  /// restored snapshot as well, so the documented order holds from the first frame rather than
  /// from the first event.
  void _apply(List<FDownloadItem> items) {
    _items = items.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  /// A queue publication that could not be decoded.
  ///
  /// The stream carries the whole queue on every change, so one malformed entry from the native
  /// side would otherwise take out the batch *and* escape as an uncaught error with no call site
  /// to catch it. Keeping the last good queue is the honest fallback: the screen goes stale
  /// rather than blank.
  void _onQueueError(Object error, StackTrace stack) {
    assert(() {
      debugPrint('fplayer: a download queue update could not be read — $error');
      return true;
    }(), '');
  }

  void _requireInitialized() {
    if (_isInitialized) return;
    throw StateError(
      'FDownloadManager.initialize() must complete before the queue can be used',
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await _subscription?.cancel();
    _subscription = null;
    if (_isInitialized) await _platform.dispose();

    super.dispose();
  }
}
