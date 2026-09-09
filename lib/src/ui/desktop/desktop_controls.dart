import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../controls/controls_overlay.dart';
import '../controls/player_button.dart';
import '../controls/progress_bar.dart';
import '../player_scope.dart';
import '../time_format.dart';
import 'volume_slider.dart';

/// The mouse-and-keyboard chrome: a title row on top and one bar at the bottom that holds
/// everything else, the way desktop players lay it out.
///
/// Different from `FControlsOverlay` where a mouse makes a difference, and no further. The
/// transport moves from the middle of the picture into the bar — a pointer does not need a
/// target the size of a thumb, and the middle of the picture is for the picture. Volume gets a
/// slider beside mute, because a wheel and a drag are natural there and a vertical swipe is not.
/// The time reads `1:23 / 12:14` next to the transport, where every desktop player puts it. The
/// top row, the seek bar and the pickers are the same widgets as on touch.
///
/// Every band is replaceable through the builder parameters on `FPlayerView`, the same as the
/// touch chrome; `centerBuilder` is honoured too, for an app that wants something there.
class FDesktopControls extends StatelessWidget {
  const FDesktopControls({
    required this.ui,
    this.title,
    this.subtitle,
    this.topBar,
    this.bottomBar,
    this.center,
    this.actions = const [],
    this.previewBuilder,
    super.key,
  });

  final FPlayerUi ui;
  final String? title;
  final String? subtitle;

  final Widget? topBar;
  final Widget? bottomBar;
  final Widget? center;

  /// Extra controls appended to the right-hand cluster, before the fullscreen button.
  final List<Widget> actions;

  /// Preview shown above the seek bar thumb while scrubbing.
  final Widget Function(BuildContext context, Duration position)? previewBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Darkened only where there is something to read: the bar at the bottom, and the title
        // at the top. The middle stays as bright as the film.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [theme.scrim, const Color(0x00000000), theme.scrim],
                stops: const [0, 0.35, 1],
              ),
            ),
          ),
        ),
        // Each bar takes every click inside it, including the gaps between its controls. The
        // pointer layer under the chrome pauses on a click, and reaching for the seek bar and
        // missing it by a few pixels is not a request to pause the film.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _DeadZone(
            child: topBar ?? FControlsTopBar(ui: ui, title: title, subtitle: subtitle),
          ),
        ),
        if (center != null) Center(child: center),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _DeadZone(
            child: bottomBar ??
                FDesktopBottomBar(ui: ui, actions: actions, previewBuilder: previewBuilder),
          ),
        ),
      ],
    );
  }
}

/// Claims the hit test for its whole area, so nothing under it in the stack sees the click,
/// while the controls inside still win the gesture arena.
class _DeadZone extends StatelessWidget {
  const _DeadZone({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Listener(behavior: HitTestBehavior.opaque, child: child);
}

/// The seek bar with the whole transport under it: play, previous and next, skip, volume, time
/// on the left; pickers, the app's actions and fullscreen on the right.
class FDesktopBottomBar extends StatelessWidget {
  const FDesktopBottomBar({
    required this.ui,
    this.actions = const [],
    this.previewBuilder,
    super.key,
  });

  final FPlayerUi ui;
  final List<Widget> actions;
  final Widget Function(BuildContext context, Duration position)? previewBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _build(context, constraints.maxWidth),
      );

  Widget _build(BuildContext context, double width) {
    final theme = ui.theme;
    final config = ui.config;
    final l10n = ui.localizations;
    final controller = ui.controller;
    final value = controller.value;
    final isCompleted = value.isCompleted;
    // A narrow inline player keeps play, mute, the time and the pickers; the skip buttons and
    // the volume slider are the first to go, being the two things the keyboard also does.
    final isNarrow = width < 480;

    return SafeArea(
      top: false,
      child: Padding(
        padding: theme.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (config.showSeekBar) ...[
              FProgressBar(ui: ui, previewBuilder: previewBuilder),
              SizedBox(height: theme.spacing / 2),
            ],
            Row(
              children: [
                FPlayerButton(
                  icon: isCompleted
                      ? Icons.replay
                      : value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                  theme: theme,
                  size: theme.iconSize * 1.25,
                  semanticLabel: isCompleted
                      ? l10n.replay
                      : value.isPlaying
                          ? l10n.pause
                          : l10n.play,
                  onPressed: controller.togglePlayPause,
                ),
                if (config.showTrackButtons && value.hasPlaylist) ...[
                  FPlayerButton(
                    icon: Icons.skip_previous,
                    theme: theme,
                    semanticLabel: l10n.previous,
                    onPressed: controller.previous,
                  ),
                  FPlayerButton(
                    icon: Icons.skip_next,
                    theme: theme,
                    semanticLabel: l10n.next,
                    onPressed: value.hasNext ? controller.next : null,
                  ),
                ],
                if (config.showSkipButtons && !isNarrow) ...[
                  FPlayerButton(
                    icon: Icons.replay_10,
                    theme: theme,
                    semanticLabel: l10n.rewind,
                    onPressed: value.isSeekable ? controller.skipBackward : null,
                  ),
                  FPlayerButton(
                    icon: Icons.forward_10,
                    theme: theme,
                    semanticLabel: l10n.forward,
                    onPressed: value.isSeekable ? controller.skipForward : null,
                  ),
                ],
                if (config.showMuteButton) ...[
                  FPlayerButton(
                    icon: value.isMuted
                        ? Icons.volume_off
                        : value.volume < 0.5
                            ? Icons.volume_down
                            : Icons.volume_up,
                    theme: theme,
                    isActive: value.isMuted,
                    semanticLabel: value.isMuted ? l10n.unmute : l10n.mute,
                    onPressed: controller.toggleMute,
                  ),
                  if (!isNarrow) FVolumeSlider(ui: ui),
                ],
                SizedBox(width: theme.spacing * 1.5),
                _Time(ui: ui),
                // The pickers scroll rather than overflow, as on the touch bar: a named control,
                // a quality summary and a speed are wider than a narrow player, and a row that
                // runs off the edge takes the fullscreen button with it.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...buildSecondaryControls(
                            context,
                            ui,
                            width: width,
                            actions: actions,
                            includeMute: false,
                          ),
                          if (config.showSettingsButton)
                            FPlayerButton(
                              icon: Icons.settings,
                              theme: theme,
                              semanticLabel: l10n.settings,
                              onPressed: ui.openSettings,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (config.showFullscreenButton)
                  FPlayerButton(
                    icon: ui.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    theme: theme,
                    semanticLabel: ui.isFullscreen ? l10n.exitFullscreen : l10n.enterFullscreen,
                    onPressed: ui.toggleFullscreen,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `1:23 / 12:14`, or the live badge on its own.
class _Time extends StatelessWidget {
  const _Time({required this.ui});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final value = ui.controller.value;

    if (value.isLive) return FTrailingTime(ui: ui);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatMediaTime(ui.displayPosition, reference: value.duration),
          style: theme.timestampStyle.copyWith(color: theme.foreground),
        ),
        Text(' / ', style: theme.timestampStyle.copyWith(color: theme.mutedForeground)),
        FTrailingTime(ui: ui),
      ],
    );
  }
}
