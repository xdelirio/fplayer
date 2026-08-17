import 'package:flutter/foundation.dart';

/// Which decoders the engine is allowed to pick.
enum FDecoderMode {
  /// Hardware decoders first, software as fallback. The right choice for almost every app:
  /// hardware decoding is what keeps battery drain and heat down.
  hardwareFirst,

  /// Software decoders first. Use to work around a device that ships a broken hardware decoder
  /// for a specific codec.
  softwareFirst,

  /// Only hardware decoders. Playback fails if none exists for the codec.
  hardwareOnly,

  /// Only software decoders. Playback fails if none exists for the codec.
  softwareOnly,
}

/// Decoding and quality-ceiling settings.
@immutable
class FDecoderConfig {
  const FDecoderConfig({
    this.mode = FDecoderMode.hardwareFirst,
    this.enableDecoderFallback = true,
    this.maxWidth,
    this.maxHeight,
    this.maxVideoBitrate,
  });

  /// Caps adaptive streaming at 720p — a reasonable ceiling for low-end phones or a data-saver
  /// toggle.
  const FDecoderConfig.dataSaver()
      : mode = FDecoderMode.hardwareFirst,
        enableDecoderFallback = true,
        maxWidth = 1280,
        maxHeight = 720,
        maxVideoBitrate = 2500000;

  final FDecoderMode mode;

  /// Try the next decoder when the preferred one fails to initialise.
  ///
  /// Costs nothing when everything works and rescues playback on devices with a flaky primary
  /// decoder, so it is on by default.
  final bool enableDecoderFallback;

  /// Upper bound on the video track the adaptive selector may choose.
  final int? maxWidth;
  final int? maxHeight;

  /// Upper bound in bits per second on the video track the adaptive selector may choose.
  final int? maxVideoBitrate;

  FDecoderConfig copyWith({
    FDecoderMode? mode,
    bool? enableDecoderFallback,
    int? maxWidth,
    int? maxHeight,
    int? maxVideoBitrate,
  }) =>
      FDecoderConfig(
        mode: mode ?? this.mode,
        enableDecoderFallback: enableDecoderFallback ?? this.enableDecoderFallback,
        maxWidth: maxWidth ?? this.maxWidth,
        maxHeight: maxHeight ?? this.maxHeight,
        maxVideoBitrate: maxVideoBitrate ?? this.maxVideoBitrate,
      );

  Map<String, Object?> toMap() => {
        'mode': mode.name,
        'enableDecoderFallback': enableDecoderFallback,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'maxVideoBitrate': maxVideoBitrate,
      };
}
