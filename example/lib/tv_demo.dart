import 'package:flutter/material.dart';
import 'package:fplayer/fplayer.dart';

/// The leanback layout, full screen, driven entirely by a remote.
///
/// This is what `FUiConfig.tv()` is for: the controls come up on the first press, the seek bar
/// takes focus and left/right scrub while it holds it, everything else walks the controls, and
/// the settings panel carries what the bottom row does not.
class TvDemoPage extends StatefulWidget {
  const TvDemoPage({super.key});

  @override
  State<TvDemoPage> createState() => _TvDemoPageState();
}

class _TvDemoPageState extends State<TvDemoPage> {
  late final FPlayerController _controller = FPlayerController(
    config: const FPlayerConfig(
      playback: FPlaybackConfig(autoPlay: true, seekStep: Duration(seconds: 10)),
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.open(
      const FPlayerSource.network(
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
        'bipbop_16x9/bipbop_16x9_variant.m3u8',
        type: FSourceType.hls,
        title: 'BipBop',
        subtitle: 'Leanback layout · drive it with the D-pad',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FPlayerView(
            controller: _controller,
            // The preset: remote-first from the first frame, no touch gestures, larger chrome,
            // and the settings panel instead of a row of small targets.
            config: FUiConfig.tv(),
            // Already filling the screen, so the fullscreen route would be a second copy of the
            // same thing.
            isFullscreen: true,
          ),
        ),
      );
}
