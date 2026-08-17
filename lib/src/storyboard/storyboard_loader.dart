import 'dart:convert';
import 'dart:io';

import '../models/player_error.dart';
import '../models/player_source.dart';
import 'storyboard.dart';
import 'storyboard_fetch.dart';
import 'storyboard_vtt.dart';

/// Fetches and parses a storyboard index.
///
/// Kept separate from the cache and the widget so an app can preload an index — while the
/// episode page is still on screen, say — and hand the parsed result to the player later.
class FStoryboardLoader {
  FStoryboardLoader({HttpClient? httpClient})
      : _httpClient = httpClient,
        _ownsClient = httpClient == null;

  final HttpClient? _httpClient;
  final bool _ownsClient;

  bool _isDisposed = false;

  HttpClient? _client;

  /// Downloads [source] and parses it.
  ///
  /// Throws [FStoryboardException] when the index cannot be fetched or is not a format this
  /// build understands.
  Future<FStoryboard> load(FStoryboardSource source) async {
    if (_isDisposed) {
      throw FStoryboardException(
        const FPlayerError(
          code: FPlayerErrorCode.unknown,
          message: 'The storyboard loader has been disposed',
        ),
      );
    }

    if (source.format != 'vtt') {
      throw FStoryboardException(
        FPlayerError(
          code: FPlayerErrorCode.unsupportedFormat,
          message: 'Unsupported storyboard format: ${source.format}',
        ),
      );
    }

    _client ??= _httpClient ?? HttpClient();
    final bytes = await fetchStoryboardBytes(
      source.uri,
      headers: source.headers,
      client: _client,
    );

    final String content;
    try {
      // Generators are inconsistent about encoding; a malformed byte should not lose the file.
      content = const Utf8Decoder(allowMalformed: true).convert(bytes);
    } on FormatException catch (e) {
      throw FStoryboardException(
        FPlayerError(
          code: FPlayerErrorCode.malformedContent,
          message: 'Storyboard index is not valid text: ${e.message}',
        ),
      );
    }

    return parseStoryboardVtt(content, baseUri: Uri.tryParse(source.uri));
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_ownsClient) _client?.close();
    _client = null;
  }
}
