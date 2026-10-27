import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer_media_kit/src/engine/dash_manifest.dart';
import 'package:fplayer_media_kit/src/engine/hls_renditions.dart';
import 'package:fplayer_media_kit/src/engine/wvtt.dart';

/// Shaped like what shaka-packager writes: labels on every set, text as fMP4 `wvtt` in one
/// segment, signed URLs on every template.
const _mpd = '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT7100.4S">
  <Period id="0">
    <AdaptationSet id="0" contentType="video">
      <Representation id="0" bandwidth="6582224" codecs="av01" mimeType="video/mp4" width="1920" height="798">
        <SegmentTemplate timescale="12288" initialization="v/init.mp4?t=a&amp;b=1" media="v/\$Number\$.m4s?t=a&amp;b=1" startNumber="1"/>
      </Representation>
    </AdaptationSet>
    <AdaptationSet id="2" contentType="audio" lang="es-419">
      <Label>Español (Latinoamérica)</Label>
      <Representation id="2" bandwidth="158903" codecs="opus" mimeType="audio/mp4"/>
    </AdaptationSet>
    <AdaptationSet id="1" contentType="audio" lang="en-US">
      <Label>English (United States)</Label>
      <Representation id="3" bandwidth="159101" codecs="opus" mimeType="audio/mp4"/>
    </AdaptationSet>
    <AdaptationSet id="3" contentType="text" lang="es-419">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="forced-subtitle"/>
      <Label>Español (Latinoamérica)</Label>
      <Representation id="4" bandwidth="1" codecs="wvtt" mimeType="application/mp4">
        <SegmentTemplate timescale="1000" initialization="s4/init.mp4?t=a&amp;b=1" media="s4/\$Number\$.m4s?t=a&amp;b=1" startNumber="1">
          <SegmentTimeline><S t="0" d="7103000"/></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
    <AdaptationSet id="5" contentType="text" lang="en-US">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="caption"/>
      <Label>English (United States) (SDH)</Label>
      <Representation id="6" bandwidth="155" codecs="wvtt" mimeType="application/mp4">
        <SegmentTemplate timescale="1000" initialization="s6/init.mp4" media="s6/\$Time\$.m4s" startNumber="1">
          <SegmentTimeline><S t="0" d="2000" r="2"/><S d="500"/></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
    <AdaptationSet id="7" contentType="text" lang="fr" mimeType="text/vtt">
      <Representation id="7" bandwidth="100">
        <BaseURL>subs/fr.vtt</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';

void main() {
  group('DashManifest', () {
    final manifest = DashManifest.parse(
      _mpd,
      Uri.parse('https://cdn.example.com/title/play/manifest.mpd?token=x'),
    );

    test('reads the audio labels FFmpeg drops', () {
      expect(manifest.audioNames, {
        'es-419': ['Español (Latinoamérica)'],
        'en-US': ['English (United States)'],
      });
    });

    test('lists every text adaptation set, with its role', () {
      expect(manifest.textTracks.map((t) => t.language), ['es-419', 'en-US', 'fr']);
      expect(manifest.textTracks.map((t) => t.label), [
        'Español (Latinoamérica)',
        'English (United States) (SDH)',
        null,
      ]);
      expect(manifest.textTracks.map((t) => t.isForced), [true, false, false]);
      expect(manifest.textTracks.map((t) => t.isClosedCaption), [false, true, false]);
    });

    test('expands a numbered template, keeping the signature and unescaping it', () {
      expect(manifest.textTracks.first.urls.map((u) => '$u'), [
        'https://cdn.example.com/title/play/s4/init.mp4?t=a&b=1',
        'https://cdn.example.com/title/play/s4/1.m4s?t=a&b=1',
      ]);
    });

    test('expands a timed template, repeats included', () {
      expect(manifest.textTracks[1].urls.map((u) => u.pathSegments.last), [
        'init.mp4',
        '0.m4s',
        '2000.m4s',
        '4000.m4s',
        '6000.m4s',
      ]);
    });

    test('takes a single file from its BaseURL', () {
      expect(manifest.textTracks[2].urls.map((u) => '$u'), [
        'https://cdn.example.com/title/play/subs/fr.vtt',
      ]);
    });
  });

  group('DashManifest.localCopy', () {
    final uri = Uri.parse('https://cdn.example.com/title/play/manifest.mpd?token=x');

    test('drops the text adaptation sets and keeps the rest', () {
      final copy = DashManifest.localCopy(_mpd, uri)!;

      expect(copy, isNot(contains('contentType="text"')));
      expect(copy, isNot(contains('text/vtt')));
      expect(copy, contains('contentType="video"'));
      expect(RegExp('contentType="audio"').allMatches(copy), hasLength(2));
      // Still the same signed segment URLs, escaped as they were.
      expect(copy, contains('v/init.mp4?t=a&amp;b=1'));
    });

    test('points relative segments where the original did', () {
      final copy = DashManifest.localCopy(_mpd, uri)!;

      expect(
        copy,
        contains('type="static" mediaPresentationDuration="PT7100.4S">'
            '<BaseURL>https://cdn.example.com/title/play/</BaseURL>'),
      );
    });

    test('resolves a relative MPD BaseURL instead of adding a second one', () {
      final copy = DashManifest.localCopy(
        '<MPD type="static"><BaseURL>media/</BaseURL><Period></Period></MPD>',
        uri,
      )!;

      expect(
        copy,
        '<MPD type="static"><BaseURL>https://cdn.example.com/title/play/media/</BaseURL>'
        '<Period></Period></MPD>',
      );
    });

    test('leaves a live manifest to be reloaded from its URL', () {
      expect(
        DashManifest.localCopy('<MPD type="dynamic"><Period></Period></MPD>', uri),
        isNull,
      );
    });

    test('leaves what is not a manifest alone', () {
      expect(DashManifest.localCopy('<html></html>', uri), isNull);
    });
  });

  group('HlsRenditionNames', () {
    test('reads NAME by language, for audio and subtitles', () {
      final names = HlsRenditionNames.parse('''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",LANGUAGE="es-419",NAME="Español (Latinoamérica)",DEFAULT=YES,URI="a/es.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",LANGUAGE="en",NAME="English, with commentary",URI="a/en.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",LANGUAGE="es",NAME="Español",URI="s/es.m3u8"
#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",LANGUAGE="en",NAME="CC1",INSTREAM-ID="CC1"
#EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="a",SUBTITLES="s"
v/720.m3u8
''');

      expect(names.audio, {
        'es-419': ['Español (Latinoamérica)'],
        'en': ['English, with commentary'],
      });
      expect(names.subtitles, {
        'es': ['Español'],
      });
    });

    test('finds nothing in a media playlist', () {
      expect(HlsRenditionNames.parse('#EXTM3U\n#EXTINF:6,\nseg0.ts\n').isEmpty, isTrue);
    });
  });

  group('wvttToWebVtt', () {
    test('turns the samples of a fragment into timed cues', () {
      final vtt = wvttToWebVtt(_wvttTrack())!;

      expect(
        vtt,
        'WEBVTT\n\n'
        '00:00:02.000 --> 00:00:04.500 align:center\n'
        'Bueno. Sube.\n\n'
        '00:00:04.500 --> 00:00:05.000\n'
        'Espera.\n\n',
      );
    });

    test('has nothing to say about a file with no cues', () {
      expect(wvttToWebVtt(Uint8List.fromList(_box('ftyp', _ascii('iso6')))), isNull);
    });
  });
}

// region Building wvtt in fragmented MP4

List<int> _u32(int v) => [v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff];

List<int> _ascii(String s) => s.codeUnits;

List<int> _box(String type, List<int> body) => [..._u32(8 + body.length), ..._ascii(type), ...body];

List<int> _fullBox(String type, int version, int flags, List<int> body) =>
    _box(type, [version, flags >> 16 & 0xff, flags >> 8 & 0xff, flags & 0xff, ...body]);

/// Timescale 1000, one fragment starting at 1 s: a one-second gap, then two cues.
Uint8List _wvttTrack() {
  final init = [
    ..._box('ftyp', _ascii('iso6')),
    ..._box('moov', [
      ..._box('trak', [
        ..._box('mdia', [
          ..._fullBox('mdhd', 0, 0, [..._u32(0), ..._u32(0), ..._u32(1000), ..._u32(0), 0, 0, 0, 0]),
        ]),
      ]),
      ..._box('mvex', [
        ..._fullBox('trex', 0, 0, [..._u32(1), ..._u32(1), ..._u32(0), ..._u32(0), ..._u32(0)]),
      ]),
    ]),
  ];

  final samples = [
    _box('vtte', []),
    _box('vttc', [
      ..._box('sttg', _ascii('align:center')),
      ..._box('payl', utf8.encode('Bueno. Sube.')),
    ]),
    _box('vttc', [..._box('payl', utf8.encode('Espera.'))]),
  ];
  const durations = [1000, 2500, 500];

  List<int> moof(int dataOffset) => _box('moof', [
    ..._fullBox('mfhd', 0, 0, _u32(1)),
    ..._box('traf', [
      // default-base-is-moof
      ..._fullBox('tfhd', 0, 0x020000, _u32(1)),
      ..._fullBox('tfdt', 0, 0, _u32(1000)),
      // data offset, then a duration and a size per sample
      ..._fullBox('trun', 0, 0x000301, [
        ..._u32(samples.length),
        ..._u32(dataOffset),
        for (final (i, sample) in samples.indexed) ...[..._u32(durations[i]), ..._u32(sample.length)],
      ]),
    ]),
  ]);

  // The offset counts from the start of the moof to the first sample, past the mdat header.
  final moofSize = moof(0).length;
  final segment = [
    ...moof(moofSize + 8),
    ..._box('mdat', [for (final sample in samples) ...sample]),
  ];

  return Uint8List.fromList([...init, ...segment]);
}

// endregion
