import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/player_error.dart';
import '../models/player_source.dart';
import 'sprite_cache.dart';
import 'storyboard.dart';
import 'storyboard_fetch.dart';
import 'storyboard_loader.dart';

/// Owns a storyboard end to end: the index, the decoded sheets, and the state a UI reacts to.
///
/// Deliberately separate from the player controller. A storyboard is optional, has its own
/// failure modes, and its lifetime is the source's — a player that never scrubs should not pay
/// for any of it.
///
/// ```dart
/// final storyboard = FStoryboardController()..load(source.storyboard);
/// // …
/// FStoryboardPreview(controller: storyboard, position: hoverPosition)
/// ```
class FStoryboardController extends ChangeNotifier {
  FStoryboardController({FSpriteCache? cache, FStoryboardLoader? loader})
      : _cache = cache ?? FSpriteCache(),
        _ownsCache = cache == null,
        _loader = loader ?? FStoryboardLoader(),
        _ownsLoader = loader == null;

  final FSpriteCache _cache;
  final bool _ownsCache;
  final FStoryboardLoader _loader;
  final bool _ownsLoader;

  FStoryboardSource? _source;
  FStoryboard _storyboard = const FStoryboard.empty();
  FPlayerError? _error;
  bool _isLoading = false;
  bool _isDisposed = false;

  /// Bumped on every [load] so a slow response for an old source cannot overwrite a newer one.
  int _generation = 0;

  /// The parsed index. Empty until a load succeeds.
  FStoryboard get storyboard => _storyboard;

  /// Whether an index is being fetched.
  bool get isLoading => _isLoading;

  /// Why the last load failed, or null.
  ///
  /// A failed storyboard is not a playback failure: show the scrubber without thumbnails rather
  /// than an error.
  FPlayerError? get error => _error;

  /// Whether there are thumbnails to show.
  bool get hasFrames => _storyboard.isNotEmpty;

  /// Sheets held in memory right now, in bytes.
  int get cachedBytes => _cache.usedBytes;

  /// Loads [source], replacing anything loaded before.
  ///
  /// Passing null clears the storyboard, which is what a source without thumbnails should do.
  Future<void> load(FStoryboardSource? source) async {
    if (_isDisposed) return;

    final generation = ++_generation;
    _source = source;

    if (source == null) {
      _storyboard = const FStoryboard.empty();
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    FStoryboard result;
    FPlayerError? failure;
    try {
      result = await _loader.load(source);
    } on FStoryboardException catch (e) {
      result = const FStoryboard.empty();
      failure = e.error;
    } on Object catch (e) {
      result = const FStoryboard.empty();
      failure = FPlayerError(
        code: FPlayerErrorCode.unknown,
        message: 'Storyboard could not be loaded: $e',
      );
    }

    if (_isDisposed || generation != _generation) return;

    _storyboard = result;
    _error = failure;
    _isLoading = false;
    notifyListeners();
  }

  /// Thumbnail to show for [position]. See [FStoryboard.frameAt].
  FStoryboardFrame? frameAt(Duration position, {bool clamp = true}) =>
      _storyboard.frameAt(position, clamp: clamp);

  /// A sheet that is already decoded, or null.
  ///
  /// The returned image is a clone the caller owns and must dispose.
  ui.Image? peekImage(FStoryboardFrame frame) => _cache.peek(frame.url);

  /// Fetches and decodes the sheet [frame] lives in.
  ///
  /// Resolves to null when it cannot be loaded. The returned image is a clone the caller owns and
  /// must dispose.
  Future<ui.Image?> imageFor(FStoryboardFrame frame) =>
      _cache.load(frame.url, headers: _source?.headers ?? const {});

  /// Warms the first [limit] sheets so the first hover is not blank.
  ///
  /// One sheet usually covers several minutes of media, so the default is enough for the start of
  /// playback; raise it if your scrubber is used to jump far ahead immediately.
  Future<void> prefetch({int limit = 1}) async {
    // Guarded like `load`: warming is slow, and a source change or a disposal partway through
    // means these sheets are for a storyboard nobody is looking at any more.
    final generation = _generation;
    final headers = _source?.headers ?? const <String, String>{};

    for (final url in _storyboard.imageUrls.take(limit)) {
      if (_isDisposed || generation != _generation) return;
      final image = await _cache.load(url, headers: headers);
      // Warming only needs the cache populated; the clone handed back here is ours to release.
      image?.dispose();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    if (_ownsCache) _cache.dispose();
    if (_ownsLoader) _loader.dispose();
    super.dispose();
  }
}
