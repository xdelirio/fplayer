import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';
import 'package:fplayer_media_kit/src/engine/mpv_error.dart';
import 'package:media_kit/media_kit.dart' as mk;

mk.PlayerLog _log(String prefix, String text, {String level = 'error'}) =>
    mk.PlayerLog(prefix: prefix, level: level, text: text);

void main() {
  group('isMpvLoadFailure', () {
    test('recognises mpv giving up on a file', () {
      expect(isMpvLoadFailure(_log('stream', 'Failed to open https://x/nope.mp4.')), isTrue);
      expect(isMpvLoadFailure(_log('cplayer', 'Failed to recognize file format.')), isTrue);
      expect(isMpvLoadFailure(_log('lavf', '...treating it as fatal error.')), isTrue);
    });

    test('lets error-level noise through', () {
      expect(isMpvLoadFailure(_log('lavf', 'Failed to create file cache.')), isFalse);
      expect(isMpvLoadFailure(_log('ffmpeg', 'Cannot seek backward in linear streams!')), isFalse);
      expect(isMpvLoadFailure(_log('media_kit', 'error: property not found')), isFalse);
      expect(isMpvLoadFailure(_log('vd', 'Error while decoding frame')), isFalse);
    });

    test('is not fooled by a warning that mentions opening', () {
      expect(isMpvLoadFailure(_log('stream', 'Failed to open x', level: 'warn')), isFalse);
    });
  });

  group('classifyMpvLog', () {
    test('ignores anything below warn, and warnings that give no reason', () {
      expect(classifyMpvLog(_log('ffmpeg', 'https: HTTP error 404', level: 'info')), isNull);
      expect(
        classifyMpvLog(_log('playlist', 'Reading plaintext playlist.', level: 'warn')),
        isNull,
      );
    });

    test('gives no reason for noise', () {
      expect(classifyMpvLog(_log('lavf', 'Failed to create file cache.')), isNull);
      expect(classifyMpvLog(_log('media_kit', 'error: property not found')), isNull);
      expect(classifyMpvLog(_log('ffmpeg', 'Cannot seek backward in linear streams!')), isNull);
    });

    test('reads the HTTP status out of the message, at the level ffmpeg logs it', () {
      final notFound = classifyMpvLog(
        _log('ffmpeg', 'https: HTTP error 404 Not Found', level: 'warn'),
      )!;
      expect(notFound.code, FPlayerErrorCode.notFound);
      expect(notFound.httpStatus, 404);
      expect(notFound.isRetryable, isFalse);

      expect(
        classifyMpvLog(_log('ffmpeg', 'https: HTTP error 401 Unauthorized'))!.code,
        FPlayerErrorCode.unauthorized,
      );
      expect(
        classifyMpvLog(_log('ffmpeg', 'https: HTTP error 403 Forbidden'))!.code,
        FPlayerErrorCode.forbidden,
      );

      final serverError = classifyMpvLog(_log('ffmpeg', 'https: HTTP error 503 Unavailable'))!;
      expect(serverError.code, FPlayerErrorCode.badHttpStatus);
      expect(serverError.httpStatus, 503);
      expect(serverError.isRetryable, isTrue, reason: 'a 5xx may clear up');
    });

    test('network failures are retryable', () {
      final dns = classifyMpvLog(_log('ffmpeg', 'tcp: Failed to resolve hostname cdn.example'))!;
      expect(dns.code, FPlayerErrorCode.network);
      expect(dns.isRetryable, isTrue);

      final timeout = classifyMpvLog(_log('ffmpeg', 'tcp: Connection timed out'))!;
      expect(timeout.code, FPlayerErrorCode.timeout);
      expect(timeout.isRetryable, isTrue);
    });

    test('a file mpv cannot read is not retryable', () {
      final format = classifyMpvLog(_log('cplayer', 'Failed to recognize file format.'))!;
      expect(format.code, FPlayerErrorCode.unsupportedFormat);
      expect(format.isRetryable, isFalse);

      expect(
        classifyMpvLog(_log('file', "Cannot open file '/x.mp4': No such file or directory"))!.code,
        FPlayerErrorCode.io,
      );
      expect(
        classifyMpvLog(_log('stream', 'Failed to open /x.mp4.'))!.code,
        FPlayerErrorCode.malformedContent,
        reason: 'the giving-up line on its own says nothing more specific',
      );
    });

    test('classifies by the component that gave up', () {
      expect(
        classifyMpvLog(_log('vd', 'Error while decoding frame'))!.code,
        FPlayerErrorCode.decoder,
      );
      expect(classifyMpvLog(_log('ad', 'Error decoding audio'))!.code, FPlayerErrorCode.decoder);
      expect(
        classifyMpvLog(_log('ao', 'Failed to initialize audio driver'))!.code,
        FPlayerErrorCode.audioOutput,
      );
    });

    test('keeps the component in the message', () {
      expect(classifyMpvLog(_log('vd', 'boom'))!.message, '[vd] boom');
    });
  });
}
