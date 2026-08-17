import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/track.dart';
import '../player_scope.dart';
import '../theme.dart';
import '../time_format.dart';
import 'focus_highlight.dart';

/// Track and speed picker, shown as a panel over the video.
///
/// A side panel rather than a modal bottom sheet: it keeps the picture visible while you compare
/// options, it needs no Navigator or Material ancestor, and it is the layout a remote can already
/// walk — the same widget serves the TV build.
class FSettingsPanel extends StatefulWidget {
  const FSettingsPanel({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  State<FSettingsPanel> createState() => _FSettingsPanelState();
}

enum _Section { root, audio, subtitles, quality, speed }

class _FSettingsPanelState extends State<FSettingsPanel> {
  _Section _section = _Section.root;

  FPlayerUi get _ui => widget.ui;

  @override
  Widget build(BuildContext context) {
    final theme = _ui.theme;

    return Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        child: Container(
          width: 300,
          margin: EdgeInsets.all(theme.spacing),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: theme.borderRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                ui: _ui,
                title: _titleFor(_section),
                onBack: _section == _Section.root
                    ? null
                    : () => setState(() => _section = _Section.root),
                onClose: _ui.closeSettings,
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _rowsFor(_section),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        _Section.audio => _audioRows(),
        _Section.subtitles => _subtitleRows(),
        _Section.quality => _qualityRows(),
        _Section.speed => _speedRows(),
      };

  List<Widget> _rootRows() {
    final l10n = _ui.localizations;
    final tracks = _ui.controller.tracks;

    return [
      if (tracks.audio.length > 1)
        _Row(
          ui: _ui,
          icon: Icons.multitrack_audio,
          label: l10n.audio,
          value: tracks.selectedAudio?.displayName ?? l10n.auto,
          hasChildren: true,
          onTap: () => setState(() => _section = _Section.audio),
        ),
      if (tracks.hasSubtitles)
        _Row(
          ui: _ui,
          icon: Icons.subtitles,
          label: l10n.subtitles,
          value: tracks.selectedText?.displayName ?? l10n.off,
          hasChildren: true,
          onTap: () => setState(() => _section = _Section.subtitles),
        ),
      if (tracks.hasMultipleQualities)
        _Row(
          ui: _ui,
          icon: Icons.high_quality,
          label: l10n.quality,
          value: tracks.isVideoAuto
              ? '${l10n.auto}${tracks.activeVideo?.qualityLabel != null ? ' · ${tracks.activeVideo!.qualityLabel}' : ''}'
              : tracks.selectedVideo?.displayName ?? l10n.auto,
          hasChildren: true,
          onTap: () => setState(() => _section = _Section.quality),
        ),
      _Row(
        ui: _ui,
        icon: Icons.speed,
        label: l10n.speed,
        value: _ui.controller.speed == 1.0
            ? l10n.normal
            : formatPlaybackSpeed(_ui.controller.speed),
        hasChildren: true,
        onTap: () => setState(() => _section = _Section.speed),
      ),
    ];
  }

  List<Widget> _audioRows() {
    final tracks = _ui.controller.tracks;
    return [
      for (final track in tracks.audio)
        _Row(
          ui: _ui,
          label: _audioLabel(track),
          isSelected: track.isActive,
          isEnabled: track.isSupported,
          onTap: () {
            _ui.controller.selectAudioTrack(track);
            _ui.closeSettings();
          },
        ),
    ];
  }

  String _audioLabel(FAudioTrack track) => [
        track.displayName,
        if (track.channelLabel != null) track.channelLabel!,
        if (track.isDescriptive) 'AD',
      ].join(' · ');

  List<Widget> _subtitleRows() {
    final tracks = _ui.controller.tracks;
    return [
      _Row(
        ui: _ui,
        label: _ui.localizations.off,
        isSelected: tracks.selectedText == null,
        onTap: () {
          _ui.controller.disableSubtitles();
          _ui.closeSettings();
        },
      ),
      for (final track in tracks.text)
        _Row(
          ui: _ui,
          label: [
            track.displayName,
            if (track.isForced) 'forced',
            if (track.isClosedCaption) 'CC',
          ].join(' · '),
          isSelected: tracks.selectedText?.id == track.id,
          isEnabled: track.isSupported,
          onTap: () {
            _ui.controller.selectTextTrack(track);
            _ui.closeSettings();
          },
        ),
    ];
  }

  List<Widget> _qualityRows() {
    final tracks = _ui.controller.tracks;
    final l10n = _ui.localizations;

    return [
      _Row(
        ui: _ui,
        label: l10n.auto,
        value: tracks.isVideoAuto ? tracks.activeVideo?.qualityLabel : null,
        isSelected: tracks.isVideoAuto,
        onTap: () {
          _ui.controller.enableAutoQuality();
          _ui.closeSettings();
        },
      ),
      // Highest first: a viewer opening this menu is usually reaching for more quality, not less.
      for (final track in tracks.video.toList().reversed)
        _Row(
          ui: _ui,
          label: track.qualityLabel ?? track.displayName,
          value: track.bitrate == null ? null : '${(track.bitrate! / 1000).round()} kbps',
          isSelected: tracks.selectedVideo?.id == track.id,
          isEnabled: track.isSupported,
          onTap: () {
            _ui.controller.selectVideoTrack(track);
            _ui.closeSettings();
          },
        ),
    ];
  }

  List<Widget> _speedRows() => [
        for (final speed in _ui.config.speeds)
          _Row(
            ui: _ui,
            label: speed == 1.0 ? _ui.localizations.normal : formatPlaybackSpeed(speed),
            isSelected: (_ui.controller.speed - speed).abs() < 0.01,
            onTap: () {
              _ui.controller.setSpeed(speed);
              _ui.closeSettings();
            },
          ),
      ];
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ui,
    required this.title,
    required this.onBack,
    required this.onClose,
  });

  final FPlayerUi ui;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: theme.spacing, vertical: theme.spacing / 2),
      child: Row(
        children: [
          if (onBack != null)
            _IconTap(theme: theme, icon: Icons.arrow_back, onTap: onBack!)
          else
            SizedBox(width: theme.spacing),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing / 2),
              child: Text(
                title,
                style: theme.titleStyle.copyWith(color: theme.foreground),
              ),
            ),
          ),
          _IconTap(theme: theme, icon: Icons.close, onTap: onClose),
        ],
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.theme, required this.icon, required this.onTap});

  final FPlayerTheme theme;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(theme.spacing / 2),
          child: Icon(icon, size: theme.iconSize, color: theme.foreground),
        ),
      );
}

class _Row extends StatefulWidget {
  const _Row({
    required this.ui,
    required this.label,
    required this.onTap,
    this.icon,
    this.value,
    this.isSelected = false,
    this.hasChildren = false,
    this.isEnabled = true,
  });

  final FPlayerUi ui;
  final IconData? icon;
  final String label;
  final String? value;
  final bool isSelected;
  final bool hasChildren;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> with FFocusHighlight {

  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;
    final color = widget.isEnabled ? theme.foreground : theme.disabledForeground;

    return Focus(
      canRequestFocus: widget.isEnabled,
      onFocusChange: onFocusChanged,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.isEnabled ? widget.onTap : null,
        child: Container(
          color: showsFocusRing
              ? theme.accent.withValues(alpha: 0.22)
              : const Color(0x00000000),
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing * 1.5,
            vertical: theme.spacing * 1.25,
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: theme.iconSize, color: color),
                SizedBox(width: theme.spacing),
              ] else if (widget.isSelected) ...[
                Icon(Icons.check, size: theme.iconSize, color: theme.accent),
                SizedBox(width: theme.spacing),
              ] else
                SizedBox(width: theme.iconSize + theme.spacing),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.labelStyle.copyWith(
                    color: widget.isSelected ? theme.accent : color,
                  ),
                ),
              ),
              if (widget.value != null)
                Padding(
                  padding: EdgeInsets.only(left: theme.spacing),
                  child: Text(
                    widget.value!,
                    style: theme.subtitleStyle.copyWith(color: theme.mutedForeground),
                  ),
                ),
              if (widget.hasChildren)
                Icon(Icons.chevron_right, size: theme.iconSize, color: theme.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
