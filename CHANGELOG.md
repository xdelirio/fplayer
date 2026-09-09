# Changelog

## Unreleased

### Added

- **`fplayer_media_kit`.** A sibling package with a libmpv engine for iOS, macOS,
  Windows and Linux, behind the same `FPlaybackEngine` interface the Media3
  and libmdk engines implement. `createPlatformEngine()` hands a controller
  Media3 on Android and mpv anywhere else. Sources, headers, side-loaded
  subtitles, tracks and cues come through as on Android; adaptive bitrate,
  PiP, media session, brightness and DRM do not, and say so. Native
  libraries are pulled per platform, so an Android build carries none of it.

### Removed

- **`fplayer_telemetry`.** The sibling package that queued `FPlayerObserver`
  events on disk and posted them to a backend is gone: nothing consumes it
  any more. The observer and `FPlaybackSessionTracker` stay in `fplayer`;
  what to do with the metrics is the host app's business.

### Fixed

- **Green and magenta banding over AV1 on Android TV.** The frames only ever
  reached the screen through a Flutter texture, which means through an
  `ImageReader` and a GPU import of an external image. That import needs a plain
  linear buffer, and television AV1 decoders do not write one — Mali-based SoCs
  hand their output over AFBC-compressed, and the import read that as stripes.
  Nothing about the media was wrong, which is why re-encoding from 10-bit to
  8-bit changed nothing, and no error was ever raised, so the `fplayer_fvp`
  fallback never had a reason to engage either.

### Fixed

- **The previous screen ghosted over the video for several seconds.** Mounting
  a platform view makes Flutter park its own render surface — still holding the
  last frame it drew — and hand rendering to an overlay above it. That parked
  frame outranked the video's surface, so whatever was on screen when the
  player appeared stayed visible, half-transparent, until the first decoded
  frame covered it: on a television that is seconds of the screen behind,
  including a second seek bar sitting above the real one. The video surface now
  declares itself a media overlay, which puts it above the parked one.
- **The remote seized up once a player was rendering through a SurfaceView.**
  `PlatformViewLink` wraps the view in a focus node, and that node joined the
  traversal ring: one press of the D-pad walked focus off the chrome and into
  something invisible with nothing to activate, so every later press did
  nothing and only the system back key still worked. The video is output, never
  a destination — the whole subtree is now excluded from focus, and the
  Android-to-Flutter `onFocus` forwarding is gone with it, since it existed
  only to hand Flutter's focus to that node.
- **Creating a player on a television failed outright.** `build` calls
  `attachSurface` before anything is playing, and that reads the
  `SurfaceProducer` — which the SurfaceView path never creates. The
  `UninitializedPropertyAccessException` landed in the constructor's own
  try/catch, which released the ExoPlayer it had just built, so the log read
  `Init` immediately followed by `Release` and Dart got `create_failed`. Guarded
  inside `attachSurface` rather than at the call site, so every path through it
  is covered.

### Changed

- **The audio and subtitles dialog no longer closes on the first row tapped.**
  It exists because the decision is one decision — Japanese audio with English
  subtitles — and applying immediately undid that: the viewer who came to change
  both had to open it twice, and the second trip re-selected the track they had
  just picked. Choices are held and ticked in place, `Apply` pushes them
  together, and `Cancel`, the close control and a tap outside all discard.
  Applying sends only what moved, so confirming a subtitle change does not
  re-select the audio track that was already playing. The settings panel keeps
  its old behaviour: it walks one axis at a time, so a tap there is a whole
  decision.

### Added

- **`FUiConfig.showQualityBitrate`**, off by default, and a `showBitrate`
  override on `qualityRows`. The kbps beside each rung is what separates two
  renditions of the same size, and noise to an audience that reads `1080p` and
  nothing else — so the menu stays plain unless it is asked for.
- **`FPlayerLocalizations.cancel` and `.apply`**, for the dialog's two ways out.
- **`FTrackStaging`**, which turns `audioRows` and `subtitleRows` from lists
  that act into lists that only record. Public because the row builders already
  were.
- **`FPanelFooterButton`**, the primary/quiet pair a panel confirms with.
- **`FPlayerConfig.renderMode`**, an `FVideoRenderMode` of `auto` (the new
  default), `texture` or `surfaceView`. `auto` resolves natively: a `SurfaceView`
  mounted as a platform view on televisions, the existing texture everywhere
  else. The SurfaceView path hands the decoder's buffer to SurfaceFlinger
  untouched, so it survives any layout a decoder produces; it costs hybrid
  composition, which is why it is not the default off a TV.
- **`FPlayerController.platformViewId`**, non-null exactly when `textureId` is
  null. `FVideoSurface` picks between the two on its own; a custom output widget
  now has to handle both.

## 0.7.0

A hardening release. Two review passes over the whole package — one hunting
leaks and bugs, one attacking the fixes from the first — plus verification on a
phone and an Android TV emulator. Nothing here is a new feature; all of it is
something that was wrong.

### Fixed — leaks

- **A player disposed while it was still being created leaked the native
  player.** The engine marked itself disposed with no id to release, and the
  creation that landed a moment later allocated an ExoPlayer, a texture, a
  progress ticker and an event subscription that nothing owned. Ten open/close
  cycles left ten players ticking. The creation is now held so disposal can wait
  for the thing it has to release.
- **`initialize()` called twice registered the controller with the binding
  twice**, and the binding only ever removes one observer — which pinned the
  controller, its engine and its whole value graph for the life of the process.
  The documented `initialize(); open();` pattern from an `initState` did exactly
  that. Concurrent calls now share one creation, as does the telemetry reporter,
  which had the same shape.
- **Disposal completes even when a step throws.** A `MissingPluginException` on
  the way out is ordinary while the engine detaches, and it was enough to leave a
  notifier and two stream controllers behind.
- **PiP auto-enter was armed on the Activity and never disarmed**, so closing a
  video left the app shrinking into an empty PiP window on every Home press for
  the rest of the Activity's life.
- **A half-built `PlayerHost` leaked everything it had already allocated** — a
  texture, an ExoPlayer, a process-wide MediaSession and a started foreground
  service. A negative `minBufferMs` was enough to trigger it.
- The media service is stopped when the last session goes, and the queued event
  sink is bounded rather than growing for as long as nobody is listening.

### Fixed — things that did not work

- **The controls never auto-hid while playing.** The countdown was restarted on
  every controller notification, and the engine reports progress four times a
  second, so it could never fire.
- **The exit-fullscreen and back controls could not leave fullscreen.** Both went
  through `maybePop`, which the `PopScope` that makes the remote's back key close
  the chrome first vetoes — and those controls are only reachable with the chrome
  open. `exitOnComplete` had the same problem.
- **Left and right seeked from wherever focus happened to be**, so a remote
  trying to reach the next control scrubbed the film instead. Seeking is now what
  the seek bar does with those keys while it holds focus.
- **Every panel row, speed chip, skip-intro and up-next card was focusable but
  inert**: a bare `Focus` answers no key, so a remote could walk to them and OK
  did nothing. Panels also take focus when they open instead of leaving it on the
  chrome behind the scrim.
- **Storyboard thumbnails never appeared.** `whenComplete(() => map.remove(k))`
  returned the future it had just removed — itself — so every first load of every
  sheet waited on itself forever and `prefetch()` deadlocked its caller.
- **One volume or brightness swipe left a percentage badge parked mid-picture**
  for the rest of the film, and a hold interrupted by the view going away left
  playback at 2× with no gesture to undo it.
- **A player that could not be created was a permanent spinner**: the retry
  ladder re-prepared an engine that did not exist. Failures from `create` and
  `setSource` now become the error state, and a retry rebuilds the player.
- Telemetry lost delivered batches whenever events arrived during a flush; an
  expired token discarded the batch instead of retrying with a fresh one, and
  quality changes were never emitted at all.
- Background playback had nothing keeping the CPU awake, so with the screen off
  it stuttered between buffer fills.

### Fixed — behaviour

- The playhead no longer rubber-bands when a progress tick from before a seek
  arrives after it, and unmuting restores the level a gesture dragged to zero
  from rather than jumping to full.
- The centre transport scales down instead of overflowing on a narrow player, the
  bottom row scrolls instead of overflowing, and neither the error view nor the
  spinner shares its space with the play button any more.
- Positioned WebVTT cues stay inside the picture, and a platform cue with no
  anchor is centred like an ordinary subtitle instead of running rightwards from
  the middle.
- `FPlayerValue` and `FPlayerSource` compare by value, so the chrome is not
  rebuilt four times a second by ticks that change nothing — and a manifest
  refresh carrying better track labels is no longer discarded.
- Watching the same video again starts a new analytics session; replays used to
  be invisible.

### Changed

- **The audio and subtitles control is named rather than drawn**: `Audio &
  Subtitles`, or `Audio & Subs` where the row is tight, instead of a `CC` glyph
  that said nothing about picking a language.
- **No speed control under a remote**, where it is one more stop for the D-pad on
  the way to anything else. The settings panel still carries it.
- **The focus ring is on from the first frame in a leanback build.** Flutter
  starts Android in touch-highlight mode, so a remote-only screen showed no focus
  at all until the first key press — one press too late.
- `FPlayerController(engine:)` is public rather than `@visibleForTesting`:
  installing an engine is the documented way to use another backend, and the
  annotation made every consumer doing it fail their own analysis.
- `FFullscreenConfig.restoreSystemUiMode`, so leaving fullscreen restores the
  app's own system-bar mode instead of forcing `edgeToEdge`.
- `FPlayerUi.cancelScrub()`, for a gesture the system took away.
- `FTvScope` publishes whether a remote is driving the player, and the seek it
  performs, to any control under `FPlayerView`.
- `FPlayerLocalizations.audioAndSubsShort`.

### Removed

- **Offline downloads.** `FDownloadManager` and everything under it — the Dart
  API, the Kotlin bridge, the Media3 download service and cache, the example
  screen and the manifest recipe. Playback from a local cache went with it: a
  source is a source, and the package no longer keeps a download index.

### Added

- `example/lib/tv_demo.dart`: the leanback layout, full screen, driven entirely
  by a D-pad. Nothing in the example exercised TV before.
- `LICENSE` — MIT, which is what the README always said.
- Tests for the paths that had none: controller lifetime and failure handling,
  the sprite cache, chrome behaviour under a remote, and the engine handoff.

## 0.6.0

A chrome that gets out of the way, and controls where you can see them.

### Added

- **Audio and subtitles in one dialog**, side by side, opened by a single control in the bottom bar. Two columns where there is room, stacked where there is not. The decision is one decision — Japanese audio with English subtitles — so it takes one panel and no menu to walk.
- **A quality control that reads as a value**: `Auto · 1080p` in the bottom bar, the ladder one tap away, the long form dropped for the short one when the player is narrow. Speed works the same way.
- **One row per rung in the quality menu.** Manifests routinely carry several renditions of the same size — a second codec, a second bitrate ladder — and a list with `1080p` three times asks a question nobody can answer. Each size keeps its best rendition; the pinned one still lights up if it was one of the duplicates.
- **`showIdleProgressBar`**: a hairline of progress along the bottom edge while the controls are away, so the one thing worth knowing without asking is on screen.
- **`FPlayerPanel`** with `openPanel` / `closePanel` / `panel` on `FPlayerUi`, for opening the same panels from your own controls.
- `FPlayerTheme.menuWidth`, and the panel chrome (`FPanelSheet`, `FPanelOptionRow`, `FPanelHeader`, …) as reusable pieces.
- `FPlayerLocalizations.audioAndSubtitles`, `.audioAndSubsShort` and `.seconds`.
- **`FTvScope`**: whether a remote is driving the player, and the seek it performs, readable from any control under `FPlayerView`. It is how the chrome lays itself out for a D-pad, and how a custom seek bar gets the same accelerated, deferred seek as the bundled one.
- **The seek bar takes focus**, with a thicker track and a halo on the thumb to say so. It was the one control a remote could not see itself land on.

### Changed

- **The controls no longer appear on start.** `showControlsOnStart` now defaults to false: the picture is what someone opened the screen for, and the chrome is one tap away. `FUiConfig.tv()` keeps it on — a remote needs something focused to start from.
- **The double-tap seek looks like the players people already use**: a half-screen ripple with a curved inner edge, three chevrons travelling in the direction of travel, and a count that keeps climbing while taps land — and once it is up, single taps on the same side add another step.
- **The settings panel was rebuilt**: frosted surface, rounded rows, a real hierarchy, one level of depth, speeds as pills, and a scrim that dismisses on a tap outside. It is off by default on touch, where the bottom bar covers the same ground in one tap; `FUiConfig.tv()` turns it back on, because a row of small targets is worse to walk with a D-pad than one list.
- `showSettingsButton` now defaults to false. `isSettingsOpen` means "any panel is open".
- **The audio and subtitles control is named rather than drawn.** `Audio & Subtitles` — `Audio & Subs` where the row is tight — instead of a `CC` glyph: the control picks a language as often as it turns subtitles on, and no icon says that. It tints with the accent colour while a subtitle track is on.
- **No speed control under a remote.** It was one more stop for the D-pad to walk through on the way to anything else, for a setting nobody changes from a sofa. The settings panel still carries it.
- **The bottom row scrolls instead of overflowing.** With every control turned on, a named track button and a quality summary are wider than a 360-wide phone.

### Fixed

- **Left and right no longer seek from wherever focus happens to be.** They were claimed for the whole player, so a remote trying to reach the next control scrubbed the film instead — the bug was visible on every button in the bottom row. Seeking is now what the seek bar does with them while it holds focus; everywhere else they move focus, and **OK** on the bar commits the seek without waiting out the quiet time.

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
