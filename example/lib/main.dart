import 'package:flutter/material.dart';
import 'package:fplayer/fplayer.dart';

import 'tv_demo.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'fplayer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE50914),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const DemoPage(),
      );
}

/// Host machine as seen from the Android emulator, for the local header-check server.
const _host = 'http://10.0.2.2:8099';

class _Demo {
  const _Demo(this.label, this.source, {this.queue = const []});

  final String label;
  final FPlayerSource source;

  /// When set, the entry loads a queue instead of a single source.
  final List<FPlayerSource> queue;
}

const _demos = <_Demo>[
  _Demo(
    'DASH · Angel One (audio en/es/de/fr + subs el/fr/en)',
    FPlayerSource.network(
      'https://cdn.tibibyte.com/bcdn_token=HS256-M_utLdACZHXC65Ltn1N_Tjn_iOAHY5dlVugDDqFb1P8&token_path=%2F01M060K2FGA3E5ZPB5SHVCGCAF%2Fplay%2F&expires=1786930619/01M060K2FGA3E5ZPB5SHVCGCAF/play/01M060QJ67AEWXVNTWMTPCRRQ0.mpd',
      type: FSourceType.dash,
      title: 'Angel One',
      subtitle: 'Muxed multi-audio and subtitles',
    storyboard: FStoryboardSource.vtt('https://cdn.tibibyte.com/01M060K2FGA3E5ZPB5SHVCGCAF/assets/storyboard.vtt')
    ),
  ),
  _Demo(
    'HLS · Tears of Steel (audio en/it, ultrawide)',
    FPlayerSource.network(
      'https://demo.unified-streaming.com/k8s/features/stable/video/'
      'tears-of-steel/tears-of-steel-multi-lang.ism/.m3u8',
      title: 'Tears of Steel',
      subtitle: 'Quality ladder, 224p to 1680×750',
    ),
  ),
  _Demo(
    'HLS · Apple bipbop (ABR)',
    FPlayerSource.network(
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
      'bipbop_16x9/bipbop_16x9_variant.m3u8',
      type: FSourceType.hls,
      title: 'BipBop',
      subtitle: 'Test pattern, 30 minutes',
    ),
  ),
  _Demo(
    'Local MP4 + external subtitle + storyboard',
    FPlayerSource.network(
      '$_host/sample.mp4',
      title: 'Header check',
      subtitle: 'The VTT receives only its own headers',
      headers: {
        'Authorization': 'Bearer media-token',
        'X-Fplayer-Media': 'yes',
      },
      subtitles: [
        FSubtitleSource.network(
          '$_host/demo-es.vtt',
          label: 'Spanish (external)',
          language: 'es',
          headers: {'X-Fplayer-Subtitle': 'yes'},
        ),
      ],
      storyboard: FStoryboardSource.vtt('$_host/storyboard.vtt'),
    ),
  ),
  _Demo(
    'Queue of 3 · autoplay + up-next card',
    FPlayerSource.network('https://media.w3.org/2010/05/sintel/trailer.mp4'),
    queue: [
      FPlayerSource.network(
        'https://media.w3.org/2010/05/sintel/trailer.mp4',
        title: 'Sintel',
        subtitle: 'Episode 1 of 3',
      ),
      // Deliberately not the w3.org bunny trailer: it is 853×480, and an odd frame width makes
      // MediaCodec fail to configure on the emulator even though it reports the format supported.
      FPlayerSource.network(
        'https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd',
        type: FSourceType.dash,
        title: 'Angel One',
        subtitle: 'Episode 2 of 3',
      ),
      FPlayerSource.network(
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
        'bipbop_16x9/bipbop_16x9_variant.m3u8',
        type: FSourceType.hls,
        title: 'BipBop',
        subtitle: 'Episode 3 of 3',
      ),
    ],
  ),
  _Demo(
    'Invalid URL (error path)',
    FPlayerSource.network(
      'https://example.com/does-not-exist.m3u8',
      title: 'Expected to fail',
    ),
  ),
];

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final FPlayerController _controller = FPlayerController(
    config: const FPlayerConfig(
      playback: FPlaybackConfig(
        autoPlay: true,
        preferredAudioLanguages: ['es', 'en'],
        preferredTextLanguages: ['es'],
      ),
      buffering: FBufferConfig.fastStart(),
      network: FNetworkConfig(
        loadingTimeout: Duration(seconds: 20),
        retry: FRetryPolicy(maxAttempts: 2),
      ),
      pip: FPipConfig(autoEnterOnLeave: true),
      background: FBackgroundConfig.audioInBackground(),
    ),
  );

  late final FPlaybackSessionTracker _tracker = FPlaybackSessionTracker(
    controller: _controller,
    progressInterval: const Duration(seconds: 10),
    observers: [_LoggingObserver()],
  );

  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    _tracker.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load(int index) async {
    setState(() => _selected = index);
    final demo = _demos[index];
    if (demo.queue.isNotEmpty) {
      await _controller.setPlaylist(demo.queue);
    } else {
      await _controller.open(demo.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (context) => const TvDemoPage()),
        ),
        icon: const Icon(Icons.tv),
        label: const Text('TV layout'),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          // The Picture-in-Picture window mirrors the whole Flutter tree, so everything but the
          // video steps aside while it is open.
          if (_controller.value.isPipActive) {
            return FPlayerView(controller: _controller, config: const FUiConfig.bare());
          }

          return SafeArea(
            child: ListView(
              children: [
                FPlayerView(
                  controller: _controller,
                  config: const FUiConfig(
                    localizations: FPlayerLocalizations(),
                    showFitButton: true,
                    showRemainingTime: true,
                  ),
                  onBack: () => debugPrint('[fplayer] back'),
                ),
                const Divider(height: 24),
                for (var i = 0; i < _demos.length; i++)
                  ListTile(
                    dense: true,
                    selected: i == _selected,
                    leading: Icon(
                      i == _selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(_demos[i].label),
                    onTap: () => _load(i),
                  ),
                const Divider(height: 24),
                _StatePanel(controller: _controller, metrics: _tracker.metrics),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Prints what an analytics backend would receive.
class _LoggingObserver extends FPlayerObserver {
  @override
  void onFirstFrame(FPlaybackMetrics metrics) =>
      debugPrint('[fplayer] first frame in ${metrics.timeToFirstFrame}');

  @override
  void onRebufferEnd(FPlaybackMetrics metrics, Duration stall) =>
      debugPrint('[fplayer] rebuffer #${metrics.rebufferCount} lasted $stall');

  @override
  void onSessionEnd(FPlaybackMetrics metrics, FSessionEndReason reason) => debugPrint(
        '[fplayer] session ${metrics.sessionId} ended (${reason.name}): '
        'watched ${metrics.watchedTime}, ${metrics.rebufferCount} rebuffers',
      );
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({required this.controller, required this.metrics});

  final FPlayerController controller;
  final FPlaybackMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final tracks = value.tracks;

    final rows = <String, String>{
      'status': value.status.name,
      'position': '${value.position} / ${value.duration}',
      'size': '${value.size.width.toInt()}×${value.size.height.toInt()}',
      'audio': '${tracks.audio.length} · ${tracks.selectedAudio?.displayName ?? "—"}',
      'text': '${tracks.text.length} · ${tracks.selectedText?.displayName ?? "off"}',
      'video': '${tracks.video.length} · '
          '${tracks.isVideoAuto ? "auto" : "fixed"} '
          '${tracks.activeVideo?.qualityLabel ?? "—"}',
      'cues': value.cues.isEmpty ? '—' : value.cues.map((c) => c.text).join(' | '),
      'queue': value.hasPlaylist
          ? '${value.currentIndex + 1}/${value.playlist.length} · next '
              '${value.nextInPlaylist?.title ?? "—"}'
          : '—',
      'network': value.isOnline ? 'online' : 'offline',
      'pip': 'supported ${value.isPipSupported} · active ${value.isPipActive}',
      'session': 'watched ${metrics?.watchedTime ?? "—"} · '
          'rebuffers ${metrics?.rebufferCount ?? "—"} · '
          'seeks ${metrics?.seekCount ?? "—"}',
      'error': value.error?.toString() ?? '—',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
