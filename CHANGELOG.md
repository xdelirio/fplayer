# Changelog

## 0.6.0

A chrome that gets out of the way, and controls where you can see them.

### Added

- **Audio and subtitles in one dialog**, side by side, opened by a single control in the bottom bar. Two columns where there is room, stacked where there is not. The decision is one decision — Japanese audio with English subtitles — so it takes one panel and no menu to walk.
- **A quality control that reads as a value**: `Auto · 1080p` in the bottom bar, the ladder one tap away, the long form dropped for the short one when the player is narrow. Speed works the same way.
- **One row per rung in the quality menu.** Manifests routinely carry several renditions of the same size — a second codec, a second bitrate ladder — and a list with `1080p` three times asks a question nobody can answer. Each size keeps its best rendition; the pinned one still lights up if it was one of the duplicates.
- **`showIdleProgressBar`**: a hairline of progress along the bottom edge while the controls are away, so the one thing worth knowing without asking is on screen.
- **`FPlayerPanel`** with `openPanel` / `closePanel` / `panel` on `FPlayerUi`, for opening the same panels from your own controls.
- `FPlayerTheme.menuWidth`, and the panel chrome (`FPanelSheet`, `FPanelOptionRow`, `FPanelHeader`, …) as reusable pieces.
- `FPlayerLocalizations.audioAndSubtitles` and `.seconds`.

### Changed

- **The controls no longer appear on start.** `showControlsOnStart` now defaults to false: the picture is what someone opened the screen for, and the chrome is one tap away. `FUiConfig.tv()` keeps it on — a remote needs something focused to start from.
- **The double-tap seek looks like the players people already use**: a half-screen ripple with a curved inner edge, three chevrons travelling in the direction of travel, and a count that keeps climbing while taps land — and once it is up, single taps on the same side add another step.
- **The settings panel was rebuilt**: frosted surface, rounded rows, a real hierarchy, one level of depth, speeds as pills, and a scrim that dismisses on a tap outside. It is off by default on touch, where the bottom bar covers the same ground in one tap; `FUiConfig.tv()` turns it back on, because a row of small targets is worse to walk with a D-pad than one list.
- `showSettingsButton` now defaults to false. `isSettingsOpen` means "any panel is open".

### Fixed

- **The chrome no longer inherits Flutter's error text style** — yellow, underlined, monospaced — when it sits in a route with no Material ancestor. The fullscreen route is exactly such a route, so every label in it was painted that way. The view now supplies its own text baseline.

## 0.5.0

Wakelock, brightness, real DRM, and the `fvp` engine as a sibling package. Closes phase 11.

### Added

- **The screen no longer sleeps during playback.** The flag is held while frames advance and released on pause, reference-counted across players — a paused player cannot switch the screen off underneath one that is playing. Turn it off with `FPlaybackConfig.keepScreenOn`.
- **Brightness gesture** on the left half, defined but inert since phase 3 while the plugin had no Activity. It affects the app's window rather than the device setting, so it reverts on its own when the app goes away. Also available as `controller.setBrightness()`.
- **Real Widevine DRM.** `FDrmConfig` had been in the API since phase 1 and was silently ignored; it now reaches the `MediaItem`, with license headers kept separate from the media's. Adds `playClearContentWithoutKey` and `forceDefaultLicenseUri`.
- **`fplayer_fvp`**: sibling package with the libmdk/FFmpeg engine and `FFallbackEngine`, which plays through Media3 and hands a source to libmdk only when the codec is unsupported. Outside the base package on purpose — it weighs 11.5 MB per ABI against 1–2 MB for all of Media3, and closes one narrow gap: AV1 by software on Android below 12.

### Changed

- **`FPlaybackEngine.textureId` is now `int?`.** Media3 allocates the texture when the player is created and keeps it; libmdk sizes its own from the decoded frame, so there is none until a source is prepared and it recreates one per source.
- The barrel exports the engine signals and `FMedia3Engine`, so an external engine can implement the interface and compose with the built-in one.

### Removed

- `FDrmConfig.forceL3`, which never worked: there is no security-level override in that Media3 API.

## 0.4.0

Playback queue, network resilience and offline downloads. Phases 8, 9 and part of 11.

### Added

- **Playback queue**: `setPlaylist`, `next`, `previous`, `jumpTo`, with `hasNext` / `hasPrevious` / `nextInPlaylist` on the state, auto-advance at the end of an item, and `repeatPlaylist`. Previous/next track controls, and an "up next" card near the end that stays visible even with the chrome faded out.
- **Connectivity awareness**: losing the network parks playback instead of burning the retry budget, and it resumes from the same position when the signal returns. `FPlayerValue.isOnline` / `isOffline` / `isWaitingForNetwork`, an `FConnectivityChanged` event, and a spinner that says *"Waiting for a connection…"* rather than turning with no explanation. Switch it off with `FNetworkConfig.waitForNetwork`.
- **`FSegmentRetryPolicy`**: the *inner* retry ladder, per segment / manifest / key, without playback leaving the playing state. Distinct from `FRetryPolicy`, which retries the whole source; the budgets multiply, and both classes document it.
- **`FPlayerValue.bufferedAhead`**: media buffered ahead of the playhead, which is the figure that predicts a stall. `buffered` is absolute and says nothing right after a seek.
- **Offline downloads** (`FDownloadManager`): a persistent queue on Media3, a choice of which renditions to fetch with an estimated size per quality, requirements enforced by the platform (unmetered only, charging only), pause / resume / remove, and observable state. A completed download plays through the ordinary `FPlayerSource.network`.
- **`FSeeked`**: an explicit seek event.

### Fixed

- A downloaded adaptive stream now plays from its `DownloadRequest`, constrained to the stream keys actually fetched. Before, offline, the adaptive selector reached for a quality that was never on disk and the stream died.
- A progressive MP4 could not be queued: `DownloadHelper` has no track information for progressive media, and asking it about periods threw an exception with no message.
- An enqueued download sat at `queued` forever when the app declares no download service: nobody called `resumeDownloads()`, which is what creating that service normally does.
- Download bridge failures whose exception carries no message no longer reach Dart as `null`.

### Requirements for the consuming app

Background downloads need the `FplayerDownloadService` `<service>` and foreground-service permissions; without it they work only while the app is alive. See the README.

## 0.3.0

Full UI, TV, storyboard, PiP, media session and analytics. Phases 3–7, 9 (UI) and 10 of the plan.

### Added

- **`FPlayerView`**: the player with its chrome — video, gestures, subtitles, controls, settings panel and error states. Every band is replaceable through a builder, and inside any of them `FPlayerScope.of(context)` gives the same view state the built-in controls use.
- **`FUiConfig`** with `.bare()` (video only) and `.tv()` (leanback) presets, `FPlayerTheme` (+`.tv()`), `FPlayerLocalizations` (+`.spanish()`), `FGestureConfig`, `FFullscreenConfig`, `FTvConfig`.
- **Gestures**: tap to reveal the controls, double tap to skip or toggle depending on the third, horizontal drag to scrub with a preview, vertical drag for volume, hold to speed up, pinch to change the fit.
- **Fullscreen** reusing the same controller — and therefore the same texture — so entering and leaving costs a route transition rather than a reload. Orientation derived from the shape of the video, and immersive sticky.
- **Remote control**: ←/→ scrub with progressive acceleration and a deferred commit, ↑/↓ move focus, media keys act immediately, Back closes the controls before it closes the player. An `auto` mode that switches on with the first directional key, needing no native code.
- **Storyboard**: WebVTT parser with `#xywh`, an LRU cache of sprite sheets that de-duplicates in-flight requests, binary search over thousands of cues, and cropping straight onto the canvas. It wires itself up when the source declares one.
- **Chapters**: boundaries punched out of the seek bar, and a button to skip an intro / recap / credits / ad.
- **Picture-in-Picture**: `enterPip()`, auto-entry when leaving the app, actions inside the window, and `isPipSupported` / `isPipActive` so the UI can strip itself while it lasts.
- **MediaSession**: notification, lock screen, headset buttons and metadata from the source. Off by default.
- **Background**: `stop`, `pause` and `continueAudio` modes. The controller is a `WidgetsBindingObserver` and resynchronises itself on return.
- **Analytics**: `FPlayerObserver` and `FPlaybackSessionTracker`, deriving real watched time (discounting pauses and stalls, adjusted for speed), time to first frame, rebuffers, quality changes and seeks — attached from outside, without touching the core.
- **`fplayer_telemetry`**: sibling package with a persistent on-disk queue, batched delivery with backoff, and `Retry-After` honoured.
- **`FSeeked`**: an explicit seek event, so an observer never has to infer one from a jump in position.

### Changed

- `FPipConfig` and `FBackgroundConfig` live on `FPlayerConfig` alongside the rest.
- `FPlaybackConfig.seekStep` travels to the native side, so the PiP skip actions use the app's own step.
- `FPlayerController` emits `FSpeedChanged` when the change comes from the engine too.

### Requirements for the consuming app

PiP needs `android:supportsPictureInPicture="true"` and `android:resizeableActivity="true"` on the Activity. The media session additionally needs the `FplayerMediaService` `<service>` and foreground-service permissions; without it the session is skipped silently and `hasMediaSession` stays false. See the README.

## 0.2.0

Tracks and subtitles. Phase 2 of the plan.

### Added

- Enumeration of audio, subtitle and quality tracks from the manifest (`FTracks`, `FAudioTrack`, `FTextTrack`, `FVideoTrack`), with language, label, codec, bitrate, channels, resolution, frame rate and the forced / CC / audio-description flags.
- Selection at runtime: `selectAudioTrack`, `selectTextTrack`, `selectVideoTrack`, `disableSubtitles`, `enableAutoQuality`.
- External subtitles by URL or file (SRT, VTT, ASS/SSA, TTML) declared on `FPlayerSource.subtitles`, with per-track headers.
- `addSubtitle`, to attach a subtitle to media already playing while keeping the position.
- Preferred languages for automatic selection (`preferredAudioLanguages`, `preferredTextLanguages`, `autoSelectSubtitles`) and `setPreferredLanguages` at runtime.
- Cues delivered to Dart with their geometry (`FSubtitleCue`) and rendered in Flutter by `FSubtitleView`, styled through `FSubtitleStyle` (size, user scale, outline, shadow, box, margins).
- `FTracksChanged` on the event stream.
- `FVideoTrack.qualityLabel` normalises to the rungs people recognise (`1080p`, `720p`…), correcting for content wider than 16:9.

### Notes

- Headers are applied per URI: a subtitle hosted on another domain never receives the media's `Authorization`.
- `FTrack.isSelected` (in the engine's selection) and `FTrack.isActive` (being decoded) are different: in adaptive mode the whole quality ladder is selected at once. Use `FTracks.activeVideo` for what is on screen and `FTracks.selectedVideo` for what the user pinned.
- Adjusting subtitle sync at runtime is still open; Media3's `TextRenderer` is `final` and does not allow shifting its clock. The alternatives are evaluated in `docs/PLAN.md`.

## 0.1.0

First working base. Phases 0 and 1 of the plan.

### Added

- A native Android plugin over Media3/ExoPlayer 1.11.0, with one player instance, texture and pair of channels per controller.
- `FPlayerController` (`ChangeNotifier`) with immutable state in `FPlayerValue` and a stream of discrete events.
- Sources: `FPlayerSource.network` / `.file` / `.asset`, with automatic detection of HLS, DASH, SmoothStreaming and progressive.
- Per-source HTTP headers, applied to segments and range requests too.
- Resuming at a position with `startAt`.
- Playback control: play, pause, stop, absolute and relative seek, speed, volume, mute, loop.
- Configuration grouped by concern: `FPlaybackConfig`, `FBufferConfig`, `FNetworkConfig`, `FDecoderConfig`, with the `FBufferConfig.fastStart()`, `.resilient()` and `FDecoderConfig.dataSaver()` profiles.
- Decoding modes: hardware first (the default), software first, hardware only, software only.
- An error taxonomy (`FPlayerErrorCode`) carrying HTTP status and a retryable flag, plus automatic retry with exponential backoff and a loading timeout.
- Automatic recovery from `BEHIND_LIVE_WINDOW` on live streams.
- `FVideoSurface`: the texture with correct aspect, rotation and fit modes (`FVideoFit`).
- `FPlaybackEngine`, the interface that lets alternative engines be added without touching the layers above.
- An example app with HLS, DASH, MP4, header verification and an error case.
