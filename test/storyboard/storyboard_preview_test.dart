import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/src/storyboard/storyboard.dart';
import 'package:fplayer/src/storyboard/storyboard_controller.dart';
import 'package:fplayer/src/storyboard/storyboard_preview.dart';

/// Exposes a pre-parsed index without going near the network.
class _FakeStoryboardController extends FStoryboardController {
  _FakeStoryboardController(this._storyboard);

  final FStoryboard _storyboard;

  @override
  FStoryboard get storyboard => _storyboard;

  @override
  FStoryboardFrame? frameAt(Duration position, {bool clamp = true}) =>
      _storyboard.frameAt(position, clamp: clamp);
}

FStoryboard _index() => FStoryboard.of([
      for (var i = 0; i < 4; i++)
        FStoryboardFrame(
          start: Duration(seconds: i * 5),
          end: Duration(seconds: i * 5 + 5),
          url: 'sheet.jpg',
          region: Rect.fromLTWH(i * 160.0, 0, 160, 90),
        ),
    ]);

void main() {
  testWidgets('shows the placeholder until a sheet is decoded', (tester) async {
    final controller = _FakeStoryboardController(_index());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FStoryboardPreview(
          controller: controller,
          position: const Duration(seconds: 7),
          placeholder: const Text('loading'),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
  });

  testWidgets('sizes itself from the frame region', (tester) async {
    final controller = _FakeStoryboardController(_index());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FStoryboardPreview(
            controller: controller,
            position: const Duration(seconds: 7),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(FStoryboardPreview));
    expect(size.width, 160);
    expect(size.height, closeTo(160 / (160 / 90), 0.01));
  });

  testWidgets('falls back to the given aspect ratio without a region', (tester) async {
    final controller = _FakeStoryboardController(
      FStoryboard.of([
        const FStoryboardFrame(
          start: Duration.zero,
          end: Duration(seconds: 5),
          url: 'thumb.jpg',
        ),
      ]),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FStoryboardPreview(
            controller: controller,
            position: Duration.zero,
            width: 200,
            fallbackAspectRatio: 2,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(FStoryboardPreview)), const Size(200, 100));
  });

  testWidgets('survives rapid position changes and unmounting', (tester) async {
    final controller = _FakeStoryboardController(_index());
    addTearDown(controller.dispose);

    for (var seconds = 0; seconds < 20; seconds++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FStoryboardPreview(
            controller: controller,
            position: Duration(seconds: seconds),
          ),
        ),
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing to crop when the index is empty', (tester) async {
    final controller = _FakeStoryboardController(const FStoryboard.empty());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FStoryboardPreview(
          controller: controller,
          position: const Duration(seconds: 3),
          placeholder: const Text('no storyboard'),
        ),
      ),
    );

    expect(find.text('no storyboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
