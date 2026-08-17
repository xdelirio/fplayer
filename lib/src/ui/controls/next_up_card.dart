import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../player_scope.dart';
import '../time_format.dart';
import 'focus_highlight.dart';

/// The "up next" offer that appears as an item runs out.
///
/// Shown whether or not the controls are up: it is most useful exactly when the chrome has faded
/// out and the credits are rolling. It offers the jump rather than counting down to it — the
/// controller advances on its own when `autoAdvance` is on, and a countdown that races an
/// automatic transition is noise.
class FNextUpCard extends StatelessWidget {
  const FNextUpCard({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final config = ui.config;
    if (!config.showNextUpCard) return const SizedBox.shrink();

    final value = ui.controller.value;
    final next = value.nextInPlaylist;
    final remaining = value.remaining;
    if (next == null || remaining == null || value.isLive) return const SizedBox.shrink();
    if (remaining > config.nextUpThreshold) return const SizedBox.shrink();

    final theme = ui.theme;

    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        child: Padding(
          // Above the controls, so it never lands under the seek bar.
          padding: EdgeInsets.only(
            right: theme.spacing * 2,
            bottom: ui.areControlsVisible ? theme.spacing * 10 : theme.spacing * 3,
          ),
          child: _Card(ui: ui, title: next.title, remaining: remaining),
        ),
      ),
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({required this.ui, required this.title, required this.remaining});

  final FPlayerUi ui;
  final String? title;
  final Duration remaining;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with FFocusHighlight {
  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;
    final l10n = widget.ui.localizations;

    return focusable(
      onActivate: widget.ui.controller.next,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.ui.controller.next,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(maxWidth: 280),
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing * 2,
            vertical: theme.spacing * 1.25,
          ),
          decoration: BoxDecoration(
            color: showsFocusRing ? theme.accent : theme.surface,
            borderRadius: theme.borderRadius,
            border: Border.all(color: theme.foreground.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.skip_next, color: theme.foreground, size: theme.iconSize),
              SizedBox(width: theme.spacing),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.nextUp} · ${formatMediaTime(widget.remaining)}',
                      style: theme.subtitleStyle.copyWith(color: theme.mutedForeground),
                    ),
                    Text(
                      widget.title ?? l10n.playNow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.labelStyle.copyWith(color: theme.foreground),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
