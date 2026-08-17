import 'dart:math';

/// Generates identifiers that sort by creation time.
///
/// The layout is ULID's: 48 bits of millisecond timestamp followed by 80 bits of randomness,
/// rendered in Crockford base32. Sorting matters because analytics backends group by session and
/// replay them in order; a UUID v4 would force every consumer to carry a separate timestamp to
/// recover that order.
///
/// Written out rather than pulled from a package so the core stays dependency-free.
abstract final class FSessionId {
  /// Crockford base32: no `I`, `L`, `O` or `U`, so an id read aloud or typed by hand stays
  /// unambiguous.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const int _timestampLength = 10;
  static const int _randomLength = 16;

  static final Random _defaultRandom = Random.secure();

  /// A new identifier stamped with [at].
  ///
  /// [random] exists for tests; leave it alone in production so ids stay unguessable.
  static String generate({required DateTime at, Random? random}) {
    final source = random ?? _defaultRandom;
    final buffer = StringBuffer();

    var remaining = at.millisecondsSinceEpoch;
    final timestamp = List<String>.filled(_timestampLength, _alphabet[0]);
    for (var i = _timestampLength - 1; i >= 0; i--) {
      timestamp[i] = _alphabet[remaining % 32];
      remaining ~/= 32;
    }
    buffer.writeAll(timestamp);

    for (var i = 0; i < _randomLength; i++) {
      buffer.write(_alphabet[source.nextInt(32)]);
    }

    return buffer.toString();
  }

  /// Recovers the creation time encoded in [id], or null if it is not one of ours.
  static DateTime? timestampOf(String id) {
    if (id.length != _timestampLength + _randomLength) return null;

    var value = 0;
    for (var i = 0; i < _timestampLength; i++) {
      final digit = _alphabet.indexOf(id[i]);
      if (digit < 0) return null;
      value = value * 32 + digit;
    }
    // UTC, because the id encodes an absolute instant. Decoding into local time would make the
    // same id read differently on two devices.
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
}
