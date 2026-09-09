import 'package:fplayer/fplayer.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Whether this log line is mpv giving up on the file.
///
/// mpv has no error *event*: a failed load surfaces as log messages and then the player moves
/// on. Only a few lines mean the load is dead — the stream layer could not open the URL, the
/// demuxer found nothing it recognises — and everything else at error level is a component
/// complaining about something it then recovers from, or house-keeping noise such as the
/// demuxer failing to create its on-disk cache. Treating every error line as fatal would fail
/// loads that go on to play.
bool isMpvLoadFailure(mk.PlayerLog log) =>
    (log.level == 'error' || log.level == 'fatal') && _fatal.hasMatch(log.text);

/// Reads the reason out of a log line, or returns null when the line does not give one.
///
/// The *why* of a failure is logged before the failure itself, usually at warning level and by
/// the component that met it: `ffmpeg` for an HTTP status or a DNS miss, `vd` for a decoder.
/// The engine keeps the last reason it saw and reports it with the failure, so the codes the
/// retry ladder and the error screen branch on come from the specific line, not the generic
/// "Failed to open" that follows.
FPlayerError? classifyMpvLog(mk.PlayerLog log) {
  if (log.level != 'error' && log.level != 'fatal' && log.level != 'warn') return null;

  final text = log.text;
  final message = '[${log.prefix}] $text';

  final http = _httpStatus.firstMatch(text);
  if (http != null) {
    final status = int.parse(http.group(1)!);
    return FPlayerError(
      code: switch (status) {
        401 => FPlayerErrorCode.unauthorized,
        403 => FPlayerErrorCode.forbidden,
        404 => FPlayerErrorCode.notFound,
        _ => FPlayerErrorCode.badHttpStatus,
      },
      message: message,
      httpStatus: status,
      // A server that answered 5xx may answer differently in a moment; a 4xx will not.
      isRetryable: status >= 500,
    );
  }

  if (_timeout.hasMatch(text)) {
    return FPlayerError(code: FPlayerErrorCode.timeout, message: message, isRetryable: true);
  }
  if (_network.hasMatch(text)) {
    return FPlayerError(code: FPlayerErrorCode.network, message: message, isRetryable: true);
  }
  if (_unsupported.hasMatch(text)) {
    return FPlayerError(code: FPlayerErrorCode.unsupportedFormat, message: message);
  }
  if (_fatal.hasMatch(text)) {
    return FPlayerError(code: FPlayerErrorCode.malformedContent, message: message);
  }

  return switch (log.prefix) {
    'vd' || 'ad' => FPlayerError(code: FPlayerErrorCode.decoder, message: message),
    'ao' => FPlayerError(code: FPlayerErrorCode.audioOutput, message: message),
    'file' => FPlayerError(code: FPlayerErrorCode.io, message: message),
    _ => null,
  };
}

final RegExp _fatal = RegExp(
  r'^Failed to open |Failed to recognize file format|No video or audio streams selected|'
  r'treating it as fatal error',
);
final RegExp _httpStatus = RegExp(r'HTTP error (\d{3})');
final RegExp _timeout = RegExp('timed out|timeout', caseSensitive: false);
final RegExp _network = RegExp(
  'Failed to resolve hostname|Connection refused|Connection reset|Network is unreachable|'
  'No route to host|tls:',
  caseSensitive: false,
);
final RegExp _unsupported = RegExp(
  'Failed to recognize file format|No video or audio streams selected|Could not find codec',
  caseSensitive: false,
);
