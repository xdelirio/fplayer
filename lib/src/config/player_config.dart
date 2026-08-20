import 'package:flutter/foundation.dart';

import 'background_config.dart';
import 'buffer_config.dart';
import 'decoder_config.dart';
import 'network_config.dart';
import 'pip_config.dart';
import 'playback_config.dart';
import 'render_mode.dart';
import 'subtitle_style.dart';

/// Everything that shapes a player's behaviour, grouped by concern.
///
/// The grouping is deliberate: a flat object would grow to dozens of unrelated fields, and apps
/// would have no way to share, say, one buffering profile across several players while varying
/// the rest. Every group has usable defaults, so `const FPlayerConfig()` is a valid starting
/// point.
///
/// Config is applied at creation time. Values that can change during playback — speed, volume,
/// looping — are also available as methods on the controller.
@immutable
class FPlayerConfig {
  const FPlayerConfig({
    this.playback = const FPlaybackConfig(),
    this.buffering = const FBufferConfig(),
    this.network = const FNetworkConfig(),
    this.decoding = const FDecoderConfig(),
    this.subtitleStyle = const FSubtitleStyle(),
    this.pip = const FPipConfig(),
    this.background = const FBackgroundConfig(),
    this.renderMode = FVideoRenderMode.auto,
  });

  final FPlaybackConfig playback;
  final FBufferConfig buffering;
  final FNetworkConfig network;
  final FDecoderConfig decoding;

  /// Appearance of rendered subtitles. Used by the Flutter subtitle layer, not by the engine.
  final FSubtitleStyle subtitleStyle;

  /// Picture-in-Picture behaviour.
  final FPipConfig pip;

  /// What playback does when the app leaves the screen, and whether a media session is published.
  final FBackgroundConfig background;

  /// How frames reach the widget tree. Resolved natively when it is [FVideoRenderMode.auto], so
  /// the value the engine settled on is not this field but `FPlayerController.platformViewId`.
  final FVideoRenderMode renderMode;

  FPlayerConfig copyWith({
    FPlaybackConfig? playback,
    FBufferConfig? buffering,
    FNetworkConfig? network,
    FDecoderConfig? decoding,
    FSubtitleStyle? subtitleStyle,
    FPipConfig? pip,
    FBackgroundConfig? background,
    FVideoRenderMode? renderMode,
  }) =>
      FPlayerConfig(
        playback: playback ?? this.playback,
        buffering: buffering ?? this.buffering,
        network: network ?? this.network,
        decoding: decoding ?? this.decoding,
        subtitleStyle: subtitleStyle ?? this.subtitleStyle,
        pip: pip ?? this.pip,
        background: background ?? this.background,
        renderMode: renderMode ?? this.renderMode,
      );

  Map<String, Object?> toMap() => {
        'playback': playback.toMap(),
        'buffering': buffering.toMap(),
        'network': network.toMap(),
        'decoding': decoding.toMap(),
        'pip': pip.toMap(),
        'background': background.toMap(),
        'renderMode': renderMode.name,
      };
}
