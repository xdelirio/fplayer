import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/src/storyboard/storyboard.dart';

FStoryboardFrame _frame(int startSeconds, int endSeconds, {String url = 'sheet.jpg'}) =>
    FStoryboardFrame(
      start: Duration(seconds: startSeconds),
      end: Duration(seconds: endSeconds),
      url: url,
      region: Rect.fromLTWH(startSeconds * 160.0, 0, 160, 90),
    );

void main() {
  group('FStoryboardFrame', () {
    test('contains is inclusive of start and exclusive of end', () {
      final frame = _frame(5, 10);

      expect(frame.contains(const Duration(seconds: 4, milliseconds: 999)), isFalse);
      expect(frame.contains(const Duration(seconds: 5)), isTrue);
      expect(frame.contains(const Duration(seconds: 9, milliseconds: 999)), isTrue);
      expect(frame.contains(const Duration(seconds: 10)), isFalse);
    });

    test('derives the aspect ratio from the region', () {
      expect(_frame(0, 5).aspectRatio, closeTo(160 / 90, 1e-9));
    });

    test('has no aspect ratio without a region', () {
      const frame = FStoryboardFrame(
        start: Duration.zero,
        end: Duration(seconds: 5),
        url: 'thumb.jpg',
      );

      expect(frame.aspectRatio, isNull);
    });
  });

  group('FStoryboard', () {
    test('is empty by default', () {
      const storyboard = FStoryboard.empty();

      expect(storyboard.isEmpty, isTrue);
      expect(storyboard.coverage, isNull);
      expect(storyboard.frameAt(Duration.zero), isNull);
    });

    test('sorts frames when built with of()', () {
      final storyboard = FStoryboard.of([_frame(10, 15), _frame(0, 5), _frame(5, 10)]);

      expect(
        storyboard.frames.map((f) => f.start.inSeconds),
        [0, 5, 10],
      );
    });

    test('reports distinct image urls in first-use order', () {
      final storyboard = FStoryboard.of([
        _frame(0, 5, url: 'a.jpg'),
        _frame(5, 10, url: 'a.jpg'),
        _frame(10, 15, url: 'b.jpg'),
        _frame(15, 20, url: 'a.jpg'),
      ]);

      expect(storyboard.imageUrls, ['a.jpg', 'b.jpg']);
    });

    group('frameAt', () {
      final storyboard = FStoryboard.of([
        for (var i = 0; i < 1000; i++) _frame(i * 5, i * 5 + 5),
      ]);

      test('finds the covering frame at the exact start', () {
        expect(
          storyboard.frameAt(const Duration(seconds: 500))!.start,
          const Duration(seconds: 500),
        );
      });

      test('finds the covering frame mid-span', () {
        expect(
          storyboard.frameAt(const Duration(seconds: 502, milliseconds: 400))!.start,
          const Duration(seconds: 500),
        );
      });

      test('finds the first and last frames', () {
        expect(storyboard.frameAt(Duration.zero)!.start, Duration.zero);
        expect(
          storyboard.frameAt(const Duration(seconds: 4997))!.start,
          const Duration(seconds: 4995),
        );
      });

      test('agrees with a linear scan across the whole index', () {
        for (var seconds = 0; seconds < 5000; seconds += 7) {
          final position = Duration(seconds: seconds);
          final expected = storyboard.frames.firstWhere((f) => f.contains(position));

          expect(storyboard.frameAt(position, clamp: false), expected, reason: '$position');
        }
      });

      test('clamps a position before the first frame to the first frame', () {
        final gapped = FStoryboard.of([_frame(10, 15)]);
        final position = const Duration(seconds: 2);

        expect(gapped.frameAt(position)!.start, const Duration(seconds: 10));
        expect(gapped.frameAt(position, clamp: false), isNull);
      });

      test('clamps a position past the end to the last frame', () {
        final position = const Duration(seconds: 9000);

        expect(storyboard.frameAt(position)!.start, const Duration(seconds: 4995));
        expect(storyboard.frameAt(position, clamp: false), isNull);
      });

      test('clamps a position inside a gap to the preceding frame', () {
        final gapped = FStoryboard.of([_frame(0, 5), _frame(20, 25)]);
        final position = const Duration(seconds: 12);

        expect(gapped.frameAt(position)!.start, Duration.zero);
        expect(gapped.frameAt(position, clamp: false), isNull);
      });
    });
  });
}
