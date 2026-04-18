import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Action chosen in [TierResetDialog].
enum TierResetChoice {
  /// Wipe every legacy security file + DB and run the new-version
  /// first-launch wizard from scratch.
  resetAndSetupFresh,

  /// Quit the app. Lets the user reinstall an older build to export
  /// their data first.
  exitApp,
}

/// Breaking-change migration notice. Shown at startup when the
/// install carries any legacy security state (credentials.kdf,
/// keychain marker, biometric vault) but no `security_tier` field in
/// the new `config.json`. There is no automatic migration — users
/// acknowledge the reset or quit. The dialog is non-dismissible.
class TierResetDialog extends StatelessWidget {
  const TierResetDialog({super.key});

  /// Show the dialog. Never resolves until user picks one of the
  /// buttons; defaults to [TierResetChoice.exitApp] on programmatic
  /// dismiss so the app does not silently fall through to a half-
  /// migrated state.
  static Future<TierResetChoice> show(BuildContext context) async {
    final result = await showDialog<TierResetChoice>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const TierResetDialog(),
    );
    return result ?? TierResetChoice.exitApp;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return PopScope(
      canPop: false,
      child: AppDialog(
        title: l10n.tierResetTitle,
        maxWidth: 480,
        dismissible: false,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.tierResetBody,
              style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.md),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.tierResetWarning,
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
            label: l10n.tierResetExit,
            onTap: () => Navigator.of(context).pop(TierResetChoice.exitApp),
          ),
          AppDialogAction.destructive(
            label: l10n.tierResetResetContinue,
            onTap: () =>
                Navigator.of(context).pop(TierResetChoice.resetAndSetupFresh),
          ),
        ],
      ),
    );
  }
}
