# fplayer — Architecture plan and roadmap

> Status: roadmap complete. Every phase implemented and verified on device. Android in the base package; the other platforms through the `fplayer_media_kit` sibling.
> Flutter 3.47 · Dart 3.13 · minSdk 24 (Flutter's current floor) · compileSdk 36 · Media3 1.11.0
>
> **Decisions made** — engine: native Media3 plugin · DRM: not required (hooks only, phase 11) · telemetry: none — `fplayer` exposes `FPlayerObserver` and stops there

---

## 1. Engine decision

### Recommendation: **our own native plugin on Media3 (ExoPlayer) 1.11.0**, with `fvp` as an optional secondary engine.

`fvp` (libmdk + FFmpeg) is excellent, but it is tuned for *format coverage and cross-platform parity*, not for *adaptive streaming on Android*. Your requirements (HLS, DASH, headers, external subtitles, TV, PiP) land squarely on the side where Media3 wins.

| Requirement | Native Media3 | fvp (libmdk/FFmpeg) |
|---|---|---|
| HLS with **real ABR** (bitrate switching by bandwidth) | Yes, `media3-exoplayer-hls` | **No.** FFmpeg's HLS demuxer picks one variant; there is no adaptive ladder |
| DASH with ABR + multi-period | Yes, `media3-exoplayer-dash` | Partial, no ABR |
| Track selection (audio/subs/quality) from the manifest | Native (`TrackSelectionParameters`) | Limited |
| HTTP headers per request / per track | Native (`DataSource.Factory`) | Limited to global options |
| External subtitles with headers | Native (`SubtitleConfiguration`) | `setExternalSubtitle()`, no headers |
| **Widevine DRM** | Yes | **Does not exist** |
| PiP, MediaSession, notification, audio focus | `media3-session` + Activity PiP | All by hand |
| APK size | ~1-2 MB | **+10 MB per ABI** |
| HW decoding | MediaCodec (default) | MediaCodec / FFmpeg |
| **Software AV1 on Android < 12** | ❌ real gap | ✅ dav1d bundled |
| Exotic formats (odd MKVs, odd TS, AC3 in non-standard containers) | Good but not total | ✅ better |

**Media3's only real gap is software AV1 on old devices.** And it is smaller than it looks:

- Android 12+ (API 31) ships `c2.android.av1.decoder` (libgav1) in the platform → ExoPlayer picks it up on its own, with no work.
- Android 10/11 devices with a modern SoC (Dimensity 1000+, SD 8 Gen 2+) have hardware AV1.
- Verified today: Google **does not publish** `media3-decoder-av1` or `media3-decoder-ffmpeg` on its Maven (only `media3-decoder`, which is the plumbing). The extensions have to be built with the NDK, or you use a third-party prebuilt (`nextlib` — which covers H264/HEVC/VP8/VP9 + plenty of audio codecs, **but not AV1**).

→ That is why the architecture keeps the engine **pluggable** (`FPlaybackEngine`), with `fvp` arriving in a late phase as an alternative engine for that one case, switched on by config or by automatic fallback when Media3 reports `ERROR_CODE_DECODING_FORMAT_UNSUPPORTED`.

### What I am ruling out, and why

- **Official `video_player`**: no track selection, no PiP, no MediaSession, subtitles only from a local file in Dart. Very low ceiling.
- **`better_player` / forks**: what you already had; ExoPlayer 2 (deprecated), tightly coupled API, hard to extend to TV/PiP the way you want.
- **`media_kit`**: the same ABR limitations as fvp (it is libmpv/FFmpeg) plus weight, and its strength is desktop.

---

## 2. Architecture

Four layers, each usable on its own. A consumer can take just the controller and build their own UI.

```
┌─ Layer 4: ready-made UI ──────────────────────────────────┐
│  FPlayerView · touch controls · TV controls               │
│  overlays replaceable through builders                    │
├─ Layer 3: state ──────────────────────────────────────────┤
│  FPlayerController (ChangeNotifier) · FPlayerValue        │
│  playlist · tracks · storyboard · analytics               │
├─ Layer 2: engine abstraction ─────────────────────────────┤
│  FPlaybackEngine (interface) · Media3Engine · [FvpEngine] │
├─ Layer 1: native Android ─────────────────────────────────┤
│  Kotlin · ExoPlayer · SurfaceProducer · MethodChannel     │
│  EventChannel · PiP · MediaSession                        │
└───────────────────────────────────────────────────────────┘
```

### Technical points of the native layer

- **Rendering**: `TextureRegistry.SurfaceProducer` (the modern Flutter 3.22+ API, compatible with Impeller/Vulkan and with correct handling of `onSurfaceDestroyed`/`onSurfaceAvailable` when going to background). An alternative `PlatformView + SurfaceView` mode is on the table for TV/4K/HDR and secure DRM, selectable by config (`FRenderMode.texture | .surface`).
- **Multi-instance**: one `ExoPlayer` per `playerId`, each with its own `LoadControl` and `RenderersFactory`. No singletons.
- **Channels**: one global `MethodChannel` to create/destroy, plus a `MethodChannel` and an `EventChannel` per instance.
- **Subtitles**: Media3's `Cue` objects are serialised to Dart (text + position/line/alignment/size) and rendered with a Flutter widget. That gives full styling control, works the same in fullscreen and on TV, and does not depend on the native `SubtitleView`. The cue geometry is preserved so ASS/TTML positioning is not broken.
- **Decoders**: `DefaultRenderersFactory` with `EXTENSION_RENDERER_MODE_PREFER`/`OFF` depending on `FDecoderConfig.mode`, plus a custom `MediaCodecSelector` to force software (`c2.android.*`) when asked.

### Target file tree

```
lib/
├── fplayer.dart                        # single export
└── src/
    ├── core/
    │   ├── player_controller.dart       # FPlayerController
    │   ├── player_value.dart            # immutable state
    │   ├── player_status.dart
    │   ├── player_event.dart            # event stream
    │   └── playlist_controller.dart
    ├── engine/
    │   ├── playback_engine.dart         # interface
    │   ├── media3/
    │   │   ├── media3_engine.dart
    │   │   ├── media3_channel.dart
    │   │   └── media3_mappers.dart
    │   └── fvp/                         # phase 11
    ├── models/
    │   ├── source.dart                  # FPlayerSource, FSubtitleSource, FStoryboardSource
    │   ├── track.dart                   # FAudioTrack, FTextTrack, FVideoTrack
    │   ├── cue.dart
    │   ├── chapter.dart
    │   └── error.dart                   # FPlayerError + taxonomy
    ├── config/
    │   ├── player_config.dart           # aggregator
    │   ├── playback_config.dart
    │   ├── buffer_config.dart
    │   ├── network_config.dart
    │   ├── decoder_config.dart
    │   ├── ui_config.dart
    │   ├── fullscreen_config.dart
    │   ├── tv_config.dart
    │   ├── pip_config.dart
    │   ├── background_config.dart
    │   └── subtitle_style.dart
    ├── storyboard/
    │   ├── storyboard.dart
    │   ├── vtt_parser.dart              # supports #xywh and standalone frames
    │   ├── bif_parser.dart              # optional
    │   └── sprite_cache.dart
    ├── ui/
    │   ├── player_view.dart
    │   ├── video_surface.dart           # texture only, no chrome
    │   ├── fullscreen.dart
    │   ├── theme.dart
    │   ├── localizations.dart
    │   ├── touch/                       # mobile controls
    │   ├── tv/                          # D-pad controls
    │   └── shared/                      # progress bar, subtitle layer, spinner, error
    ├── platform/
    │   ├── pip.dart
    │   ├── wakelock.dart
    │   ├── brightness.dart
    │   └── device.dart                  # TV / leanback detection
    └── analytics/
        ├── observer.dart                # FPlayerObserver (interface)
        ├── metrics.dart
        └── http_reporter.dart           # optional, separate

android/src/main/kotlin/dev/chikenare/fplayer/
├── FplayerPlugin.kt
├── PlayerInstance.kt
├── SourceFactory.kt          # MediaItem + DataSource.Factory + headers
├── TrackController.kt
├── DecoderFactory.kt
├── CueBridge.kt
├── PipController.kt
├── SessionController.kt      # MediaSession + notification
└── AnalyticsBridge.kt        # AnalyticsListener → events

example/                      # demo app (mobile + TV)
```

---

## 3. Public API (draft for review)

### Source

```dart
final source = FPlayerSource.network(
  'https://cdn.example.com/master.m3u8',
  type: FSourceType.auto,          // auto | hls | dash | smooth | progressive
  headers: {'Authorization': 'Bearer $token'},
  title: 'Episode 4',
  subtitle: 'Season 2',
  posterUrl: '...',
  startAt: Duration(minutes: 12),
  isLive: false,
  subtitles: [
    FSubtitleSource.network('https://.../es.vtt',
      label: 'Spanish', language: 'es',
      headers: {...}, selectedByDefault: true),
  ],
  storyboard: FStoryboardSource.vtt('https://.../sb.vtt', headers: {...}),
  chapters: [...],
  drm: FDrmConfig.widevine(licenseUrl: '...', headers: {...}),  // phase 11
  metadata: {'contentId': 42, 'episodeId': 128},                // free-form
);

FPlayerSource.file('/storage/emulated/0/video.mkv');
FPlayerSource.asset('assets/intro.mp4');
```

### Configuration — sub-configs instead of a 60-parameter object

```dart
const config = FPlayerConfig(
  playback: FPlaybackConfig(
    autoPlay: true,
    loop: false,
    speed: 1.0,
    volume: 1.0,
    seekStep: Duration(seconds: 10),
    preferredAudioLanguages: ['es', 'en'],
    preferredTextLanguages: ['es'],
    autoSelectSubtitles: false,
  ),
  ui: FUiConfig(
    showControls: true,
    controlsTimeout: Duration(seconds: 4),
    showPipButton: true,
    showFullscreenButton: true,
    showLockButton: true,
    showSpeedButton: true,
    showSettingsButton: true,
    showSkipButtons: true,
    showTitle: true,
    gestures: FGestureConfig(
      doubleTapSeek: true,
      verticalDragVolume: true,
      verticalDragBrightness: true,
      horizontalDragSeek: true,
      pinchToZoom: true,
    ),
    fit: FVideoFit.contain,      // contain | cover | fill | fitWidth | fitHeight
    theme: FPlayerTheme.dark(accent: Color(0xFFE50914)),
  ),
  fullscreen: FFullscreenConfig(
    autoFullscreen: false,
    autoRotate: true,
    orientations: [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    exitOnComplete: true,
    systemUiMode: SystemUiMode.immersiveSticky,
  ),
  tv: FTvConfig(mode: FTvMode.auto, seekAcceleration: true),
  pip: FPipConfig(enabled: true, autoEnterOnLeave: true),
  background: FBackgroundConfig(
    mode: FBackgroundMode.pause,   // stop | pause | continueAudio
    mediaSession: true,
    notification: FNotificationConfig(...),
  ),
  buffering: FBufferConfig(minBuffer: ..., maxBuffer: ..., forPlayback: ..., backBuffer: ...),
  network: FNetworkConfig(
    connectTimeout: Duration(seconds: 8),
    readTimeout: Duration(seconds: 8),
    loadingTimeout: Duration(seconds: 30),
    retry: FRetryPolicy(maxAttempts: 3, baseDelay: Duration(seconds: 2)),
    userAgent: 'MyApp/1.0',
  ),
  decoding: FDecoderConfig(
    mode: FDecoderMode.hardwareFirst,   // hardwareFirst | softwareFirst | hardwareOnly | softwareOnly
    maxResolution: null,                 // cap for weak devices
  ),
  subtitleStyle: FSubtitleStyle(...),
  wakelock: true,
);
```

`FPlayerConfig` and every sub-config get `copyWith`, are `const`-constructible, and carry sensible defaults → the minimum usage is `FPlayerConfig()`.

### Controller

```dart
final controller = FPlayerController(config: config);
await controller.open(source);

// state (everything in value, plus convenience getters)
controller.value.status;        // idle loading ready buffering playing paused completed error
controller.position / duration / buffered / progress / speed / volume / isMuted
controller.videoSize / aspectRatio / isLive / seekableRange
controller.error;               // FPlayerError? with code, message, isRetryable, cause

// control
play() pause() togglePlayPause() stop() retry()
seek(Duration) seekBy(Duration) seekToLive()
setSpeed(double) setVolume(double) toggleMute()
setFit(FVideoFit) setZoom(double)

// tracks
controller.audioTracks / textTracks / videoTracks
selectAudioTrack(FAudioTrack?) selectTextTrack(FTextTrack?) selectVideoTrack(FVideoTrack?)  // null = auto/off
addSubtitle(FSubtitleSource) removeSubtitle(...)
setSubtitleOffset(Duration)

// playlist
setPlaylist(List<FPlayerSource>, startIndex: 0)
next() previous() jumpTo(int)

// screen
enterFullscreen() exitFullscreen() toggleFullscreen()
enterPip() exitPip()
controller.isPipSupported / isPipActive / isFullscreen

// events (on top of ChangeNotifier)
controller.events.listen((FPlayerEvent e) { ... });
```

### UI

```dart
// everything included
FPlayerView(controller: controller)

// just the video, your chrome on top
FVideoSurface(controller: controller)

// surgical customisation without forking
FPlayerView(
  controller: controller,
  overlayBuilder: (ctx, ctrl) => MyOverlay(ctrl),
  topBarBuilder: ...,
  bottomBarBuilder: ...,
  settingsBuilder: ...,
  errorBuilder: ...,
  loadingBuilder: ...,
  posterBuilder: ...,
)
```

---

## 4. Phased roadmap

Every phase is deliverable, compiles, and leaves the `example/` app working.

| # | Phase | Deliverable | Acceptance criterion |
|---|---|---|---|
| ✅ **0** | Scaffolding | Turn the package into a plugin, `android/` Kotlin, `example/`, strict lints | `flutter analyze` clean, example starts |
| ✅ **1** | Media3 engine + bridge | Playback of file/HLS/DASH/progressive, headers, play/pause/seek/speed/volume, state and position events | All 4 source types play; headers verified against an authenticated endpoint |
| ✅ **2** | Tracks and subtitles | Audio/subs/quality from the manifest, external subs by URL with headers (SRT/VTT/ASS/TTML), cues to Dart and rendered in Flutter, preferred languages | Hot track switching with no stutter; external subs with auth |
| ✅ **3** | Base UI | `FPlayerView`, progress bar with buffered range, gestures, theme, i18n, customisation builders | Player usable end to end on mobile |
| ✅ **4** | Fullscreen and lifecycle | Fullscreen with no re-buffer (same instance), orientation, immersive, wakelock, audio focus, background/foreground | Rotating and entering/leaving fullscreen does not restart the video |
| ✅ **5** | TV / D-pad | Leanback detection, focus ring, accelerated scrubbing with ←/→, media keys, side track panel, TV layout | 100% navigable with a remote on a real Android TV |
| ✅ **6** | Storyboard | VTT parser with `#xywh`, sprites, headers, cache, preview on the slider; frame-extraction fallback for local files | Smooth thumbnail while dragging on a VOD with a sprite sheet |
| ✅ **7** | PiP + MediaSession | PiP with auto-enter, in-window actions, MediaSession + notification, background audio, headset buttons | PiP works; controls on the lock screen |
| ✅ **8** | Robustness | Error taxonomy, retry with backoff, load timeout, live-edge handling, bitrate caps / data-saver mode | Network drop → reconnects on its own; fatal error → overlay with retry |
| ✅ **9** | Playlist and chapters | Queue, autoplay next, skip intro/outro markers, chapters on the bar, "next episode" card | A whole series plays back to back |
| ✅ **10** | Analytics | `FPlayerObserver` fed by Media3's `AnalyticsListener` (startup, rebuffers, dropped frames, bytes, real bitrate), optional HTTP reporter in a separate package (since removed) | Metrics match actual playback |

---

## 5. Decisions

### Settled

| Topic | Decision |
|---|---|
| Engine | Our own native plugin on Media3/ExoPlayer 1.11.0. `fvp` stays as an optional engine in phase 11 |
| DRM | Not required. The `FDrmConfig` hooks stay in the API from phase 1, with no implementation |
| Telemetry | Out of the core. `fplayer` exposes only the `FPlayerObserver` interface; the `fplayer_telemetry` reporter that once shipped it to a backend has been removed |
| Rendering | Start with `SurfaceProducer` (texture). Evaluate `PlatformView + SurfaceView` in phase 5 if a real TV drops frames at 4K |
| Subtitles | Cues serialised to Dart and rendered in Flutter, preserving cue geometry |
| Native package id | `dev.chikenare.fplayer` |

### Open questions for you

1. **Naming convention**: I propose `FPlayer*` for the big public classes (`FPlayerController`, `FPlayerView`, `FPlayerConfig`) and `F*` for models and enums (`FPlayerSource`, `FAudioTrack`, `FVideoFit`).
2. **Subtitle timing offset** (`setSubtitleOffset`), pulled out of phase 2. There is no clean route on Media3: `TextRenderer` is `final`, so you cannot shift the clock the renderer sees, and doing it in Dart would only allow delaying (a cue that runs early would have to be shown before the engine emits it). The two real ways out:
   - **Wrap `SubtitleParser` natively** and shift the timings at parse time. Works in both directions and is little code, but the offset is fixed at load: changing it live forces a source reload.

   My recommendation is the second one if the adjustment is something you configure once, and the first if you want a live sync slider. Decide it when we reach phase 8.

---

## 6. Implementation log

Findings that cost time and are worth not rediscovering.

### Phase 1

- **`SurfaceProducer.setSize()` is mandatory.** The official `video_player_android` plugin never calls it and works on its path, but on the ImageReader backend (Impeller/Vulkan, Android 15) the buffer keeps the size it was created with — the widget's. Frames of 1280×720 landed in the top-left corner of a 1344×756 buffer and got clipped by ~5% on the right and bottom. The fix: resize the texture to the decoded size in `onVideoSizeChanged` and **reassign the Surface**, because `setSize` can hand back a new one. See `PlayerHost.resizeSurface`.
- **Event order on a fatal error.** ExoPlayer moves to `STATE_IDLE` *and then* reports the error. Emitting both made Dart show "no media" for a frame before the error overlay. The `idle` is skipped when `player.playerError != null`.
- **Duration at startup.** `initialized` cannot be emitted as soon as the state is `READY`: the duration can still be `TIME_UNSET`. We wait for a valid duration, except on live where there will never be one.
- **Test URLs.** Google's `gtv-videos-bucket` (the classic *ForBiggerBlazes*, *ElephantsDream*) stopped being public and returns 403. The example uses `media.w3.org`, `shaka-demo-assets` and `demo.unified-streaming.com`.

### Phase 2

- **Selected ≠ active.** Under adaptive selection ExoPlayer marks **all** the qualities in the pool as *selected*, not just the one being decoded. Taking the first always gave the lowest: the chip read "Auto (240p)" while 720×576 was on screen. The API now distinguishes `isSelected` (it is in the selection) from `isActive` (it is being decoded), and `FTracks` exposes `activeVideo` against `selectedVideo` (the one pinned by the user, null on auto). When a group has a single selected track there is no need to compare formats — that only matters inside an adaptive group, and those always come from a manifest with ids.
- **Adaptive switches do not fire `onTracksChanged`.** The track list does not change, only the chosen rung. You need an `AnalyticsListener.onDownstreamFormatChanged`, deduplicated by a signature of the active formats so the whole list is not resent on every event.
- **Parsers fill in the format's default values.** A WebVTT cue with no positioning arrives with `position: 0.5, size: 1.0` and `line:-1`, not with empty fields. Detecting "no preference" with a plain null check routed ordinary subtitles down the absolute-positioning path, anchored at the top and overflowing at the bottom.
- **A negative `line` anchors the bottom edge.** `line:-1` means "the last row": the box grows upwards. Treating it as an offset from the top pushes two-line cues out of the frame.
- **A `Stack` with loose fit defeats `textAlign`.** The text outline is painted as a second copy inside a `Stack`; with the default fit the Stack shrinks to the text's intrinsic width and sticks to the left of the box. It needs `StackFit.passthrough`.
- **Headers per URI, not global.** Setting the media's headers as *default request properties* on `DefaultHttpDataSource` would also send them to a subtitle hosted on another domain — leaking the `Authorization` to a third party. The fix is a `ResolvingDataSource` that injects the right set based on the URI. Verified against the test server: the VTT request carries only its own headers.
- **`TextRenderer` is `final`.** It cannot be subclassed to shift the subtitle timeline, and live sync adjustment has no clean route on Media3 (see "Open questions").
- **`und` is a language.** Muxers write `und` when nobody tagged the track; showing it in a picker is worse than showing nothing. It is normalised to null and falls back to the generic numbered name.

### Phases 3–10

- **`Shortcuts` beats the `Focus` above it.** Key events bubble from the focused node towards the root, so a `Shortcuts` *closer* to the focused button sees the arrow before an ancestor `Focus` does. The "the first press only reveals the controls" logic lived in the ancestor and never ran for ←/→. Everything a directional press implies has to live in the `Shortcuts` action.
- **D-pad acceleration cannot reset on key-up.** `sendKeyEvent` (and a real remote pressed repeatedly) emits down+up per press, so the counter went back to zero between presses and only accelerated while held. Now the commit timer resets it: a burst of separate presses accelerates just like a held key, which is how a remote is actually used.
- **A `Stack` with loose fit defeats `textAlign`** (already seen with subtitles, it reappears in any composition of two copies of a `Text`).
- **The play button sits at the exact centre of the player.** Gestures over the centre only reach the gesture layer with the controls hidden — which is exactly when they are used. The tests exposed it by failing against the wrong widget.
- **Timers alive at unmount.** The load timeout (30 s) and the controls auto-hide outlive the widget tree and fail any test that does not let them expire. Not a product bug, but it forces tests to disarm those timers or let them run out.
- **Hiding the thumbnail until the index loads reintroduces the flicker** `FStoryboardPreview` was designed to avoid: the widget already draws its own placeholder. The integration must not filter on `hasFrames`.
- **The player's height depends on the video's shape.** Obvious in hindsight, but it cost three verification attempts on the emulator: the progress bar's coordinates change between a 5:4 video and a 16:9 one.
- **Inferring a seek from position jumps is approximate.** It was replaced with a real `FSeeked` event emitted by the controller: a one-second correction was indistinguishable from clock drift.
- **The PiP window does not reliably paint Flutter frames on the emulator.** The system does everything right (`mode=pinned`, correct aspect ratio, playback advancing) but the window comes up blank — even with a solid colour behind the video, so it is not the texture. One run in six does paint. It remains to be verified on physical hardware before considering the `PlatformView + SurfaceView` mode.

### Phase 9

- **`previous` does not mean "previous item".** A few seconds in it means "go back to the start of this one", which is what that button does everywhere. Always jumping to the previous one feels hostile when someone just wants to restart what they are watching.
- **`open()` clears the queue, `stop()` does not.** Opening a standalone source means "play this thing"; stopping means unloading the media but keeping the queue, so that `jumpTo` still works afterwards. An empty list in `setPlaylist` is the only case that means "there is no queue".
- **Auto-advance *after* emitting `FCompleted`**, so a listener that wants to do something on finish still sees the item that ended and not the one replacing it.
- **An odd-width frame breaks MediaCodec.** The bunny trailer on w3.org is 853×480 and the emulator's decoder fails to configure even though it reports `format_supported=YES`. The error taxonomy still classified it correctly ("this device cannot play this video"), but it is worth knowing when picking test content.
- **`fvp` costs 11.58 MB per ABI** — 30.4 MB with three — against 1-2 MB for all of Media3, and apps that never use it pay too: Gradle packages the `.so` files because the plugin is in the dependency graph, and Dart's tree-shaking does not touch them. That is why it lives in `fplayer_fvp` and not in the base package. Confirmed by measuring the APK with and without it.
- **`fvp` 0.34 does not build with Flutter 3.47**: its `build.gradle` asserts on the `version` file at the SDK root, which Flutter no longer generates. Fixed in 0.38. It is exactly the kind of coupling you do not want in the base package.
- **There is no L3 forcing in `MediaItem.DrmConfiguration`.** I invented a `forceL3` option and mapped it to a method that does something else; `javap` on the real artifact exposed it. Verify the API before exposing it, and delete the option rather than implement it wrong.
- **A shared window flag needs reference counting.** With several players, a boolean lets the one that pauses turn off the screen underneath the one that is playing.
- **Two agents editing the same file step on each other.** The network agent touched `player_controller.dart` outside its scope while I was modifying it, and we ended up with two handlers for the same event and a reference to a deleted field. File boundaries between parallel workstreams have to be respected, and it is better to merge by hand than to discard: its contribution — not spending retries while there is no network — was the right one.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Software AV1 on Android < 12 | Optional fvp engine (phase 11) or build `media3-decoder-av1` with the NDK |
| `SurfaceProducer` and the background lifecycle | Handle `onSurfaceCleanup`/`onSurfaceAvailable`; test on Android 14/15 |
| PiP with texture rendering shows the whole Activity | PiP mode hides the chrome and forces `fit: cover`; covered in `FPipConfig` |
| Manufacturer fragmentation in decoders | `MediaCodecSelector` with an exclusion list + automatic fallback to software |
| Large scope | Independent, deliverable phases; you can stop at 8 and already have a complete player |
