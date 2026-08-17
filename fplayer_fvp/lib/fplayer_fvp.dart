/// A libmdk/FFmpeg fallback engine for `fplayer`.
///
/// Lives outside the base package on purpose. It ships FFmpeg, libmdk and libass — about 11.5 MB
/// per ABI, several times the weight of everything else in the player — and closes one narrow
/// gap: codecs Android's own decoders do not cover, chiefly AV1 by software on Android below 12.
/// An app that never meets that gap should not carry the bytes.
///
/// Wrap the ordinary engine in [FFallbackEngine] and hand it to the controller:
///
/// ```dart
/// FPlayerController(
///   engine: FFallbackEngine(config: const FEngineConfig(mode: FEngineMode.automatic)),
/// )
/// ```
///
/// What it does *not* do — adaptive bitrate, Picture-in-Picture, media sessions, downloads, DRM —
/// is documented on [FFvpEngine]. Read it before switching an app to `fvpOnly`.
library;

export 'src/engine/fallback_engine.dart';
export 'src/engine/fvp_engine.dart';
export 'src/engine_config.dart';
