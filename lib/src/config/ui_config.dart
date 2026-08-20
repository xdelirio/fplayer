import 'package:flutter/foundation.dart';

import '../ui/localizations.dart';
import '../ui/theme.dart';
import '../ui/video_fit.dart';
import 'tv_config.dart';

/// Which touch gestures the player reacts to.
///
/// All of them are conventions people already know from other video apps, which is why they
/// default to on. Turn off whatever fights with your own gestures — a player embedded in a
/// horizontally-scrolling feed wants [horizontalDragSeeks] off, for instance.
@immutable
class FGestureConfig {
  const FGestureConfig({
    this.tapTogglesControls = true,
    this.doubleTapSeeks = true,
    this.horizontalDragSeeks = true,
    this.verticalDragAdjustsVolume = true,
    this.verticalDragAdjustsBrightness = true,
    this.longPressSpeed = 2.0,
    this.pinchChangesFit = true,
  });

  /// Nothing but the buttons. Useful when the player sits inside a gesture-heavy screen.
  const FGestureConfig.none()
      : tapTogglesControls = true,
        doubleTapSeeks = false,
        horizontalDragSeeks = false,
        verticalDragAdjustsVolume = false,
        verticalDragAdjustsBrightness = false,
        longPressSpeed = null,
        pinchChangesFit = false;

  /// Single tap shows or hides the controls.
  final bool tapTogglesControls;

  /// Double tap on the left or right third seeks by `FPlaybackConfig.seekStep`; in the middle it
  /// toggles play.
  final bool doubleTapSeeks;

  /// Dragging sideways scrubs, with a preview while the finger is down.
  final bool horizontalDragSeeks;

  /// Dragging up and down on the right half changes the player's volume.
  final bool verticalDragAdjustsVolume;

  /// Dragging up and down on the left half changes screen brightness.
  ///
  /// Scoped to the app's window, so it reverts when the app goes away rather than leaving the
  /// device dimmed.
  final bool verticalDragAdjustsBrightness;

  /// Speed applied while the finger is held down, restored on release. Null disables it.
  final double? longPressSpeed;

  /// Pinching cycles between contain and cover.
  final bool pinchChangesFit;
}

/// What the bundled controls show and how they behave.
///
/// Every `show*` flag exists so an app can strip the chrome down to what it needs without
/// rebuilding the overlay. To replace a piece rather than hide it, use the builder parameters on
/// `FPlayerView`.
@immutable
class FUiConfig {
  const FUiConfig({
    this.showControls = true,
    this.controlsTimeout = const Duration(seconds: 4),
    this.showControlsOnStart = false,
    this.showIdleProgressBar = true,
    this.keepControlsWhilePaused = true,
    this.showTitle = true,
    this.showBackButton = true,
    this.showSeekBar = true,
    this.showSkipButtons = true,
    this.showTrackButtons = true,
    this.showNextUpCard = true,
    this.nextUpThreshold = const Duration(seconds: 20),
    this.showRemainingTime = false,
    this.showMuteButton = true,
    this.showSpeedButton = true,
    this.showAudioSubtitlesButton = true,
    this.showQualityButton = true,
    this.showQualityBitrate = false,
    this.showSettingsButton = false,
    this.showFitButton = false,
    this.showLockButton = true,
    this.showPipButton = true,
    this.showFullscreenButton = true,
    this.speeds = const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
    this.fit = FVideoFit.contain,
    this.gestures = const FGestureConfig(),
    this.tv = const FTvConfig(),
    this.theme = const FPlayerTheme(),
    this.localizations = const FPlayerLocalizations(),
  });

  /// Preset for a leanback build: remote-first from the start, no touch gestures, larger chrome.
  const FUiConfig.tv({FPlayerTheme theme = const FPlayerTheme.tv()})
      : this(
          // A remote needs something focused to start from, unlike a finger.
          showControlsOnStart: true,
          // A row of small targets is worse to walk with a D-pad than one list, so the panel
          // takes over from the dedicated buttons.
          showSettingsButton: true,
          showAudioSubtitlesButton: false,
          showQualityButton: false,
          showSpeedButton: false,
          showLockButton: false,
          showPipButton: false,
          showFullscreenButton: false,
          showFitButton: false,
          gestures: const FGestureConfig.none(),
          tv: const FTvConfig(mode: FTvMode.enabled),
          theme: theme,
        );

  /// Video only. The gestures still run, so you can drive your own overlay from them.
  const FUiConfig.bare()
      : showControls = false,
        controlsTimeout = const Duration(seconds: 4),
        showControlsOnStart = false,
        showIdleProgressBar = false,
        keepControlsWhilePaused = false,
        showTitle = false,
        showBackButton = false,
        showSeekBar = false,
        showSkipButtons = false,
        showTrackButtons = false,
        showNextUpCard = false,
        nextUpThreshold = Duration.zero,
        showRemainingTime = false,
        showMuteButton = false,
        showSpeedButton = false,
        showAudioSubtitlesButton = false,
        showQualityButton = false,
        showQualityBitrate = false,
        showSettingsButton = false,
        showFitButton = false,
        showLockButton = false,
        showPipButton = false,
        showFullscreenButton = false,
        speeds = const [1.0],
        fit = FVideoFit.contain,
        gestures = const FGestureConfig.none(),
        tv = const FTvConfig(mode: FTvMode.disabled),
        theme = const FPlayerTheme(),
        localizations = const FPlayerLocalizations();

  final bool showControls;

  /// How long the controls stay up after the last interaction.
  final Duration controlsTimeout;

  /// Show the controls when the player first appears, then fade them out.
  ///
  /// Off by default: the picture is what someone opened the screen for, and the chrome is one tap
  /// away. [showIdleProgressBar] keeps the position readable meanwhile.
  final bool showControlsOnStart;

  /// A hairline of progress along the bottom edge while the controls are hidden.
  ///
  /// It is the one thing worth knowing without asking — how far in you are — and inline it costs
  /// no room and no attention.
  ///
  /// Never in fullscreen, whatever this is set to: there the picture is the whole screen and
  /// hiding the chrome was a request for nothing on top of it.
  final bool showIdleProgressBar;

  /// Keep the controls up while paused instead of timing out.
  ///
  /// Someone who paused is usually about to do something else — scrub, change a track — so
  /// hiding the controls under them is a small hostility.
  final bool keepControlsWhilePaused;

  final bool showTitle;
  final bool showBackButton;
  final bool showSeekBar;
  final bool showSkipButtons;

  /// Previous / next controls, shown only when a queue is loaded.
  final bool showTrackButtons;

  /// Offer the next item near the end of the current one.
  final bool showNextUpCard;

  /// How long before the end the offer appears.
  final Duration nextUpThreshold;

  /// Show time left instead of total duration on the right of the seek bar.
  final bool showRemainingTime;

  final bool showMuteButton;
  final bool showSpeedButton;

  /// One control for both track kinds, opening a dialog that shows them side by side.
  ///
  /// It appears only when there is something to pick: a second audio track, or any subtitles.
  final bool showAudioSubtitlesButton;

  /// The current rung, as a control. Appears only on adaptive media with more than one.
  final bool showQualityButton;

  /// Put each rung's bitrate beside it in the quality list — `1080p    4500 kbps`.
  ///
  /// Off by default: a quality menu is read by people who recognise `1080p`, and a number in
  /// kbps beside it answers a question they did not ask. Turn it on for an audience that is
  /// watching its data, or to tell apart two renditions of the same size.
  final bool showQualityBitrate;

  /// The catch-all panel. Off on touch, where the buttons above cover the same ground in one tap
  /// instead of two; on for `FUiConfig.tv()`, where a menu beats a row of small targets.
  final bool showSettingsButton;
  final bool showFitButton;
  final bool showLockButton;
  final bool showPipButton;
  final bool showFullscreenButton;

  /// Speeds offered in the settings panel.
  final List<double> speeds;

  /// Initial sizing mode.
  final FVideoFit fit;

  final FGestureConfig gestures;

  /// Remote-control behaviour. Leave it on `auto` and a phone build costs nothing.
  final FTvConfig tv;

  final FPlayerTheme theme;
  final FPlayerLocalizations localizations;

  FUiConfig copyWith({
    bool? showControls,
    Duration? controlsTimeout,
    bool? showControlsOnStart,
    bool? showIdleProgressBar,
    bool? keepControlsWhilePaused,
    bool? showTitle,
    bool? showBackButton,
    bool? showSeekBar,
    bool? showSkipButtons,
    bool? showTrackButtons,
    bool? showNextUpCard,
    Duration? nextUpThreshold,
    bool? showRemainingTime,
    bool? showMuteButton,
    bool? showSpeedButton,
    bool? showAudioSubtitlesButton,
    bool? showQualityButton,
    bool? showQualityBitrate,
    bool? showSettingsButton,
    bool? showFitButton,
    bool? showLockButton,
    bool? showPipButton,
    bool? showFullscreenButton,
    List<double>? speeds,
    FVideoFit? fit,
    FGestureConfig? gestures,
    FTvConfig? tv,
    FPlayerTheme? theme,
    FPlayerLocalizations? localizations,
  }) =>
      FUiConfig(
        showControls: showControls ?? this.showControls,
        controlsTimeout: controlsTimeout ?? this.controlsTimeout,
        showControlsOnStart: showControlsOnStart ?? this.showControlsOnStart,
        showIdleProgressBar: showIdleProgressBar ?? this.showIdleProgressBar,
        keepControlsWhilePaused: keepControlsWhilePaused ?? this.keepControlsWhilePaused,
        showTitle: showTitle ?? this.showTitle,
        showBackButton: showBackButton ?? this.showBackButton,
        showSeekBar: showSeekBar ?? this.showSeekBar,
        showSkipButtons: showSkipButtons ?? this.showSkipButtons,
        showTrackButtons: showTrackButtons ?? this.showTrackButtons,
        showNextUpCard: showNextUpCard ?? this.showNextUpCard,
        nextUpThreshold: nextUpThreshold ?? this.nextUpThreshold,
        showRemainingTime: showRemainingTime ?? this.showRemainingTime,
        showMuteButton: showMuteButton ?? this.showMuteButton,
        showSpeedButton: showSpeedButton ?? this.showSpeedButton,
        showAudioSubtitlesButton:
            showAudioSubtitlesButton ?? this.showAudioSubtitlesButton,
        showQualityButton: showQualityButton ?? this.showQualityButton,
        showQualityBitrate: showQualityBitrate ?? this.showQualityBitrate,
        showSettingsButton: showSettingsButton ?? this.showSettingsButton,
        showFitButton: showFitButton ?? this.showFitButton,
        showLockButton: showLockButton ?? this.showLockButton,
        showPipButton: showPipButton ?? this.showPipButton,
        showFullscreenButton: showFullscreenButton ?? this.showFullscreenButton,
        speeds: speeds ?? this.speeds,
        fit: fit ?? this.fit,
        gestures: gestures ?? this.gestures,
        tv: tv ?? this.tv,
        theme: theme ?? this.theme,
        localizations: localizations ?? this.localizations,
      );
}
