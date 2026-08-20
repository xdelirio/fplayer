import 'package:flutter/widgets.dart';

import '../player_scope.dart';
import '../theme.dart';
import '../time_format.dart';
import 'panel_chrome.dart';
import 'settings_panel.dart';

/// Audio and subtitles, side by side.
///
/// One dialog rather than two menus because the decision is one decision: Japanese audio with
/// English subtitles is chosen in a single glance, not in two trips through a nested menu. Below
/// [_twoColumnWidth] the columns stack, which is the same content in the shape that fits.
///
/// And nothing is applied until it is confirmed. A dialog that closed on the first row tapped
/// undid its own premise — the viewer who came to change both had to open it twice, and the
/// second trip re-selected the track they had just picked. Choices are held here and pushed to
/// the player together; leaving any other way discards them.
class FTrackDialog extends StatefulWidget {
  const FTrackDialog({required this.ui, super.key});

  static const _twoColumnWidth = 520.0;

  final FPlayerUi ui;

  @override
  State<FTrackDialog> createState() => _FTrackDialogState();
}

class _FTrackDialogState extends State<FTrackDialog> {
  /// Chosen but not yet applied. Null text means "Off", which is a real choice rather than an
  /// absent one, so the two are not collapsed into a single nullable selection.
  String? _audioId;
  String? _textId;

  FPlayerUi get _ui => widget.ui;

  @override
  void initState() {
    super.initState();
    final tracks = _ui.controller.tracks;
    _audioId = tracks.selectedAudio?.id;
    _textId = tracks.selectedText?.id;
  }

  /// Pushes only what actually moved.
  ///
  /// Re-selecting the track that is already playing is not free — it goes to the engine, which
  /// reconfigures the selection and can rebuffer — so a viewer who opened the dialog, changed
  /// subtitles and pressed Apply must not have their audio track re-picked underneath them.
  void _apply() {
    final controller = _ui.controller;
    final tracks = controller.tracks;

    final audioId = _audioId;
    if (audioId != null && audioId != tracks.selectedAudio?.id) {
      final track = tracks.audio.where((t) => t.id == audioId).firstOrNull;
      if (track != null) controller.selectAudioTrack(track);
    }

    final textId = _textId;
    if (textId != tracks.selectedText?.id) {
      if (textId == null) {
        controller.disableSubtitles();
      } else {
        final track = tracks.text.where((t) => t.id == textId).firstOrNull;
        if (track != null) controller.selectTextTrack(track);
      }
    }

    _ui.closePanel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _ui.theme;
    final l10n = _ui.localizations;

    return Stack(
      fit: StackFit.expand,
      children: [
        FPanelScrim(theme: theme, onTap: _ui.closePanel),
        Center(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(theme.spacing * 2),
              child: FPanelEnterTransition(
                scaleFrom: 0.96,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= FTrackDialog._twoColumnWidth;

                    return FPanelSheet(
                      theme: theme,
                      width: isWide ? theme.menuWidth * 2 : theme.menuWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FPanelHeader(
                            theme: theme,
                            title: l10n.audioAndSubtitles,
                            onClose: _ui.closePanel,
                          ),
                          FPanelDivider(theme: theme),
                          Flexible(
                            child: isWide ? _columns(theme) : _stacked(theme),
                          ),
                          FPanelDivider(theme: theme),
                          _footer(theme),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Outside the scroll view on purpose: the way to confirm cannot be something you have to
  /// scroll a long subtitle list to find.
  Widget _footer(FPlayerTheme theme) => Padding(
        padding: EdgeInsets.all(theme.spacing),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FPanelFooterButton(
              theme: theme,
              label: _ui.localizations.cancel,
              onTap: _ui.closePanel,
            ),
            SizedBox(width: theme.spacing),
            FPanelFooterButton(
              theme: theme,
              label: _ui.localizations.apply,
              isPrimary: true,
              onTap: _apply,
            ),
          ],
        ),
      );

  FTrackStaging get _audioStaging => FTrackStaging(
        selectedId: _audioId,
        onSelect: (id) => setState(() => _audioId = id),
      );

  FTrackStaging get _textStaging => FTrackStaging(
        selectedId: _textId,
        onSelect: (id) => setState(() => _textId = id),
      );

  /// Both lists scroll together, and the rule between them runs the full height of the taller
  /// one — which is what `IntrinsicHeight` is for, and why the columns are plain Columns.
  Widget _columns(FPlayerTheme theme) => SingleChildScrollView(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _column(theme, _ui.localizations.audio, audio: true)),
              Container(width: 1, color: theme.foreground.withValues(alpha: 0.08)),
              Expanded(child: _column(theme, _ui.localizations.subtitles, audio: false)),
            ],
          ),
        ),
      );

  Widget _stacked(FPlayerTheme theme) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FPanelSectionLabel(theme: theme, label: _ui.localizations.audio),
            ...audioRows(_ui, staging: _audioStaging),
            SizedBox(height: theme.spacing),
            FPanelSectionLabel(theme: theme, label: _ui.localizations.subtitles),
            ...subtitleRows(_ui, staging: _textStaging),
            SizedBox(height: theme.spacing),
          ],
        ),
      );

  Widget _column(FPlayerTheme theme, String label, {required bool audio}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FPanelSectionLabel(theme: theme, label: label),
          ...audio
              ? audioRows(_ui, staging: _audioStaging)
              : subtitleRows(_ui, staging: _textStaging),
          SizedBox(height: theme.spacing),
        ],
      );
}

/// A titled list of choices in a side sheet: quality, speed, anything with one axis.
class FOptionsSheet extends StatelessWidget {
  const FOptionsSheet({
    required this.ui,
    required this.title,
    required this.children,
    super.key,
  });

  final FPlayerUi ui;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;

    return Stack(
      fit: StackFit.expand,
      children: [
        FPanelScrim(theme: theme, onTap: ui.closePanel),
        Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(theme.spacing),
              child: FPanelEnterTransition(
                slideFrom: const Offset(28, 0),
                child: FPanelSheet(
                  theme: theme,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FPanelHeader(theme: theme, title: title, onClose: ui.closePanel),
                      FPanelDivider(theme: theme),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(vertical: theme.spacing * 0.75),
                          child: Column(mainAxisSize: MainAxisSize.min, children: children),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The speed sheet: the values as pills, because seeing them side by side is the point.
class FSpeedSheet extends StatelessWidget {
  const FSpeedSheet({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;

    return FOptionsSheet(
      ui: ui,
      title: ui.localizations.speed,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing * 1.5,
            vertical: theme.spacing,
          ),
          child: Wrap(
            spacing: theme.spacing,
            runSpacing: theme.spacing,
            children: [
              for (final speed in ui.config.speeds)
                FSpeedChip(
                  ui: ui,
                  label: speed == 1.0
                      ? ui.localizations.normal
                      : formatPlaybackSpeed(speed),
                  isSelected: (ui.controller.speed - speed).abs() < 0.01,
                  onTap: () {
                    ui.controller.setSpeed(speed);
                    ui.closePanel();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
