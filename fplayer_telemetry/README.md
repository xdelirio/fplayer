# fplayer_telemetry

Telemetría de reproducción para [`fplayer`](../): cola persistente en disco, envío por lotes y reintentos con backoff.

Vive fuera del paquete del reproductor a propósito. Reportar implica una cola en disco, un cliente HTTP y una política de reintentos; una app que no reporta no debería cargar con nada de eso.

## Cómo encaja

`fplayer` mide y expone; `fplayer_telemetry` encola y envía.

```
FPlayerController
      │ events
      ▼
FPlaybackSessionTracker ──► FPlayerObserver
                                  ▲
                                  │
                          FTelemetryReporter
                                  │
                     FTelemetryQueue (JSONL en disco)
                                  │
                          FTelemetryClient (HTTP)
```

## Uso

```dart
final reporter = FTelemetryReporter(
  config: FTelemetryConfig(
    endpoint: Uri.parse('https://api.ejemplo.com/telemetry'),
    tokenProvider: () async => await auth.currentToken(),
    appVersion: '3.4.1',
    deviceType: 'phone',
  ),
);
await reporter.start();

final tracker = FPlaybackSessionTracker(
  controller: controller,
  observers: [reporter],
  progressInterval: reporter.config.progressInterval,
);

// Al cerrar la pantalla:
tracker.dispose();
await reporter.dispose();   // intenta un último envío y deja el resto en disco
```

## Qué se envía

Cada registro lleva **totales acumulados y deltas** desde el registro anterior de la misma sesión. Los totales permiten que un envío tardío corrija el panorama; los deltas permiten sumar sin preocuparse por duplicados.

| Tipo | Cuándo |
|---|---|
| `start` | se abrió una fuente |
| `firstFrame` | apareció la imagen, con `timeToFirstFrameMs` |
| `progress` | cada `progressInterval` mientras se reproduce (nunca en pausa) |
| `rebuffer` | se recuperó de un atasco |
| `seek` | saltó la cabeza de reproducción |
| `error` | fallo que el espectador vio (los reintentos no se reportan) |
| `end` | terminó la sesión, con `endReason` |

Cuerpo de la petición:

```json
{ "events": [ { "sessionId": "01J…", "kind": "progress", "watchedDeltaMs": 30000, … } ] }
```

## Entrega

- **Cola JSONL en disco**, acotada por `maxQueuedEvents` (500 por defecto). Al superarla se descartan los más antiguos.
- **Lotes** de hasta `maxBatchSize` (50), vaciados cada `flushInterval` (60 s) y al terminar cada sesión.
- **2xx** → entregado. **429 / 408 / 5xx / fallo de red** → se reintenta con backoff exponencial, honrando `Retry-After` (en segundos o como fecha HTTP). **Otros 4xx** → se descarta el lote, porque repetirlo no puede ayudar y si no la cola nunca drena.
- Lo que no se pudo entregar **sobrevive al reinicio de la app**.

## Notas

- La ruta del archivo de cola es inyectable (`queueFile:`); si no se indica, se resuelve con `path_provider`.
- `FTelemetryClient` y `FTelemetryQueue` son inyectables, así que se puede testear el ciclo completo sin tocar red ni disco real.
- Los metadatos de `FPlayerSource.metadata` se reducen a valores JSON-seguros; lo que no lo sea se convierte a texto en vez de romper la serialización de toda la cola.
- `publish_to: none` mientras dependa de `fplayer` por ruta.

## Licencia

MIT
