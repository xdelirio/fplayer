import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../config/tv_config.dart';
import '../player_scope.dart';

/// Seek one step in a direction, from a remote's left/right key.
class FSeekIntent extends Intent {
  const FSeekIntent(this.direction);

  /// `-1` back, `1` forward.
  final int direction;
}

/// Remote-control handling wrapped around the player.
///
/// Directional keys are claimed here rather than left to Flutter's focus traversal: on a video
/// player, left and right mean *scrub*, not "move to the next button". Up and down stay with the
/// default traversal, which is what moves focus between the rows of controls.
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

  FPlayerUi get _ui => widget.ui;

  /// Whether the remote layout is in force right now.
  bool get isTvActive => switch (widget.config.mode) {
        FTvMode.enabled => true,
        FTvMode.disabled => false,
        FTvMode.auto => _sawDirectionalKey,
      };

  @override
  void dispose() {
    _commitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.mode == FTvMode.disabled) return widget.child;

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
        // This node exists to watch keys on their way out, not to take focus away from controls.
        canRequestFocus: false,
        onKeyEvent: _onKey,
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): FSeekIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowRight): FSeekIntent(1),
          },
          child: Actions(
            actions: {
              FSeekIntent: CallbackAction<FSeekIntent>(
                onInvoke: (intent) {
                  _onDirectionalSeek(intent.direction);
                  return null;
                },
              ),
            },
            child: widget.child,
          ),
        ),
      ),
    );
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

  void _onDirectionalSeek(int direction) {
    // Left and right are claimed by the `Shortcuts` below this widget's own Focus node, so they
    // never reach `_onKey`. Everything a directional press implies has to happen here.
    if (!_sawDirectionalKey) setState(() => _sawDirectionalKey = true);

    if (_ui.isSettingsOpen) return;

    // The first press on a hidden player reveals the controls and does nothing else, so a viewer
    // never triggers an action they could not see.
    if (!_ui.areControlsVisible) {
      _ui.showControls();
      return;
    }

    final value = _ui.controller.value;
    if (!value.isSeekable || value.duration == null) return;

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
