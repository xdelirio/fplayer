import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/player_error.dart';

/// Failure while fetching a storyboard resource, already classified.
///
/// It carries an [FPlayerError] so a storyboard problem reads the same way as a playback problem
/// — the UI branches on `code`, not on which layer raised it.
class FStoryboardException implements Exception {
  const FStoryboardException(this.error);

  final FPlayerError error;

  @override
  String toString() => 'FStoryboardException(${error.code.name}: ${error.message})';
}

/// Reads [uri] into memory.
///
/// Handles `http`/`https` through [client] and treats anything else as a filesystem path, so a
/// storyboard shipped next to a downloaded video works without a special case at the call site.
///
/// Throws [FStoryboardException].
Future<Uint8List> fetchStoryboardBytes(
  String uri, {
  Map<String, String> headers = const {},
  HttpClient? client,
}) async {
  final parsed = Uri.tryParse(uri);
  final isRemote = parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https');

  if (!isRemote) {
    return _readFile(parsed != null && parsed.scheme == 'file' ? parsed.toFilePath() : uri);
  }

  final ownsClient = client == null;
  final http = client ?? HttpClient();
  try {
    final request = await http.getUrl(parsed);
    headers.forEach(request.headers.set);
    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain so the connection can be reused instead of being torn down.
      await response.drain<void>();
      throw FStoryboardException(
        FPlayerError(
          code: _codeForStatus(response.statusCode),
          message: 'Storyboard request failed with HTTP ${response.statusCode}',
          httpStatus: response.statusCode,
          isRetryable: response.statusCode >= 500 || response.statusCode == 429,
        ),
      );
    }

    return await consolidateHttpClientResponseBytes(response);
  } on SocketException catch (e) {
    throw FStoryboardException(
      FPlayerError(
        code: FPlayerErrorCode.network,
        message: 'Could not reach the storyboard host: ${e.message}',
        isRetryable: true,
      ),
    );
  } on HttpException catch (e) {
    throw FStoryboardException(
      FPlayerError(
        code: FPlayerErrorCode.io,
        message: 'Storyboard transfer failed: ${e.message}',
        isRetryable: true,
      ),
    );
  } finally {
    if (ownsClient) http.close();
  }
}

Future<Uint8List> _readFile(String path) async {
  try {
    return await File(path).readAsBytes();
  } on PathNotFoundException {
    throw FStoryboardException(
      FPlayerError(
        code: FPlayerErrorCode.notFound,
        message: 'Storyboard file not found: $path',
      ),
    );
  } on FileSystemException catch (e) {
    throw FStoryboardException(
      FPlayerError(
        code: FPlayerErrorCode.io,
        message: 'Could not read storyboard file: ${e.message}',
      ),
    );
  }
}

FPlayerErrorCode _codeForStatus(int status) => switch (status) {
      401 => FPlayerErrorCode.unauthorized,
      403 => FPlayerErrorCode.forbidden,
      404 || 410 => FPlayerErrorCode.notFound,
      _ => FPlayerErrorCode.badHttpStatus,
    };
