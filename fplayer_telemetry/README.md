# fplayer_telemetry

Playback telemetry for [`fplayer`](../): a persistent on-disk queue, batched delivery and retries with backoff.

It lives outside the player package on purpose. Reporting means a queue on disk, an HTTP client and a retry policy; an app that does not report should carry none of it.

## How it fits

`fplayer` measures and exposes; `fplayer_telemetry` queues and sends.

```
FPlayerController
      │ events
      ▼
FPlaybackSessionTracker ──► FPlayerObserver
                                  ▲
                                  │
                          FTelemetryReporter
                                  │
                     FTelemetryQueue (JSONL on disk)
                                  │
                          FTelemetryClient (HTTP)
```

## Usage

```dart
final reporter = FTelemetryReporter(
  config: FTelemetryConfig(
    endpoint: Uri.parse('https://api.example.com/telemetry'),
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

// When the screen goes away:
tracker.dispose();
await reporter.dispose();   // attempts one last send and leaves the rest on disk
```

## What gets sent

Every record carries **running totals and deltas** since the previous record of the same session. The totals let a late delivery correct the picture; the deltas let you sum without worrying about duplicates.

| Kind | When |
|---|---|
| `start` | a source was opened |
| `firstFrame` | the picture appeared, with `timeToFirstFrameMs` |
| `progress` | every `progressInterval` while playing, never while paused |
| `rebuffer` | recovered from a stall |
| `seek` | the playhead was moved |
| `error` | a failure the viewer saw — retries are not reported |
| `end` | the session finished, with `endReason` |

Request body:

```json
{ "events": [ { "sessionId": "01J…", "kind": "progress", "watchedDeltaMs": 30000, … } ] }
```

## Delivery

- **JSONL queue on disk**, bounded by `maxQueuedEvents` (500 by default). Past that, the oldest are dropped.
- **Batches** of up to `maxBatchSize` (50), flushed every `flushInterval` (60 s) and at the end of each session.
- **2xx** → delivered. **429 / 408 / 5xx / network failure** → retried with exponential backoff, honouring `Retry-After` (in seconds or as an HTTP date). **Any other 4xx** → the batch is dropped, because repeating it cannot help and the queue would otherwise never drain.
- Whatever could not be delivered **survives an app restart**.

## Notes

- The queue file path is injectable (`queueFile:`); left unset, it is resolved through `path_provider`.
- `FTelemetryClient` and `FTelemetryQueue` are injectable, so the whole cycle can be tested without touching a real network or disk.
- Metadata from `FPlayerSource.metadata` is reduced to JSON-safe values; anything else is stringified rather than breaking serialisation for the entire queue.
- `publish_to: none` while it depends on `fplayer` by path.

## License

MIT
