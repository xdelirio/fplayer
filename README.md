# fplayer

Reproductor de video para Flutter construido sobre **Media3/ExoPlayer**, pensado para compartirse entre varias apps.

> **[Guía de integración](docs/integracion.html)** — cómo meterlo en una app: instalación, qué pedir al manifiesto según las funciones que uses, recetas y los detalles que muerden.

> **Estado:** roadmap completo y verificado en dispositivo. El recorrido y las decisiones están en [`docs/PLAN.md`](docs/PLAN.md).

## Qué hace hoy

- Archivos locales, assets, HTTP progresivo, **HLS y DASH con bitrate adaptativo real**
- Headers HTTP personalizados por fuente, aplicados también a segmentos y peticiones de rango
- **Pistas de audio, subtítulos y calidad** del manifiesto, con selección en caliente
- **Subtítulos externos por URL** (SRT, VTT, ASS/SSA, TTML) con headers propios, renderizados en Flutter
- Idiomas preferidos para selección automática
- Decodificación por hardware por defecto, con modos software configurables
- Reanudar en una posición (`startAt`)
- Estado observable vía `ChangeNotifier` + un stream de eventos discretos
- Taxonomía de errores accionable (`unauthorized`, `notFound`, `unsupportedFormat`, …) con reintento automático y backoff exponencial
- **UI completa** (`FPlayerView`) con controles, gestos, panel de ajustes, fullscreen y estados de error — reemplazable pieza a pieza
- **Control remoto / Android TV** con scrub acelerado y navegación por foco
- **Storyboard**: miniaturas en el slider desde un índice WebVTT con sprite sheets
- **Capítulos** en la barra y botón de saltar intro / créditos
- **Picture-in-Picture**, **MediaSession** (notificación, pantalla de bloqueo, auriculares) y **audio en background**
- **Cola de reproducción** con auto-avance y tarjeta de "a continuación"
- **Descargas offline** con cola persistente, requisitos de red y reproducción desde caché
- **Analítica** de sesión: tiempo visto real, arranque, rebuffers, cambios de calidad
- Capas sueltas (`FVideoSurface`, `FSubtitleView`, `FProgressBar`) para montar tu propia UI

Fuera del paquete base: el motor `fvp` para AV1 en Android antiguo vive en `fplayer_fvp`, porque pesa 11,5 MB por ABI. Cast no está implementado.

## Requisitos

| | |
|---|---|
| Flutter | 3.44+ |
| Android | minSdk 24, compileSdk 36 |
| Plataformas | Android (por ahora) |

## Uso

Con la UI incluida:

```dart
final controller = FPlayerController(config: const FPlayerConfig());
await controller.open(FPlayerSource.network(url));

// en build:
FPlayerView(controller: controller)
```

`FPlayerView` se dimensiona al aspecto del video, así que entra en una `Column` sin envolturas.

### Configuración

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
    'https://cdn.ejemplo.com/master.m3u8',
    headers: {'Authorization': 'Bearer $token'},
    title: 'Episodio 4',
    startAt: Duration(minutes: 12),
  ),
);
```

No olvides `controller.dispose()`.

### Personalizar la UI

`FUiConfig` decide qué se muestra; los builders deciden cómo:

```dart
FPlayerView(
  controller: controller,
  config: const FUiConfig(
    localizations: FPlayerLocalizations.spanish(),
    theme: FPlayerTheme(accent: Color(0xFF00A8E1)),
    showLockButton: false,
    controlsTimeout: Duration(seconds: 3),
  ),
  bottomBarBuilder: (context, ui) => MiBarra(ui: ui),
)
```

Dentro de un builder, `FPlayerScope.of(context)` da el mismo estado de vista que usan los controles internos — visibilidad, bloqueo, scrub, encuadre — así que tu barra puede reiniciar el auto-ocultar o iniciar un arrastre sin recablear nada.

Presets: `FUiConfig.bare()` deja solo el video (los gestos siguen activos, para alimentar tu propio overlay) y `FUiConfig.tv()` arma el layout leanback.

Si prefieres montarlo tú desde cero, las capas están sueltas: `FVideoSurface`, `FSubtitleView`, `FProgressBar`, `FSettingsPanel`, `FErrorView`.

### Fullscreen

El botón entra en una ruta que reutiliza el mismo controller, y por tanto la misma textura: no hay recarga ni re-buffer.

```dart
FPlayerView(
  controller: controller,
  fullscreen: const FFullscreenConfig(
    orientation: FFullscreenOrientation.followVideo,  // horizontal si el video lo es
    systemUiMode: SystemUiMode.immersiveSticky,
    exitOnComplete: true,
  ),
)
```

### Android TV y mandos

```dart
FUiConfig(tv: FTvConfig(mode: FTvMode.auto))   // por defecto
```

`auto` no cambia nada hasta que llega la primera tecla direccional; a partir de ahí el anillo de foco aparece y el mando manda. Un build solo para TV usa `FTvMode.enabled` y `FPlayerTheme.tv()`.

- **←/→** buscan, acelerando cuanto más se insiste, y el motor recibe un único seek cuando paras. La vista previa se mueve al instante.
- **↑/↓** mueven el foco entre filas de controles.
- **OK** activa el control enfocado; la primera pulsación con los controles ocultos solo los muestra.
- **Atrás** cierra el panel de ajustes, luego los controles, y solo después sale.
- Las **teclas de medios** actúan siempre, sin revelar nada primero.

### Gestos

```dart
FUiConfig(
  gestures: FGestureConfig(
    doubleTapSeeks: true,          // tercio izquierdo/derecho salta, centro pausa
    horizontalDragSeeks: true,     // con vista previa mientras el dedo está abajo
    verticalDragAdjustsVolume: true,
    longPressSpeed: 2.0,           // mantener acelera, soltar restaura
    pinchChangesFit: true,
  ),
)
```

`FGestureConfig.none()` los apaga todos salvo el toque que muestra los controles.

### Fuentes

```dart
FPlayerSource.network(url, headers: {...}, type: FSourceType.auto)
FPlayerSource.file('/storage/emulated/0/video.mkv')
FPlayerSource.asset('assets/intro.mp4')
```

`FSourceType.auto` deja que el motor deduzca el formato de la URI y del `Content-Type`. Fuérzalo solo si tu endpoint sirve un manifiesto sin extensión *y* con un `Content-Type` incorrecto.

### Control

```dart
controller.play();
controller.pause();
controller.togglePlayPause();
controller.seekTo(Duration(minutes: 3));
controller.seekBy(Duration(seconds: -30));
controller.skipForward();          // usa FPlaybackConfig.seekStep
controller.setSpeed(1.5);
controller.setVolume(0.4);
controller.toggleMute();
controller.retry();
controller.stop();
```

### Pistas

```dart
final tracks = controller.tracks;

tracks.audio;   // List<FAudioTrack> — idioma, canales, bitrate, audiodescripción
tracks.text;    // List<FTextTrack>  — idioma, forzado, CC
tracks.video;   // List<FVideoTrack> — resolución, bitrate, fps

controller.selectAudioTrack(tracks.audio.first);
controller.selectTextTrack(tracks.text.first);
controller.disableSubtitles();
controller.selectVideoTrack(tracks.video.last);   // fija la calidad
controller.enableAutoQuality();                   // vuelve a adaptativo
```

**Seleccionada no es lo mismo que activa.** En modo adaptativo el motor mantiene *todas* las calidades del pool como seleccionadas y va cambiando entre ellas:

```dart
tracks.activeVideo;    // la que se está decodificando ahora mismo
tracks.selectedVideo;  // la que fijó el usuario; null si está en auto
tracks.isVideoAuto;

// Para etiquetar el botón de calidad:
final label = tracks.isVideoAuto
    ? 'Auto (${tracks.activeVideo?.qualityLabel})'
    : tracks.selectedVideo!.qualityLabel;
```

`qualityLabel` normaliza a los peldaños que la gente reconoce. Contenido cinematográfico es más ancho que 16:9, así que una rendition de 1680×750 se etiqueta `1080p` y no `750p`; `width` y `height` siguen disponibles si prefieres los números crudos.

### Subtítulos

Declarados en la fuente:

```dart
FPlayerSource.network(
  url,
  headers: {'Authorization': 'Bearer $token'},
  subtitles: [
    FSubtitleSource.network(
      'https://subs.ejemplo.com/es.vtt',
      label: 'Español',
      language: 'es',
      headers: {'X-Api-Key': 'otra-cosa'},   // headers propios de esta pista
      selectedByDefault: true,
    ),
  ],
)
```

Los headers se aplican **por URI**: la petición del subtítulo lleva solo los suyos. El `Authorization` del media nunca se filtra a un host de subtítulos de terceros.

Añadir uno después de empezar (recarga la fuente conservando la posición):

```dart
await controller.addSubtitle(FSubtitleSource.network(uri, label: 'Español'));
```

Selección automática por idioma:

```dart
FPlaybackConfig(
  preferredAudioLanguages: ['es', 'en'],
  preferredTextLanguages: ['es'],
  autoSelectSubtitles: true,   // por defecto false: los subtítulos empiezan apagados
)
```

Estilo:

```dart
FPlayerConfig(
  subtitleStyle: FSubtitleStyle(
    fontSize: 18,
    scale: 1.2,                    // multiplicador para el usuario
    edge: FSubtitleEdge.outline,   // legible sobre cualquier imagen
    bottomMargin: 0.06,
  ),
)

// O con caja opaca:
FSubtitleStyle.boxed()
```

`FSubtitleView` acepta `bottomInset` para subir los subtítulos mientras los controles están visibles.

> Ajustar la sincronía de los subtítulos en caliente todavía no está soportado; el porqué y las opciones están en `docs/PLAN.md`.

### Storyboard (miniaturas en el slider)

```dart
FPlayerSource.network(
  url,
  storyboard: FStoryboardSource.vtt('https://cdn.ejemplo.com/sb.vtt', headers: {...}),
)
```

Nada más: si la fuente declara uno, `FPlayerView` lo carga y muestra la miniatura sobre el thumb al arrastrar. El índice es WebVTT donde cada cue apunta a una imagen, opcionalmente con `#xywh=x,y,w,h` para recortar de un sprite sheet; las URLs relativas se resuelven contra la del propio VTT.

Las hojas se decodifican una vez y se recortan en canvas, con caché LRU y deduplicado de peticiones en vuelo. Pasa un `FStoryboardController` compartido a varios players si quieres una sola caché para toda la app.

### Cola de reproducción

```dart
await controller.setPlaylist(episodios, startIndex: 2);

controller.next();
controller.previous();
controller.jumpTo(0);

controller.value.currentIndex;     // posición en la cola
controller.value.hasNext;
controller.value.nextInPlaylist;   // qué viene después
```

Al terminar un ítem pasa al siguiente solo (`FPlaybackConfig.autoAdvance`, activo por defecto), y `repeatPlaylist` vuelve al principio tras el último. Cerca del final aparece la tarjeta de "a continuación" con el título del siguiente, visible aunque los controles estén ocultos.

`previous` reinicia el ítem si ya llevas más de tres segundos, y solo salta al anterior si acabas de empezar — que es lo que hace ese botón en todas partes. Abrir una fuente con `open()` limpia la cola; `stop()` la conserva.

### Capítulos y saltar intro

```dart
FPlayerSource.network(
  url,
  chapters: [
    FChapter(start: Duration.zero, end: Duration(seconds: 45),
             title: 'Intro', kind: FChapterKind.intro),
    FChapter(start: Duration(seconds: 45), title: 'Episodio'),
  ],
)
```

Los límites aparecen troquelados en la barra, y mientras la reproducción está dentro de un tramo marcado como `intro`, `recap`, `credits` o `ad` aparece un botón para saltarlo — visible aunque los controles estén ocultos, que es justo cuando hace falta.

### Picture-in-Picture

```dart
FPlayerConfig(pip: FPipConfig(autoEnterOnLeave: true))
```

La ventana de PiP refleja **todo** el árbol Flutter, así que usa `isPipActive` para desnudar la UI:

```dart
if (controller.value.isPipActive) {
  return FPlayerView(controller: controller, config: const FUiConfig.bare());
}
```

`isPipSupported` es false hasta el primer frame: el sistema necesita una relación de aspecto para dimensionar la ventana.

### Sesión de medios y background

```dart
FPlayerConfig(background: FBackgroundConfig.audioInBackground())
```

Publica una sesión con notificación, controles en la pantalla de bloqueo y botones de auriculares, y mantiene el audio al salir de la app. Apagada por defecto para no imponer una notificación a quien no la quiere. Los modos son `stop`, `pause` (por defecto) y `continueAudio`.

### Descargas offline

```dart
await FDownloadManager.instance.initialize(
  const FDownloadConfig(requirements: FDownloadRequirements.unmeteredOnly()),
);

// Qué se puede bajar y cuánto ocupa
final options = await FDownloadManager.instance.inspect(source);

await FDownloadManager.instance.enqueue(
  source,
  selection: const FDownloadSelection.standard(),   // hasta 720p
);
```

`FDownloadManager` es un `ChangeNotifier`: escúchalo y tendrás la cola con estado, progreso y bytes. Los requisitos (solo Wi-Fi, solo cargando…) los aplica el sistema, así que una descarga esperando Wi-Fi se reanuda sola con la app cerrada.

Lo importante: **una descarga completada se reproduce con el mismo `FPlayerSource.network` de siempre**. La caché está indexada por URI, así que el sitio donde llamas a `open()` no sabe que los bytes son locales.

Los metadatos de la fuente viajan en el índice de descargas de Media3, así que una pantalla de "Mis descargas" se reconstruye sola desde `list()` — títulos, pósters, ids — sin una segunda base de datos que mantener sincronizada.

> Los headers se guardan en el índice para que una descarga reanudada tras un reinicio pueda re-autenticarse. Eso deja un token en disco: usa tokens de vida corta.

### Analítica

```dart
final tracker = FPlaybackSessionTracker(
  controller: controller,
  observers: [MiObservador()],
);
// ...
tracker.dispose();
```

Se engancha desde fuera —escucha el controller, no lo modifica— y deriva: tiempo visto real (sin pausas ni atascos, ajustado por velocidad), tiempo hasta el primer frame, número y duración de rebuffers, cambios de calidad, seeks, bitrate y altura media ponderados por tiempo en pantalla.

Para enviarlo a un backend con cola persistente y reintentos, usa el paquete hermano `fplayer_telemetry`.

> Bytes descargados y frames descartados requieren un puente nativo que aún no existe; los campos están en el modelo pero siempre valen null.

### Estado

`controller.value` es un `FPlayerValue` inmutable:

```dart
final v = controller.value;
v.status;            // idle · loading · ready · buffering · completed · error
v.isPlaying;
v.position;  v.buffered;  v.duration;  v.remaining;
v.progress;  v.bufferedProgress;       // 0..1, listos para un slider
v.aspectRatio;                          // ya considera rotación y píxeles anamórficos
v.isLive;    v.isSeekable;
v.tracks;                               // FTracks
v.cues;                                 // List<FSubtitleCue> en pantalla ahora
v.error;                                // FPlayerError?
```

### Errores

```dart
switch (controller.value.error?.code) {
  case FPlayerErrorCode.unauthorized: await refreshToken(); controller.retry();
  case FPlayerErrorCode.notFound:     mostrarNoDisponible();
  case FPlayerErrorCode.network:      // ya se reintentó solo según FRetryPolicy
  default:                            mostrarGenerico();
}
```

Los errores marcados como reintentables se reintentan solos con backoff exponencial antes de llegar a la UI, para no parpadear un overlay que desaparece dos segundos después.

### Eventos

Para analítica y para reaccionar a transiciones concretas:

```dart
controller.events.listen((event) {
  if (event is FCompleted) reproducirSiguiente();
  if (event is FErrorOccurred) log(event.error);
});
```

### Decodificación

Hardware por defecto. Los otros modos existen para depurar o para esquivar dispositivos con un decodificador roto para cierto códec:

```dart
FDecoderConfig(mode: FDecoderMode.softwareFirst)
FDecoderConfig.dataSaver()   // tope de 720p / 2.5 Mbps
```

Nota sobre AV1: Android 12+ trae un decodificador AV1 por software en la plataforma y ExoPlayer lo usa solo. En dispositivos anteriores sin AV1 por hardware no hay decodificador disponible; ese caso lo cubrirá el motor alternativo previsto en la fase 11.

## Configuración de Android

El plugin declara `INTERNET` y nada más: no quiero obligar a toda app a justificar permisos que quizá no use.

**HTTP plano** (streams sin TLS):
```xml
<application android:usesCleartextTraffic="true">
```

**Picture-in-Picture**:
```xml
<activity android:name=".MainActivity"
          android:supportsPictureInPicture="true"
          android:resizeableActivity="true" ... />
```

**Sesión de medios** (solo si activas `background.mediaSession` o el modo `continueAudio`):
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

Sin ese `<service>` la sesión se omite en silencio y `hasMediaSession` queda en false — se comprueba antes de construir nada.

**Descargas en background** (sin esto funcionan, pero solo mientras la app está viva):
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<!-- Solo para reanudar tras un reinicio del dispositivo -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<service android:name="dev.chikenare.fplayer.download.FplayerDownloadService"
         android:exported="false"
         android:foregroundServiceType="dataSync">
    <intent-filter>
        <action android:name="androidx.media3.exoplayer.offline.DownloadService" />
    </intent-filter>
</service>
```

**Android TV**, para que la app aparezca en el lanzador leanback:
```xml
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<uses-feature android:name="android.software.leanback" android:required="false" />
```

## Ejemplo

`example/` demuestra HLS, DASH, MP4 con headers y subtítulo externo verificados contra un servidor local, storyboard, capítulos y una fuente que falla a propósito, con un panel del estado en vivo y las métricas de sesión.

```bash
cd example && flutter run
```

## Tests

```bash
flutter test                           # 166 tests
cd fplayer_telemetry && flutter test   # 26 tests
```

## Licencia

MIT
