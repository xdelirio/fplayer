import 'package:flutter/widgets.dart';

/// Route used for the fullscreen player.
///
/// A plain fade rather than a platform page transition: the video is already on screen, and
/// sliding it in from the side reads as a different video appearing. Fading keeps the picture
/// continuous while the chrome around it changes.
class FFullscreenRoute<T> extends PageRouteBuilder<T> {
  FFullscreenRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          opaque: true,
          barrierColor: const Color(0xFF000000),
        );
}

/// Full-bleed black host for the fullscreen player.
///
/// Deliberately not a `Scaffold`: the package must not require a Material ancestor, and there is
/// nothing here a Scaffold would contribute.
class FFullscreenPage extends StatelessWidget {
  const FFullscreenPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF000000),
        child: Center(child: child),
      );
}
