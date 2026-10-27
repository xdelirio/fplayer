import 'dart:convert' show utf8;
import 'dart:typed_data';

/// Turns WebVTT carried in fragmented MP4 (`wvtt`, ISO/IEC 14496-30) back into a WebVTT file.
///
/// DASH packagers put subtitles in MP4 segments, and neither the FFmpeg that media_kit ships nor
/// any later one reads `wvtt` samples, so mpv never lists them. mpv does read WebVTT text, so the
/// segments are converted here and handed over as a file.
///
/// [bytes] is the initialization segment followed by the media segments, in order — or a whole
/// single-file track, which is the same thing. Returns null when no cue could be read.
String? wvttToWebVtt(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var timescale = 1000;
  var trexDuration = 0;
  final cues = <_Cue>[];

  void walk(int start, int end, void Function(String type, int body, int end, int boxStart) on) {
    var offset = start;
    while (offset + 8 <= end) {
      var size = data.getUint32(offset);
      final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
      var header = 8;
      if (size == 1) {
        if (offset + 16 > end) return;
        size = data.getUint64(offset + 8);
        header = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < header || offset + size > end) return;
      on(type, offset + header, offset + size, offset);
      offset += size;
    }
  }

  void readFragment(int moofStart, int moofEnd) {
    walk(moofStart + 8, moofEnd, (type, body, end, _) {
      if (type != 'traf') return;
      int? baseDataOffset;
      var defaultDuration = trexDuration;
      var defaultSize = 0;
      var decodeTime = 0;
      final runs = <int>[];

      walk(body, end, (type, body, end, boxStart) {
        final flags = data.getUint32(body) & 0xffffff;
        final version = bytes[body];
        switch (type) {
          case 'tfhd':
            var p = body + 8; // version/flags and track id
            if (flags & 0x01 != 0) {
              baseDataOffset = data.getUint64(p);
              p += 8;
            }
            if (flags & 0x02 != 0) p += 4;
            if (flags & 0x08 != 0) {
              defaultDuration = data.getUint32(p);
              p += 4;
            }
            if (flags & 0x10 != 0) defaultSize = data.getUint32(p);
          case 'tfdt':
            decodeTime = version == 1 ? data.getUint64(body + 4) : data.getUint32(body + 4);
          case 'trun':
            runs.add(boxStart);
        }
      });

      // Sample data is addressed from the start of the fragment unless the track says otherwise:
      // what `default-base-is-moof` asks for, and what every DASH packager writes.
      final base = baseDataOffset ?? moofStart;
      var time = decodeTime;
      for (final run in runs) {
        final body = run + 8;
        final flags = data.getUint32(body) & 0xffffff;
        final count = data.getUint32(body + 4);
        var p = body + 8;
        var dataOffset = moofEnd + 8;
        if (flags & 0x01 != 0) {
          dataOffset = base + data.getInt32(p);
          p += 4;
        }
        if (flags & 0x04 != 0) p += 4;

        for (var i = 0; i < count; i++) {
          var duration = defaultDuration;
          var size = defaultSize;
          if (flags & 0x100 != 0) {
            duration = data.getUint32(p);
            p += 4;
          }
          if (flags & 0x200 != 0) {
            size = data.getUint32(p);
            p += 4;
          }
          if (flags & 0x400 != 0) p += 4;
          if (flags & 0x800 != 0) p += 4;

          if (dataOffset + size <= bytes.length) {
            _readSample(bytes, dataOffset, dataOffset + size, walk, (cue) {
              cues.add(
                _Cue(
                  start: time * 1000 ~/ timescale,
                  end: (time + duration) * 1000 ~/ timescale,
                  id: cue.id,
                  settings: cue.settings,
                  text: cue.text,
                ),
              );
            });
          }
          dataOffset += size;
          time += duration;
        }
      }
    });
  }

  void readMovie(int start, int end) {
    walk(start, end, (type, body, end, _) {
      switch (type) {
        case 'trak' || 'mdia' || 'mvex':
          readMovie(body, end);
        case 'mdhd':
          final version = bytes[body];
          timescale = data.getUint32(body + (version == 1 ? 20 : 12));
        case 'trex':
          trexDuration = data.getUint32(body + 12);
      }
    });
  }

  walk(0, bytes.length, (type, body, end, boxStart) {
    switch (type) {
      case 'moov':
        readMovie(body, end);
      case 'moof':
        readFragment(boxStart, end);
    }
  });

  if (timescale <= 0 || cues.isEmpty) return null;

  final out = StringBuffer('WEBVTT\n\n');
  for (final cue in cues) {
    if (cue.id.isNotEmpty) out.writeln(cue.id);
    out.write('${_timestamp(cue.start)} --> ${_timestamp(cue.end)}');
    if (cue.settings.isNotEmpty) out.write(' ${cue.settings}');
    out
      ..writeln()
      ..writeln(cue.text)
      ..writeln();
  }
  return out.toString();
}

/// The cues in one sample: one per `vttc` box. A `vtte` box is a gap with nothing on screen.
void _readSample(
  Uint8List bytes,
  int start,
  int end,
  void Function(int, int, void Function(String, int, int, int)) walk,
  void Function(({String id, String settings, String text})) onCue,
) {
  walk(start, end, (type, body, end, _) {
    if (type != 'vttc') return;
    var id = '';
    var settings = '';
    var text = '';
    walk(body, end, (type, body, end, _) {
      final value = utf8.decode(bytes.sublist(body, end), allowMalformed: true);
      switch (type) {
        case 'iden':
          id = value;
        case 'sttg':
          settings = value;
        case 'payl':
          text = value;
      }
    });
    if (text.trim().isNotEmpty) onCue((id: id, settings: settings, text: text.trimRight()));
  });
}

String _timestamp(int ms) {
  final h = ms ~/ 3600000;
  final m = ms ~/ 60000 % 60;
  final s = ms ~/ 1000 % 60;
  final f = ms % 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}.${f.toString().padLeft(3, '0')}';
}

class _Cue {
  const _Cue({
    required this.start,
    required this.end,
    required this.id,
    required this.settings,
    required this.text,
  });

  final int start;
  final int end;
  final String id;
  final String settings;
  final String text;
}
