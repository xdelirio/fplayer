import 'package:flutter/material.dart';
import 'package:fplayer/fplayer.dart';

/// Offline downloads: enqueue, watch progress, pause, delete, and play what is on disk.
///
/// The point to notice is the last one — a completed download plays through the ordinary
/// `FPlayerSource.network`, because the cache is keyed by URI. Nothing at the playback call site
/// knows the bytes are local.
class DownloadsDemoPage extends StatefulWidget {
  const DownloadsDemoPage({super.key});

  @override
  State<DownloadsDemoPage> createState() => _DownloadsDemoPageState();
}

const _catalogue = <FPlayerSource>[
  FPlayerSource.network(
    'https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd',
    type: FSourceType.dash,
    title: 'Angel One',
    subtitle: 'DASH · multi-audio',
  ),
  FPlayerSource.network(
    'https://media.w3.org/2010/05/sintel/trailer.mp4',
    title: 'Sintel',
    subtitle: 'MP4 progresivo',
  ),
  FPlayerSource.network(
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
    'bipbop_16x9/bipbop_16x9_variant.m3u8',
    type: FSourceType.hls,
    title: 'BipBop',
    subtitle: 'HLS · 30 minutos',
  ),
];

class _DownloadsDemoPageState extends State<DownloadsDemoPage> {
  final FDownloadManager _downloads = FDownloadManager.instance;
  FPlayerController? _player;
  String? _status;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _downloads.initialize(
      const FDownloadConfig(
        maxParallelDownloads: 2,
        notification: FDownloadNotificationConfig(channelName: 'Descargas'),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _enqueue(FPlayerSource source) async {
    setState(() => _status = 'Leyendo el manifiesto de ${source.title}…');
    try {
      final options = await _downloads.inspect(source);
      await _downloads.enqueue(
        source,
        selection: const FDownloadSelection.standard(),
      );
      if (mounted) setState(() => _status = _describe(source, options));
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Falló: $e');
    }
  }

  String _describe(FPlayerSource source, FDownloadOptions options) {
    final best = options.video.isEmpty ? null : options.video.last;
    final size = best?.estimatedBytes;
    return '${source.title}: ${options.video.length} calidades, '
        '${options.audio.length} audios'
        '${size == null ? '' : ' · máx ~${_megabytes(size)}'}';
  }

  Future<void> _play(FDownloadItem item) async {
    await _player?.dispose();
    final player = FPlayerController(
      config: const FPlayerConfig(playback: FPlaybackConfig(autoPlay: true)),
    );
    setState(() => _player = player);
    // The same URI it was downloaded from: the cache answers, the network is never touched.
    await player.open(item.toSource());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Descargas')),
      body: ListenableBuilder(
        listenable: _downloads,
        builder: (context, _) {
          if (!_downloads.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            children: [
              if (_player != null)
                FPlayerView(
                  controller: _player!,
                  config: const FUiConfig(
                    localizations: FPlayerLocalizations.spanish(),
                  ),
                ),
              const _Heading('Catálogo'),
              for (final source in _catalogue)
                ListTile(
                  dense: true,
                  title: Text(source.title ?? source.uri),
                  subtitle: Text(source.subtitle ?? ''),
                  trailing: _CatalogueAction(
                    state: _downloads.stateOf(source),
                    onDownload: () => _enqueue(source),
                  ),
                ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    _status!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              const Divider(),
              _QueueHeading(downloads: _downloads),
              for (final item in _downloads.items)
                _QueueRow(
                  item: item,
                  onPause: () => _downloads.pause(item.id),
                  onResume: () => _downloads.resume(item.id),
                  onRemove: () => _downloads.remove(item.id),
                  onPlay: item.isPlayableOffline ? () => _play(item) : null,
                ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

class _CatalogueAction extends StatelessWidget {
  const _CatalogueAction({required this.state, required this.onDownload});

  final FDownloadState? state;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => switch (state) {
        null || FDownloadState.failed => IconButton(
            icon: const Icon(Icons.download),
            onPressed: onDownload,
          ),
        FDownloadState.completed => const Icon(Icons.download_done, color: Colors.green),
        _ => const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      };
}

class _QueueHeading extends StatelessWidget {
  const _QueueHeading({required this.downloads});

  final FDownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    final active = downloads.active.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              active == 0
                  ? 'Cola · ${downloads.items.length} · ${_megabytes(downloads.bytesOnDisk)} en disco'
                  : 'Cola · $active activas · '
                      '${(downloads.overallProgress * 100).round()}%',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          TextButton(onPressed: downloads.pauseAll, child: const Text('Pausar')),
          TextButton(onPressed: downloads.resumeAll, child: const Text('Seguir')),
          TextButton(onPressed: downloads.removeAll, child: const Text('Borrar')),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    required this.onPlay,
  });

  final FDownloadItem item;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final title = item.metadata['title'] as String? ?? item.uri;

    return ListTile(
      dense: true,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.state.name} · ${_megabytes(item.bytesDownloaded)}'
            '${item.contentLength == null ? '' : ' / ${_megabytes(item.contentLength!)}'}'
            '${item.error == null ? '' : ' · ${item.error!.code.name}'}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          if (item.state.isActive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: item.progress),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPlay != null)
            IconButton(icon: const Icon(Icons.play_arrow), onPressed: onPlay)
          else if (item.state == FDownloadState.paused || item.state == FDownloadState.failed)
            IconButton(icon: const Icon(Icons.play_circle_outline), onPressed: onResume)
          else
            IconButton(icon: const Icon(Icons.pause_circle_outline), onPressed: onPause),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      );
}

String _megabytes(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
