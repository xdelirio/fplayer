import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'storyboard_fetch.dart';

/// Decoded sprite sheets, kept around so scrubbing does not re-decode.
///
/// A storyboard packs hundreds of thumbnails into a handful of images, so the same file is asked
/// for on nearly every pointer move. Decoding is the expensive part — far more than the fetch
/// once the bytes are warm — which is why this caches [ui.Image] rather than bytes.
///
/// Entries are evicted least-recently-used once the decoded footprint passes [maxBytes].
///
/// **Ownership**: every image handed out is a clone the caller owns and must dispose. Cloning is
/// what makes eviction safe — releasing the cache's copy leaves the pixel buffer alive for as
/// long as any handed-out clone still references it.
class FSpriteCache {
  FSpriteCache({this.maxBytes = _defaultMaxBytes, HttpClient? httpClient})
      : _httpClient = httpClient,
        _ownsClient = httpClient == null;

  /// Roughly two 4K sheets. Storyboard sheets are small, so this holds a lot of them.
  static const int _defaultMaxBytes = 32 << 20;

  /// Ceiling on the decoded pixel data held at once, in bytes.
  final int maxBytes;

  final HttpClient? _httpClient;
  final bool _ownsClient;

  HttpClient? _client;

  /// Insertion order doubles as recency: a hit re-inserts the entry at the end.
  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap<String, _Entry>();

  /// Requests already in flight, so a burst of scrub events triggers one fetch, not twenty.
  final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};

  int _bytes = 0;
  bool _isDisposed = false;

  /// Decoded bytes currently held.
  int get usedBytes => _bytes;

  int get length => _entries.length;

  /// An already-decoded sheet, or null if it has to be fetched first.
  ///
  /// Lets a scrubber paint the previous thumbnail on the same frame as the gesture instead of
  /// flashing a placeholder between two frames of the same sheet.
  ///
  /// The result is a clone the caller owns.
  ui.Image? peek(String url) {
    if (_isDisposed) return null;
    final entry = _entries.remove(url);
    if (entry == null) return null;
    _entries[url] = entry;
    return entry.image.clone();
  }

  /// Fetches and decodes [url], or returns the cached copy.
  ///
  /// Returns null when the image cannot be fetched or decoded — a missing thumbnail is not worth
  /// failing a scrub gesture over. The result is a clone the caller owns.
  Future<ui.Image?> load(String url, {Map<String, String> headers = const {}}) {
    if (_isDisposed) return Future<ui.Image?>.value();

    final cached = peek(url);
    if (cached != null) return Future<ui.Image?>.value(cached);

    final inFlight = _pending[url];
    if (inFlight != null) return inFlight.then((image) => image?.clone());

    final request = _fetchAndDecode(url, headers).whenComplete(() => _pending.remove(url));
    _pending[url] = request;
    return request.then((image) => image?.clone());
  }

  Future<ui.Image?> _fetchAndDecode(String url, Map<String, String> headers) async {
    Uint8List bytes;
    try {
      _client ??= _httpClient ?? HttpClient();
      bytes = await fetchStoryboardBytes(url, headers: headers, client: _client);
    } on FStoryboardException {
      return null;
    }

    final ui.Image image;
    try {
      image = await _decode(bytes);
    } on Exception {
      return null;
    }

    if (_isDisposed) {
      image.dispose();
      return null;
    }

    _store(url, image);
    return image;
  }

  void _store(String url, ui.Image image) {
    _entries.remove(url)?.release();
    final entry = _Entry(image);
    _entries[url] = entry;
    _bytes += entry.bytes;
    _evict();
  }

  void _evict() {
    while (_bytes > maxBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      final entry = _entries.remove(oldest)!;
      _bytes -= entry.bytes;
      entry.release();
    }
  }

  /// Releases every decoded sheet.
  ///
  /// Clones already handed out stay valid until their owners dispose them.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    for (final entry in _entries.values) {
      entry.release();
    }
    _entries.clear();
    _bytes = 0;

    if (_ownsClient) _client?.close();
    _client = null;
  }
}

class _Entry {
  _Entry(this.image) : bytes = image.width * image.height * 4;

  final ui.Image image;

  /// Decoded footprint, four bytes per pixel. Close enough for a budget, and it never lies in the
  /// dangerous direction — the real cost is at most this.
  final int bytes;

  void release() => image.dispose();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final codec = await descriptor.instantiateCodec();
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}
