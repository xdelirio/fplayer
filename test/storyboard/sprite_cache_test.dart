import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

/// The sprite cache had no tests at all, which is how a `whenComplete` that waited on its own
/// future shipped: every first load of every sheet hung, so scrubbing thumbnails — the feature
/// this whole subsystem exists for — never showed anything the cache had not already been given.
///
/// These run under `runAsync` because decoding an image needs the real event loop.
void main() {
  late Directory dir;
  late String url;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('fplayer-sprites');
    final file = File('${dir.path}/sheet.png');
    await file.writeAsBytes(await _pngBytes(160, 90));
    url = file.path;
  });

  tearDownAll(() => dir.delete(recursive: true));

  testWidgets('a first load completes and hands out an image', (tester) async {
    final cache = FSpriteCache();
    addTearDown(cache.dispose);

    await tester.runAsync(() async {
      final image = await cache.load(url).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('load() never completed'),
          );

      expect(image, isNotNull);
      expect(image!.width, 160);
      expect(cache.length, 1);
      image.dispose();
    });
  });

  testWidgets('a burst of requests costs one fetch and every caller gets an image',
      (tester) async {
    final cache = FSpriteCache();
    addTearDown(cache.dispose);

    await tester.runAsync(() async {
      final images = await Future.wait([
        cache.load(url),
        cache.load(url),
        cache.load(url),
      ]).timeout(const Duration(seconds: 5));

      expect(images.every((image) => image != null), isTrue);
      expect(cache.length, 1, reason: 'one sheet, however many callers asked for it');
      for (final image in images) {
        image!.dispose();
      }
    });
  });

  testWidgets('an image handed out survives the cache dropping its own copy', (tester) async {
    // The ownership rule the whole design rests on: a clone keeps the pixels alive.
    final cache = FSpriteCache();

    await tester.runAsync(() async {
      final image = await cache.load(url).timeout(const Duration(seconds: 5));
      cache.dispose();

      expect(image, isNotNull);
      expect(() => image!.width, returnsNormally);
      image!.dispose();
    });
  });

  testWidgets('a sheet asked for twice does not double-count its bytes', (tester) async {
    final cache = FSpriteCache();
    addTearDown(cache.dispose);

    await tester.runAsync(() async {
      final first = await cache.load(url).timeout(const Duration(seconds: 5));
      final bytes = cache.usedBytes;
      first!.dispose();

      final second = await cache.load(url).timeout(const Duration(seconds: 5));
      second!.dispose();

      expect(cache.usedBytes, bytes);
    });
  });

  testWidgets('a sheet that cannot be fetched resolves to null rather than hanging',
      (tester) async {
    final cache = FSpriteCache();
    addTearDown(cache.dispose);

    await tester.runAsync(() async {
      final image = await cache
          .load('${dir.path}/missing.png')
          .timeout(const Duration(seconds: 5));

      expect(image, isNull);
      expect(cache.length, 0);
    });
  });
}

/// A real PNG, encoded through the engine so the test does not carry a binary blob.
Future<Uint8List> _pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366FF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}
