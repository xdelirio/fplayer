# fplayer

A Flutter video player built on **Media3/ExoPlayer**, meant to be shared across several apps.

> **[Integration guide](docs/integration.html)** — how to drop it into an app: installation, what the manifest needs depending on the features you use, recipes, and the details that bite.

> **Status:** roadmap complete and verified on device. The route taken and the decisions behind it are in [`docs/PLAN.md`](docs/PLAN.md).

## What it does today

- Local files, assets, progressive HTTP, **HLS and DASH with real adaptive bitrate**
- Custom HTTP headers per source, applied to segments and range requests too
- **Audio, subtitle and quality tracks** from the manifest, selectable at runtime
- **External subtitles by URL** (SRT, VTT, ASS/SSA, TTML) with their own headers, rendered in Flutter
- Preferred languages for automatic selection
- Hardware decoding by default, with configurable software modes
- Resume at a position (`startAt`)
- Observable state through a `ChangeNotifier` plus a stream of discrete events
- An actionable error taxonomy (`unauthorized`, `notFound`, `unsupportedFormat`, …) with automatic retry and exponential backoff
- **A complete UI** (`FPlayerView`) with bottom-bar controls, gestures, an audio-and-subtitles dialog, fullscreen and error states — replaceable piece by piece
- **Remote control / Android TV** with accelerated scrubbing and focus navigation
- **Storyboard**: thumbnails on the seek bar from a WebVTT index with sprite sheets
- **Chapters** on the bar and a skip intro / credits button
- **Picture-in-Picture**, **MediaSession** (notification, lock screen, headset) and **background audio**
- **A playback queue** with auto-advance and an "up next" card
- **Session analytics**: real watched time, startup, rebuffers, quality changes
- Loose layers (`FVideoSurface`, `FSubtitleView`, `FProgressBar`) for building your own UI

Outside the base package: the `fvp` engine for AV1 on older Android lives in `fplayer_fvp`, because it weighs 11.5 MB per ABI. Both siblings — `fplayer_fvp` and `fplayer_telemetry` — are consumed as path or git dependencies rather than from pub.dev. Offline downloads and Cast are not implemented.

## Requirements

| | |
|---|---|
| Flutter | 3.44+ |
| Android | minSdk 24, compileSdk 36 |
| Platforms | Android (for now) |

## Usage

With the bundled UI:

```dart
final controller = FPlayerController(config: const FPlayerConfig());
await controller.open(FPlayerSource.network(url));

// in build:
FPlayerView(controller: controller)
```

`FPlayerView` sizes itself to the video's aspect ratio, so it drops into a `Column` without wrappers.

### Configuration

```dart
final controller = FPlayerController(
  config: const FPlayerConfig(
    playback: FPlaybackConfig(autoPlay: true, seekStep: Duration(seconds: 10)),
    buffering: FBufferConfig.fastStart(),
    network: FNetworkConfig(retry: FRetryPolicy(maxAttempts: 3)),
  ),
);

await controller.open(
  FPlayerSource.network(
    'https://cdn.example.com/master.m3u8',
    headers: {'Authorization': 'Bearer $token'},
    title: 'Episode 4',
    startAt: Duration(minutes: 12),
  ),
);
```

Don't forget `controller.dispose()`.

### Customising the UI

`FUiConfig` decides what is shown; the builders decide how:

```dart
FPlayerView(
  controller: controller,
  config: const FUiConfig(
    localizations: FPlayerLocalizations.spanish(),
    theme: FPlayerTheme(accent: Color(0xFF00A8E1)),
    showLockButton: false,
    controlsTimeout: Duration(seconds: 3),
  ),
  bottomBarBuilder: (context, ui) => MyBottomBar(ui: ui),
)
```

Inside a builder, `FPlayerScope.of(context)` gives you the same view state the built-in controls use — visibility, lock, scrub, fit — so your bar can restart the auto-hide or begin a drag without rewiring anything.

Presets: `FUiConfig.bare()` leaves only the video — no chrome and no gestures, for a player you drive entirely yourself — and `FUiConfig.tv()` assembles the leanback layout.

If you would rather build it from scratch, the layers are available on their own: `FVideoSurface`, `FSubtitleView`, `FProgressBar`, `FTrackDialog`, `FSettingsPanel`, `FErrorView`.

**The chrome starts away.** The picture is what someone opened the screen for, so nothing covers it until they ask: a tap brings the controls up, and meanwhile a hairline of progress along the bottom edge answers the one question worth answering without one — inline only, never over a fullscreen picture. `showControlsOnStart: true` restores the old behaviour, `showIdleProgressBar: false` drops the hairline. `FUiConfig.tv()` shows the controls on start, because a remote needs something focused to start from.

**The controls live at the bottom.** Everything configurable is one tap away, no menu to walk:

| | |
|---|---|
| `showAudioSubtitlesButton` | reads `Audio & Subtitles`, opens both track lists side by side; hidden when there is nothing to pick |
| `showQualityButton` | reads `Auto · 1080p`, opens the ladder; only on adaptive media with more than one rung |
| `showQualityBitrate` | the kbps beside each rung in that ladder. On by default; `false` leaves `1080p` alone |
| `showSpeedButton` | reads `1x`, opens the speeds as pills. Dropped under a remote, where the settings panel carries it instead |
| `showMuteButton`, `showFitButton`, `showFullscreenButton` | |
| `showSettingsButton` | the catch-all panel. Off on touch, on for `FUiConfig.tv()` |

Every one of those is a `bool` on `FUiConfig`, so `FUiConfig(showMuteButton: false)` is all it takes to drop a control.

To open the same panels from your own controls:

```dart
ui.openPanel(FPlayerPanel.tracks);   // .quality · .speed · .settings
ui.closePanel();
ui.panel;                            // what is open, if anything
```

### Fullscreen

The button pushes a route that reuses the same controller, and therefore the same texture: there is no reload and no re-buffer.

```dart
FPlayerView(
  controller: controller,
  fullscreen: const FFullscreenConfig(
    orientation: FFullscreenOrientation.followVideo,  // landscape if the video is
    systemUiMode: SystemUiMode.immersiveSticky,
    exitOnComplete: true,
  ),
)
```

### Android TV and remotes

```dart
FUiConfig(tv: FTvConfig(mode: FTvMode.auto))   // the default
```

`auto` changes nothing until the first directional key arrives; from then on the focus ring appears and the remote is in charge. A TV-only build uses `FTvMode.enabled` and `FPlayerTheme.tv()`.

- **←/→** seek **while the seek bar holds focus**, accelerating the longer you hold, and the engine receives a single seek when you stop. The preview moves immediately. Anywhere else on the chrome they do what they do in every other app: move to the control next door.
- **↑/↓** move focus between rows of controls.
- **OK** activates the focused control, or commits the seek in progress without waiting; the first press with the controls hidden only reveals them.
- **Back** closes the settings panel, then the controls, and only then exits.
- **Media keys** always act, without revealing anything first.

### Gestures

```dart
FUiConfig(
  gestures: FGestureConfig(
    doubleTapSeeks: true,          // left/right third skips, centre toggles
    horizontalDragSeeks: true,     // with a preview while the finger is down
    verticalDragAdjustsVolume: true,
    longPressSpeed: 2.0,           // hold to speed up, release to restore
    pinchChangesFit: true,
  ),
)
```

`FGestureConfig.none()` turns them all off except the tap that reveals the controls.

A double tap on a side washes that half of the picture and counts what it skipped — `10 seconds`, `20 seconds` — and while that is on screen a **single** tap on the same side adds another step, so crossing a minute is one double tap and four taps rather than five double taps.

### Sources

```dart
FPlayerSource.network(url, headers: {...}, type: FSourceType.auto)
FPlayerSource.file('/storage/emulated/0/video.mkv')
FPlayerSource.asset('assets/intro.mp4')
```

`FSourceType.auto` lets the engine infer the format from the URI and the `Content-Type`. Force it only if your endpoint serves a manifest with no extension *and* a wrong `Content-Type`.

### Control

```dart
controller.play();
controller.pause();
controller.togglePlayPause();
controller.seekTo(Duration(minutes: 3));
controller.seekBy(Duration(seconds: -30));
controller.skipForward();          // uses FPlaybackConfig.seekStep
controller.setSpeed(1.5);
controller.setVolume(0.4);
controller.toggleMute();
controller.retry();
controller.stop();
```

### Tracks

```dart
final tracks = controller.tracks;

tracks.audio;   // List<FAudioTrack> — language, channels, bitrate, audio description
tracks.text;    // List<FTextTrack>  — language, forced, CC
tracks.video;   // List<FVideoTrack> — resolution, bitrate, fps

controller.selectAudioTrack(tracks.audio.first);
controller.selectTextTrack(tracks.text.first);
controller.disableSubtitles();
controller.selectVideoTrack(tracks.video.last);   // pins the quality
controller.enableAutoQuality();                   // back to adaptive
```

**Selected is not the same as active.** In adaptive mode the engine keeps *every* quality in the pool selected and switches between them:

```dart
tracks.activeVideo;    // the one being decoded right now
tracks.selectedVideo;  // the one the user pinned; null when on auto
tracks.isVideoAuto;

// To label the quality button:
final label = tracks.isVideoAuto
    ? 'Auto (${tracks.activeVideo?.qualityLabel})'
    : tracks.selectedVideo!.qualityLabel;
```

The quality menu shows one row per rung: manifests routinely carry several renditions of the same size, and a list with `1080p` three times asks a question nobody can answer. Each size keeps its best rendition; `tracks.video` still holds them all. Each row carries its bitrate — the number that actually separates two renditions of the same size — which `FUiConfig(showQualityBitrate: false)` drops for an audience that reads `1080p` and nothing else.

**The audio and subtitles dialog holds its choices until they are applied.** It exists because the decision is one decision — Japanese audio with English subtitles — and closing on the first row tapped meant a second trip through it for the second half. Rows tick as they are chosen, `Apply` pushes them to the player, and `Cancel`, the close control and a tap outside all discard. Only what actually moved is sent, so confirming a subtitle change does not re-select the audio track that was already playing. The settings panel is unchanged: it walks one axis at a time, so a tap there is a whole decision and it closes on it.

`qualityLabel` normalises to the rungs people recognise. Cinematic content is wider than 16:9, so a 1680×750 rendition is labelled `1080p` and not `750p`; `width` and `height` are still there if you prefer the raw numbers.

### Subtitles

Declared on the source:

```dart
FPlayerSource.network(
  url,
  headers: {'Authorization': 'Bearer $token'},
  subtitles: [
    FSubtitleSource.network(
      'https://subs.example.com/es.vtt',
      label: 'Spanish',
      language: 'es',
      headers: {'X-Api-Key': 'something-else'},   // this track's own headers
      selectedByDefault: true,
    ),
  ],
)
```

Headers are applied **per URI**: the subtitle request carries only its own. The media's `Authorization` never leaks to a third-party subtitle host.

Adding one after playback has started (reloads the source, keeping the position):

```dart
await controller.addSubtitle(FSubtitleSource.network(uri, label: 'Spanish'));
```

Automatic selection by language:

```dart
FPlaybackConfig(
  preferredAudioLanguages: ['es', 'en'],
  preferredTextLanguages: ['es'],
  autoSelectSubtitles: true,   // false by default: subtitles start off
)
```

Styling:

```dart
FPlayerConfig(
  subtitleStyle: FSubtitleStyle(
    fontSize: 18,
    scale: 1.2,                    // the user's multiplier
    edge: FSubtitleEdge.outline,   // legible over any picture
    bottomMargin: 0.06,
  ),
)

// Or with an opaque box:
FSubtitleStyle.boxed()
```

`FSubtitleView` takes a `bottomInset` to lift the subtitles while the controls are up.

> Adjusting subtitle sync at runtime is not supported yet; the why and the options are in `docs/PLAN.md`.

### Storyboard (thumbnails on the seek bar)

```dart
FPlayerSource.network(
  url,
  storyboard: FStoryboardSource.vtt('https://cdn.example.com/sb.vtt', headers: {...}),
)
```

Nothing else: if the source declares one, `FPlayerView` loads it and shows the thumbnail above the thumb while dragging. The index is WebVTT where each cue points at an image, optionally with `#xywh=x,y,w,h` to crop out of a sprite sheet; relative URLs resolve against the VTT's own.

Sheets are decoded once and cropped on canvas, with an LRU cache and de-duplication of in-flight requests. Pass a shared `FStoryboardController` to several players if you want a single cache for the whole app.

### Playback queue

```dart
await controller.setPlaylist(episodes, startIndex: 2);

controller.next();
controller.previous();
controller.jumpTo(0);

controller.value.currentIndex;     // position in the queue
controller.value.hasNext;
controller.value.nextInPlaylist;   // what comes next
```

When an item ends it moves on by itself (`FPlaybackConfig.autoAdvance`, on by default), and `repeatPlaylist` wraps back to the start after the last one. Near the end an "up next" card appears with the next title, visible even with the controls hidden.

`previous` restarts the current item if you are more than three seconds in, and only jumps back if you have just started — which is what that button does everywhere. Opening a source with `open()` clears the queue; `stop()` keeps it.

### Chapters and skip intro

```dart
FPlayerSource.network(
  url,
  chapters: [
    FChapter(start: Duration.zero, end: Duration(seconds: 45),
             title: 'Intro', kind: FChapterKind.intro),
    FChapter(start: Duration(seconds: 45), title: 'Episode'),
  ],
)
```

The boundaries are punched out of the seek bar, and while playback sits inside a span marked `intro`, `recap`, `credits` or `ad` a button appears to skip it — visible even with the controls hidden, which is exactly when it is needed.

### Picture-in-Picture

```dart
FPlayerConfig(pip: FPipConfig(autoEnterOnLeave: true))
```

The PiP window mirrors **the whole** Flutter tree, so use `isPipActive` to strip the UI down:

```dart
if (controller.value.isPipActive) {
  return FPlayerView(controller: controller, config: const FUiConfig.bare());
}
```

`isPipSupported` is false until the first frame: the system needs an aspect ratio to size the window.

### Media session and background

```dart
FPlayerConfig(background: FBackgroundConfig.audioInBackground())
```

Publishes a session with a notification, lock-screen controls and headset buttons, and keeps the audio going when you leave the app. Off by default, so a notification is never imposed on an app that doesn't want one. The modes are `stop`, `pause` (the default) and `continueAudio`.

### Analytics

```dart
final tracker = FPlaybackSessionTracker(
  controller: controller,
  observers: [MyObserver()],
);
// ...
tracker.dispose();
```

It attaches from the outside — it listens to the controller, it doesn't modify it — and derives: real watched time (without pauses or stalls, adjusted for speed), time to first frame, the count and duration of rebuffers, quality changes, seeks, and bitrate and height averaged by time on screen.

To ship that to a backend with a persistent queue and retries, use the sibling package `fplayer_telemetry`.

> Bytes downloaded and dropped frames need a native bridge that does not exist yet; the fields are in the model but always read null.

### State

`controller.value` is an immutable `FPlayerValue`:

```dart
final v = controller.value;
v.status;            // idle · loading · ready · buffering · completed · error
v.isPlaying;
v.position;  v.buffered;  v.duration;  v.remaining;
v.progress;  v.bufferedProgress;       // 0..1, ready for a slider
v.aspectRatio;                          // already accounts for rotation and anamorphic pixels
v.isLive;    v.isSeekable;
v.tracks;                               // FTracks
v.cues;                                 // List<FSubtitleCue> on screen right now
v.error;                                // FPlayerError?
```

### Errors

```dart
switch (controller.value.error?.code) {
  case FPlayerErrorCode.unauthorized: await refreshToken(); controller.retry();
  case FPlayerErrorCode.notFound:     showUnavailable();
  case FPlayerErrorCode.network:      // already retried on its own, per FRetryPolicy
  default:                            showGeneric();
}
```

Errors marked retryable are retried on their own with exponential backoff before they reach the UI, so an overlay doesn't flash up and vanish two seconds later.

### Events

For analytics, and for reacting to specific transitions:

```dart
controller.events.listen((event) {
  if (event is FCompleted) playNext();
  if (event is FErrorOccurred) log(event.error);
});
```

### Decoding

Hardware by default. The other modes exist for debugging, or for dodging devices with a broken decoder for a given codec:

```dart
FDecoderConfig(mode: FDecoderMode.softwareFirst)
FDecoderConfig.dataSaver()   // capped at 720p / 2.5 Mbps
```

A note on AV1: Android 12+ ships a software AV1 decoder in the platform and ExoPlayer picks it up by itself. On older devices with no hardware AV1 there is no decoder available; that case is covered by the alternative engine from phase 11.

### Rendering

Frames reach the widget tree one of two ways, and by default the choice is made for you:

```dart
FPlayerConfig(renderMode: FVideoRenderMode.auto)         // default: SurfaceView on TV, texture elsewhere
FPlayerConfig(renderMode: FVideoRenderMode.texture)      // always a Flutter texture
FPlayerConfig(renderMode: FVideoRenderMode.surfaceView)  // always an Android SurfaceView
```

A texture composites like any other widget and costs nothing extra, but a frame gets there through an `ImageReader` and a GPU import of an external image, which only works while the decoder writes a plain linear buffer. Television SoCs do not: their AV1 decoders hand over vendor-compressed frames — AFBC on Mali — and the import misreads those into green and magenta banding. The decode is fine; the handoff is not, which is why forcing 8-bit or a lower resolution changes nothing.

A `SurfaceView` has no handoff. The buffer goes to SurfaceFlinger in whatever layout it arrived in, so the picture is correct whatever the decoder produced. It is mounted as a platform view under hybrid composition, which makes every Flutter frame drawn above the video cost a copy — worth it on a TV, wasteful on a phone. Hence `auto`.

On the SurfaceView path `controller.textureId` is null for the player's whole life and `controller.platformViewId` is the id instead. `FVideoSurface` handles both; custom output widgets have to check the pair.

## Android setup

The plugin declares `INTERNET` and nothing else: I don't want to force every app to justify permissions it may never use.

**Cleartext HTTP** (streams without TLS):
```xml
<application android:usesCleartextTraffic="true">
```

**Picture-in-Picture**:
```xml
<activity android:name=".MainActivity"
          android:supportsPictureInPicture="true"
          android:resizeableActivity="true" ... />
```

**Media session** (only if you turn on `background.mediaSession` or the `continueAudio` mode):
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<service android:name="dev.chikenare.fplayer.FplayerMediaService"
         android:exported="false"
         android:foregroundServiceType="mediaPlayback">
    <intent-filter>
        <action android:name="androidx.media3.session.MediaSessionService" />
    </intent-filter>
</service>
```

Without that `<service>` the session is skipped silently and `hasMediaSession` stays false — it is checked before anything gets built.

**Android TV**, so the app shows up in the leanback launcher:
```xml
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<uses-feature android:name="android.software.leanback" android:required="false" />
```

## Example

`example/` demonstrates HLS, DASH, MP4 with headers and an external subtitle verified against a local server, a storyboard, a queue with the up-next card and a source that fails on purpose, with a live state panel and the session metrics. **TV layout** opens the leanback screen: full screen, `FUiConfig.tv()`, driven entirely by a D-pad.

```bash
cd example && flutter run
```

## Tests

```bash
flutter test                           # the package
cd fplayer_telemetry && flutter test   # the telemetry sibling
cd fplayer_fvp && flutter test         # the libmdk engine sibling
```

## License

MIT — see [LICENSE](LICENSE).
