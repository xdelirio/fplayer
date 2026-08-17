import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../config/download_config.dart';
import '../models/player_source.dart';
import 'download_item.dart';
import 'download_options.dart';
import 'download_selection.dart';

/// The platform side of downloads.
///
/// An interface rather than direct channel calls so [FDownloadManager] can be exercised without a
/// device — the queue's behaviour is worth testing, and none of it is Android-specific.
abstract interface class FDownloadPlatform {
  /// The queue, re-published whenever anything in it changes.
  Stream<List<FDownloadItem>> get queue;

  Future<void> initialize(FDownloadConfig config);

  Future<List<FDownloadItem>> list();

  Future<FDownloadOptions> inspect(FPlayerSource source);

  Future<void> enqueue({
    required String id,
    required FPlayerSource source,
    required FDownloadSelection selection,
    required String? metadata,
  });

  /// Stops or resumes a single download. Its state survives a restart.
  Future<void> setPaused({required String id, required bool paused});

  /// Stops or resumes the whole queue.
  Future<void> setAllPaused({required bool paused});

  Future<void> remove(String id);

  Future<void> removeAll();

  Future<void> dispose();
}

/// Talks to the Media3 `DownloadManager` over the plugin's channels.
class FMedia3DownloadPlatform implements FDownloadPlatform {
  static const MethodChannel _methods = MethodChannel('dev.chikenare.fplayer/downloads');
  static const EventChannel _events = EventChannel('dev.chikenare.fplayer/downloads/events');

  Stream<List<FDownloadItem>>? _queue;

  @override
  Stream<List<FDownloadItem>> get queue =>
      _queue ??= _events.receiveBroadcastStream().map(_decodeQueue);

  @override
  Future<void> initialize(FDownloadConfig config) =>
      _methods.invokeMethod<void>('initialize', {'config': config.toMap()});

  @override
  Future<List<FDownloadItem>> list() async {
    final raw = await _methods.invokeListMethod<Object?>('list') ?? const [];
    return _decodeItems(raw);
  }

  @override
  Future<FDownloadOptions> inspect(FPlayerSource source) async {
    final raw = await _methods.invokeMapMethod<String, Object?>('inspect', {
      'source': source.toMap(),
    });
    return FDownloadOptions.fromMap(raw ?? const {});
  }

  @override
  Future<void> enqueue({
    required String id,
    required FPlayerSource source,
    required FDownloadSelection selection,
    required String? metadata,
  }) =>
      _methods.invokeMethod<void>('enqueue', {
        'id': id,
        'source': source.toMap(),
        'selection': selection.toMap(),
        'metadata': metadata,
      });

  @override
  Future<void> setPaused({required String id, required bool paused}) =>
      _methods.invokeMethod<void>('setPaused', {'id': id, 'paused': paused});

  @override
  Future<void> setAllPaused({required bool paused}) =>
      _methods.invokeMethod<void>('setAllPaused', {'paused': paused});

  @override
  Future<void> remove(String id) => _methods.invokeMethod<void>('remove', {'id': id});

  @override
  Future<void> removeAll() => _methods.invokeMethod<void>('removeAll');

  @override
  Future<void> dispose() => _methods.invokeMethod<void>('dispose');

  static List<FDownloadItem> _decodeQueue(Object? event) =>
      _decodeItems(event is List ? event : const []);

  static List<FDownloadItem> _decodeItems(List<Object?> raw) => [
        for (final entry in raw)
          if (entry is Map) FDownloadItem.fromMap(entry.cast<Object?, Object?>()),
      ];
}

/// Encodes an app payload for storage next to the downloaded bytes.
///
/// Returns null for an empty map so nothing is written when there is nothing to say.
String? encodeDownloadMetadata(Map<String, Object?>? metadata) {
  if (metadata == null || metadata.isEmpty) return null;
  return jsonEncode(metadata);
}
