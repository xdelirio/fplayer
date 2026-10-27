/// The names an HLS master playlist gives its audio and subtitle renditions.
///
/// FFmpeg keeps a rendition's `NAME` in a `comment` tag, and mpv reads only `title`, so a track
/// reaches the menus as its bare language tag — `es-419` where Media3 shows "Español
/// (Latinoamérica)". The names are read from the playlist instead and matched to mpv's tracks by
/// language, in order, through `manifestNameFor`.
class HlsRenditionNames {
  const HlsRenditionNames({this.audio = const {}, this.subtitles = const {}});

  /// Parses the `EXT-X-MEDIA` lines of [playlist]. A media playlist, or anything that is not a
  /// playlist at all, has none and yields an empty result.
  factory HlsRenditionNames.parse(String playlist) {
    final audio = <String, List<String>>{};
    final subtitles = <String, List<String>>{};

    for (final line in playlist.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#EXT-X-MEDIA:')) continue;
      final attributes = _attributes(trimmed.substring('#EXT-X-MEDIA:'.length));
      final name = attributes['NAME'];
      final language = attributes['LANGUAGE'];
      if (name == null || name.isEmpty || language == null || language.isEmpty) continue;

      final target = switch (attributes['TYPE']) {
        'AUDIO' => audio,
        'SUBTITLES' => subtitles,
        _ => null,
      };
      target?.putIfAbsent(language, () => []).add(name);
    }

    return HlsRenditionNames(audio: audio, subtitles: subtitles);
  }

  static const empty = HlsRenditionNames();

  /// Rendition names by language, in playlist order.
  final Map<String, List<String>> audio;
  final Map<String, List<String>> subtitles;

  bool get isEmpty => audio.isEmpty && subtitles.isEmpty;

  /// `KEY=VALUE,KEY="quoted, value"` into a map.
  static Map<String, String> _attributes(String list) {
    final result = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
    for (final match in pattern.allMatches(list)) {
      var value = match.group(2)!;
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      result[match.group(1)!] = value;
    }
    return result;
  }
}
