import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'telemetry_event.dart';

/// Durable FIFO of telemetry events, backed by a JSONL file.
///
/// Line-delimited JSON rather than one big array: appending a record is a single write with no
/// read-modify-write, and a file truncated by a crash loses its last line instead of becoming
/// unparseable.
///
/// Kept in memory as well as on disk. The queue is capped in the hundreds, so holding it costs
/// almost nothing and spares every read a file parse.
class FTelemetryQueue {
  FTelemetryQueue({required this.file, this.maxEntries = 500});

  final File file;

  /// Past this many entries the oldest are dropped.
  final int maxEntries;

  final List<FTelemetryEvent> _events = <FTelemetryEvent>[];

  /// Serialises disk work. Observer callbacks are synchronous and fire in bursts, so writes are
  /// chained instead of racing each other onto the same file.
  Future<void> _pending = Future<void>.value();

  bool _isLoaded = false;

  int get length => _events.length;

  bool get isEmpty => _events.isEmpty;

  /// Everything currently queued, oldest first.
  List<FTelemetryEvent> get events => List.unmodifiable(_events);

  /// Reads whatever a previous run left behind.
  ///
  /// Malformed lines are skipped rather than fatal: one corrupt record must not cost the rest of
  /// the queue.
  Future<void> load() async {
    if (_isLoaded) return;
    _isLoaded = true;

    if (!file.existsSync()) return;

    final content = await file.readAsString();
    for (final line in const LineSplitter().convert(content)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?>) {
          _events.add(FTelemetryEvent.fromJson(decoded));
        }
      } on FormatException {
        continue;
      }
    }

    if (_events.length > maxEntries) {
      _events.removeRange(0, _events.length - maxEntries);
      unawaited(_schedule(_rewrite));
    }
  }

  /// Appends [event], dropping the oldest record if the queue is already full.
  void add(FTelemetryEvent event) {
    _events.add(event);

    if (_events.length > maxEntries) {
      _events.removeRange(0, _events.length - maxEntries);
      unawaited(_schedule(_rewrite));
      return;
    }

    _schedule(() async {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  /// The next batch, without removing it. Call [remove] once the backend has accepted it.
  List<FTelemetryEvent> peek(int count) =>
      _events.take(count < 0 ? 0 : count).toList(growable: false);

  /// Drops the first [count] records.
  void remove(int count) {
    if (count <= 0) return;
    _events.removeRange(0, count.clamp(0, _events.length));
    unawaited(_schedule(_rewrite));
  }

  Future<void> clear() {
    _events.clear();
    return _schedule(_rewrite);
  }

  /// Waits for every queued write to reach disk. Tests and shutdown paths need this.
  Future<void> flushToDisk() => _pending;

  Future<void> _schedule(Future<void> Function() work) {
    _pending = _pending.then((_) => work()).catchError((Object _) {});
    return _pending;
  }

  /// Rewrites the file through a temporary and renames it into place, so an interrupted rewrite
  /// leaves the previous file intact rather than a half-written one.
  Future<void> _rewrite() async {
    await file.parent.create(recursive: true);

    final temporary = File('${file.path}.tmp');
    final buffer = StringBuffer();
    for (final event in _events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    await temporary.writeAsString(buffer.toString(), flush: true);
    await temporary.rename(file.path);
  }
}
