import 'package:flutter/foundation.dart';

/// Retry behaviour applied by the controller once a whole *source* has failed.
///
/// Every attempt re-prepares the media from scratch, so this is the outer and more expensive of
/// the two retry ladders — see [FSegmentRetryPolicy] for the inner one.
///
/// Delays follow `baseDelay * 2^attempt`, capped at [maxDelay].
@immutable
class FRetryPolicy {
  const FRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
  });

  /// Disables automatic retries; errors surface immediately.
  const FRetryPolicy.none()
      : maxAttempts = 0,
        baseDelay = Duration.zero,
        maxDelay = Duration.zero;

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  /// Delay before attempt number [attempt], counting from zero.
  Duration delayFor(int attempt) {
    final ms = baseDelay.inMilliseconds * (1 << attempt);
    return ms >= maxDelay.inMilliseconds ? maxDelay : Duration(milliseconds: ms);
  }
}

/// Retry behaviour applied by the engine to a single failed *load*: one segment, one manifest
/// refresh, one key request.
///
/// This ladder runs inside the engine and playback never leaves the playing state while it does
/// its work — a dropped chunk costs the viewer a brief stall at worst. Only when it is exhausted
/// does the whole playback fail and [FRetryPolicy] take over.
///
/// The two budgets multiply. Three segment retries at up to five seconds each, wrapped in three
/// source retries with exponential backoff, is more than a minute of spinner before an error
/// appears; shorten whichever one matters for your content.
@immutable
class FSegmentRetryPolicy {
  const FSegmentRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 5),
  });

  /// Fails the load on the first error, handing straight over to [FRetryPolicy].
  const FSegmentRetryPolicy.none()
      : maxAttempts = 0,
        baseDelay = Duration.zero,
        maxDelay = Duration.zero;

  /// Attempts per load before it is treated as failed.
  final int maxAttempts;

  /// Delay before the first retry; each further attempt doubles it up to [maxDelay].
  final Duration baseDelay;

  final Duration maxDelay;

  Map<String, Object?> toMap() => {
        'segmentRetryCount': maxAttempts,
        'segmentRetryBaseDelayMs': baseDelay.inMilliseconds,
        'segmentRetryMaxDelayMs': maxDelay.inMilliseconds,
      };
}

/// HTTP behaviour for network sources.
@immutable
class FNetworkConfig {
  const FNetworkConfig({
    this.connectTimeout = const Duration(seconds: 8),
    this.readTimeout = const Duration(seconds: 8),
    this.loadingTimeout = const Duration(seconds: 30),
    this.allowCrossProtocolRedirects = true,
    this.userAgent,
    this.retry = const FRetryPolicy(),
    this.segmentRetry = const FSegmentRetryPolicy(),
    this.waitForNetwork = true,
  });

  final Duration connectTimeout;
  final Duration readTimeout;

  /// How long the player may sit in "loading" before it gives up and reports a timeout.
  ///
  /// This is a wall-clock guard around the whole load, separate from the socket timeouts above.
  /// [Duration.zero] disables it.
  final Duration loadingTimeout;

  /// Follow redirects that switch between HTTP and HTTPS. Many CDNs need this.
  final bool allowCrossProtocolRedirects;

  /// Default `User-Agent`. A `User-Agent` header on the source overrides it.
  final String? userAgent;

  /// Outer ladder: retries the whole source after playback has failed.
  final FRetryPolicy retry;

  /// Inner ladder: retries a single segment, manifest or key without stopping playback.
  final FSegmentRetryPolicy segmentRetry;

  /// Park playback when the device loses its network, and resume when it returns.
  ///
  /// Without it, walking into a tunnel spends the whole retry budget against a network that is
  /// not there and lands the viewer on an error screen seconds later. With it, the failure is
  /// held, `FPlayerValue.isOffline` goes true so the UI can say so, and playback picks up from
  /// the same position the moment there is signal again.
  ///
  /// Turn it off if your app already drives its own connectivity handling — two layers deciding
  /// when to re-prepare will fight.
  final bool waitForNetwork;

  Map<String, Object?> toMap() => {
        'connectTimeoutMs': connectTimeout.inMilliseconds,
        'readTimeoutMs': readTimeout.inMilliseconds,
        'allowCrossProtocolRedirects': allowCrossProtocolRedirects,
        'userAgent': userAgent,
        'waitForNetwork': waitForNetwork,
        ...segmentRetry.toMap(),
      };
}
