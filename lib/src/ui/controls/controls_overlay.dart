import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../core/player_status.dart';
import '../desktop/desktop_layer.dart' show FDesktopScope;
import '../player_scope.dart';
import '../time_format.dart';
import '../tv/tv_layer.dart';
import '../video_fit.dart';
import 'player_button.dart';
import 'progress_bar.dart';
import 'settings_panel.dart' show qualitySummary;

/// The default chrome: a title row on top, transport controls in the middle, a seek bar and
/// buttons at the bottom.
///
/// Every band is replaceable through the builder parameters on `FPlayerView`; this is what fills
/// in when they are not given.
class FControlsOverlay extends StatelessWidget {
  const FControlsOverlay({
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

  /// Extra controls appended to the bottom row, before the fullscreen button.
  final List<Widget> actions;

  /// Preview shown above the seek bar thumb while scrubbing.
  final Widget Function(BuildContext context, Duration position)? previewBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;

    return Stack(
      fit: StackFit.expand,
      children: [
        // A gradient rather than a flat veil: the picture stays visible in the middle, where
        // there is nothing to read, and darkens exactly where the text sits.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [theme.scrim, const Color(0x00000000), theme.scrim],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: topBar ?? FControlsTopBar(ui: ui, title: title, subtitle: subtitle),
        ),
        Center(child: center ?? _CenterControls(ui: ui)),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: bottomBar ??
              _BottomBar(ui: ui, actions: actions, previewBuilder: previewBuilder),
        ),
      ],
    );
  }
}

/// The title row: back, title and subtitle, then lock, Picture-in-Picture and settings, each
/// as the config allows.
///
/// Shared by the touch and the desktop chrome. Which of the trailing controls appear is what
/// tells the two apart, and that is the config's decision, not the widget's.
class FControlsTopBar extends StatelessWidget {
  const FControlsTopBar({required this.ui, this.title, this.subtitle, super.key});

  final FPlayerUi ui;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final config = ui.config;
    final l10n = ui.localizations;

    final isDesktop = FDesktopScope.maybeOf(context)?.isActive ?? false;

    final source = ui.controller.value.source;
    final resolvedTitle = title ?? source?.title;
    final resolvedSubtitle = subtitle ?? source?.subtitle;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: theme.padding,
        child: Row(
          children: [
            if (config.showBackButton)
              FPlayerButton(
                icon: Icons.arrow_back,
                theme: theme,
                semanticLabel: l10n.back,
                onPressed: ui.back,
              ),
            if (config.showTitle && resolvedTitle != null) ...[
              SizedBox(width: theme.spacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      resolvedTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleStyle.copyWith(color: theme.foreground),
                    ),
                    if (resolvedSubtitle != null)
                      Text(
                        resolvedSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.subtitleStyle.copyWith(color: theme.mutedForeground),
                      ),
                  ],
                ),
              ),
            ] else
              const Spacer(),
            // Locking exists to survive a hand on the screen. A mouse is never that, so under
            // the desktop layout the control would be a button that solves nothing.
            if (config.showLockButton && !isDesktop)
              FPlayerButton(
                icon: Icons.lock_open,
                theme: theme,
                semanticLabel: l10n.lock,
                onPressed: () => ui.setLocked(locked: true),
              ),
            if (config.showPipButton && ui.controller.value.isPipSupported)
              FPlayerButton(
                icon: Icons.picture_in_picture_alt,
                theme: theme,
                semanticLabel: l10n.pictureInPicture,
                onPressed: ui.controller.enterPip,
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
    );
  }
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.ui});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final config = ui.config;
    final l10n = ui.localizations;
    final controller = ui.controller;
    final value = controller.value;

    // A spinner in the middle would sit exactly where the play button is; showing both at once
    // reads as a broken control, so the transport steps aside while the player is waiting — for
    // data or for a network that is not there.
    //
    // The error view sits in the same place and has the same claim: a play triangle drawn
    // through "Playback failed" is not a control anyone can act on.
    //
    // Hidden rather than unmounted while merely buffering: unmounting takes the focused button
    // out of the tree with it, so every rebuffer dropped a remote's focus and the autofocus
    // grabbed it back when the stall ended.
    final isWaiting = value.status.isWaiting || value.isWaitingForNetwork;
    if (value.hasError) return const SizedBox.shrink();

    final isCompleted = value.isCompleted;

    // Scaled down rather than overflowed: an inline player can be any width its host
    // gives it, and the transport is the one band that cannot be dropped.
    return Opacity(
      opacity: isWaiting ? 0 : 1,
      child: IgnorePointer(
        ignoring: isWaiting,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (config.showTrackButtons && value.hasPlaylist)
                FPlayerButton(
                  icon: Icons.skip_previous,
                  theme: theme,
                  size: theme.primaryIconSize * 0.6,
                  semanticLabel: l10n.previous,
                  onPressed: controller.previous,
                ),
              if (config.showSkipButtons)
                FPlayerButton(
                  icon: Icons.replay_10,
                  theme: theme,
                  size: theme.primaryIconSize * 0.65,
                  semanticLabel: l10n.rewind,
                  onPressed: value.isSeekable ? controller.skipBackward : null,
                ),
              SizedBox(width: theme.spacing * 2),
              FPlayerButton(
                icon: isCompleted
                    ? Icons.replay
                    : value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                theme: theme,
                size: theme.primaryIconSize,
                autofocus: true,
                semanticLabel: isCompleted
                    ? l10n.replay
                    : value.isPlaying
                        ? l10n.pause
                        : l10n.play,
                onPressed: controller.togglePlayPause,
              ),
              SizedBox(width: theme.spacing * 2),
              if (config.showSkipButtons)
                FPlayerButton(
                  icon: Icons.forward_10,
                  theme: theme,
                  size: theme.primaryIconSize * 0.65,
                  semanticLabel: l10n.forward,
                  onPressed: value.isSeekable ? controller.skipForward : null,
                ),
              if (config.showTrackButtons && value.hasPlaylist)
                FPlayerButton(
                  icon: Icons.skip_next,
                  theme: theme,
                  size: theme.primaryIconSize * 0.6,
                  semanticLabel: l10n.next,
                  onPressed: value.hasNext ? controller.next : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.ui,
    required this.actions,
    this.previewBuilder,
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
    final value = ui.controller.value;

    return SafeArea(
      top: false,
      child: Padding(
        padding: theme.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (config.showSeekBar) ...[
              Row(
                children: [
                  Text(
                    formatMediaTime(ui.displayPosition, reference: value.duration),
                    style: theme.timestampStyle.copyWith(color: theme.foreground),
                  ),
                  SizedBox(width: theme.spacing),
                  Expanded(
                    child: FProgressBar(ui: ui, previewBuilder: previewBuilder),
                  ),
                  SizedBox(width: theme.spacing),
                  FTrailingTime(ui: ui),
                ],
              ),
              SizedBox(height: theme.spacing / 2),
            ],
            Row(
              children: [
                // The controls scroll rather than overflow. Which of them are on is the app's
                // call, and a named control plus a quality summary plus a speed on a 360-wide
                // phone is wider than the phone — a row that runs off the edge takes the
                // fullscreen button with it, where scrolling only costs a swipe.
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: buildSecondaryControls(
                        context,
                        ui,
                        width: width,
                        actions: actions,
                      ),
                    ),
                  ),
                ),
                if (config.showFullscreenButton)
                  FPlayerButton(
                    icon: ui.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    theme: theme,
                    semanticLabel:
                        ui.isFullscreen ? l10n.exitFullscreen : l10n.enterFullscreen,
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

/// The controls that pick something — audio and subtitles, quality, speed — plus mute, fit and
/// the app's own [actions], each as the config allows.
///
/// One list for both chromes: the touch bar scrolls it on the left of the fullscreen button, the
/// desktop bar right-aligns it after the transport. [width] is the room the row has, which
/// decides between the long and the short labels. [includeMute] is off for the desktop bar,
/// which puts mute beside its volume slider instead.
List<Widget> buildSecondaryControls(
  BuildContext context,
  FPlayerUi ui, {
  required double width,
  List<Widget> actions = const [],
  bool includeMute = true,
}) {
  final theme = ui.theme;
  final config = ui.config;
  final l10n = ui.localizations;
  final controller = ui.controller;
  final value = controller.value;
  final isTv = FTvScope.maybeOf(context)?.isActive ?? false;

  return [
    if (config.showAudioSubtitlesButton && hasTracksToPick(ui))
      // Named rather than a `CC` glyph: the control picks a language as often as it turns
      // subtitles on, and no icon says that. The short form only when the row is tight.
      FPlayerTextButton(
        label: width < 420 ? l10n.audioAndSubsShort : l10n.audioAndSubtitles,
        theme: theme,
        isActive: controller.tracks.selectedText != null,
        semanticLabel: l10n.audioAndSubtitles,
        onPressed: () => ui.openPanel(FPlayerPanel.tracks),
      ),
    if (config.showQualityButton && controller.tracks.hasMultipleQualities)
      FPlayerTextButton(
        // The long form only when there is room for it: `Auto · 1080p` says more, but not at
        // the cost of pushing everything else off a phone.
        label: width < 420
            ? controller.tracks.activeVideo?.qualityLabel ?? l10n.auto
            : qualitySummary(ui),
        theme: theme,
        semanticLabel: l10n.quality,
        onPressed: () => ui.openPanel(FPlayerPanel.quality),
      ),
    // Speed is a phone control. On a remote it is one more stop the D-pad has to walk through
    // to reach anything else, for a setting nobody changes from a sofa — and the settings
    // panel still carries it for the rare time they do.
    if (config.showSpeedButton && !isTv)
      FPlayerTextButton(
        label: formatPlaybackSpeed(value.speed),
        theme: theme,
        semanticLabel: l10n.speed,
        onPressed: () => ui.openPanel(FPlayerPanel.speed),
      ),
    if (includeMute && config.showMuteButton)
      FPlayerButton(
        icon: value.isMuted ? Icons.volume_off : Icons.volume_up,
        theme: theme,
        isActive: value.isMuted,
        semanticLabel: value.isMuted ? l10n.unmute : l10n.mute,
        onPressed: controller.toggleMute,
      ),
    if (config.showFitButton)
      FPlayerButton(
        icon: ui.fit == FVideoFit.cover ? Icons.fullscreen_exit : Icons.aspect_ratio,
        theme: theme,
        semanticLabel: 'Fit: ${ui.fit.name}',
        onPressed: ui.cycleFit,
      ),
    ...actions,
  ];
}

/// Whether the picker has anything to offer: a second audio track, or any subtitles at all.
bool hasTracksToPick(FPlayerUi ui) {
  final tracks = ui.controller.tracks;
  return tracks.audio.length > 1 || tracks.hasSubtitles;
}

/// Duration, time remaining, or a live badge that doubles as "jump to the edge".
///
/// Shared by the touch and the desktop chrome; the desktop bar puts it beside the position with
/// a slash between, the touch bar at the far end of the seek bar.
class FTrailingTime extends StatelessWidget {
  const FTrailingTime({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final value = ui.controller.value;

    if (value.isLive) {
      final isAtEdge = value.duration == null ||
          (value.duration! - value.position) < const Duration(seconds: 10);

      return GestureDetector(
        onTap: ui.controller.seekToLive,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAtEdge ? theme.accent : theme.mutedForeground,
              ),
            ),
            SizedBox(width: theme.spacing / 2),
            Text(
              ui.localizations.live,
              style: theme.timestampStyle.copyWith(
                color: isAtEdge ? theme.foreground : theme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    final duration = value.duration ?? Duration.zero;
    final text = ui.config.showRemainingTime
        ? '-${formatMediaTime(duration - ui.displayPosition, reference: duration)}'
        : formatMediaTime(duration);

    return Text(
      text,
      style: theme.timestampStyle.copyWith(color: theme.mutedForeground),
    );
  }
}
