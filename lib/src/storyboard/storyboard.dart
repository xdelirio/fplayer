import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// One thumbnail of a storyboard, and where to find its pixels.
///
/// Storyboards are almost always packed as sprite sheets — a grid of small frames in one image —
/// because a two-hour film at one thumbnail per five seconds is well over a thousand pictures,
/// and fetching them individually would be unusable while scrubbing. [region] is the rectangle
/// this frame occupies inside [url]; it is null only when the file holds a single thumbnail.
@immutable
class FStoryboardFrame {
  const FStoryboardFrame({
    required this.start,
    required this.end,
    required this.url,
    this.region,
  });

  /// First position this thumbnail represents.
  final Duration start;

  /// Position at which the next thumbnail takes over. Exclusive.
  final Duration end;

  /// Absolute URL or file path of the image holding this frame.
  final String url;

  /// Area of [url] to crop, in image pixels. Null means "the whole image".
  final Rect? region;

  /// Whether [position] falls inside this frame's span.
  bool contains(Duration position) => position >= start && position < end;

  /// Shape of the thumbnail, when the index declared one.
  ///
  /// Null for whole-image frames, whose size is only known once the file is decoded.
  double? get aspectRatio {
    final rect = region;
    if (rect == null || rect.height <= 0) return null;
    return rect.width / rect.height;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FStoryboardFrame &&
          other.start == start &&
          other.end == end &&
          other.url == url &&
          other.region == region;

  @override
  int get hashCode => Object.hash(start, end, url, region);

  @override
  String toString() => 'FStoryboardFrame($start-$end, $url${region == null ? '' : ' $region'})';
}

/// A parsed storyboard index: every thumbnail of a piece of media, in timeline order.
///
/// Frames are kept sorted so a lookup is a binary search rather than a scan — a scrubber queries
/// this on every pointer move, and long media can hold thousands of entries.
@immutable
class FStoryboard {
  /// Takes ownership of [frames], which must already be sorted by [FStoryboardFrame.start].
  ///
  /// Prefer [FStoryboard.of], which sorts for you, unless the input order is guaranteed.
  const FStoryboard(this.frames);

  const FStoryboard.empty() : frames = const [];

  /// Sorts [frames] by start position before building the index.
  factory FStoryboard.of(Iterable<FStoryboardFrame> frames) {
    final sorted = frames.toList()..sort((a, b) => a.start.compareTo(b.start));
    return FStoryboard(List.unmodifiable(sorted));
  }

  final List<FStoryboardFrame> frames;

  bool get isEmpty => frames.isEmpty;

  bool get isNotEmpty => frames.isNotEmpty;

  int get length => frames.length;

  /// Position the last thumbnail stops covering, or null when there are no frames.
  Duration? get coverage => frames.isEmpty ? null : frames.last.end;

  /// Distinct image files this storyboard draws from, in first-use order.
  ///
  /// Useful for warming a cache: a whole storyboard usually resolves to a handful of sheets.
  Iterable<String> get imageUrls {
    final seen = <String>{};
    return frames.map((f) => f.url).where(seen.add);
  }

  /// The thumbnail to show for [position].
  ///
  /// With [clamp] on — the sensible default for a scrubber — a position that falls in a gap
  /// between cues, or past the end, resolves to the closest preceding frame instead of blanking
  /// the preview. Pass `clamp: false` when you need the strict "is this position covered?"
  /// answer.
  FStoryboardFrame? frameAt(Duration position, {bool clamp = true}) {
    if (frames.isEmpty) return null;

    // Last frame whose start is at or before the position.
    var low = 0;
    var high = frames.length - 1;
    var candidate = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (frames[mid].start <= position) {
        candidate = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (candidate < 0) return clamp ? frames.first : null;

    final frame = frames[candidate];
    if (position < frame.end) return frame;
    return clamp ? frame : null;
  }

  @override
  String toString() => 'FStoryboard(${frames.length} frames, coverage: $coverage)';
}
