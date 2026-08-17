# Changelog

## 0.5.0

Wakelock, brillo, DRM real y el motor `fvp` como paquete hermano. Cierra la fase 11.

### Añadido

- **La pantalla ya no se apaga viendo un video.** El flag se mantiene mientras los frames avanzan y se libera al pausar, con conteo de referencias entre players — un player pausado no puede apagar la pantalla debajo de otro que reproduce. Se desactiva con `FPlaybackConfig.keepScreenOn`.
- **Gesto de brillo** en la mitad izquierda, que en la fase 3 quedó definido pero inerte a la espera de que el plugin tuviera la Activity. Afecta a la ventana de la app, no al ajuste del dispositivo, así que revierte solo al salir. También disponible como `controller.setBrightness()`.
- **DRM Widevine de verdad.** `FDrmConfig` existía desde la fase 1 y se ignoraba en silencio; ahora llega al `MediaItem`, con los headers de licencia separados de los del media. Se añaden `playClearContentWithoutKey` y `forceDefaultLicenseUri`.
- **`fplayer_fvp`**: paquete hermano con el motor libmdk/FFmpeg y `FFallbackEngine`, que usa Media3 y cae a libmdk solo cuando el códec no está soportado. Fuera del paquete base a propósito — pesa 11,5 MB por ABI frente a los 1-2 MB de todo Media3, y cierra un hueco estrecho: AV1 por software en Android anterior a 12.

### Cambiado

- **`FPlaybackEngine.textureId` ahora es `int?`.** Media3 asigna la textura al crear el player y la conserva; libmdk la dimensiona desde el frame decodificado, así que no existe hasta que hay medio preparado y la recrea por fuente.
- El barrel exporta las señales del motor y `FMedia3Engine`, para que un motor externo pueda implementar la interfaz y componerse con el de serie.

### Quitado

- `FDrmConfig.forceL3`, que nunca funcionó: no existe forzado de nivel de seguridad en esa API de Media3.

## 0.4.0

Cola de reproducción, robustez de red y descargas offline. Fases 8, 9 y parte de la 11.

### Añadido

- **Cola de reproducción**: `setPlaylist`, `next`, `previous`, `jumpTo`, con `hasNext` / `hasPrevious` / `nextInPlaylist` en el estado, auto-avance al terminar y `repeatPlaylist`. Botones de pista anterior/siguiente y tarjeta de "a continuación" cerca del final, visible aunque los controles estén ocultos.
- **Conciencia de conectividad**: al perder la red la reproducción se aparca en vez de quemar el presupuesto de reintentos, y se reanuda desde la misma posición cuando vuelve la señal. `FPlayerValue.isOnline` / `isOffline` / `isWaitingForNetwork`, evento `FConnectivityChanged`, y el spinner dice *"Esperando conexión…"* en vez de girar sin explicación. Se apaga con `FNetworkConfig.waitForNetwork`.
- **`FSegmentRetryPolicy`**: la escalera *interna* de reintentos, por segmento / manifiesto / clave, sin que la reproducción salga de playing. Distinta de `FRetryPolicy`, que reintenta la fuente entera; los presupuestos se multiplican y ambas clases lo documentan.
- **`FPlayerValue.bufferedAhead`**: media bufferizada por delante del playhead, que es la que predice un atasco. `buffered` es absoluta y no dice nada justo después de un seek.
- **Descargas offline** (`FDownloadManager`): cola persistente sobre Media3, selección de qué renditions bajar con tamaño estimado por calidad, requisitos aplicados por el sistema (solo Wi-Fi, solo cargando), pausar / reanudar / borrar, y estado observable. Una descarga completada se reproduce con el mismo `FPlayerSource.network` de siempre.
- **`FSeeked`**: evento de seek explícito.

### Corregido

- Un stream adaptativo descargado se reproduce ahora desde su `DownloadRequest`, restringido a las stream keys realmente bajadas. Antes, sin red, el selector adaptativo alcanzaba una calidad que no estaba en disco y el stream moría.
- Un MP4 progresivo no se podía encolar: `DownloadHelper` no tiene información de pistas para media progresiva y consultarle por períodos lanzaba una excepción sin mensaje.
- Una descarga encolada se quedaba en `queued` indefinidamente cuando la app no declara el servicio de descargas: nadie llamaba a `resumeDownloads()`, que es lo que normalmente hace ese servicio al crearse.
- Los errores del puente de descargas con excepción sin mensaje ya no llegan a Dart como `null`.

### Requisitos de la app consumidora

Las descargas en background necesitan el `<service>` de `FplayerDownloadService` y permisos de foreground service; sin él funcionan solo mientras la app está viva. Ver el README.

## 0.3.0

UI completa, TV, storyboard, PiP, sesión de medios y analítica. Fases 3–7, 9 (UI) y 10 del plan.

### Añadido

- **`FPlayerView`**: el player con su chrome — video, gestos, subtítulos, controles, panel de ajustes y estados de error. Cada banda es reemplazable por un builder, y dentro de cualquiera `FPlayerScope.of(context)` da el mismo estado de vista que usan los controles internos.
- **`FUiConfig`** con presets `.bare()` (solo video) y `.tv()` (leanback), `FPlayerTheme` (+`.tv()`), `FPlayerLocalizations` (+`.spanish()`), `FGestureConfig`, `FFullscreenConfig`, `FTvConfig`.
- **Gestos**: tocar para mostrar controles, doble toque para saltar o pausar según el tercio, arrastre horizontal para buscar con vista previa, arrastre vertical para volumen, mantener para acelerar, pellizcar para cambiar el encuadre.
- **Fullscreen** reutilizando el mismo controller — y por tanto la misma textura — así que entrar y salir cuesta una transición de ruta, no una recarga. Orientación derivada de la forma del video e immersive sticky.
- **Control remoto**: ←/→ hacen scrub con aceleración progresiva y commit diferido, ↑/↓ mueven el foco, teclas de medios actúan de inmediato, Back cierra los controles antes que el player. Modo `auto` que se activa con la primera tecla direccional, sin código nativo.
- **Storyboard**: parser WebVTT con `#xywh`, caché LRU de sprite sheets con deduplicado de peticiones en vuelo, búsqueda binaria sobre miles de cues y recorte directo en canvas. Se conecta solo si la fuente declara uno.
- **Capítulos**: marcas troqueladas en la barra y botón de saltar intro / resumen / créditos / anuncio.
- **Picture-in-Picture**: `enterPip()`, auto-entrada al salir de la app, acciones dentro de la ventana, y `isPipSupported` / `isPipActive` para desnudar la UI mientras dura.
- **MediaSession**: notificación, pantalla de bloqueo, botones de auriculares y metadatos de la fuente. Apagada por defecto.
- **Background**: modos `stop`, `pause` y `continueAudio`. El controller es `WidgetsBindingObserver` y se resincroniza solo al volver.
- **Analítica**: `FPlayerObserver` y `FPlaybackSessionTracker`, que derivan tiempo visto real (descontando pausas y atascos, ajustado por velocidad), tiempo hasta el primer frame, rebuffers, cambios de calidad y seeks — enganchándose desde fuera, sin tocar el core.
- **`fplayer_telemetry`**: paquete hermano con cola persistente en disco, envío por lotes con backoff y respeto de `Retry-After`.
- **`FSeeked`**: evento de seek explícito, para que un observador no tenga que inferirlo de un salto de posición.

### Cambiado

- `FPipConfig` y `FBackgroundConfig` viven en `FPlayerConfig` junto al resto.
- `FPlaybackConfig.seekStep` viaja al nativo, así que los botones de salto del PiP usan el paso de la app.
- `FPlayerController` emite `FSpeedChanged` también cuando el cambio viene del motor.

### Requisitos de la app consumidora

PiP necesita `android:supportsPictureInPicture="true"` y `android:resizeableActivity="true"` en la Activity. La sesión de medios necesita además el `<service>` de `FplayerMediaService` y los permisos de foreground service; sin él la sesión se omite en silencio y `hasMediaSession` queda en false. Ver el README.

## 0.2.0

Pistas y subtítulos. Fase 2 del plan.

### Añadido

- Enumeración de pistas de audio, subtítulos y calidad desde el manifiesto (`FTracks`, `FAudioTrack`, `FTextTrack`, `FVideoTrack`), con idioma, etiqueta, códec, bitrate, canales, resolución, fps y banderas de forzado / CC / audiodescripción.
- Selección en caliente: `selectAudioTrack`, `selectTextTrack`, `selectVideoTrack`, `disableSubtitles`, `enableAutoQuality`.
- Subtítulos externos por URL o archivo (SRT, VTT, ASS/SSA, TTML) declarados en `FPlayerSource.subtitles`, con headers propios por pista.
- `addSubtitle` para adjuntar un subtítulo a la media ya cargada, conservando la posición.
- Idiomas preferidos para la selección automática (`preferredAudioLanguages`, `preferredTextLanguages`, `autoSelectSubtitles`) y `setPreferredLanguages` en caliente.
- Cues entregadas a Dart con su geometría (`FSubtitleCue`) y renderizadas en Flutter con `FSubtitleView`, con estilo configurable vía `FSubtitleStyle` (tamaño, escala de usuario, contorno, sombra, caja, márgenes).
- `FTracksChanged` en el stream de eventos.
- `FVideoTrack.qualityLabel` normaliza a peldaños reconocibles (`1080p`, `720p`…), corrigiendo el contenido más ancho que 16:9.

### Notas

- Los headers se aplican por URI: un subtítulo alojado en otro dominio no recibe el `Authorization` del media.
- `FTrack.isSelected` (está en la selección del motor) y `FTrack.isActive` (se está decodificando) son distintos: en modo adaptativo toda la escalera de calidades está seleccionada a la vez. Usa `FTracks.activeVideo` para saber qué se ve y `FTracks.selectedVideo` para saber qué fijó el usuario.
- El ajuste de sincronía de subtítulos en caliente queda pendiente; `TextRenderer` de Media3 es `final` y no admite desplazar su reloj. Las alternativas están evaluadas en `docs/PLAN.md`.

## 0.1.0

Primera base funcional. Fases 0 y 1 del plan.

### Añadido

- Plugin Android nativo sobre Media3/ExoPlayer 1.11.0, con una instancia de player, textura y par de canales por controlador.
- `FPlayerController` (`ChangeNotifier`) con estado inmutable en `FPlayerValue` y un stream de eventos discretos.
- Fuentes: `FPlayerSource.network` / `.file` / `.asset`, con detección automática de HLS, DASH, SmoothStreaming y progresivo.
- Headers HTTP por fuente, aplicados también a segmentos y peticiones de rango.
- Reanudar en una posición con `startAt`.
- Control de reproducción: play, pause, stop, seek absoluto y relativo, velocidad, volumen, mute, loop.
- Configuración por áreas: `FPlaybackConfig`, `FBufferConfig`, `FNetworkConfig`, `FDecoderConfig`, con perfiles `FBufferConfig.fastStart()`, `.resilient()` y `FDecoderConfig.dataSaver()`.
- Modos de decodificación: hardware primero (por defecto), software primero, solo hardware, solo software.
- Taxonomía de errores (`FPlayerErrorCode`) con estado HTTP y marca de reintentable, más reintento automático con backoff exponencial y timeout de carga.
- Recuperación automática de `BEHIND_LIVE_WINDOW` en directos.
- `FVideoSurface`: textura con aspecto, rotación y modos de encuadre (`FVideoFit`).
- `FPlaybackEngine`, la interfaz que permitirá añadir motores alternativos sin tocar las capas superiores.
- App de ejemplo con HLS, DASH, MP4, verificación de headers y caso de error.
