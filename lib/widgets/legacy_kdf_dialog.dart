import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Action chosen by the user in [LegacyKdfDialog].
enum LegacyKdfChoice {
  /// Wipe all encrypted data and continue with a fresh credential set.
  resetAndContinue,

  /// Quit the app without mutating storage. Lets the user reinstall an
  /// older build of LetsFLUTssh to export their data first if they
  /// regret the upgrade.
  exitApp,
}

/// Force-breaking migration notice. Shown at startup when the install
/// carries the legacy PBKDF2 `credentials.salt` file but no new
/// `credentials.kdf` — the only path forward is to reset credentials or
/// quit. The dialog is non-dismissible; both buttons return a concrete
/// [LegacyKdfChoice] so the caller knows which path to take.
class LegacyKdfDialog extends StatelessWidget {
  const LegacyKdfDialog({super.key});

  /// Show the dialog and wait for a choice. Never resolves until the
  /// user picks exit or reset. Returns the chosen action.
  static Future<LegacyKdfChoice> show(BuildContext context) async {
    final result = await showDialog<LegacyKdfChoice>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const LegacyKdfDialog(),
    );
    return result ?? LegacyKdfChoice.exitApp;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return PopScope(
      canPop: false,
      child: AppDialog(
        title: l10n.legacyKdfTitle,
        maxWidth: 480,
        dismissible: false,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.legacyKdfBody,
              style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.md),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.legacyKdfWarning,
              style: TextStyle(
                color: AppTheme.red,
                fontSize: AppFonts.sm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          AppDialogAction.secondary(
            label: l10n.legacyKdfExit,
            onTap: () => Navigator.of(context).pop(LegacyKdfChoice.exitApp),
          ),
          AppDialogAction.destructive(
            label: l10n.legacyKdfResetContinue,
            onTap: () =>
                Navigator.of(context).pop(LegacyKdfChoice.resetAndContinue),
          ),
        ],
      ),
    );
  }
}
