import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../config/tv_config.dart';
import '../controls/focus_highlight.dart';
import '../player_scope.dart';

/// Seek one step in a direction, from a remote's left/right key.
///
/// Dispatched by the seek bar while it holds focus, and available to any custom control that
/// wants the same accelerated, deferred seek: `Actions.invoke(context, const FSeekIntent(1))`.
class FSeekIntent extends Intent {
  const FSeekIntent(this.direction);

  /// `-1` back, `1` forward.
  final int direction;
}

/// Remote-control handling wrapped around the player.
///
/// Directional keys stay with Flutter's focus traversal, so left and right walk the row of
/// controls the way a remote user expects everywhere else. Scrubbing is what the *seek bar* does
/// with those keys once it holds focus: [FProgressBar] asks this layer for a step, and the
/// acceleration and the deferred commit live here.
///
/// What this layer does own is everything that is not tied to one control: media keys, back, and
/// the rule that the first press on a hidden player only brings the chrome up.
class FTvLayer extends StatefulWidget {
  const FTvLayer({
    required this.ui,
    required this.config,
    required this.child,
    super.key,
  });

  final FPlayerUi ui;
  final FTvConfig config;
  final Widget child;

  @override
  State<FTvLayer> createState() => FTvLayerState();
}

class FTvLayerState extends State<FTvLayer> {
  Timer? _commitTimer;
  Duration _seekTarget = Duration.zero;
  int _repeats = 0;
  bool _sawDirectionalKey = false;

  /// Where focus rests while the chrome is away.
  ///
  /// The controls are unfocusable when hidden — an invisible button that answers OK is worse
  /// than no button — which leaves a remote with nothing to press against. This node is that
  /// somewhere: out of traversal, invisible, and holding the key handling that brings the chrome
  /// back on the first press.
  final FocusNode _parked = FocusNode(debugLabel: 'fplayer.tv-layer', skipTraversal: true);

  FPlayerUi get _ui => widget.ui;

  /// Whether the remote layout is in force right now.
  bool get isTvActive => switch (widget.config.mode) {
        FTvMode.enabled => true,
        FTvMode.disabled => false,
        FTvMode.auto => _sawDirectionalKey,
      };

  @override
  void dispose() {
    // A seek the viewer asked for and then left the screen on is still a seek they asked for:
    // dropping it silently is the one outcome nobody wants.
    if (_commitTimer?.isActive ?? false) _ui.endScrub();
    _commitTimer?.cancel();
    _parked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.mode == FTvMode.disabled) return widget.child;

    // Focus follows the chrome: parked here while it is away, handed back to a real control when
    // it returns. Without the second half, focus stays on a node that spans the whole player and
    // contains every candidate, so directional traversal has nowhere to go and the remote is
    // stuck — the controls are on screen and nothing answers.
    //
    // Only under a remote, and only over focus the player already held. This runs on every
    // controller notification — four times a second while playing — so an unconditional
    // `requestFocus` would take focus from the app around it and keep taking it: a text field
    // beside an inline player could not hold focus at all.
    if (isTvActive) {
      WidgetsBinding.instance.addPostFrameCallback(_settleFocus);
    }

    return PopScope(
      // Back gets to close the controls before it closes the player, but only while they are up.
      canPop: !(widget.config.backHidesControls && _ui.areControlsVisible),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_ui.isSettingsOpen) {
          _ui.closeSettings();
        } else {
          _ui.hideControls();
        }
      },
      child: Focus(
        // This node watches keys on their way out rather than competing for focus with the
        // controls — but it can hold focus itself, for the stretch when there is no chrome to
        // hold it. See [_parked].
        focusNode: _parked,
        onKeyEvent: _onKey,
        child: Actions(
          // Left as an action rather than a shortcut: a shortcut here would fire wherever focus
          // happens to be, which is exactly the bug where every button seeked instead of moving
          // focus. The seek bar invokes it; so can a custom control.
          actions: {
            FSeekIntent: CallbackAction<FSeekIntent>(
              onInvoke: (intent) => seekStep(intent.direction),
            ),
          },
          child: FTvScope(
            isActive: isTvActive,
            seek: seekStep,
            commitSeek: commitSeek,
            // A leanback build has no touch to tell Flutter that focus is worth drawing, so on a
            // remote-first player the ring has to be on from the first frame rather than from
            // the first press.
            child: FTvFocusMode(
              isRemoteDriven: isTvActive,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps focus somewhere usable as the chrome comes and goes.
  void _settleFocus(Duration _) {
    if (!mounted || !isTvActive) return;

    if (_ui.areControlsVisible) {
      if (_parked.hasPrimaryFocus) _parked.nextFocus();
      return;
    }

    // `hasFocus`, not `hasPrimaryFocus`: this is asking "was the focus that just disappeared
    // ours?". Every control is a descendant of this node, so on the frame the chrome is taken
    // away that is still true — and it is exactly the case worth catching. When the answer is
    // no, the focus belongs to the app around the player and is none of this layer's business.
    if (_parked.hasFocus && !_parked.hasPrimaryFocus) {
      _parked.requestFocus();
      return;
    }

    // Nobody at all holds focus yet: the first frame of a remote-first player whose chrome
    // starts away. There is nothing to take focus *from*, and without this the player has no
    // focusable node and no key handling — every press on the remote goes nowhere.
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) _parked.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Releasing a key is not an action. The repeat count is reset by the commit timer instead,
    // so a run of quick separate presses accelerates the same way a held key does — which is how
    // people actually drive a remote.
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (widget.config.handleMediaKeys && _handleMediaKey(key)) {
      return KeyEventResult.handled;
    }

    if (_isDirectional(key) || _isSelect(key)) {
      if (!_sawDirectionalKey) setState(() => _sawDirectionalKey = true);

      // The first press on a hidden player reveals the controls and does nothing else, so a
      // viewer never triggers an action they could not see.
      if (!_ui.areControlsVisible) {
        _ui.showControls();
        return KeyEventResult.handled;
      }
      _ui.showControls();
    }

    return KeyEventResult.ignored;
  }

  bool _handleMediaKey(LogicalKeyboardKey key) {
    final controller = _ui.controller;

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      controller.togglePlayPause();
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      controller.play();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      controller.pause();
    } else if (key == LogicalKeyboardKey.mediaStop) {
      controller.pause();
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      controller.skipForward();
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      controller.skipBackward();
    } else {
      return false;
    }

    _ui.showControls();
    return true;
  }

  /// Moves the pending seek one step in [direction], accelerating over a run of presses.
  ///
  /// The seek bar calls this when it holds focus and a directional key arrives; nothing reaches
  /// `_onKey` in that case, so everything a directional press implies has to happen here.
  ///
  /// Returns whether the press was spent on a seek. When it was not — a panel is over the
  /// picture, the media cannot be seeked — the caller has to let the key travel on, or the seek
  /// bar becomes a place focus can enter and never leave.
  bool seekStep(int direction) {
    if (!_sawDirectionalKey) setState(() => _sawDirectionalKey = true);

    if (_ui.isSettingsOpen) return false;

    // The first press on a hidden player reveals the controls and does nothing else, so a viewer
    // never triggers an action they could not see.
    if (!_ui.areControlsVisible) {
      _ui.showControls();
      return true;
    }

    final value = _ui.controller.value;
    if (!value.isSeekable || value.duration == null) return false;

    if (!_ui.isScrubbing) {
      _seekTarget = value.position;
      _repeats = 0;
      _ui.beginScrub();
    }

    _repeats++;
    final step = _ui.controller.config.playback.seekStep * _multiplier;
    _seekTarget += direction > 0 ? step : -step;

    final duration = value.duration!;
    if (_seekTarget < Duration.zero) _seekTarget = Duration.zero;
    if (_seekTarget > duration) _seekTarget = duration;

    _ui.updateScrub(_seekTarget);
    _ui.showControls();

    _commitTimer?.cancel();
    _commitTimer = Timer(widget.config.seekCommitDelay, () {
      _repeats = 0;
      if (mounted) _ui.endScrub();
    });
    return true;
  }

  /// Sends the pending seek to the engine now, instead of waiting out the quiet time.
  ///
  /// This is what OK means while the seek bar is being walked: the viewer has arrived.
  void commitSeek() {
    _commitTimer?.cancel();
    _repeats = 0;
    _ui.endScrub();
  }

  /// Grows every few presses so a long hold covers ground, then flattens out.
  int get _multiplier {
    if (!widget.config.seekAcceleration) return 1;
    return (1 + _repeats ~/ 4).clamp(1, widget.config.maxSeekMultiplier);
  }

  static bool _isDirectional(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  static bool _isSelect(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;
}

/// Whether a remote is driving the player, and the seek that remote performs.
///
/// The controls read [isActive] to lay themselves out for a D-pad — a control that costs two
/// presses to reach and is never touched from a sofa does not belong in the row a remote has to
/// walk. The seek bar uses [seek] and [commitSeek] so the acceleration and the deferred commit
/// stay in one place instead of being reimplemented per control.
class FTvScope extends InheritedWidget {
  const FTvScope({
    required this.isActive,
    required this.seek,
    required this.commitSeek,
    required super.child,
    super.key,
  });

  /// Whether the remote layout is in force: always in `FTvMode.enabled`, and from the first
  /// directional press in `FTvMode.auto`.
  final bool isActive;

  /// Moves the pending seek one step: `-1` back, `1` forward.
  ///
  /// The preview moves at once and grows with a run of presses; the engine is told once the
  /// presses stop, or when [commitSeek] is called. Answers whether the step was taken: a player
  /// with a panel open, or media that cannot be seeked, leaves the key to whoever else wants it.
  final bool Function(int direction) seek;

  /// Commits the pending seek immediately.
  final VoidCallback commitSeek;

  /// The nearest TV layer, or null when there is none — a player with `FTvMode.disabled`, or a
  /// control built outside `FPlayerView`.
  static FTvScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FTvScope>();

  @override
  bool updateShouldNotify(FTvScope oldWidget) => oldWidget.isActive != isActive;
}
