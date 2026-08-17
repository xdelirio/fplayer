# Changelog

## 0.1.0

First release.

### Added

- `FTelemetryReporter`: an `FPlayerObserver` that turns playback observations into records carrying per-session totals and deltas.
- `FTelemetryQueue`: a bounded, persistent FIFO queue in JSONL, dropping the oldest entries past its cap and rewriting atomically through a temporary file. It survives a restart and skips corrupt lines rather than losing the file.
- `FTelemetryClient`: batched delivery with response classification — delivered, retry or drop — honouring `Retry-After` both in seconds and as an HTTP date.
- `FTelemetryConfig`: endpoint, static token or token provider, extra headers, progress and flush intervals, batch size, queue cap, backoff, timeout, an enabled switch and a verbose mode.
- `FTelemetryEvent`: a serialisable model that sanitises arbitrary metadata down to JSON-safe values.
