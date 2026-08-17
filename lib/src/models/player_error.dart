import 'package:flutter/foundation.dart';

/// Stable classification of a playback failure.
///
/// The codes describe *what went wrong from the app's point of view*, not which engine reported
/// it. That way the UI can decide between "show a retry button" and "ask the user to log in
/// again" without knowing anything about ExoPlayer.
enum FPlayerErrorCode {
  /// Could not reach the server: DNS failure, no route, connection refused.
  network,

  /// The connection was established but stalled past the configured timeout.
  timeout,

  /// HTTP 401. Credentials are missing or expired.
  unauthorized,

  /// HTTP 403, or the OS denied read access to a local file.
  forbidden,

  /// HTTP 404/410, or the file path does not exist.
  notFound,

  /// A non-2xx status that is not one of the cases above.
  badHttpStatus,

  /// The app blocked a plaintext HTTP request. See `usesCleartextTraffic`.
  cleartextNotPermitted,

  /// Generic I/O failure while reading the source.
  io,

  /// The manifest or container could be read but is invalid.
  malformedContent,

  /// No decoder on this device can play the media, or it exceeds the device's capabilities.
  unsupportedFormat,

  /// A decoder existed but failed to initialise or crashed mid-stream.
  decoder,

  /// The audio output could not be opened or written to.
  audioOutput,

  /// DRM licensing failure.
  drm,

  /// The playback position fell outside a live stream's sliding window.
  behindLiveWindow,

  /// Anything the engine did not classify.
  unknown,
}

/// A playback failure, already classified and enriched with what the UI needs to react.
@immutable
class FPlayerError {
  const FPlayerError({
    required this.code,
    required this.message,
    this.nativeCode,
    this.httpStatus,
    this.isRetryable = false,
  });

  factory FPlayerError.fromMap(Map<String, Object?> map) => FPlayerError(
        code: _codeByName[map['code']] ?? FPlayerErrorCode.unknown,
        message: map['message'] as String? ?? 'Unknown playback error',
        nativeCode: map['nativeCode'] as String?,
        httpStatus: (map['httpStatus'] as num?)?.toInt(),
        isRetryable: map['retryable'] as bool? ?? false,
      );

  /// What kind of failure this is.
  final FPlayerErrorCode code;

  /// Human-readable description, taken from the engine. Not localised — do not show it raw to
  /// end users; branch on [code] instead.
  final String message;

  /// The engine's own error name, kept for logs and bug reports.
  final String? nativeCode;

  /// HTTP status, when the failure came from an HTTP response.
  final int? httpStatus;

  /// Whether retrying the exact same source could plausibly succeed.
  final bool isRetryable;

  /// The code an engine named, or null when the name is not one of these.
  ///
  /// For a failure that arrives as a bare platform error rather than the classified payload the
  /// native side normally sends.
  static FPlayerErrorCode? codeByName(String? name) => _codeByName[name];

  static const Map<Object?, FPlayerErrorCode> _codeByName = {
    'network': FPlayerErrorCode.network,
    'timeout': FPlayerErrorCode.timeout,
    'unauthorized': FPlayerErrorCode.unauthorized,
    'forbidden': FPlayerErrorCode.forbidden,
    'notFound': FPlayerErrorCode.notFound,
    'badHttpStatus': FPlayerErrorCode.badHttpStatus,
    'cleartextNotPermitted': FPlayerErrorCode.cleartextNotPermitted,
    'io': FPlayerErrorCode.io,
    'malformedContent': FPlayerErrorCode.malformedContent,
    'unsupportedFormat': FPlayerErrorCode.unsupportedFormat,
    'decoder': FPlayerErrorCode.decoder,
    'audioOutput': FPlayerErrorCode.audioOutput,
    'drm': FPlayerErrorCode.drm,
    'behindLiveWindow': FPlayerErrorCode.behindLiveWindow,
    'unknown': FPlayerErrorCode.unknown,
  };

  @override
  String toString() => 'FPlayerError(${code.name}'
      '${httpStatus != null ? ' $httpStatus' : ''}: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FPlayerError &&
          other.code == code &&
          other.message == message &&
          other.nativeCode == nativeCode &&
          other.httpStatus == httpStatus &&
          other.isRetryable == isRetryable;

  @override
  int get hashCode => Object.hash(code, message, nativeCode, httpStatus, isRetryable);
}
