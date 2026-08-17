import 'package:flutter/foundation.dart';

/// How much media the engine keeps in memory ahead of and behind the playhead.
///
/// The defaults are ExoPlayer's, which are tuned for on-demand video. The two named constructors
/// cover the cases where they are wrong.
@immutable
class FBufferConfig {
  const FBufferConfig({
    this.minBuffer = const Duration(milliseconds: 50000),
    this.maxBuffer = const Duration(milliseconds: 50000),
    this.bufferForPlayback = const Duration(milliseconds: 2500),
    this.bufferForPlaybackAfterRebuffer = const Duration(milliseconds: 5000),
    this.backBuffer = Duration.zero,
    this.prioritizeTimeOverSizeThresholds = false,
  });

  /// Starts playing sooner at the cost of being more sensitive to bandwidth dips.
  ///
  /// Useful when the app is judged on how fast the first frame appears.
  const FBufferConfig.fastStart()
      : minBuffer = const Duration(milliseconds: 15000),
        maxBuffer = const Duration(milliseconds: 30000),
        bufferForPlayback = const Duration(milliseconds: 500),
        bufferForPlaybackAfterRebuffer = const Duration(milliseconds: 2000),
        backBuffer = Duration.zero,
        prioritizeTimeOverSizeThresholds = true;

  /// Buffers aggressively to survive unstable connections, at the cost of memory and of a slower
  /// first frame.
  const FBufferConfig.resilient()
      : minBuffer = const Duration(milliseconds: 60000),
        maxBuffer = const Duration(milliseconds: 120000),
        bufferForPlayback = const Duration(milliseconds: 3000),
        bufferForPlaybackAfterRebuffer = const Duration(milliseconds: 8000),
        backBuffer = const Duration(milliseconds: 30000),
        prioritizeTimeOverSizeThresholds = true;

  /// Below this, the engine keeps loading.
  final Duration minBuffer;

  /// Above this, the engine stops loading until playback drains it.
  final Duration maxBuffer;

  /// How much must be buffered before playback starts.
  final Duration bufferForPlayback;

  /// How much must be buffered before playback resumes after a stall.
  final Duration bufferForPlaybackAfterRebuffer;

  /// Media kept *behind* the playhead. Non-zero makes short seeks backwards instant, at the cost
  /// of memory.
  final Duration backBuffer;

  /// Keep buffering to reach [minBuffer] even when the memory target is already met.
  final bool prioritizeTimeOverSizeThresholds;

  Map<String, Object?> toMap() => {
        'minBufferMs': minBuffer.inMilliseconds,
        'maxBufferMs': maxBuffer.inMilliseconds,
        'bufferForPlaybackMs': bufferForPlayback.inMilliseconds,
        'bufferForPlaybackAfterRebufferMs': bufferForPlaybackAfterRebuffer.inMilliseconds,
        'backBufferMs': backBuffer.inMilliseconds,
        'prioritizeTimeOverSizeThresholds': prioritizeTimeOverSizeThresholds,
      };
}
