import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';
// Imported from source: `lib/fplayer.dart` does not export the download layer yet, and adding the
// exports is the integrating owner's change to make.

void main() {
  Map<Object?, Object?> wire({
    String id = 'https://cdn.example.com/a.m3u8',
    String state = 'downloading',
    double percent = 42.5,
    int bytes = 1024,
    int contentLength = 4096,
    String? metadata,
    Map<String, Object?>? error,
  }) =>
      {
        'id': id,
        'uri': id,
        'state': state,
        'percent': percent,
        'bytesDownloaded': bytes,
        'contentLength': contentLength,
        'startedAtMs': 1700000000000,
        'updatedAtMs': 1700000060000,
        'metadata': metadata,
        'error': error,
      };

  group('decoding', () {
    test('maps the platform percentage onto a 0..1 fraction', () {
      expect(FDownloadItem.fromMap(wire()).progress, closeTo(0.425, 0.0001));
    });

    test('an unknown size reads as unknown, not as zero', () {
      // Adaptive streams report -1 until every segment list has been read.
      final item = FDownloadItem.fromMap(wire(contentLength: -1));
      expect(item.contentLength, isNull);
    });

    test('a negative percentage before the size is known clamps to zero', () {
      expect(FDownloadItem.fromMap(wire(percent: -1)).progress, 0);
    });

    test('every state name round-trips', () {
      for (final state in FDownloadState.values) {
        expect(FDownloadItem.fromMap(wire(state: state.name)).state, state);
      }
    });

    test('an unrecognised state falls back to queued rather than throwing', () {
      expect(FDownloadItem.fromMap(wire(state: 'martian')).state, FDownloadState.queued);
    });

    test('a failure carries the same error taxonomy playback uses', () {
      final item = FDownloadItem.fromMap(
        wire(
          state: 'failed',
          error: {
            'code': 'unauthorized',
            'message': 'token expired',
            'httpStatus': 401,
            'retryable': false,
          },
        ),
      );

      expect(item.error!.code, FPlayerErrorCode.unauthorized);
      expect(item.error!.httpStatus, 401);
      expect(item.error!.isRetryable, isFalse);
    });

    test('timestamps are read as UTC, so two devices agree on them', () {
      final item = FDownloadItem.fromMap(wire());
      expect(item.startedAt.isUtc, isTrue);
      expect(item.startedAt.millisecondsSinceEpoch, 1700000000000);
    });
  });

  group('metadata', () {
    test('round-trips the app payload', () {
      final item = FDownloadItem.fromMap(
        wire(metadata: '{"title":"Episodio 4","episodeId":128}'),
      );

      expect(item.metadata['title'], 'Episodio 4');
      expect(item.metadata['episodeId'], 128);
    });

    test('absent metadata reads as empty', () {
      expect(FDownloadItem.fromMap(wire()).metadata, isEmpty);
    });

    test('unreadable metadata is dropped rather than thrown', () {
      // A queue entry written by an older build should still list, just without its labels.
      expect(FDownloadItem.fromMap(wire(metadata: 'not json')).metadata, isEmpty);
    });

    test('a JSON value that is not an object is ignored', () {
      expect(FDownloadItem.fromMap(wire(metadata: '[1,2,3]')).metadata, isEmpty);
    });
  });

  group('toSource', () {
    test('plays from the same URI, which is what the cache is keyed by', () {
      final item = FDownloadItem.fromMap(
        wire(state: 'completed', metadata: '{"title":"Episodio 4"}'),
      );

      final source = item.toSource(startAt: const Duration(minutes: 3));
      expect(source.uri, item.uri);
      expect(source.title, 'Episodio 4');
      expect(source.startAt, const Duration(minutes: 3));
    });

    test('an explicit title beats the stored one', () {
      final item = FDownloadItem.fromMap(wire(metadata: '{"title":"stored"}'));
      expect(item.toSource(title: 'explicit').title, 'explicit');
    });
  });

  group('state predicates', () {
    test('only completed is playable offline', () {
      for (final state in FDownloadState.values) {
        expect(
          FDownloadItem.fromMap(wire(state: state.name)).isPlayableOffline,
          state == FDownloadState.completed,
        );
      }
    });

    test('restarting counts as active, because work is still coming', () {
      expect(FDownloadState.restarting.isActive, isTrue);
      expect(FDownloadState.paused.isActive, isFalse);
      expect(FDownloadState.paused.isStopped, isTrue);
      expect(FDownloadState.failed.isStopped, isTrue);
    });
  });
}
