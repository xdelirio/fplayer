/// What a DASH manifest says about its audio and text that FFmpeg leaves out.
///
/// FFmpeg's DASH demuxer keeps an adaptation set's `lang` but drops its `<Label>`, so audio reaches
/// the menus as `es-419` where Media3 shows "Español (Latinoamérica)". It skips text adaptation
/// sets altogether, so subtitles never reach them at all. Both are read from the manifest here.
///
/// A deliberately small reader: the attributes and elements the packagers in use write, without a
/// full XML parser.
class DashManifest {
  const DashManifest({this.audioNames = const {}, this.textTracks = const []});

  /// Parses [xml], with relative URLs resolved against [manifestUri].
  factory DashManifest.parse(String xml, Uri manifestUri) {
    final audioNames = <String, List<String>>{};
    final textTracks = <DashTextTrack>[];

    final mpdBase = _resolveBase(manifestUri, _firstChild(_beforeFirst(xml, '<Period'), 'BaseURL'));
    final periodMatch = RegExp(r'<Period\b([^>]*)>([\s\S]*?)</Period>').firstMatch(xml);
    if (periodMatch == null) return const DashManifest();

    final periodBody = periodMatch.group(2)!;
    final periodBase = _resolveBase(
      mpdBase,
      _firstChild(_beforeFirst(periodBody, '<AdaptationSet'), 'BaseURL'),
    );
    final periodDuration =
        _duration(_attributes(periodMatch.group(1)!)['duration']) ??
        _duration(_attributes(_openingTag(xml, 'MPD') ?? '')['mediaPresentationDuration']);

    for (final set in RegExp(
      r'<AdaptationSet\b([^>]*)>([\s\S]*?)</AdaptationSet>',
    ).allMatches(periodBody)) {
      final attributes = _attributes(set.group(1)!);
      final body = set.group(2)!;
      final firstRepresentation = RegExp(r'<Representation\b([^>]*)>').firstMatch(body);
      final representationAttributes = firstRepresentation == null
          ? const <String, String>{}
          : _attributes(firstRepresentation.group(1)!);

      final contentType =
          attributes['contentType'] ??
          _typeOf(attributes['mimeType'] ?? representationAttributes['mimeType']);
      final language = attributes['lang'];
      final label = _text(_firstChild(body, 'Label'));
      final roles = RegExp(r'<Role\b([^>]*)/?>')
          .allMatches(body)
          .map((m) => _attributes(m.group(1)!)['value'])
          .whereType<String>()
          .toSet();

      if (contentType == 'audio') {
        if (language != null && label != null) {
          audioNames.putIfAbsent(language, () => []).add(label);
        }
        continue;
      }
      if (contentType != 'text') continue;

      final setHead = _beforeFirst(body, '<Representation');
      final setBase = _resolveBase(periodBase, _firstChild(setHead, 'BaseURL'));
      final setTemplate = _openingTag(setHead, 'SegmentTemplate');
      final setTimeline = _firstChild(setHead, 'SegmentTimeline');

      // One track per adaptation set: the first representation is the text, and any others are
      // the same text again.
      final representation = RegExp(r'<Representation\b([^>]*?)(?:/>|>([\s\S]*?)</Representation>)')
          .firstMatch(body);
      if (representation == null) continue;
      final repAttributes = _attributes(representation.group(1)!);
      final repBody = representation.group(2) ?? '';
      final base = _resolveBase(setBase, _firstChild(repBody, 'BaseURL'));
      final template = _openingTag(repBody, 'SegmentTemplate') ?? setTemplate;
      final timeline = _firstChild(repBody, 'SegmentTimeline') ?? setTimeline;

      final urls = template == null
          ? [base]
          : _templateUrls(base, _attributes(template), timeline, repAttributes, periodDuration);
      if (urls.isEmpty) continue;

      textTracks.add(
        DashTextTrack(
          language: language,
          label: label,
          urls: urls,
          isForced: roles.contains('forced-subtitle') || roles.contains('forced_subtitle'),
          isClosedCaption: roles.contains('caption'),
        ),
      );
    }

    return DashManifest(audioNames: audioNames, textTracks: textTracks);
  }

  static const empty = DashManifest();

  /// Audio labels by language, in manifest order.
  final Map<String, List<String>> audioNames;

  final List<DashTextTrack> textTracks;

  /// Segment counts past this are not fetched: a text track cut into a few seconds a segment would
  /// be thousands of requests for one film.
  static const maxSegments = 2000;

  static List<Uri> _templateUrls(
    Uri base,
    Map<String, String> template,
    String? timeline,
    Map<String, String> representation,
    Duration? periodDuration,
  ) {
    String fill(String pattern, {int? number, int? time}) => pattern.replaceAllMapped(
      RegExp(r'\$(RepresentationID|Bandwidth|Number|Time)(%0(\d+)d)?\$|\$\$'),
      (m) {
        if (m.group(0) == r'$$') return r'$';
        final value = switch (m.group(1)) {
          'RepresentationID' => representation['id'] ?? '',
          'Bandwidth' => representation['bandwidth'] ?? '',
          'Number' => '$number',
          _ => '$time',
        };
        final width = int.tryParse(m.group(3) ?? '');
        return width == null ? value : value.padLeft(width, '0');
      },
    );

    final urls = <Uri>[];
    final initialization = template['initialization'];
    if (initialization != null) urls.add(base.resolve(fill(initialization)));

    final media = template['media'];
    if (media == null) return urls;
    var number = int.tryParse(template['startNumber'] ?? '') ?? 1;
    final timescale = int.tryParse(template['timescale'] ?? '') ?? 1;

    if (timeline != null) {
      var time = 0;
      for (final s in RegExp(r'<S\b([^>]*)/?>').allMatches(timeline)) {
        final a = _attributes(s.group(1)!);
        time = int.tryParse(a['t'] ?? '') ?? time;
        final duration = int.tryParse(a['d'] ?? '') ?? 0;
        var repeat = int.tryParse(a['r'] ?? '') ?? 0;
        if (repeat < 0 && duration > 0 && periodDuration != null) {
          final end = periodDuration.inMicroseconds * timescale ~/ Duration.microsecondsPerSecond;
          repeat = ((end - time) / duration).ceil() - 1;
        }
        for (var i = 0; i <= repeat; i++) {
          if (urls.length > maxSegments) return const [];
          urls.add(base.resolve(fill(media, number: number, time: time)));
          number++;
          time += duration;
        }
      }
      return urls;
    }

    final duration = int.tryParse(template['duration'] ?? '');
    if (duration == null || duration <= 0 || periodDuration == null) return const [];
    final count =
        (periodDuration.inMicroseconds * timescale / Duration.microsecondsPerSecond / duration)
            .ceil();
    if (count > maxSegments) return const [];
    for (var i = 0; i < count; i++) {
      urls.add(base.resolve(fill(media, number: number + i, time: i * duration)));
    }
    return urls;
  }

  static String? _typeOf(String? mimeType) => switch (mimeType?.split('/').first) {
    'audio' => 'audio',
    'video' => 'video',
    'text' => 'text',
    // `application/mp4` with a text codec, or TTML.
    'application' => 'text',
    _ => null,
  };

  static Uri _resolveBase(Uri parent, String? baseUrl) {
    final value = _text(baseUrl);
    return value == null ? parent : parent.resolve(value);
  }

  static String _beforeFirst(String xml, String tag) {
    final index = xml.indexOf(tag);
    return index < 0 ? xml : xml.substring(0, index);
  }

  static String? _openingTag(String xml, String name) =>
      RegExp('<$name\\b([^>]*?)/?>').firstMatch(xml)?.group(1);

  static String? _firstChild(String xml, String name) =>
      RegExp('<$name\\b[^>]*?(?:/>|>([\\s\\S]*?)</$name>)').firstMatch(xml)?.group(1);

  static String? _text(String? value) {
    if (value == null) return null;
    final text = _unescape(value.trim());
    return text.isEmpty ? null : text;
  }

  static Map<String, String> _attributes(String tag) => {
    for (final m in RegExp(r'([\w:.-]+)\s*=\s*"([^"]*)"').allMatches(tag))
      m.group(1)!: _unescape(m.group(2)!),
  };

  static String _unescape(String value) => value
      .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
        final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      })
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// An ISO 8601 duration as DASH writes it: `PT7100.416504S`, `PT1H58M20.4S`, `P1DT2H`.
  static Duration? _duration(String? value) {
    if (value == null) return null;
    final m = RegExp(
      r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
    ).firstMatch(value.trim());
    if (m == null) return null;
    double part(int i) => double.tryParse(m.group(i) ?? '') ?? 0;
    final seconds = part(1) * 86400 + part(2) * 3600 + part(3) * 60 + part(4);
    return Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
  }
}

/// A text adaptation set: where its segments are, and what to call it.
class DashTextTrack {
  const DashTextTrack({
    required this.language,
    required this.label,
    required this.urls,
    this.isForced = false,
    this.isClosedCaption = false,
  });

  final String? language;
  final String? label;

  /// The initialization segment, if any, then the media segments in order — or one URL for a
  /// track that is a single file.
  final List<Uri> urls;
  final bool isForced;
  final bool isClosedCaption;
}
