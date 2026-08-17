# fplayer — Plan de arquitectura y roadmap

> Estado: roadmap completo. Todas las fases implementadas y verificadas en dispositivo. Android-only.
> Flutter 3.47 · Dart 3.13 · minSdk 24 (piso actual de Flutter) · compileSdk 36 · Media3 1.11.0
>
> **Decisiones tomadas** — motor: plugin nativo Media3 · DRM: no requerido (solo ganchos, fase 11) · telemetría: paquete hermano `fplayer_telemetry`

---

## 1. Decisión de motor

### Recomendación: **plugin nativo propio sobre Media3 (ExoPlayer) 1.11.0**, con `fvp` como motor secundario opcional.

`fvp` (libmdk + FFmpeg) es excelente, pero está optimizado para *cobertura de formatos y paridad multiplataforma*, no para *streaming adaptativo en Android*. Tus requisitos (HLS, DASH, headers, subtítulos externos, TV, PiP) caen justo del lado donde Media3 gana.

| Requisito | Media3 nativo | fvp (libmdk/FFmpeg) |
|---|---|---|
| HLS con **ABR real** (cambio de bitrate por ancho de banda) | Sí, `media3-exoplayer-hls` | **No.** El demuxer HLS de FFmpeg selecciona una variante; no hay escalera adaptativa |
| DASH con ABR + multi-period | Sí, `media3-exoplayer-dash` | Parcial, sin ABR |
| Selección de pistas (audio/sub/calidad) desde el manifest | Nativo (`TrackSelectionParameters`) | Limitado |
| Headers HTTP por request / por pista | Nativo (`DataSource.Factory`) | Limitado a opciones globales |
| Subtítulos externos con headers | Nativo (`SubtitleConfiguration`) | `setExternalSubtitle()`, sin headers |
| **Widevine DRM** | Sí | **No existe** |
| PiP, MediaSession, notificación, audio focus | `media3-session` + Activity PiP | Todo a mano |
| Descargas offline | `DownloadManager` de Media3 | No |
| Tamaño del APK | ~1-2 MB | **+10 MB por ABI** |
| Decodificación HW | MediaCodec (default) | MediaCodec / FFmpeg |
| **AV1 por software en Android < 12** | ❌ gap real | ✅ dav1d integrado |
| Formatos exóticos (MKV raros, TS raros, AC3 en contenedores no estándar) | Bueno pero no total | ✅ mejor |

**El único hueco real de Media3 es AV1 por software en dispositivos viejos.** Y es más chico de lo que parece:

- Android 12+ (API 31) trae `c2.android.av1.decoder` (libgav1) en la plataforma → ExoPlayer lo usa solo, sin hacer nada.
- Android 10/11 con SoC moderno (Dimensity 1000+, SD 8 Gen 2+) tienen AV1 por hardware.
- Verificado hoy: Google **no publica** `media3-decoder-av1` ni `media3-decoder-ffmpeg` en su Maven (solo `media3-decoder`, que es la infraestructura). Las extensiones hay que compilarlas con NDK o usar un prebuilt de terceros (`nextlib` — que soporta H264/HEVC/VP8/VP9 + muchos audios, **pero no AV1**).

→ Por eso la arquitectura deja el motor **enchufable** (`FPlaybackEngine`), y `fvp` entra en una fase tardía como motor alternativo para ese caso concreto, activable por config o por fallback automático cuando Media3 reporta `ERROR_CODE_DECODING_FORMAT_UNSUPPORTED`.

### Lo que descarto y por qué

- **`video_player` oficial**: sin selección de pistas, sin PiP, sin MediaSession, subtítulos solo por archivo local en Dart. Techo muy bajo.
- **`better_player` / forks**: es lo que ya tenías; ExoPlayer 2 (deprecado), API acoplada, difícil de extender a TV/PiP como quieres.
- **`media_kit`**: mismas limitaciones de ABR que fvp (es libmpv/FFmpeg) + peso, y su fuerte es desktop.

---

## 2. Arquitectura

Cuatro capas, cada una usable por separado. Un consumidor puede tomar solo el controller y hacer su propia UI.

```
┌─ Capa 4: UI lista para usar ────────────────────────────┐
│  FPlayerView · controles táctiles · controles TV        │
│  overlays reemplazables por builders                    │
├─ Capa 3: Estado ────────────────────────────────────────┤
│  FPlayerController (ChangeNotifier) · FPlayerValue       │
│  playlist · tracks · storyboard · analytics             │
├─ Capa 2: Abstracción de motor ──────────────────────────┤
│  FPlaybackEngine (interfaz) · Media3Engine · [FvpEngine] │
├─ Capa 1: Nativo Android ────────────────────────────────┤
│  Kotlin · ExoPlayer · SurfaceProducer · MethodChannel   │
│  EventChannel · PiP · MediaSession                       │
└─────────────────────────────────────────────────────────┘
```

### Puntos técnicos de la capa nativa

- **Render**: `TextureRegistry.SurfaceProducer` (API moderna de Flutter 3.22+, compatible con Impeller/Vulkan y con el manejo correcto de `onSurfaceDestroyed`/`onSurfaceAvailable` al ir a background). Se contempla un modo alterno `PlatformView + SurfaceView` para TV/4K/HDR y DRM secure, seleccionable por config (`FRenderMode.texture | .surface`).
- **Multi-instancia**: un `ExoPlayer` por `playerId`, con `LoadControl` y `RenderersFactory` propios. Nada de singletons.
- **Canales**: un `MethodChannel` global para crear/destruir + un `MethodChannel` y un `EventChannel` por instancia.
- **Subtítulos**: las `Cue` de Media3 se serializan a Dart (texto + posición/línea/alineación/tamaño) y se renderizan con un widget Flutter. Así tienes control total de estilo, funciona igual en fullscreen y en TV, y no dependes de `SubtitleView` nativo. Se guarda la geometría de la cue para no romper posicionamiento de ASS/TTML.
- **Decoders**: `DefaultRenderersFactory` con `EXTENSION_RENDERER_MODE_PREFER`/`OFF` según `FDecoderConfig.mode`, más un `MediaCodecSelector` custom para forzar software (`c2.android.*`) cuando se pide.

### Árbol de archivos objetivo

```
lib/
├── fplayer.dart                        # export único
└── src/
    ├── core/
    │   ├── player_controller.dart       # FPlayerController
    │   ├── player_value.dart            # estado inmutable
    │   ├── player_status.dart
    │   ├── player_event.dart            # stream de eventos
    │   └── playlist_controller.dart
    ├── engine/
    │   ├── playback_engine.dart         # interfaz
    │   ├── media3/
    │   │   ├── media3_engine.dart
    │   │   ├── media3_channel.dart
    │   │   └── media3_mappers.dart
    │   └── fvp/                         # fase 11
    ├── models/
    │   ├── source.dart                  # FPlayerSource, FSubtitleSource, FStoryboardSource
    │   ├── track.dart                   # FAudioTrack, FTextTrack, FVideoTrack
    │   ├── cue.dart
    │   ├── chapter.dart
    │   └── error.dart                   # FPlayerError + taxonomía
    ├── config/
    │   ├── player_config.dart           # agregador
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
    │   ├── vtt_parser.dart              # soporta #xywh y frames sueltos
    │   ├── bif_parser.dart              # opcional
    │   └── sprite_cache.dart
    ├── ui/
    │   ├── player_view.dart
    │   ├── video_surface.dart           # solo textura, sin chrome
    │   ├── fullscreen.dart
    │   ├── theme.dart
    │   ├── localizations.dart
    │   ├── touch/                       # controles móvil
    │   ├── tv/                          # controles D-pad
    │   └── shared/                      # progress bar, subtitle layer, spinner, error
    ├── platform/
    │   ├── pip.dart
    │   ├── wakelock.dart
    │   ├── brightness.dart
    │   └── device.dart                  # detección TV / leanback
    └── analytics/
        ├── observer.dart                # FPlayerObserver (interfaz)
        ├── metrics.dart
        └── http_reporter.dart           # opcional, aparte

android/src/main/kotlin/dev/chikenare/fplayer/
├── FplayerPlugin.kt
├── PlayerInstance.kt
├── SourceFactory.kt          # MediaItem + DataSource.Factory + headers
├── TrackController.kt
├── DecoderFactory.kt
├── CueBridge.kt
├── PipController.kt
├── SessionController.kt      # MediaSession + notificación
└── AnalyticsBridge.kt        # AnalyticsListener → eventos

example/                      # app demo (móvil + TV)
```

---

## 3. API pública (borrador para revisar)

### Fuente

```dart
final source = FPlayerSource.network(
  'https://cdn.example.com/master.m3u8',
  type: FSourceType.auto,          // auto | hls | dash | smooth | progressive
  headers: {'Authorization': 'Bearer $token'},
  title: 'Episodio 4',
  subtitle: 'Temporada 2',
  posterUrl: '...',
  startAt: Duration(minutes: 12),
  isLive: false,
  subtitles: [
    FSubtitleSource.network('https://.../es.vtt',
      label: 'Español', language: 'es',
      headers: {...}, selectedByDefault: true),
  ],
  storyboard: FStoryboardSource.vtt('https://.../sb.vtt', headers: {...}),
  chapters: [...],
  drm: FDrmConfig.widevine(licenseUrl: '...', headers: {...}),  // fase 11
  metadata: {'contentId': 42, 'episodeId': 128},                // libre
);

FPlayerSource.file('/storage/emulated/0/video.mkv');
FPlayerSource.asset('assets/intro.mp4');
```

### Configuración — sub-configs en vez de un objeto de 60 parámetros

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
    userAgent: 'MiApp/1.0',
  ),
  decoding: FDecoderConfig(
    mode: FDecoderMode.hardwareFirst,   // hardwareFirst | softwareFirst | hardwareOnly | softwareOnly
    maxResolution: null,                 // cap para dispositivos flojos
  ),
  subtitleStyle: FSubtitleStyle(...),
  wakelock: true,
);
```

`FPlayerConfig` y cada sub-config con `copyWith`, `const`-constructibles, y valores por defecto sensatos → el uso mínimo es `FPlayerConfig()`.

### Controller

```dart
final controller = FPlayerController(config: config);
await controller.open(source);

// estado (todo en value, además de getters de conveniencia)
controller.value.status;        // idle loading ready buffering playing paused completed error
controller.position / duration / buffered / progress / speed / volume / isMuted
controller.videoSize / aspectRatio / isLive / seekableRange
controller.error;               // FPlayerError? con code, message, isRetryable, cause

// control
play() pause() togglePlayPause() stop() retry()
seek(Duration) seekBy(Duration) seekToLive()
setSpeed(double) setVolume(double) toggleMute()
setFit(FVideoFit) setZoom(double)

// pistas
controller.audioTracks / textTracks / videoTracks
selectAudioTrack(FAudioTrack?) selectTextTrack(FTextTrack?) selectVideoTrack(FVideoTrack?)  // null = auto/off
addSubtitle(FSubtitleSource) removeSubtitle(...)
setSubtitleOffset(Duration)

// playlist
setPlaylist(List<FPlayerSource>, startIndex: 0)
next() previous() jumpTo(int)

// pantalla
enterFullscreen() exitFullscreen() toggleFullscreen()
enterPip() exitPip()
controller.isPipSupported / isPipActive / isFullscreen

// eventos (además de ChangeNotifier)
controller.events.listen((FPlayerEvent e) { ... });
```

### UI

```dart
// todo incluido
FPlayerView(controller: controller)

// solo el video, tu chrome encima
FVideoSurface(controller: controller)

// personalización quirúrgica sin forkear
FPlayerView(
  controller: controller,
  overlayBuilder: (ctx, ctrl) => MiOverlay(ctrl),
  topBarBuilder: ...,
  bottomBarBuilder: ...,
  settingsBuilder: ...,
  errorBuilder: ...,
  loadingBuilder: ...,
  posterBuilder: ...,
)
```

---

## 4. Roadmap por fases

Cada fase es entregable, compila, y tiene la app `example/` funcionando.

| # | Fase | Entregable | Criterio de aceptación |
|---|---|---|---|
| ✅ **0** | Andamiaje | Convertir el paquete en plugin, `android/` Kotlin, `example/`, lints estrictos | `flutter analyze` limpio, example arranca |
| ✅ **1** | Motor Media3 + puente | Reproducción de file/HLS/DASH/progresivo, headers, play/pause/seek/speed/volume, eventos de estado y posición | Los 4 tipos de fuente reproducen; headers verificados contra endpoint autenticado |
| ✅ **2** | Pistas y subtítulos | Audio/subs/calidad del manifest, subs externos por URL con headers (SRT/VTT/ASS/TTML), cues a Dart y renderizado en Flutter, idiomas preferidos | Cambio de pista en caliente sin cortes; subs externos con auth |
| ✅ **3** | UI base | `FPlayerView`, barra de progreso con buffered, gestos, tema, i18n, builders de personalización | Player usable de punta a punta en móvil |
| ✅ **4** | Fullscreen y ciclo de vida | Fullscreen sin re-buffer (misma instancia), orientación, immersive, wakelock, audio focus, background/foreground | Rotar y entrar/salir de fullscreen no reinicia el video |
| ✅ **5** | TV / D-pad | Detección leanback, focus ring, scrub acelerado con ←/→, teclas media, panel lateral de pistas, layout TV | Navegable 100% con control remoto en un Android TV real |
| ✅ **6** | Storyboard | Parser VTT con `#xywh`, sprites, headers, caché, preview en el slider; fallback de extracción de frames para archivos locales | Miniatura fluida al arrastrar en un VOD con sprite sheet |
| ✅ **7** | PiP + MediaSession | PiP con auto-enter, acciones en la ventana, MediaSession + notificación, audio en background, botones de auriculares | PiP funcional; controles en pantalla de bloqueo |
| ✅ **8** | Robustez | Taxonomía de errores, retry con backoff, timeout de carga, manejo de live edge, caps de bitrate / modo ahorro de datos | Corte de red → reconecta solo; error fatal → overlay con reintento |
| ✅ **9** | Playlist y capítulos | Cola, autoplay next, marcadores skip intro/outro, capítulos en la barra, tarjeta "siguiente episodio" | Serie completa reproduce en cadena |
| ✅ **10** | Analytics | `FPlayerObserver` alimentado por `AnalyticsListener` de Media3 (startup, rebuffers, dropped frames, bytes, bitrate real), reporter HTTP opcional en paquete aparte | Métricas coinciden con la reproducción real |
| ✅ **11** | Extras | ✅ descargas offline · ✅ motor `fvp` con caída por códec (paquete hermano) · ✅ Widevine DRM · descartados: Cast y screenshot | AV1 reproduce en un Android 10 |

---

## 5. Decisiones

### Cerradas

| Tema | Decisión |
|---|---|
| Motor | Plugin nativo propio sobre Media3/ExoPlayer 1.11.0. `fvp` queda como motor opcional en fase 11 |
| DRM | No requerido. Se dejan los ganchos `FDrmConfig` en la API desde la fase 1, sin implementación |
| Telemetría | Fuera del core. `fplayer` expone solo la interfaz `FPlayerObserver`; el reporter con cola persistente y cliente HTTP vive en `fplayer_telemetry` (paquete hermano) |
| Render | Arrancar con `SurfaceProducer` (textura). Evaluar `PlatformView + SurfaceView` en fase 5 si en TV real hay caídas de frames en 4K |
| Subtítulos | Cues serializadas a Dart y renderizadas en Flutter, conservando geometría de la cue |
| Package id nativo | `dev.chikenare.fplayer` |

### Pendientes de revisar contigo

1. **Convención de nombres**: propongo `FPlayer*` para las clases públicas grandes (`FPlayerController`, `FPlayerView`, `FPlayerConfig`) y `F*` para modelos y enums (`FPlayerSource`, `FAudioTrack`, `FVideoFit`).
2. **Ajuste de sincronía de subtítulos** (`setSubtitleOffset`), sacado de la fase 2. No hay ruta limpia sobre Media3: `TextRenderer` es `final`, así que no se puede desplazar el reloj que ve el renderizador, y hacerlo en Dart solo permitiría retrasar (una cue adelantada tendría que mostrarse antes de que el motor la emita). Las dos salidas reales:
   - **Descargar y parsear los subtítulos externos en Dart** en vez de delegarlos a Media3. Da desplazamiento en ambos sentidos, estilo por cue y cero ida y vuelta por el canal, a cambio de escribir parsers de SRT/VTT/ASS y de una segunda ruta de código junto a las pistas embebidas.
   - **Envolver `SubtitleParser` en nativo** y desplazar los tiempos al parsear. Sirve para ambos sentidos y es poco código, pero el desplazamiento se fija al cargar: cambiarlo en caliente obliga a recargar la fuente.

   Mi recomendación es la segunda si el ajuste es algo que se configura una vez, y la primera si quieres un control deslizante de sincronía en vivo. Decidilo cuando lleguemos a la fase 8.

---

## 6. Bitácora de implementación

Hallazgos que costaron tiempo y conviene no volver a descubrir.

### Fase 1

- **`SurfaceProducer.setSize()` es obligatorio.** El plugin oficial `video_player_android` nunca lo llama y funciona en su ruta, pero en el backend de ImageReader (Impeller/Vulkan, Android 15) el buffer conserva el tamaño con el que se creó — el del widget. Los frames de 1280×720 aterrizaban en la esquina superior izquierda de un buffer de 1344×756 y se recortaba ~5 % por derecha e inferior. La corrección: redimensionar la textura al tamaño decodificado en `onVideoSizeChanged` y **volver a asignar el Surface**, porque `setSize` puede devolver uno nuevo. Ver `PlayerHost.resizeSurface`.
- **Orden de eventos en un error fatal.** ExoPlayer pasa a `STATE_IDLE` *y luego* reporta el error. Emitir ambos hacía que Dart mostrara "sin media" durante un frame antes del overlay de error. Se omite el `idle` cuando `player.playerError != null`.
- **Duración en el arranque.** `initialized` no se puede emitir en cuanto el estado es `READY`: la duración puede seguir siendo `TIME_UNSET`. Se espera a que haya duración válida, salvo en directo donde nunca la habrá.
- **URLs de prueba.** El bucket `gtv-videos-bucket` de Google (el clásico *ForBiggerBlazes*, *ElephantsDream*) dejó de ser público y devuelve 403. El example usa `media.w3.org`, `shaka-demo-assets` y `demo.unified-streaming.com`.

### Fase 2

- **Seleccionada ≠ activa.** En selección adaptativa ExoPlayer marca como *seleccionadas* **todas** las calidades del pool, no solo la que se decodifica. Tomar la primera daba siempre la más baja: el chip mostraba "Auto (240p)" mientras se veía 720×576. La API ahora distingue `isSelected` (está en la selección) de `isActive` (se está decodificando), y `FTracks` expone `activeVideo` frente a `selectedVideo` (la fijada por el usuario, null en auto). Cuando el grupo tiene una sola pista seleccionada no hace falta comparar formatos — eso solo importa dentro de un grupo adaptativo, y esos siempre vienen de un manifiesto con ids.
- **Los switches adaptativos no disparan `onTracksChanged`.** La lista de pistas no cambia, solo el peldaño elegido. Hace falta un `AnalyticsListener.onDownstreamFormatChanged`, con deduplicado por firma de formatos activos para no reenviar la lista entera en cada evento.
- **Los parsers rellenan los valores por defecto del formato.** Una cue WebVTT sin posicionamiento llega con `position: 0.5, size: 1.0` y `line:-1`, no con campos vacíos. Detectar "sin preferencia" con un simple null routeaba los subtítulos normales por la ruta de posicionamiento absoluto, anclados arriba y desbordando por abajo.
- **`line` negativo ancla el borde inferior.** `line:-1` significa "la última fila": la caja crece hacia arriba. Tratarlo como offset desde arriba empuja las cues de dos líneas fuera del cuadro.
- **Un `Stack` con ajuste laxo anula `textAlign`.** El contorno del texto se pinta como una segunda copia dentro de un `Stack`; con el ajuste por defecto el Stack encoge al ancho intrínseco del texto y se pega a la izquierda de la caja. Necesita `StackFit.passthrough`.
- **Headers por URI, no globales.** Poner los headers del media como *default request properties* del `DefaultHttpDataSource` los enviaría también a un subtítulo alojado en otro dominio — filtrando el `Authorization` a un tercero. La solución es un `ResolvingDataSource` que inyecta el conjunto correcto según la URI. Verificado en el servidor de pruebas: la petición al VTT lleva solo sus propios headers.
- **`TextRenderer` es `final`.** No se puede subclasear para desplazar la línea de tiempo de los subtítulos, y el ajuste de sincronía en caliente no tiene ruta limpia sobre Media3 (ver "Pendientes").
- **`und` es un idioma.** Los muxers escriben `und` cuando nadie etiquetó la pista; mostrarlo en un selector es peor que no mostrar nada. Se normaliza a null y cae al nombre genérico numerado.

### Fases 3–10

- **`Shortcuts` gana al `Focus` de arriba.** Los eventos de teclado suben desde el nodo con foco hacia la raíz, así que un `Shortcuts` *más cercano* al botón enfocado ve la flecha antes que un `Focus` ancestro. La lógica de "la primera pulsación solo revela los controles" estaba en el ancestro y nunca se ejecutaba para ←/→. Todo lo que implica una pulsación direccional tiene que vivir en la acción del `Shortcuts`.
- **La aceleración del D-pad no puede resetearse en el key-up.** `sendKeyEvent` (y un mando real pulsando repetido) emite down+up por pulsación, así que el contador volvía a cero entre pulsaciones y solo aceleraba manteniendo. Ahora lo resetea el temporizador de commit: una ráfaga de pulsaciones sueltas acelera igual que una tecla mantenida, que es como se usa un mando de verdad.
- **Un `Stack` con ajuste laxo anula `textAlign`** (ya visto en subtítulos, reaparece en cualquier composición de dos copias de un `Text`).
- **El botón de play ocupa el centro exacto del player.** Los gestos sobre el centro solo llegan a la capa de gestos con los controles ocultos — que es justamente cuando se usan. Los tests lo destaparon al fallar sobre el widget equivocado.
- **Timers vivos al desmontar.** El timeout de carga (30 s) y el auto-ocultar de controles sobreviven al árbol de widgets y hacen fallar cualquier test que no los deje expirar. No es un bug de producto, pero obliga a que los tests desarmen esos temporizadores o los dejen vencer.
- **Ocultar la miniatura hasta que carga el índice reintroduce el parpadeo** que `FStoryboardPreview` fue diseñado para evitar: el widget ya dibuja su propio placeholder. La integración no debe filtrar por `hasFrames`.
- **La altura del player depende de la forma del video.** Obvio en retrospectiva, pero costó tres intentos de verificación en emulador: las coordenadas de la barra de progreso cambian entre un video 5:4 y uno 16:9.
- **Inferir un seek de los saltos de posición es aproximado.** Se cambió por un evento `FSeeked` real emitido por el controller: una corrección de un segundo era indistinguible de la deriva del reloj.
- **La ventana de PiP no pinta frames de Flutter de forma fiable en emulador.** El sistema hace todo bien (`mode=pinned`, aspecto correcto, reproducción avanzando) pero la ventana sale en blanco — incluso con un color sólido detrás del video, así que no es la textura. Una de cada seis ejecuciones sí pinta. Queda por verificar en hardware físico antes de considerar el modo `PlatformView + SurfaceView`.

### Fase 9 y descargas

- **`previous` no significa "ítem anterior".** Pasados unos segundos significa "vuelve al principio de esto", que es lo que hace ese botón en todas partes. Saltar siempre al anterior resulta hostil cuando alguien solo quiere reiniciar lo que está viendo.
- **`open()` limpia la cola, `stop()` no.** Abrir una fuente suelta significa "reproduce esta cosa"; parar significa descargar el medio pero conservar la cola, para que `jumpTo` siga funcionando después. Una lista vacía en `setPlaylist` es el único caso que significa "no hay cola".
- **Auto-avanzar *después* de emitir `FCompleted`**, para que un oyente que quiera hacer algo al terminar todavía vea el ítem que acabó y no el que lo reemplaza.
- **Un stream adaptativo descargado sigue anunciando calidades que no están en disco.** El manifiesto lista las cinco renditions aunque solo se bajara una; sin red, el selector adaptativo alcanza una que no existe y el stream muere. La solución correcta es construir el `MediaSource` desde el `DownloadRequest`, que lleva las stream keys realmente descargadas. MP4 progresivo no tiene este problema.
- **La caché de descargas se abre en solo lectura para reproducir.** Si no, el streaming normal iría llenando el directorio de descargas con contenido que el usuario nunca pidió guardar, y el evictor no-op no lo soltaría nunca.
- **Los headers persisten en el índice de descargas** para que una descarga reanudada tras un reinicio pueda re-autenticarse. Eso deja un token en disco: usa tokens de vida corta.
- **Un frame de ancho impar rompe MediaCodec.** El trailer de bunny en w3.org es 853×480 y el decodificador del emulador falla al configurarse aunque reporte `format_supported=YES`. La taxonomía de errores lo clasificó bien igualmente ("este dispositivo no puede reproducir este video"), pero conviene saberlo al elegir contenido de prueba.
- **Sin un `DownloadService` declarado, nadie arranca la cola.** Ese servicio es quien normalmente llama a `resumeDownloads()` al crearse; sin él una descarga encolada se queda en `queued` para siempre. El caso solo aparece en dispositivo, no en tests.
- **`DownloadHelper` no describe media progresiva.** Preguntarle por períodos para un MP4 suelto lanza `IllegalStateException` **sin mensaje**, que llega a Dart como `PlatformException(create_failed, null)`. Dos lecciones: guardar el caso progresivo (no hay renditions que elegir, se baja entero) y no dejar nunca que un mensaje nulo cruce el puente.
- **`fvp` cuesta 11,58 MB por ABI** — 30,4 MB con tres — frente a 1-2 MB de todo Media3, y lo pagan también las apps que nunca lo usen: Gradle empaqueta las `.so` por estar el plugin en el grafo de dependencias, y el tree-shaking de Dart no las toca. Por eso vive en `fplayer_fvp` y no en el paquete base. Confirmado midiendo el APK con y sin él.
- **`fvp` 0.34 no compila con Flutter 3.47**: su `build.gradle` hace `assert` sobre el archivo `version` de la raíz del SDK, que Flutter ya no genera. Arreglado en 0.38. Es justo el tipo de acoplamiento que no quieres en el paquete base.
- **No existe forzado de L3 en `MediaItem.DrmConfiguration`.** Inventé una opción `forceL3` y la mapeé a un método que hace otra cosa; `javap` sobre el artefacto real lo destapó. Verificar la API antes de exponerla, y borrar la opción antes que implementarla mal.
- **Un flag de ventana compartido necesita conteo de referencias.** Con varios players, un booleano deja que el que pausa apague la pantalla debajo del que reproduce.
- **Dos agentes editando el mismo archivo se pisan.** El agente de red tocó `player_controller.dart` fuera de su ámbito mientras yo lo modificaba, y acabamos con dos manejadores del mismo evento y una referencia a un campo eliminado. Los límites de archivos entre frentes paralelos hay que respetarlos, y conviene fusionar a mano en vez de descartar: su aportación —no gastar reintentos mientras no hay red— era la buena.

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| AV1 por software en Android < 12 | Motor fvp opcional (fase 11) o compilar `media3-decoder-av1` con NDK |
| `SurfaceProducer` y ciclo de vida en background | Manejar `onSurfaceCleanup`/`onSurfaceAvailable`; probar en Android 14/15 |
| PiP con render por textura muestra toda la Activity | Modo PiP oculta el chrome y fuerza `fit: cover`; contemplado en `FPipConfig` |
| Fragmentación de fabricantes en decodificadores | `MediaCodecSelector` con lista de exclusión + fallback automático a software |
| Alcance grande | Fases independientes y entregables; se puede parar en la 8 y ya es un player completo |
