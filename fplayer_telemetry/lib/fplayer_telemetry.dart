/// Playback telemetry for `fplayer`.
///
/// Kept out of the player package on purpose: reporting means a disk queue, an HTTP client and a
/// retry policy, and an app that does not report should not carry any of it.
library;

export 'src/telemetry_client.dart';
export 'src/telemetry_config.dart';
export 'src/telemetry_event.dart';
export 'src/telemetry_queue.dart';
export 'src/telemetry_reporter.dart';
