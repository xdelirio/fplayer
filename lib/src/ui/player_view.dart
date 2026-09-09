import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config/fullscreen_config.dart';
import '../config/subtitle_style.dart';
import '../config/tv_config.dart';
import '../config/ui_config.dart';
import '../core/player_controller.dart';
import '../core/player_status.dart';
import '../models/player_error.dart';
import '../models/player_source.dart';
import '../storyboard/storyboard_controller.dart';
import '../storyboard/storyboard_preview.dart';
import 'controls/controls_overlay.dart';
import 'controls/error_view.dart';
import 'controls/next_up_card.dart';
import 'controls/panel_chrome.dart';
import 'controls/player_button.dart';
import 'controls/settings_panel.dart';
import 'controls/skip_marker.dart';
import 'controls/track_dialog.dart';
import 'desktop/desktop_controls.dart';
import 'desktop/desktop_layer.dart';
import 'fullscreen.dart';
import 'gestures/gesture_layer.dart';
import 'localizations.dart';
import 'player_scope.dart';
import 'subtitle_view.dart';
import 'theme.dart';
import 'tv/tv_layer.dart';
import 'video_fit.dart';
import 'video_surface.dart';

/// The player with its chrome: video, subtitles, gestures, controls, settings and error states.
///
/// Sizes itself to the video's aspect ratio unless [aspectRatio] says otherwise, so it drops into
/// a column without extra wrapping.
///
/// Each `*Builder` replaces one band of the chrome while everything else keeps working. Inside a
/// builder, `FPlayerScope.of(context)` gives the same view state the built-in controls use, so a
/// custom bottom bar can still restart the auto-hide timer or start a scrub.
///
/// ```dart
/// FPlayerView(
///   controller: controller,
///   config: const FUiConfig(showLockButton: false),
///   bottomBarBuilder: (context, ui) => MyBottomBar(ui: ui),
/// )
/// ```
class FPlayerView extends StatefulWidget {
  const FPlayerView({
    required this.controller,
    this.config = const FUiConfig(),
    this.fullscreen = const FFullscreenConfig(),
    this.subtitleStyle,
    this.title,
    this.subtitle,
    this.aspectRatio,
    this.backgroundColor = const Color(0xFF000000),
    this.actions = const [],
    this.overlayBuilder,
    this.topBarBuilder,
    this.bottomBarBuilder,
    this.centerBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.posterBuilder,
    this.previewBuilder,
    this.onBack,
    this.onFullscreenChanged,
    this.isFullscreen = false,
    this.storyboardController,
    super.key,
  });

  final FPlayerController controller;
  final FUiConfig config;

  /// Orientation and system-bar behaviour of the fullscreen route.
  final FFullscreenConfig fullscreen;

  /// Overrides `FPlayerConfig.subtitleStyle` for this view. Useful to bump the size in
  /// fullscreen without changing the inline player.
  final FSubtitleStyle? subtitleStyle;

  /// Overrides the title from the source.
  final String? title;
  final String? subtitle;

  /// Forces a ratio instead of following the video's own.
  final double? aspectRatio;

  final Color backgroundColor;

  /// Extra controls appended to the bottom row.
  final List<Widget> actions;

  /// Drawn above everything, including the controls.
  final Widget Function(BuildContext context, FPlayerUi ui)? overlayBuilder;

  final Widget Function(BuildContext context, FPlayerUi ui)? topBarBuilder;
  final Widget Function(BuildContext context, FPlayerUi ui)? bottomBarBuilder;
  final Widget Function(BuildContext context, FPlayerUi ui)? centerBuilder;
  final Widget Function(BuildContext context, FPlayerUi ui)? loadingBuilder;
  final Widget Function(BuildContext context, FPlayerUi ui, FPlayerError error)? errorBuilder;
  final Widget Function(BuildContext context, FPlayerUi ui)? posterBuilder;

  /// Replaces the thumbnail shown above the seek bar thumb while scrubbing.
  ///
  /// Leave it null and the view renders the source's storyboard on its own; supply it to preview
  /// something else entirely.
  final Widget Function(BuildContext context, Duration position)? previewBuilder;

  /// Runs when the back control is used and the player is not fullscreen. Defaults to popping
  /// the current route.
  final VoidCallback? onBack;

  /// Notified when the view enters or leaves fullscreen.
  final ValueChanged<bool>? onFullscreenChanged;

  /// Whether this instance *is* the fullscreen one. Set by the fullscreen route; leave it alone
  /// for the inline player.
  final bool isFullscreen;

  /// Storyboard loader to use instead of a private one.
  ///
  /// Pass a shared instance when several players show the same library, so the sprite cache is
  /// filled once. The view disposes only the controller it created itself.
  final FStoryboardController? storyboardController;

  @override
  State<FPlayerView> createState() => _FPlayerViewState();
}

class _FPlayerViewState extends State<FPlayerView> implements FPlayerUi {
  Timer? _hideTimer;
  bool _areControlsVisible = false;
  bool _isLocked = false;
  FPlayerPanel? _panel;
  bool _isScrubbing = false;
  Duration _scrubPosition = Duration.zero;
  late FVideoFit _fit = widget.config.fit;

  late final FStoryboardController _storyboard =
      widget.storyboardController ?? FStoryboardController();

  /// Whether this view built the storyboard controller it uses, and therefore owns its disposal.
  ///
  /// Read from the first widget, like the controller itself: deciding at disposal time from the
  /// current widget disposes the caller's shared controller when the parameter was cleared, and
  /// leaks the private one when it was filled in.
  late final bool _ownsStoryboard = widget.storyboardController == null;

  FStoryboardSource? _loadedStoryboard;
  bool _hasAutoEnteredFullscreen = false;

  /// Whether playback was running at the last notification, so the auto-hide countdown can be
  /// restarted when that changes rather than on every progress tick.
  bool _wasPlaying = false;

  /// Whether this view has already popped its own fullscreen route.
  bool _hasLeftFullscreen = false;

  /// Whether a fullscreen route is being pushed, so a second press cannot push another.
  bool _isEnteringFullscreen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPlaybackChanged);
    _syncStoryboard();
    if (widget.config.showControlsOnStart) {
      _areControlsVisible = true;
      _restartHideTimer();
    }
  }

  @override
  void didUpdateWidget(FPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPlaybackChanged);
      widget.controller.addListener(_onPlaybackChanged);
    }
    if (oldWidget.config.fit != widget.config.fit) _fit = widget.config.fit;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onPlaybackChanged);
    if (_ownsStoryboard) _storyboard.dispose();
    super.dispose();
  }

  /// Loads the storyboard when the source changes, and only then.
  ///
  /// Playback notifies several times a second; re-fetching the index on each of those would put
  /// the sprite sheets through the network for nothing.
  void _syncStoryboard() {
    final source = widget.controller.value.source?.storyboard;
    if (identical(source, _loadedStoryboard)) return;
    _loadedStoryboard = source;
    unawaited(_storyboard.load(source));
  }

  // region FPlayerUi

  @override
  FPlayerController get controller => widget.controller;

  @override
  FUiConfig get config => widget.config;

  @override
  FPlayerTheme get theme => widget.config.theme;

  @override
  FPlayerLocalizations get localizations => widget.config.localizations;

  @override
  bool get areControlsVisible => _areControlsVisible;

  @override
  bool get isLocked => _isLocked;

  @override
  bool get isScrubbing => _isScrubbing;

  @override
  Duration get displayPosition =>
      _isScrubbing ? _scrubPosition : widget.controller.value.position;

  @override
  FVideoFit get fit => _fit;

  @override
  bool get isFullscreen => widget.isFullscreen;

  @override
  bool get isSettingsOpen => _panel != null;

  @override
  FPlayerPanel? get panel => _panel;

  @override
  void showControls() {
    if (!_areControlsVisible) setState(() => _areControlsVisible = true);
    _restartHideTimer();
  }

  @override
  void hideControls() {
    _hideTimer?.cancel();
    if (_areControlsVisible) setState(() => _areControlsVisible = false);
  }

  @override
  void toggleControls() {
    if (_isLocked) {
      // The only thing a locked player reacts to is the affordance that unlocks it, and that has
      // to be findable — so a tap still surfaces it.
      showControls();
      return;
    }
    _areControlsVisible ? hideControls() : showControls();
  }

  @override
  void setLocked({required bool locked}) {
    // Locking takes the seek bar off the screen, and with it whatever would have ended a scrub
    // in progress: left set, the flag freezes the position readout and stops the chrome from
    // ever auto-hiding again.
    if (locked && _isScrubbing) endScrub();
    setState(() {
      _isLocked = locked;
      _panel = null;
    });
    showControls();
  }

  @override
  void setFit(FVideoFit fit) {
    setState(() => _fit = fit);
    showControls();
  }

  @override
  void cycleFit() => setFit(_fit.next);

  @override
  void openSettings() => openPanel(FPlayerPanel.settings);

  @override
  void openPanel(FPlayerPanel panel) {
    _hideTimer?.cancel();
    setState(() {
      _panel = panel;
      _areControlsVisible = true;
    });
  }

  @override
  void closeSettings() => closePanel();

  @override
  void closePanel() {
    setState(() => _panel = null);
    showControls();
  }

  @override
  void beginScrub() {
    _hideTimer?.cancel();
    setState(() {
      _isScrubbing = true;
      _scrubPosition = widget.controller.value.position;
      _areControlsVisible = true;
    });
  }

  @override
  void updateScrub(Duration position) => setState(() => _scrubPosition = position);

  @override
  void cancelScrub() {
    if (!_isScrubbing) return;
    setState(() => _isScrubbing = false);
    _restartHideTimer();
  }

  @override
  void endScrub() {
    if (!_isScrubbing) return;
    final target = _scrubPosition;
    setState(() => _isScrubbing = false);
    unawaited(widget.controller.seekTo(target));
    _restartHideTimer();
  }

  @override
  Future<void> toggleFullscreen() async {
    if (widget.isFullscreen) {
      _leaveFullscreen();
      return;
    }
    // Two presses inside the route transition would otherwise push two fullscreen copies of the
    // same player, and the viewer would have to leave twice.
    if (_isEnteringFullscreen) return;
    _isEnteringFullscreen = true;

    final fullscreen = widget.fullscreen;
    final navigator = Navigator.of(context);

    widget.onFullscreenChanged?.call(true);
    // Asked for, not waited on. The route is what the viewer pressed for; the orientation and
    // the system bars are the platform's business, and a device that is slow to answer — or
    // never answers — must not be able to swallow the press.
    unawaited(
      SystemChrome.setPreferredOrientations(
        fullscreen.orientationsFor(widget.controller.value.aspectRatio),
      ),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(fullscreen.systemUiMode));
    unawaited(widget.controller.setWindowFullscreen(fullscreen: true));

    // The same controller, and therefore the same texture, so entering fullscreen costs a route
    // transition rather than a reload.
    await navigator.push(
      FFullscreenRoute<void>(
        builder: (context) => FFullscreenPage(child: _fullscreenCopy()),
      ),
    );

    _isEnteringFullscreen = false;
    unawaited(widget.controller.setWindowFullscreen(fullscreen: false));
    unawaited(SystemChrome.setPreferredOrientations(fullscreen.restoreOrientations));
    unawaited(SystemChrome.setEnabledSystemUIMode(fullscreen.restoreSystemUiMode));
    widget.onFullscreenChanged?.call(false);
  }

  @override
  void back() {
    if (widget.isFullscreen) {
      _leaveFullscreen();
      return;
    }
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    _pop();
  }

  /// Leaves the fullscreen route.
  ///
  /// Deliberately not `maybePop`: the remote's back button is allowed to close the controls
  /// before it closes the player, and that rule is expressed as a `PopScope` veto — which a
  /// *control the viewer had to open the chrome to reach* would trip over every time. Pressing
  /// "exit fullscreen" and watching the chrome fade instead is the bug that rule caused.
  ///
  /// Once, and only while this view's own route is on top. The end of a video produces several
  /// notifications carrying `completed`, and `exitOnComplete` fires on each of them: unlatched,
  /// the second pop took the page underneath the player with it.
  void _leaveFullscreen() {
    if (_hasLeftFullscreen) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    _hasLeftFullscreen = true;
    Navigator.of(context).pop();
  }

  void _pop() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  // endregion

  /// Thumbnail shown above the seek bar: the caller's, the source's storyboard, or nothing.
  Widget Function(BuildContext, Duration)? get _previewBuilder {
    if (widget.previewBuilder != null) return widget.previewBuilder;
    if (_loadedStoryboard == null) return null;

    return (context, position) => FStoryboardPreview(
          controller: _storyboard,
          position: position,
          border: Border.all(color: widget.config.theme.foreground, width: 2),
        );
  }

  void _onPlaybackChanged() {
    if (!mounted) return;
    _syncStoryboard();
    // A player that just finished, or just failed, should not leave the viewer tapping a black
    // rectangle to find the controls again.
    final value = widget.controller.value;
    final wasPlaying = _wasPlaying;
    _wasPlaying = value.isPlaying;

    if (value.hasError || value.isCompleted) {
      showControls();
    } else if (_areControlsVisible && wasPlaying != value.isPlaying) {
      // Only when playback itself started or stopped. The engine reports progress four times a
      // second, and restarting the countdown on every one of those meant it could never fire —
      // the chrome sat over the picture for as long as the video played.
      _restartHideTimer();
    }

    if (widget.fullscreen.exitOnComplete && widget.isFullscreen && value.isCompleted) {
      _leaveFullscreen();
    } else if (widget.fullscreen.autoOnPlay &&
        !widget.isFullscreen &&
        !_hasAutoEnteredFullscreen &&
        value.isPlaying) {
      // Once per view: a viewer who left fullscreen should not be dragged back into it the next
      // time playback resumes.
      _hasAutoEnteredFullscreen = true;
      unawaited(toggleFullscreen());
    }

    setState(() {});
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (!_canAutoHide) return;
    _hideTimer = Timer(widget.config.controlsTimeout, () {
      if (mounted && _canAutoHide) setState(() => _areControlsVisible = false);
    });
  }

  bool get _canAutoHide {
    if (_panel != null || _isScrubbing) return false;
    final value = widget.controller.value;
    if (value.hasError) return false;
    if (widget.config.keepControlsWhilePaused && !value.isPlaying) return false;
    return true;
  }

  /// The same view, rebuilt for the fullscreen route.
  FPlayerView _fullscreenCopy() => FPlayerView(
        controller: widget.controller,
        config: widget.config,
        fullscreen: widget.fullscreen,
        subtitleStyle: widget.subtitleStyle,
        title: widget.title,
        subtitle: widget.subtitle,
        aspectRatio: widget.aspectRatio,
        backgroundColor: widget.backgroundColor,
        actions: widget.actions,
        overlayBuilder: widget.overlayBuilder,
        topBarBuilder: widget.topBarBuilder,
        bottomBarBuilder: widget.bottomBarBuilder,
        centerBuilder: widget.centerBuilder,
        loadingBuilder: widget.loadingBuilder,
        errorBuilder: widget.errorBuilder,
        posterBuilder: widget.posterBuilder,
        previewBuilder: widget.previewBuilder,
        onBack: widget.onBack,
        isFullscreen: true,
        storyboardController: _storyboard,
      );

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme;

    final content = FPlayerScope(
      ui: this,
      // Its own text baseline, because the chrome cannot count on having one. Every style here is
      // built with `copyWith`, so it inherits whatever ambient style there is — and a route with
      // no Material ancestor supplies Flutter's error style, which paints the whole player's text
      // yellow and underlined. The fullscreen route is exactly such a route.
      child: DefaultTextStyle(
        style: TextStyle(
          color: theme.foreground,
          fontSize: theme.labelStyle.fontSize,
          fontWeight: FontWeight.w400,
          decoration: TextDecoration.none,
        ),
        child: FTvLayer(
          ui: this,
          config: _tvConfig,
          child: _isDesktop
              ? FDesktopLayer(
                  key: _desktopLayer,
                  ui: this,
                  config: widget.config.desktop,
                  child: _buildStack(context),
                )
              : _buildStack(context),
        ),
      ),
    );

    if (widget.isFullscreen) return content;

    return AspectRatio(
      aspectRatio: widget.aspectRatio ?? widget.controller.value.aspectRatio,
      child: content,
    );
  }

  Widget _buildStack(BuildContext context) {
    final value = widget.controller.value;

    // In Picture-in-Picture the system shows the whole Activity in a thumbnail. Anything but the
    // picture is unreadable at that size and steals room from it.
    if (value.isPipActive) {
      final surface = FVideoSurface(
        controller: widget.controller,
        fit: FVideoFit.contain,
        backgroundColor: widget.backgroundColor,
      );
      if (!_isDesktop) return surface;
      // A desktop's floating window has no system chrome to bring the player back with, so the
      // pointer keeps its say: click pauses, double-click leaves.
      return Stack(
        fit: StackFit.expand,
        children: [
          surface,
          FDesktopPointerLayer(ui: this, config: widget.config.desktop),
        ],
      );
    }

    final showPoster = !value.isInitialized && value.source?.posterUrl != null;

    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FVideoSurface(
            controller: widget.controller,
            fit: _fit,
            backgroundColor: widget.backgroundColor,
          ),
          if (showPoster)
            widget.posterBuilder?.call(context, this) ??
                Image.network(
                  value.source!.posterUrl!,
                  fit: BoxFit.cover,
                  // A poster is decoration. One that 404s should leave the black frame the
                  // player would have shown anyway, not a console error and a broken box.
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
          FGestureLayer(ui: this),
          if (_isDesktop) FDesktopPointerLayer(ui: this, config: widget.config.desktop),
          FSubtitleView(
            controller: widget.controller,
            style: widget.subtitleStyle ?? widget.controller.config.subtitleStyle,
            bottomInset: _areControlsVisible && widget.config.showControls ? _bottomBarHeight : 0,
          ),
          if (widget.config.showControls && !_isLocked)
            IgnorePointer(
              ignoring: !_areControlsVisible,
              // Any touch on the chrome is an interaction, and an interaction restarts the
              // countdown. The controller's own notifications used to do this by accident, four
              // times a second; now that they no longer do, pressing mute or skip would let the
              // chrome fade out from under the viewer's finger.
              child: Listener(
                onPointerDown: (_) {
                  showControls();
                  // A click on a button is as much a claim on the keyboard as a click on the
                  // picture: pressing Pause in the bar and then Space should not type a space
                  // into whatever field held focus before.
                  _desktopLayer.currentState?.focusNode.requestFocus();
                },
                // Chrome that is not on screen must not be reachable either. Left focusable, the
                // autofocused play button keeps holding focus while invisible, so OK toggles
                // playback with nothing to show for it — and a screen reader walks a row of
                // buttons the viewer cannot see. A panel does the same to the chrome under it.
                child: ExcludeFocus(
                  excluding: !_areControlsVisible || _panel != null,
                  child: ExcludeSemantics(
                    excluding: !_areControlsVisible,
                    child: AnimatedOpacity(
                      opacity: _areControlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _buildChrome(context),
                    ),
                  ),
                ),
              ),
            ),
          // Not in fullscreen: there, the picture is the whole screen and the viewer chose to
          // put the chrome away. A hairline burning along the bottom edge of a film is the one
          // thing still on top of it.
          if (widget.config.showControls &&
              widget.config.showIdleProgressBar &&
              !widget.isFullscreen)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _areControlsVisible || value.hasError ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: _IdleProgress(key: const Key('fplayer.idle-progress'), ui: this),
              ),
            ),
          if (!_isLocked) FSkipMarker(ui: this),
          if (!_isLocked) FNextUpCard(ui: this),
          if (_isLocked) _LockedAffordance(ui: this),
          // Waiting for signal is not a "loading" status: the engine parks the failed load and
          // reports the player as simply not playing. Without this the viewer gets a play button
          // that does nothing and no hint as to why.
          if (value.status.isWaiting || value.isWaitingForNetwork)
            widget.loadingBuilder?.call(context, this) ?? _Spinner(ui: this),
          if (value.hasError)
            widget.errorBuilder?.call(context, this, value.error!) ??
                FErrorView(ui: this, error: value.error!),
          if (_panel != null) FPanelFocusScope(child: _panelFor(_panel!)),
          if (widget.overlayBuilder != null) widget.overlayBuilder!(context, this),
        ],
      ),
    );
  }

  Widget _panelFor(FPlayerPanel panel) => switch (panel) {
        FPlayerPanel.tracks => FTrackDialog(ui: this),
        FPlayerPanel.quality => FOptionsSheet(
            ui: this,
            title: widget.config.localizations.quality,
            children: qualityRows(this, onSelected: closePanel),
          ),
        FPlayerPanel.speed => FSpeedSheet(ui: this),
        FPlayerPanel.settings => FSettingsPanel(ui: this),
      };

  /// The desktop layer, for handing it the keyboard from a click on the chrome.
  final GlobalKey<FDesktopLayerState> _desktopLayer = GlobalKey<FDesktopLayerState>();

  /// Whether the mouse-and-keyboard chrome is in force: `FDesktopControls` in place of
  /// `FControlsOverlay`, and the pointer and key handling that goes with it.
  ///
  /// A remote layout asked for by name wins: `FTvMode.enabled` on a desktop is someone running a
  /// leanback build on their workstation, and they want to see the leanback build.
  bool get _isDesktop =>
      widget.config.tv.mode != FTvMode.enabled && isDesktopActive(widget.config.desktop);

  /// The remote config the TV layer is given.
  ///
  /// Under the desktop layout, `auto` is pinned to off. The desktop layer answers most keys,
  /// but the ones it leaves alone — Enter, an arrow while a panel is open — bubble up to the TV
  /// layer, and one of those was enough for `auto` to arm the remote layout for good: focus
  /// rings on, the speed control gone, and the parked focus node taking the shortcuts' focus
  /// away after every auto-hide.
  FTvConfig get _tvConfig => _isDesktop && widget.config.tv.mode == FTvMode.auto
      ? widget.config.tv.copyWith(mode: FTvMode.disabled)
      : widget.config.tv;

  /// The chrome for the input at hand. Both take the same bands from the same builders; only
  /// what fills in when a builder is not given differs.
  Widget _buildChrome(BuildContext context) {
    final topBar = widget.topBarBuilder?.call(context, this);
    final bottomBar = widget.bottomBarBuilder?.call(context, this);
    final center = widget.centerBuilder?.call(context, this);

    if (_isDesktop) {
      return FDesktopControls(
        ui: this,
        title: widget.title,
        subtitle: widget.subtitle,
        actions: widget.actions,
        previewBuilder: _previewBuilder,
        topBar: topBar,
        bottomBar: bottomBar,
        center: center,
      );
    }
    return FControlsOverlay(
      ui: this,
      title: widget.title,
      subtitle: widget.subtitle,
      actions: widget.actions,
      previewBuilder: _previewBuilder,
      topBar: topBar,
      bottomBar: bottomBar,
      center: center,
    );
  }

  /// Room the bottom band takes, so subtitles slide above it instead of hiding behind it.
  double get _bottomBarHeight {
    final theme = widget.config.theme;
    final seekBar = widget.config.showSeekBar ? theme.thumbRadius * 2 + 16 : 0;
    return theme.padding.vertical + seekBar + theme.iconSize + theme.spacing * 2;
  }
}

/// A hairline of progress along the bottom edge, shown while the controls are away.
///
/// The chrome starts hidden, so this is what answers "how far in am I" without asking for a tap.
/// Deliberately not interactive: it is thinner than any usable target, and the seek bar it hints
/// at is one tap away.
class _IdleProgress extends StatelessWidget {
  const _IdleProgress({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final value = ui.controller.value;
    if (value.duration == null || value.isLive) return const SizedBox.shrink();

    final played = value.progress.clamp(0.0, 1.0);
    final buffered = value.bufferedProgress.clamp(played, 1.0);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: 2.5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.trackColor.withValues(alpha: 0.25)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: buffered,
              child: ColoredBox(color: theme.bufferedColor.withValues(alpha: 0.35)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: played,
              child: ColoredBox(color: theme.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one control a locked player still answers to.
class _LockedAffordance extends StatelessWidget {
  const _LockedAffordance({required this.ui});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: ui.areControlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !ui.areControlsVisible,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.all(ui.theme.spacing * 2),
            child: FPlayerButton(
              icon: Icons.lock,
              theme: ui.theme,
              isActive: true,
              semanticLabel: ui.localizations.unlock,
              onPressed: () => ui.setLocked(locked: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal indeterminate spinner, so the package does not drag in Material's.
class _Spinner extends StatefulWidget {
  const _Spinner({required this.ui});

  final FPlayerUi ui;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;

    // A spinner with no explanation is indistinguishable from a hang. When the engine knows it
    // is parked waiting for signal, say so rather than let the viewer guess.
    final isWaitingForNetwork = widget.ui.controller.value.isWaitingForNetwork;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: theme.primaryIconSize,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _SpinnerPainter(progress: _controller.value, color: theme.foreground),
              ),
            ),
          ),
          if (isWaitingForNetwork) ...[
            SizedBox(height: theme.spacing),
            Text(
              widget.ui.localizations.waitingForNetwork,
              style: theme.labelStyle.copyWith(color: theme.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(
      Offset.zero & size,
      progress * 6.283185,
      2.2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.progress != progress || old.color != color;
}
