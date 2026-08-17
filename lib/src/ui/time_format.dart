/// Formats a media timestamp the way players do: `m:ss`, growing to `h:mm:ss` only when the
/// media is actually an hour long.
///
/// [reference] keeps digit counts stable across a pair of labels — pass the duration so a
/// two-hour film shows `0:04:12 / 2:11:03` rather than `4:12 / 2:11:03`, which jitters the layout
/// as the position crosses the hour.
String formatMediaTime(Duration value, {Duration? reference}) {
  final total = value.isNegative ? Duration.zero : value;
  // The longer of the two decides the shape. A container whose declared duration under-reports —
  // VBR in a container, a manifest rounding down — would otherwise drop the hour from a position
  // past it and show `0:05` for `1:00:05`.
  final scale = reference == null || reference < total ? total : reference;

  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);
  final secondsText = seconds.toString().padLeft(2, '0');

  if (scale.inHours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsText';
  }
  return '$minutes:$secondsText';
}

/// Formats a playback rate for a button: `1×`, `1.5×`, `0.75×`.
String formatPlaybackSpeed(double speed) {
  final text = speed.toStringAsFixed(2);
  final trimmed = text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
  return '$trimmed×';
}
