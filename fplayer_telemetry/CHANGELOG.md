# Changelog

## 0.1.0

Primera versión.

### Añadido

- `FTelemetryReporter`: un `FPlayerObserver` que convierte las observaciones de reproducción en registros con totales y deltas por sesión.
- `FTelemetryQueue`: cola FIFO persistente en JSONL, acotada, con descarte de los más antiguos y reescritura atómica vía archivo temporal. Sobrevive al reinicio y salta líneas corruptas en vez de perder el archivo.
- `FTelemetryClient`: envío por lotes con clasificación de la respuesta — entregado, reintentar o descartar — honrando `Retry-After` en segundos y en formato de fecha HTTP.
- `FTelemetryConfig`: endpoint, token estático o proveedor de token, cabeceras extra, intervalos de progreso y vaciado, tamaño de lote, tope de cola, backoff, timeout, activación y modo verboso.
- `FTelemetryEvent`: modelo serializable con saneado de metadatos arbitrarios a valores JSON-seguros.
