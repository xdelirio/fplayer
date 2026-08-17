import 'package:flutter/foundation.dart';

/// Which playback backend a controller uses.
enum FEngineMode {
  /// Media3/ExoPlayer only. The right choice for streaming: it is the only backend here with real
  /// adaptive bitrate, DRM, Picture-in-Picture, a media session and offline downloads.
  media3Only,

  /// Media3, falling back to libmdk only when a source fails for want of a decoder.
  ///
  /// Costs nothing until a failure happens, and buys playback of codecs the device's own decoders
  /// do not cover — AV1 on Android below 12, mostly. Everything the fallback cannot do is listed
  /// on `FFvpEngine`; expect a plainer player for whatever lands on it.
  automatic,

  /// libmdk only. For debugging the fallback, or for an app that plays nothing but local files in
  /// exotic containers.
  fvpOnly,
}

/// Backend selection and the decoder preferences that go with it.
@immutable
class FEngineConfig {
  const FEngineConfig({
    this.mode = FEngineMode.media3Only,
    this.fvpVideoDecoders = const ['AMediaCodec', 'FFmpeg', 'dav1d'],
    this.fvpAudioDecoders = const ['FFmpeg'],
    this.fvpMaxTextureWidth,
    this.fvpMaxTextureHeight,
  });

  final FEngineMode mode;

  /// Decoder priority handed to libmdk, most preferred first.
  ///
  /// Hardware first, then FFmpeg's software decoders, then dav1d for AV1 — which is the whole
  /// reason the fallback exists. Names come from libmdk, not from Android.
  final List<String> fvpVideoDecoders;

  final List<String> fvpAudioDecoders;

  /// Caps the texture libmdk allocates.
  ///
  /// Its texture is the video's own size by default, and a 4K surface being scaled down to a
  /// phone screen costs memory for detail nobody sees. Null keeps the native size.
  final int? fvpMaxTextureWidth;
  final int? fvpMaxTextureHeight;

  FEngineConfig copyWith({
    FEngineMode? mode,
    List<String>? fvpVideoDecoders,
    List<String>? fvpAudioDecoders,
    int? fvpMaxTextureWidth,
    int? fvpMaxTextureHeight,
  }) =>
      FEngineConfig(
        mode: mode ?? this.mode,
        fvpVideoDecoders: fvpVideoDecoders ?? this.fvpVideoDecoders,
        fvpAudioDecoders: fvpAudioDecoders ?? this.fvpAudioDecoders,
        fvpMaxTextureWidth: fvpMaxTextureWidth ?? this.fvpMaxTextureWidth,
        fvpMaxTextureHeight: fvpMaxTextureHeight ?? this.fvpMaxTextureHeight,
      );
}
