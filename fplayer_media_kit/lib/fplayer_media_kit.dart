/// A libmpv engine for `fplayer`, for every platform that is not Android.
///
/// Lives outside the base package on purpose: it ships libmpv and FFmpeg for iOS, macOS, Windows
/// and Linux, and an Android-only app should not carry the bytes or the plugin registrations.
/// The native libraries are pulled per platform rather than through `media_kit_libs_video`, so
/// nothing of it lands in an Android build either.
///
/// Hand the controller the engine for the platform it runs on:
///
/// ```dart
/// FPlayerController(engine: createPlatformEngine())
/// ```
///
/// What the mpv engine does *not* do — adaptive bitrate, Picture-in-Picture, media sessions,
/// DRM, positioned subtitles — is documented on [FMediaKitEngine].
library;

import 'dart:io' show Platform;

import 'package:fplayer/fplayer.dart';

import 'src/engine/media_kit_engine.dart';

export 'src/engine/media_kit_engine.dart';

/// The engine for the platform this process runs on: Media3 on Android, libmpv anywhere else.
///
/// The Android engine keeps everything the platform offers — adaptive bitrate, PiP, the media
/// session, the SurfaceView for televisions — and the mpv one covers the rest of the platforms
/// with one implementation.
FPlaybackEngine createPlatformEngine() => Platform.isAndroid ? FMedia3Engine() : FMediaKitEngine();
