import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fplayer/fplayer.dart';

import 'fake_engine.dart';
import 'pump_player.dart';

/// Mounts a bare [FVideoSurface] at a known size.
Future<void> pumpSurface(
  WidgetTester tester, {
  required FPlayerController controller,
  FVideoFit fit = FVideoFit.contain,
  Size size = const Size(800, 400),
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: FVideoSurface(controller: controller, fit: fit),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late FakeEngine engine;
  late FPlayerController controller;

  setUp(() {
    engine = FakeEngine();
    controller = quietController(engine);
  });

  tearDown(() => controller.dispose());

  group('texture path', () {
    testWidgets('renders the texture the engine handed out', (tester) async {
      await controller.initialize();
      engine.becomeReady();
      await pumpSurface(tester, controller: controller);

      expect(find.byType(Texture), findsOneWidget);
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 42);
      expect(find.byType(PlatformViewLink), findsNothing);
    });

    testWidgets('renders nothing before the engine exists', (tester) async {
      await pumpSurface(tester, controller: controller);

      expect(find.byType(Texture), findsNothing);
      expect(find.byType(PlatformViewLink), findsNothing);
    });
  });

  group('platform view path', () {
    // Answering `create` with null is what hybrid composition gets back on a device: the view
    // lives in the native hierarchy, so there is no texture id to hand over.
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });

    Future<void> readyOnPlatformView(
      WidgetTester tester, {
      FVideoFit fit = FVideoFit.contain,
      Size size = const Size(800, 400),
    }) async {
      engine
        ..textureIdOverride = null
        ..platformViewIdOverride = 7;
      await controller.initialize();
      engine.becomeReady();
      await pumpSurface(tester, controller: controller, fit: fit, size: size);
    }

    testWidgets('mounts a platform view instead of a texture', (tester) async {
      await readyOnPlatformView(tester);

      expect(find.byType(PlatformViewLink), findsOneWidget);
      expect(find.byType(Texture), findsNothing);
    });

    testWidgets('is kept out of focus traversal', (tester) async {
      // The video is output, never a destination. `PlatformViewLink` puts a focus node around
      // the view, and on a remote that node joined the traversal ring: pressing down walked
      // focus off the chrome into something invisible with nothing to activate, which reads as
      // the controls having seized up.
      await readyOnPlatformView(tester);

      expect(
        find.ancestor(
          of: find.byType(PlatformViewLink),
          matching: find.byType(ExcludeFocus),
        ),
        findsOneWidget,
      );

      final scope = FocusScope.of(tester.element(find.byType(FVideoSurface)));
      expect(scope.traversalDescendants, isEmpty);
    });

    testWidgets('sizes the view itself rather than scaling it', (tester) async {
      // A 16:9 frame in an 800×400 box: `contain` gives 711.1×400, and the platform view has to
      // be laid out at that size. Handing it a unit box and a transform — what the texture path
      // does — would leave the SurfaceView with a buffer a couple of pixels wide.
      await readyOnPlatformView(tester);

      final size = tester.getSize(find.byType(PlatformViewLink));
      expect(size.height, moreOrLessEquals(400, epsilon: 0.01));
      expect(size.width, moreOrLessEquals(400 * 16 / 9, epsilon: 0.01));
    });

    testWidgets('cover overflows the box and is clipped', (tester) async {
      await readyOnPlatformView(tester, fit: FVideoFit.cover);

      final size = tester.getSize(find.byType(PlatformViewLink));
      expect(size.width, moreOrLessEquals(800, epsilon: 0.01));
      expect(size.height, moreOrLessEquals(800 * 9 / 16, epsilon: 0.01));
      expect(find.byType(ClipRect), findsWidgets);
    });

    testWidgets('fill takes the whole box', (tester) async {
      await readyOnPlatformView(tester, fit: FVideoFit.fill);

      expect(tester.getSize(find.byType(PlatformViewLink)), const Size(800, 400));
    });
  });
}
