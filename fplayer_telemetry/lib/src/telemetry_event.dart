import 'package:flutter/foundation.dart';

/// The measurable moment a telemetry record describes.
enum FTelemetryEventKind {
  start,
  firstFrame,
  progress,
  rebuffer,
  quality,
  seek,
  error,
  end,
}

/// One record on its way to the backend.
///
/// Carries both cumulative totals and deltas since the previous record of the same session.
/// Totals let a late arrival correct the picture; deltas let the backend sum without worrying
/// about which records it already counted.
@immutable
class FTelemetryEvent {
  const FTelemetryEvent({
    required this.sessionId,
    required this.kind,
    required this.occurredAt,
    required this.position,
    this.duration,
    this.contentTitle,
    this.metadata,
    this.watchedDelta = Duration.zero,
    this.stallCountDelta = 0,
    this.stallDelta = Duration.zero,
    this.seekCountDelta = 0,
    this.watchedTotal = Duration.zero,
    this.stallCountTotal = 0,
    this.stallTotal = Duration.zero,
    this.timeToFirstFrame,
    this.averageBitrate,
    this.averageVideoHeight,
    this.peakVideoHeight,
    this.isLive = false,
    this.endReason,
    this.errorCode,
    this.errorMessage,
    this.httpStatus,
    this.appVersion,
    this.deviceType,
  });

  factory FTelemetryEvent.fromJson(Map<String, Object?> json) => FTelemetryEvent(
        sessionId: json['sessionId']! as String,
        kind: FTelemetryEventKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => FTelemetryEventKind.progress,
        ),
        occurredAt: DateTime.parse(json['occurredAt']! as String),
        position: _duration(json['positionMs']) ?? Duration.zero,
        duration: _duration(json['durationMs']),
        contentTitle: json['contentTitle'] as String?,
        metadata: json['metadata'] as Map<String, Object?>?,
        watchedDelta: _duration(json['watchedDeltaMs']) ?? Duration.zero,
        stallCountDelta: (json['stallCountDelta'] as num?)?.toInt() ?? 0,
        stallDelta: _duration(json['stallDeltaMs']) ?? Duration.zero,
        seekCountDelta: (json['seekCountDelta'] as num?)?.toInt() ?? 0,
        watchedTotal: _duration(json['watchedTotalMs']) ?? Duration.zero,
        stallCountTotal: (json['stallCountTotal'] as num?)?.toInt() ?? 0,
        stallTotal: _duration(json['stallTotalMs']) ?? Duration.zero,
        timeToFirstFrame: _duration(json['timeToFirstFrameMs']),
        averageBitrate: (json['averageBitrate'] as num?)?.toInt(),
        averageVideoHeight: (json['averageVideoHeight'] as num?)?.toDouble(),
        peakVideoHeight: (json['peakVideoHeight'] as num?)?.toInt(),
        isLive: json['isLive'] as bool? ?? false,
        endReason: json['endReason'] as String?,
        errorCode: json['errorCode'] as String?,
        errorMessage: json['errorMessage'] as String?,
        httpStatus: (json['httpStatus'] as num?)?.toInt(),
        appVersion: json['appVersion'] as String?,
        deviceType: json['deviceType'] as String?,
      );

  final String sessionId;
  final FTelemetryEventKind kind;
  final DateTime occurredAt;

  final Duration position;
  final Duration? duration;
  final String? contentTitle;

  /// Whatever the app put on `FPlayerSource.metadata`, reduced to JSON-safe values.
  final Map<String, Object?>? metadata;

  final Duration watchedDelta;
  final int stallCountDelta;
  final Duration stallDelta;
  final int seekCountDelta;

  final Duration watchedTotal;
  final int stallCountTotal;
  final Duration stallTotal;

  final Duration? timeToFirstFrame;
  final int? averageBitrate;
  final double? averageVideoHeight;
  final int? peakVideoHeight;
  final bool isLive;

  final String? endReason;
  final String? errorCode;
  final String? errorMessage;
  final int? httpStatus;

  final String? appVersion;
  final String? deviceType;

  /// Wire form. Null fields are dropped so a batch stays small on a metered connection.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'kind': kind.name,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'positionMs': position.inMilliseconds,
      'durationMs': duration?.inMilliseconds,
      'contentTitle': contentTitle,
      'metadata': metadata,
      'watchedDeltaMs': watchedDelta.inMilliseconds,
      'stallCountDelta': stallCountDelta,
      'stallDeltaMs': stallDelta.inMilliseconds,
      'seekCountDelta': seekCountDelta,
      'watchedTotalMs': watchedTotal.inMilliseconds,
      'stallCountTotal': stallCountTotal,
      'stallTotalMs': stallTotal.inMilliseconds,
      'timeToFirstFrameMs': timeToFirstFrame?.inMilliseconds,
      'averageBitrate': averageBitrate,
      'averageVideoHeight': averageVideoHeight,
      'peakVideoHeight': peakVideoHeight,
      'isLive': isLive,
      'endReason': endReason,
      'errorCode': errorCode,
      'errorMessage': errorMessage,
      'httpStatus': httpStatus,
      'appVersion': appVersion,
      'deviceType': deviceType,
    };
    json.removeWhere((key, value) => value == null);
    return json;
  }

  static Duration? _duration(Object? milliseconds) {
    final value = (milliseconds as num?)?.toInt();
    return value == null ? null : Duration(milliseconds: value);
  }

  @override
  String toString() => 'FTelemetryEvent(${kind.name}, $sessionId, at $position)';
}

/// Reduces arbitrary source metadata to something `jsonEncode` will accept.
///
/// Apps put whatever they like on `FPlayerSource.metadata` — including their own model objects —
/// and a telemetry queue that throws while serialising one of them would lose every event behind
/// it. Anything unrecognised becomes its string form instead.
Map<String, Object?>? sanitizeMetadata(Object? metadata) {
  if (metadata == null) return null;
  if (metadata is Map) {
    return {
      for (final entry in metadata.entries) '${entry.key}': _sanitizeValue(entry.value),
    };
  }
  return {'value': _sanitizeValue(metadata)};
}

Object? _sanitizeValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) return value;
  if (value is Iterable) return value.map(_sanitizeValue).toList();
  if (value is Map) {
    return {for (final entry in value.entries) '${entry.key}': _sanitizeValue(entry.value)};
  }
  return value.toString();
}
