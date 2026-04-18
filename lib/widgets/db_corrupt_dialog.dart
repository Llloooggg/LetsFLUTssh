import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Outcome of the DB-corruption reset dialog.
enum DbCorruptChoice {
  /// User accepted the destructive reset — caller wipes every
  /// security file + DB + keychain entries, then drops into the
  /// first-launch wizard.
  resetAndSetupFresh,

  /// User chose to quit so they can reinstall a compatible build and
  /// recover their data instead of wiping.
  exitApp,
}

/// Non-dismissible dialog shown when the database file on disk does
/// not match the cipher recorded in `config.json` — typically a
/// tier-refactor interruption or a build mismatch.
///
/// Mirrors [TierResetDialog] in shape and tone: two explicit
/// actions, a red warning paragraph, no back-button escape. Never
/// wipes by itself — the caller owns the destructive step only
/// after the user clicks "Reset & Setup Fresh".
class DbCorruptDialog extends StatelessWidget {
  const DbCorruptDialog({super.key});

  static Future<DbCorruptChoice> show(BuildContext context) async {
    final result = await AppDialog.show<DbCorruptChoice>(
      context,
      barrierDismissible: false,
      builder: (_) => const DbCorruptDialog(),
    );
    return result ?? DbCorruptChoice.exitApp;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.dbCorruptTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.dbCorruptBody,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.dbCorruptWarning,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.red),
          ),
        ],
      ),
      actions: [
        AppDialogAction.secondary(
          label: l10n.dbCorruptExit,
          onTap: () => Navigator.of(context).pop(DbCorruptChoice.exitApp),
        ),
        AppDialogAction.destructive(
          label: l10n.dbCorruptResetContinue,
          onTap: () =>
              Navigator.of(context).pop(DbCorruptChoice.resetAndSetupFresh),
        ),
      ],
    );
  }
}
