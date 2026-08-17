import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/player_error.dart';
import '../localizations.dart';
import '../player_scope.dart';
import 'player_button.dart';

/// What the player shows when playback has failed for good.
///
/// The engine's own message is not shown: it is untranslated and written for a developer. The
/// error *code* is what carries meaning, so it is turned into a sentence the viewer can act on,
/// and the raw text is left in `controller.value.error` for logs.
class FErrorView extends StatelessWidget {
  const FErrorView({required this.ui, required this.error, super.key});

  final FPlayerUi ui;
  final FPlayerError error;

  @override
  Widget build(BuildContext context) {
    final theme = ui.theme;
    final l10n = ui.localizations;

    return ColoredBox(
      color: const Color(0xE6000000),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(theme.spacing * 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(error.code),
                size: theme.primaryIconSize,
                color: theme.mutedForeground,
              ),
              SizedBox(height: theme.spacing * 1.5),
              Text(
                l10n.errorTitle,
                textAlign: TextAlign.center,
                style: theme.titleStyle.copyWith(color: theme.foreground),
              ),
              SizedBox(height: theme.spacing / 2),
              Text(
                messageFor(error.code, l10n),
                textAlign: TextAlign.center,
                style: theme.subtitleStyle.copyWith(color: theme.mutedForeground),
              ),
              if (error.isRetryable) ...[
                SizedBox(height: theme.spacing * 2),
                FPlayerTextButton(
                  label: l10n.retry,
                  theme: theme,
                  onPressed: ui.controller.retry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Sentence for an error code. Public so a custom error builder can reuse the mapping instead
  /// of writing its own switch.
  static String messageFor(FPlayerErrorCode code, FPlayerLocalizations l10n) => switch (code) {
        FPlayerErrorCode.network ||
        FPlayerErrorCode.timeout ||
        FPlayerErrorCode.io =>
          l10n.errorNetwork,
        FPlayerErrorCode.unauthorized => l10n.errorUnauthorized,
        FPlayerErrorCode.forbidden || FPlayerErrorCode.notFound => l10n.errorNotFound,
        FPlayerErrorCode.unsupportedFormat || FPlayerErrorCode.decoder => l10n.errorUnsupported,
        _ => l10n.errorGeneric,
      };

  static IconData _iconFor(FPlayerErrorCode code) => switch (code) {
        FPlayerErrorCode.network || FPlayerErrorCode.timeout => Icons.wifi_off,
        FPlayerErrorCode.unauthorized || FPlayerErrorCode.forbidden => Icons.lock,
        FPlayerErrorCode.notFound => Icons.search_off,
        FPlayerErrorCode.unsupportedFormat || FPlayerErrorCode.decoder => Icons.videocam_off,
        _ => Icons.error_outline,
      };
}
