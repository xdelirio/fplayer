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
class FTrackDialog extends StatelessWidget {
  const FTrackDialog({required this.ui, super.key});

  static const _twoColumnWidth = 520.0;

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final l10n = ui.localizations;

    return Stack(
      fit: StackFit.expand,
      children: [
        FPanelScrim(theme: theme, onTap: ui.closePanel),
        Center(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(theme.spacing * 2),
              child: FPanelEnterTransition(
                scaleFrom: 0.96,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= _twoColumnWidth;

                    return FPanelSheet(
                      theme: theme,
                      width: isWide ? theme.menuWidth * 2 : theme.menuWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FPanelHeader(
                            theme: theme,
                            title: l10n.audioAndSubtitles,
                            onClose: ui.closePanel,
                          ),
                          FPanelDivider(theme: theme),
                          Flexible(
                            child: isWide ? _columns(theme) : _stacked(theme),
                          ),
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

  /// Both lists scroll together, and the rule between them runs the full height of the taller
  /// one — which is what `IntrinsicHeight` is for, and why the columns are plain Columns.
  Widget _columns(FPlayerTheme theme) => SingleChildScrollView(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _column(theme, ui.localizations.audio, audio: true)),
              Container(width: 1, color: theme.foreground.withValues(alpha: 0.08)),
              Expanded(child: _column(theme, ui.localizations.subtitles, audio: false)),
            ],
          ),
        ),
      );

  Widget _stacked(FPlayerTheme theme) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FPanelSectionLabel(theme: theme, label: ui.localizations.audio),
            ...audioRows(ui, onSelected: ui.closePanel),
            SizedBox(height: theme.spacing),
            FPanelSectionLabel(theme: theme, label: ui.localizations.subtitles),
            ...subtitleRows(ui, onSelected: ui.closePanel),
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
              ? audioRows(ui, onSelected: ui.closePanel)
              : subtitleRows(ui, onSelected: ui.closePanel),
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
