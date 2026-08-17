import 'package:flutter/widgets.dart';

import '../../models/player_source.dart';
import '../player_scope.dart';
import 'focus_highlight.dart';

/// The "skip intro" affordance, shown while playback sits inside a marked span.
///
/// Independent of the controls: it has to be reachable when the chrome has faded out, because
/// that is exactly when an intro is playing and someone wants past it.
class FSkipMarker extends StatelessWidget {
  const FSkipMarker({required this.ui, super.key});

  final FPlayerUi ui;

  @override
  Widget build(BuildContext context) {
    final chapter = _currentSkippable;
    if (chapter == null) return const SizedBox.shrink();

    final theme = ui.theme;

    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        child: Padding(
          // Sits above the controls so it never lands under the seek bar.
          padding: EdgeInsets.only(
            right: theme.spacing * 2,
            bottom: ui.areControlsVisible ? theme.spacing * 10 : theme.spacing * 3,
          ),
          child: _SkipButton(
            ui: ui,
            label: _labelFor(chapter.kind),
            onPressed: () => ui.controller.seekTo(chapter.end!),
          ),
        ),
      ),
    );
  }

  /// The marked span the playhead is inside, if it is one worth offering to skip.
  ///
  /// A span with no end cannot be skipped past, so it is ignored rather than offered.
  FChapter? get _currentSkippable {
    final value = ui.controller.value;
    final chapters = value.source?.chapters ?? const <FChapter>[];
    if (chapters.isEmpty || !value.isSeekable) return null;

    final position = value.position;
    for (final chapter in chapters) {
      final end = chapter.end;
      if (end == null || chapter.kind == FChapterKind.chapter) continue;
      if (position >= chapter.start && position < end) return chapter;
    }
    return null;
  }

  String _labelFor(FChapterKind kind) => switch (kind) {
        FChapterKind.intro => ui.localizations.skipIntro,
        FChapterKind.recap => ui.localizations.skipRecap,
        FChapterKind.credits => ui.localizations.skipCredits,
        FChapterKind.ad => ui.localizations.skipAd,
        FChapterKind.chapter => ui.localizations.next,
      };
}

class _SkipButton extends StatefulWidget {
  const _SkipButton({required this.ui, required this.label, required this.onPressed});

  final FPlayerUi ui;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> with FFocusHighlight {
  @override
  Widget build(BuildContext context) {
    final theme = widget.ui.theme;

    return focusable(
      onActivate: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing * 2,
            vertical: theme.spacing,
          ),
          decoration: BoxDecoration(
            color: showsFocusRing ? theme.accent : theme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.foreground.withValues(alpha: 0.35)),
          ),
          child: Text(
            widget.label,
            style: theme.labelStyle.copyWith(color: theme.foreground),
          ),
        ),
      ),
    );
  }
}
