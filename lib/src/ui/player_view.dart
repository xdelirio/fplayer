import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config/fullscreen_config.dart';
import '../config/subtitle_style.dart';
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
import 'controls/player_button.dart';
import 'controls/settings_panel.dart';
import 'controls/skip_marker.dart';
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
  bool _isSettingsOpen = false;
  bool _isScrubbing = false;
  Duration _scrubPosition = Duration.zero;
  late FVideoFit _fit = widget.config.fit;

  late final FStoryboardController _storyboard =
      widget.storyboardController ?? FStoryboardController();
  FStoryboardSource? _loadedStoryboard;
  bool _hasAutoEnteredFullscreen = false;

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
    if (widget.storyboardController == null) _storyboard.dispose();
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
  bool get isSettingsOpen => _isSettingsOpen;

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
    setState(() {
      _isLocked = locked;
      _isSettingsOpen = false;
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
  void openSettings() {
    _hideTimer?.cancel();
    setState(() {
      _isSettingsOpen = true;
      _areControlsVisible = true;
    });
  }

  @override
  void closeSettings() {
    setState(() => _isSettingsOpen = false);
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
      Navigator.of(context).maybePop();
      return;
    }

    final fullscreen = widget.fullscreen;
    final navigator = Navigator.of(context);

    widget.onFullscreenChanged?.call(true);
    await SystemChrome.setPreferredOrientations(
      fullscreen.orientationsFor(widget.controller.value.aspectRatio),
    );
    await SystemChrome.setEnabledSystemUIMode(fullscreen.systemUiMode);

    // The same controller, and therefore the same texture, so entering fullscreen costs a route
    // transition rather than a reload.
    await navigator.push(
      FFullscreenRoute<void>(
        builder: (context) => FFullscreenPage(child: _fullscreenCopy()),
      ),
    );

    await SystemChrome.setPreferredOrientations(fullscreen.restoreOrientations);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    widget.onFullscreenChanged?.call(false);
  }

  @override
  void back() {
    if (widget.isFullscreen) {
      Navigator.of(context).maybePop();
      return;
    }
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    Navigator.of(context).maybePop();
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
    if (value.hasError || value.isCompleted) {
      showControls();
    } else if (_areControlsVisible) {
      _restartHideTimer();
    }

    if (widget.fullscreen.exitOnComplete && widget.isFullscreen && value.isCompleted) {
      Navigator.of(context).maybePop();
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
    if (_isSettingsOpen || _isScrubbing) return false;
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
    final content = FPlayerScope(
      ui: this,
      child: FTvLayer(
        ui: this,
        config: widget.config.tv,
        child: _buildStack(context),
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
      return FVideoSurface(
        controller: widget.controller,
        fit: FVideoFit.contain,
        backgroundColor: widget.backgroundColor,
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
                Image.network(value.source!.posterUrl!, fit: BoxFit.cover),
          FGestureLayer(ui: this),
          FSubtitleView(
            controller: widget.controller,
            style: widget.subtitleStyle ?? widget.controller.config.subtitleStyle,
            bottomInset: _areControlsVisible && widget.config.showControls ? _bottomBarHeight : 0,
          ),
          if (widget.config.showControls && !_isLocked)
            IgnorePointer(
              ignoring: !_areControlsVisible,
              child: AnimatedOpacity(
                opacity: _areControlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: FControlsOverlay(
                  ui: this,
                  title: widget.title,
                  subtitle: widget.subtitle,
                  actions: widget.actions,
                  previewBuilder: _previewBuilder,
                  topBar: widget.topBarBuilder?.call(context, this),
                  bottomBar: widget.bottomBarBuilder?.call(context, this),
                  center: widget.centerBuilder?.call(context, this),
                ),
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
          if (_isSettingsOpen) FSettingsPanel(ui: this),
          if (widget.overlayBuilder != null) widget.overlayBuilder!(context, this),
        ],
      ),
    );
  }

  /// Room the bottom band takes, so subtitles slide above it instead of hiding behind it.
  double get _bottomBarHeight {
    final theme = widget.config.theme;
    final seekBar = widget.config.showSeekBar ? theme.thumbRadius * 2 + 16 : 0;
    return theme.padding.vertical + seekBar + theme.iconSize + theme.spacing * 2;
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
