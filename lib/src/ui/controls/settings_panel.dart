import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/track.dart';
import '../player_scope.dart';
import '../theme.dart';
import '../time_format.dart';
import 'focus_highlight.dart';
import 'panel_chrome.dart';

/// Everything the player can be told to do, in one sheet.
///
/// On touch the bottom bar carries dedicated buttons and this panel is off; it earns its place on
/// a remote, where a row of small targets is worse to walk than one list. `FUiConfig.tv()` turns
/// it back on for that reason.
class FSettingsPanel extends StatefulWidget {
  const FSettingsPanel({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  State<FSettingsPanel> createState() => _FSettingsPanelState();
}

enum _Section { root, audio, subtitles, quality, speed }

class _FSettingsPanelState extends State<FSettingsPanel> {
  _Section _section = _Section.root;

  /// Which way the next section slides in from, so going deeper and coming back feel different.
  bool _isDescending = true;

  FPlayerUi get _ui => widget.ui;

  void _open(_Section section) => setState(() {
        _isDescending = true;
        _section = section;
      });

  void _back() => setState(() {
        _isDescending = false;
        _section = _Section.root;
      });

  @override
  Widget build(BuildContext context) {
    final theme = _ui.theme;

    return Stack(
      fit: StackFit.expand,
      children: [
        FPanelScrim(theme: theme, onTap: _ui.closeSettings),
        Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(theme.spacing),
              child: FPanelEnterTransition(
                slideFrom: const Offset(28, 0),
                child: FPanelSheet(theme: theme, child: _content(theme)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(FPlayerTheme theme) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FPanelHeader(
            theme: theme,
            title: _titleFor(_section),
            onBack: _section == _Section.root ? null : _back,
            onClose: _ui.closeSettings,
          ),
          FPanelDivider(theme: theme),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: theme.spacing * 0.75),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _SectionTransition(
                  // A new key restarts the animation, so each section slides in on arrival.
                  key: ValueKey(_section),
                  from: _isDescending ? 24 : -24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _rowsFor(_section),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  String _titleFor(_Section section) {
    final l10n = _ui.localizations;
    return switch (section) {
      _Section.root => l10n.settings,
      _Section.audio => l10n.audio,
      _Section.subtitles => l10n.subtitles,
      _Section.quality => l10n.quality,
      _Section.speed => l10n.speed,
    };
  }

  List<Widget> _rowsFor(_Section section) => switch (section) {
        _Section.root => _rootRows(),
        _Section.audio => audioRows(_ui),
        _Section.subtitles => subtitleRows(_ui),
        _Section.quality => qualityRows(_ui),
        _Section.speed => _speedRows(),
      };

  List<Widget> _rootRows() {
    final l10n = _ui.localizations;
    final tracks = _ui.controller.tracks;

    return [
      if (tracks.audio.length > 1)
        _NavRow(
          ui: _ui,
          icon: Icons.multitrack_audio,
          label: l10n.audio,
          value: tracks.selectedAudio?.displayName ?? l10n.auto,
          onTap: () => _open(_Section.audio),
        ),
      if (tracks.hasSubtitles)
        _NavRow(
          ui: _ui,
          icon: Icons.subtitles_outlined,
          label: l10n.subtitles,
          value: tracks.selectedText?.displayName ?? l10n.off,
          onTap: () => _open(_Section.subtitles),
        ),
      if (tracks.hasMultipleQualities)
        _NavRow(
          ui: _ui,
          icon: Icons.high_quality_outlined,
          label: l10n.quality,
          value: qualitySummary(_ui),
          onTap: () => _open(_Section.quality),
        ),
      _NavRow(
        ui: _ui,
        icon: Icons.speed_outlined,
        label: l10n.speed,
        value: _ui.controller.speed == 1.0
            ? l10n.normal
            : formatPlaybackSpeed(_ui.controller.speed),
        onTap: () => _open(_Section.speed),
      ),
    ];
  }

  List<Widget> _speedRows() {
    final theme = _ui.theme;

    // Chips rather than a list: the values are short, the set is small, and seeing them side by
    // side is the whole point — 1.5× means little without 1.25× and 2× next to it.
    return [
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing * 1.5,
          vertical: theme.spacing,
        ),
        child: Wrap(
          spacing: theme.spacing,
          runSpacing: theme.spacing,
          children: [
            for (final speed in _ui.config.speeds)
              FSpeedChip(
                ui: _ui,
                label: speed == 1.0
                    ? _ui.localizations.normal
                    : formatPlaybackSpeed(speed),
                isSelected: (_ui.controller.speed - speed).abs() < 0.01,
                onTap: () {
                  _ui.controller.setSpeed(speed);
                  _ui.closeSettings();
                },
              ),
          ],
        ),
      ),
    ];
  }
}

/// A choice a list holds instead of pushing to the player.
///
/// The settings panel has no use for this: it walks one axis at a time, so a tap there is a whole
/// decision and the panel closes on it. The track dialog puts audio and subtitles side by side
/// precisely because they are chosen together, so it stages both and applies them on the way out.
@immutable
class FTrackStaging {
  const FTrackStaging({required this.selectedId, required this.onSelect});

  /// Id of the row that reads as chosen. Null is the "Off" row for subtitles.
  final String? selectedId;

  /// Called with the chosen track's id, or null for "Off". Nothing reaches the player.
  final ValueChanged<String?> onSelect;
}

/// The audio choices, as rows. Shared with the track dialog so the two cannot disagree.
///
/// [staging] turns the list from one that acts into one that only records; without it a tap
/// selects the track and runs [onSelected], defaulting to closing the settings panel.
List<Widget> audioRows(FPlayerUi ui, {VoidCallback? onSelected, FTrackStaging? staging}) {
  final tracks = ui.controller.tracks;
  return [
    for (final track in tracks.audio)
      FPanelOptionRow(
        ui: ui,
        label: track.displayName,
        detail: [
          if (track.channelLabel != null) track.channelLabel!,
          if (track.isDescriptive) 'AD',
        ].join(' · '),
        isSelected: staging == null ? track.isActive : staging.selectedId == track.id,
        isEnabled: track.isSupported,
        onTap: () {
          if (staging != null) {
            staging.onSelect(track.id);
            return;
          }
          ui.controller.selectAudioTrack(track);
          (onSelected ?? ui.closeSettings)();
        },
      ),
  ];
}

/// The subtitle choices, as rows, with "Off" first. See [audioRows] for [staging].
List<Widget> subtitleRows(FPlayerUi ui, {VoidCallback? onSelected, FTrackStaging? staging}) {
  final tracks = ui.controller.tracks;
  return [
    FPanelOptionRow(
      ui: ui,
      label: ui.localizations.off,
      isSelected: staging == null ? tracks.selectedText == null : staging.selectedId == null,
      onTap: () {
        if (staging != null) {
          staging.onSelect(null);
          return;
        }
        ui.controller.disableSubtitles();
        (onSelected ?? ui.closeSettings)();
      },
    ),
    for (final track in tracks.text)
      FPanelOptionRow(
        ui: ui,
        label: track.displayName,
        badge: track.isClosedCaption ? 'CC' : null,
        detail: track.isForced ? 'forced' : '',
        isSelected:
            staging == null ? tracks.selectedText?.id == track.id : staging.selectedId == track.id,
        isEnabled: track.isSupported,
        onTap: () {
          if (staging != null) {
            staging.onSelect(track.id);
            return;
          }
          ui.controller.selectTextTrack(track);
          (onSelected ?? ui.closeSettings)();
        },
      ),
  ];
}

/// The quality rungs, as rows.
///
/// [showBitrate] overrides `FUiConfig.showQualityBitrate` for this one list. The number is
/// genuinely useful to someone watching their data and noise to everyone else, which is why it is
/// a choice rather than a default either way.
List<Widget> qualityRows(FPlayerUi ui, {VoidCallback? onSelected, bool? showBitrate}) {
  final tracks = ui.controller.tracks;
  final selected = tracks.selectedVideo;
  final withBitrate = showBitrate ?? ui.config.showQualityBitrate;

  return [
    FPanelOptionRow(
      ui: ui,
      label: ui.localizations.auto,
      detail: tracks.isVideoAuto ? tracks.activeVideo?.qualityLabel ?? '' : '',
      isSelected: tracks.isVideoAuto,
      onTap: () {
        ui.controller.enableAutoQuality();
        (onSelected ?? ui.closeSettings)();
      },
    ),
    for (final track in distinctQualityRungs(tracks.video))
      FPanelOptionRow(
        ui: ui,
        label: track.qualityLabel ?? track.displayName,
        badge: qualityBadge(track),
        detail: !withBitrate || track.bitrate == null
            ? ''
            : '${(track.bitrate! / 1000).round()} kbps',
        // A rung stands for every rendition of that size, so the pinned one lights up even when
        // it is one of the duplicates that was collapsed away.
        isSelected: selected != null &&
            (selected.id == track.id ||
                (selected.qualityLabel != null &&
                    selected.qualityLabel == track.qualityLabel)),
        isEnabled: track.isSupported,
        onTap: () {
          ui.controller.selectVideoTrack(track);
          (onSelected ?? ui.closeSettings)();
        },
      ),
  ];
}

/// One row per rung, highest first.
///
/// Manifests routinely carry several renditions of the same size — a second codec, a second
/// bitrate ladder — and a menu that lists `1080p` three times asks the viewer a question they
/// cannot answer. Each size keeps its best rendition, which is the one anyone picking that size
/// meant. Renditions with no readable size are left alone rather than merged.
List<FVideoTrack> distinctQualityRungs(List<FVideoTrack> video) {
  final best = <String, FVideoTrack>{};

  for (final track in video) {
    final key = track.qualityLabel ?? track.id;
    final current = best[key];
    if (current == null || (track.bitrate ?? 0) > (current.bitrate ?? 0)) {
      best[key] = track;
    }
  }

  // Highest first: a viewer opening this menu is usually reaching for more quality, not less.
  return best.values.toList()
    ..sort((a, b) {
      final size = (b.height ?? 0).compareTo(a.height ?? 0);
      return size != 0 ? size : (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
}

/// The shorthand people read off a quality menu, when the rung earns one.
String? qualityBadge(FVideoTrack track) {
  final height = track.height;
  if (height == null) return null;
  if (height >= 2000) return '4K';
  if (height >= 700) return 'HD';
  return null;
}

/// What the quality control says without being opened: `Auto · 1080p`, or the pinned rung.
String qualitySummary(FPlayerUi ui) {
  final tracks = ui.controller.tracks;
  final l10n = ui.localizations;

  if (!tracks.isVideoAuto) {
    return tracks.selectedVideo?.qualityLabel ??
        tracks.selectedVideo?.displayName ??
        l10n.auto;
  }
  final active = tracks.activeVideo?.qualityLabel;
  return active == null ? l10n.auto : '${l10n.auto} · $active';
}

/// A playback speed, as a pill.
class FSpeedChip extends StatefulWidget {
  const FSpeedChip({
    required this.ui,
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final FPlayerUi ui;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<FSpeedChip> createState() => _FSpeedChipState();
}

class _FSpeedChipState extends State<FSpeedChip> with FFocusHighlight {
  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;

    return focusable(
      onActivate: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing * 1.75,
            vertical: theme.spacing * 0.9,
          ),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.accent
                : theme.foreground.withValues(alpha: showsFocusRing ? 0.22 : 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: showsFocusRing && !widget.isSelected
                  ? theme.accent
                  : const Color(0x00000000),
              width: 1.5,
            ),
          ),
          child: Text(
            widget.label,
            style: theme.labelStyle.copyWith(
              color: theme.foreground,
              fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// A root entry: what it changes, what it is set to now, and a way in.
class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.ui,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final FPlayerUi ui;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> with FFocusHighlight {
  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;
    final tile = theme.iconSize * 1.9;

    return focusable(
      onActivate: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: FPanelRowSurface(
          theme: theme,
          isHighlighted: showsFocusRing,
          child: Row(
            children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: theme.foreground.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(theme.spacing * 1.25),
                ),
                child: Icon(widget.icon, size: theme.iconSize * 0.9, color: theme.foreground),
              ),
              SizedBox(width: theme.spacing * 1.25),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.labelStyle.copyWith(color: theme.foreground),
                    ),
                    SizedBox(height: theme.spacing * 0.25),
                    Text(
                      widget.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.subtitleStyle.copyWith(color: theme.mutedForeground),
                    ),
                  ],
                ),
              ),
              SizedBox(width: theme.spacing),
              Icon(Icons.chevron_right, size: theme.iconSize, color: theme.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides a section in from [from] pixels away.
///
/// Deliberately not an `AnimatedSwitcher`: only one section is ever in the tree, so a row can
/// never be found twice while the transition runs.
class _SectionTransition extends StatelessWidget {
  const _SectionTransition({required this.from, required this.child, super.key});

  final double from;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(from * (1 - t), 0), child: child),
        ),
        child: child,
      );
}
