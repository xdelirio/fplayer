import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../config/desktop_config.dart';
import '../player_scope.dart';
import '../tv/tv_layer.dart' show handleMediaKey;

/// Whether the mouse-and-keyboard layout applies for [config] on the platform this runs on.
bool isDesktopActive(FDesktopConfig config) => switch (config.mode) {
      FDesktopMode.enabled => true,
      FDesktopMode.disabled => false,
      FDesktopMode.auto => switch (defaultTargetPlatform) {
          TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
          _ => false,
        },
    };

/// Mouse and keyboard handling around the whole player.
///
/// Sits where `FTvLayer` sits, around the stack, so the pointer is seen wherever it is — over
/// the picture or over the chrome — and the keys reach the player without a button having to
/// hold focus. Moving the mouse reveals the controls, leaving the player hides them, and an idle
/// pointer over a playing picture disappears along with them.
///
/// What a click *on the picture* does is [FDesktopPointerLayer]'s job, which lives inside the
/// stack so the chrome above it keeps its clicks.
class FDesktopLayer extends StatefulWidget {
  const FDesktopLayer({
    required this.ui,
    required this.config,
    required this.child,
    super.key,
  });

  final FPlayerUi ui;
  final FDesktopConfig config;
  final Widget child;

  @override
  State<FDesktopLayer> createState() => FDesktopLayerState();
}

class FDesktopLayerState extends State<FDesktopLayer> {
  /// Focus for the shortcuts: held by the player as a whole, not by any one control, so Space
  /// pauses whether or not a button was the last thing clicked.
  final FocusNode focusNode = FocusNode(debugLabel: 'fplayer.desktop-layer');

  Timer? _leaveTimer;

  FPlayerUi get _ui => widget.ui;

  @override
  void dispose() {
    _leaveTimer?.cancel();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _ui.controller.value;
    final hideCursor = widget.config.hideCursorWithControls &&
        !_ui.areControlsVisible &&
        value.isPlaying &&
        !_ui.isLocked;

    return FDesktopScope(
      isActive: true,
      focusNode: focusNode,
      child: Focus(
        focusNode: focusNode,
        autofocus: widget.config.autofocus,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (_) => _onPointerMoved(),
          onEnter: (_) => _onPointerMoved(),
          onExit: (_) => _onPointerLeft(),
          child: widget.child,
        ),
      ),
    );
  }

  void _onPointerMoved() {
    _leaveTimer?.cancel();
    if (_ui.isLocked) return;
    _ui.showControls();
  }

  /// The pointer left the player: the chrome goes away soon after, without waiting out the
  /// full idle timeout. Someone who moved to another window is not about to click a button.
  void _onPointerLeft() {
    _leaveTimer?.cancel();
    if (_ui.isSettingsOpen) return;
    _leaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _ui.isSettingsOpen || _ui.isScrubbing) return;
      // Paused keeps the chrome on the touch layout too, and for the same reason: whoever
      // paused is about to do something with it.
      if (_ui.config.keepControlsWhilePaused && !_ui.controller.value.isPlaying) return;
      _ui.hideControls();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final controller = _ui.controller;

    if (handleMediaKey(controller, key)) {
      _ui.showControls();
      return KeyEventResult.handled;
    }

    if (!widget.config.keyboardShortcuts || _ui.isLocked) return KeyEventResult.ignored;

    // A panel owns the keyboard while it is up: arrows walk its rows, Escape closes it.
    if (_ui.isSettingsOpen) {
      if (key == LogicalKeyboardKey.escape) {
        _ui.closePanel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final value = controller.value;
    final step = widget.config.volumeStep;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      controller.togglePlayPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (!value.isSeekable) return KeyEventResult.ignored;
      controller.skipBackward();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (!value.isSeekable) return KeyEventResult.ignored;
      controller.skipForward();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      controller.setVolume(value.volume + step);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      controller.setVolume(value.volume - step);
    } else if (key == LogicalKeyboardKey.keyM) {
      controller.toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      _ui.toggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape) {
      if (!_ui.isFullscreen) return KeyEventResult.ignored;
      _ui.toggleFullscreen();
    } else {
      return KeyEventResult.ignored;
    }

    _ui.showControls();
    return KeyEventResult.handled;
  }
}

/// What a mouse does on the picture itself: click to pause, double-click for fullscreen, scroll
/// for volume.
///
/// Inside the stack, above the touch gestures and below the chrome, so a click on a button is a
/// button press and a click anywhere else is a pause. Opaque on purpose: the touch gesture layer
/// under it — swipe to seek, pinch to fit — is not what a mouse is for.
class FDesktopPointerLayer extends StatelessWidget {
  const FDesktopPointerLayer({required this.ui, required this.config, super.key});

  final FPlayerUi ui;
  final FDesktopConfig config;

  @override
  Widget build(BuildContext context) {
    final controller = ui.controller;

    return Listener(
      onPointerSignal: config.scrollAdjustsVolume ? _onScroll : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => FDesktopScope.maybeOf(context)?.focusNode.requestFocus(),
        onTap: () {
          if (ui.isLocked) return;
          if (config.clickTogglesPlayback) {
            controller.togglePlayPause();
          } else {
            ui.toggleControls();
          }
        },
        // With a double-click to watch for, a single click is only reported once the window for
        // a second one has closed — the same short pause before a pause that every desktop
        // player with the same two gestures has.
        onDoubleTap: config.doubleClickTogglesFullscreen && !ui.isLocked ? ui.toggleFullscreen : null,
        child: const SizedBox.expand(),
      ),
    );
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || ui.isLocked) return;
    final controller = ui.controller;
    final direction = event.scrollDelta.dy.sign;
    if (direction == 0) return;
    // Wheel up raises the volume, as it does in every desktop player, and dy is negative then.
    controller.setVolume(controller.value.volume - direction * config.volumeStep);
    ui.showControls();
  }
}

/// Tells the chrome the mouse layout is in force and where the shortcut focus lives.
class FDesktopScope extends InheritedWidget {
  const FDesktopScope({
    required this.isActive,
    required this.focusNode,
    required super.child,
    super.key,
  });

  final bool isActive;

  /// The node that answers the keyboard shortcuts. A control that takes focus for its own
  /// purposes — the volume slider while dragging — hands it back here.
  final FocusNode focusNode;

  static FDesktopScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FDesktopScope>();

  @override
  bool updateShouldNotify(FDesktopScope oldWidget) =>
      oldWidget.isActive != isActive || oldWidget.focusNode != focusNode;
}
