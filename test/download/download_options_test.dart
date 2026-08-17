import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

void main() {
  Map<Object?, Object?> track({
    String type = 'video',
    int width = 1280,
    int height = 720,
    int bitrate = 2500000,
    String? language,
    String? label,
    int? estimatedBytes,
  }) =>
      {
        'type': type,
        'groupIndex': 0,
        'trackIndex': 0,
        'label': label,
        'language': language,
        'codecs': 'avc1.4d401f',
        'bitrate': bitrate,
        'width': width,
        'height': height,
        'estimatedBytes': estimatedBytes,
      };

  group('quality labels', () {
    test('uses the height for ordinary 16:9 renditions', () {
      expect(FDownloadTrack.fromMap(track()).qualityLabel, '720p');
      expect(
        FDownloadTrack.fromMap(track(width: 1920, height: 1080)).qualityLabel,
        '1080p',
      );
    });

    test('normalises cinematic renditions to the rung people recognise', () {
      // 1680x750 has the detail of 1080p; calling it "750p" would mean nothing to a viewer.
      expect(
        FDownloadTrack.fromMap(track(width: 1680, height: 750)).qualityLabel,
        '1080p',
      );
      expect(
        FDownloadTrack.fromMap(track(width: 784, height: 350)).qualityLabel,
        '480p',
      );
    });

    test('is absent when the size is unknown', () {
      final decoded = FDownloadTrack.fromMap(track(width: -1, height: -1));
      expect(decoded.qualityLabel, isNull);
      expect(decoded.width, isNull);
      expect(decoded.height, isNull);
    });

    test('falls back through label, quality and language for a menu row', () {
      expect(FDownloadTrack.fromMap(track(label: 'HD')).displayName, 'HD');
      expect(FDownloadTrack.fromMap(track()).displayName, '720p');
      expect(
        FDownloadTrack.fromMap(track(type: 'audio', width: -1, height: -1, language: 'es'))
            .displayName,
        'es',
      );
    });
  });

  group('options', () {
    test('sorts video lowest quality first, the order a picker reads', () {
      final options = FDownloadOptions.fromMap({
        'durationMs': 600000,
        'video': [
          track(width: 1920, height: 1080),
          track(width: 640, height: 360),
          track(),
        ],
        'audio': [track(type: 'audio', language: 'es')],
        'text': [track(type: 'text', language: 'en')],
      });

      // The native side sorts; this asserts the decode preserves it.
      expect(options.video.length, 3);
      expect(options.duration, const Duration(minutes: 10));
      expect(options.audioLanguages, ['es']);
      expect(options.textLanguages, ['en']);
      expect(options.hasChoice, isTrue);
    });

    test('a single rendition with no subtitles is nothing to ask about', () {
      final options = FDownloadOptions.fromMap({
        'video': [track()],
        'audio': [track(type: 'audio')],
      });

      expect(options.hasChoice, isFalse);
    });

    test('an unbounded stream reports no duration', () {
      expect(FDownloadOptions.fromMap({'durationMs': -1}).duration, isNull);
      expect(FDownloadOptions.fromMap(const {}).duration, isNull);
    });

    test('decodes an empty payload rather than throwing', () {
      final options = FDownloadOptions.fromMap(const {});
      expect(options.video, isEmpty);
      expect(options.audio, isEmpty);
      expect(options.text, isEmpty);
    });

    test('carries the size estimate that makes a picker useful', () {
      final decoded = FDownloadTrack.fromMap(track(estimatedBytes: 480 * 1024 * 1024));
      expect(decoded.estimatedBytes, 480 * 1024 * 1024);
      expect(decoded.type, FTrackType.video);
    });
  });

  group('selection', () {
    test('serialises what the native selector needs', () {
      const selection = FDownloadSelection(
        maxHeight: 720,
        maxBitrate: 3000000,
        audioLanguages: ['es', 'en'],
        textLanguages: ['es'],
      );

      expect(selection.toMap(), {
        'maxHeight': 720,
        'maxBitrate': 3000000,
        'audioLanguages': ['es', 'en'],
        'textLanguages': ['es'],
        'allAudioLanguages': false,
        'allTextLanguages': false,
      });
    });

    test('everything takes the best video and every language', () {
      const selection = FDownloadSelection.everything();
      expect(selection.maxHeight, isNull);
      expect(selection.allAudioLanguages, isTrue);
      expect(selection.allTextLanguages, isTrue);
    });

    test('standard carries the languages it was given', () {
      const selection = FDownloadSelection.standard(textLanguages: ['es']);
      expect(selection.maxHeight, 720);
      expect(selection.textLanguages, ['es']);
    });

    test('compares by value, so a rebuild does not look like a change', () {
      expect(
        const FDownloadSelection(maxHeight: 720, audioLanguages: ['es']),
        const FDownloadSelection(maxHeight: 720, audioLanguages: ['es']),
      );
      expect(
        const FDownloadSelection(maxHeight: 720),
        isNot(const FDownloadSelection(maxHeight: 1080)),
      );
    });

    test('copyWith changes one axis at a time', () {
      const base = FDownloadSelection.standard();
      expect(base.copyWith(maxHeight: 1080).maxHeight, 1080);
      expect(base.copyWith(maxHeight: 1080).allTextLanguages, isFalse);
    });
  });
}
