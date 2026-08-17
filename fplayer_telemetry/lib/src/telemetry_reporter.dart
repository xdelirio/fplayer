import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fplayer/fplayer.dart';
import 'package:path_provider/path_provider.dart';

import 'telemetry_client.dart';
import 'telemetry_config.dart';
import 'telemetry_event.dart';
import 'telemetry_queue.dart';

/// Turns playback observations into queued, batched, retried telemetry.
///
/// Register it with `FPlaybackSessionTracker(observers: [reporter])`. Nothing it does can block
/// playback: observer callbacks only append to an in-memory list, and disk and network happen on
/// their own schedule.
///
/// ```dart
/// final reporter = FTelemetryReporter(
///   config: FTelemetryConfig(endpoint: Uri.parse('https://api.example.com/telemetry')),
/// );
/// await reporter.start();
/// final tracker = FPlaybackSessionTracker(
///   controller: controller,
///   observers: [reporter],
///   progressInterval: reporter.config.progressInterval,
/// );
/// ```
class FTelemetryReporter extends FPlayerObserver {
  FTelemetryReporter({
    required this.config,
    File? queueFile,
    FTelemetryClient? client,
    FTelemetryQueue? queue,
  })  : _explicitQueueFile = queueFile,
        _client = client ?? FTelemetryClient(config: config),
        // Injectable so a test can run the whole loop without touching path_provider or a real
        // application directory.
        _queue = queue; // ignore: prefer_initializing_formals

  final FTelemetryConfig config;

  final File? _explicitQueueFile;
  final FTelemetryClient _client;

  FTelemetryQueue? _queue;
  Timer? _flushTimer;
  Timer? _retryTimer;
  bool _isFlushing = false;
  int _failedAttempts = 0;
  bool _isDisposed = false;

  /// What has already been reported per session, so each record carries a delta rather than the
  /// running total the backend would have to diff itself.
  final Map<String, _SessionCursor> _cursors = <String, _SessionCursor>{};

  /// Events queued so far. Exposed for tests and for a diagnostics screen.
  int get queuedCount => _queue?.length ?? 0;

  /// The start in flight, shared by every concurrent caller.
  Future<void>? _starting;

  /// The flush in flight, so disposal can wait for it instead of stepping around it.
  Future<void>? _flushing;

  /// Loads anything a previous run left behind and starts the flush loop.
  Future<void> start() {
    if (!config.enabled || _isDisposed) return Future<void>.value();
    // Shared rather than re-entered: the null check sits before an await, so two overlapping
    // calls both built a queue over the same file, each with its own write chain — interleaved
    // appends and duelling rewrites of one JSONL.
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      _queue ??= FTelemetryQueue(
        file: _explicitQueueFile ?? await _defaultQueueFile(),
        maxEntries: config.maxQueuedEvents,
      );
      await _queue!.load();
      if (_isDisposed) return;

      _flushTimer?.cancel();
      _flushTimer = Timer.periodic(config.flushInterval, (_) => unawaited(flush()));

      // Whatever survived the last run goes out immediately; it is already late.
      unawaited(flush());
    } finally {
      _starting = null;
    }
  }

  // region Observations

  @override
  void onSessionStart(FPlaybackMetrics metrics) =>
      _enqueue(metrics, FTelemetryEventKind.start);

  @override
  void onFirstFrame(FPlaybackMetrics metrics) =>
      _enqueue(metrics, FTelemetryEventKind.firstFrame);

  @override
  void onProgress(FPlaybackMetrics metrics) =>
      _enqueue(metrics, FTelemetryEventKind.progress);

  @override
  void onRebufferEnd(FPlaybackMetrics metrics, Duration stallDuration) =>
      _enqueue(metrics, FTelemetryEventKind.rebuffer);

  @override
  void onSeek(FPlaybackMetrics metrics, {required Duration from, required Duration to}) =>
      _enqueue(metrics, FTelemetryEventKind.seek);

  @override
  void onError(FPlaybackMetrics metrics, FPlayerError error, {required bool isFatal}) {
    // Only failures the viewer actually saw are reported. A retried blip is noise at this level,
    // and it already shows up as a stall in the numbers.
    if (!isFatal) return;
    _enqueue(metrics, FTelemetryEventKind.error, error: error);
  }

  @override
  void onSessionEnd(FPlaybackMetrics metrics, FSessionEndReason reason) {
    _enqueue(metrics, FTelemetryEventKind.end, endReason: reason);
    _cursors.remove(metrics.sessionId);
    // The session is over and nothing else will arrive for it; send what is queued now, while the
    // app is still likely alive.
    unawaited(flush());
  }

  // endregion

  void _enqueue(
    FPlaybackMetrics metrics,
    FTelemetryEventKind kind, {
    FPlayerError? error,
    FSessionEndReason? endReason,
  }) {
    final queue = _queue;
    if (!config.enabled || _isDisposed || queue == null) return;

    final cursor = _cursors.putIfAbsent(metrics.sessionId, _SessionCursor.new);

    queue.add(
      FTelemetryEvent(
        sessionId: metrics.sessionId,
        kind: kind,
        occurredAt: metrics.updatedAt,
        position: metrics.position,
        duration: metrics.duration,
        contentTitle: metrics.contentTitle,
        metadata: sanitizeMetadata(metrics.sourceMetadata),
        watchedDelta: metrics.watchedTime - cursor.watched,
        stallCountDelta: metrics.rebufferCount - cursor.stallCount,
        stallDelta: metrics.rebufferTime - cursor.stallTime,
        seekCountDelta: metrics.seekCount - cursor.seekCount,
        watchedTotal: metrics.watchedTime,
        stallCountTotal: metrics.rebufferCount,
        stallTotal: metrics.rebufferTime,
        timeToFirstFrame: metrics.timeToFirstFrame,
        averageBitrate: metrics.averageBitrate,
        averageVideoHeight: metrics.averageVideoHeight,
        peakVideoHeight: metrics.peakVideoHeight,
        isLive: metrics.isLive,
        endReason: endReason?.name,
        errorCode: error?.code.name,
        errorMessage: error?.message,
        httpStatus: error?.httpStatus,
        appVersion: config.appVersion,
        deviceType: config.deviceType,
      ),
    );

    cursor.watched = metrics.watchedTime;
    cursor.stallCount = metrics.rebufferCount;
    cursor.stallTime = metrics.rebufferTime;
    cursor.seekCount = metrics.seekCount;

    _log('queued ${kind.name} (${queue.length} pending)');
  }

  /// Drains the queue in batches until it is empty or the backend asks us to wait.
  Future<void> flush() async {
    final queue = _queue;
    if (!config.enabled || _isDisposed || queue == null || _isFlushing) return;

    return _flushing = _flush(queue);
  }

  Future<void> _flush(FTelemetryQueue queue) async {
    _isFlushing = true;
    try {
      while (!queue.isEmpty && !_isDisposed) {
        final batch = queue.peek(config.maxBatchSize);
        // Taken before the send, so records evicted from the front while the batch is on the
        // wire shift the removal rather than making it delete past the batch.
        final cursor = queue.cursorAfter(batch.length);
        final delivery = await _client.send(batch);

        switch (delivery.status) {
          case FTelemetryDeliveryStatus.delivered:
          case FTelemetryDeliveryStatus.dropped:
            queue.removeThrough(cursor);
            _failedAttempts = 0;
          case FTelemetryDeliveryStatus.retry:
            _scheduleRetry(delivery.retryAfter);
            return;
        }
      }
    } finally {
      _isFlushing = false;
      _flushing = null;
    }
  }

  void _scheduleRetry(Duration? requested) {
    // A send that fails *because* the client was closed on the way out must not arm a timer on
    // a disposed reporter — up to five minutes of dangling work with nothing to deliver.
    if (_isDisposed) return;

    final delay = requested ?? config.delayFor(_failedAttempts);
    _failedAttempts++;

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(flush()));
    _log('retrying in $delay (attempt $_failedAttempts)');
  }

  /// Stops the loop and makes a final attempt to deliver what is queued.
  Future<void> dispose() async {
    if (_isDisposed) return;

    _flushTimer?.cancel();
    _retryTimer?.cancel();

    // Wait for a flush already running rather than skipping the shutdown flush because one was:
    // `flush()` answers a re-entrant call with nothing, so the last batch used to be dropped
    // whenever disposal happened to land on a periodic flush.
    await _flushing;
    await flush();

    _isDisposed = true;
    _retryTimer?.cancel();
    await _queue?.flushToDisk();
    _client.close();
  }

  Future<File> _defaultQueueFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/fplayer_telemetry/queue.jsonl');
  }

  void _log(String message) {
    if (config.verbose) debugPrint('[fplayer_telemetry] $message');
  }
}

/// Last reported totals for one session.
class _SessionCursor {
  Duration watched = Duration.zero;
  int stallCount = 0;
  Duration stallTime = Duration.zero;
  int seekCount = 0;
}
