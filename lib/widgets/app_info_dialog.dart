import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Reusable threat-model explainer.
///
/// Shown from the `(i)` button next to security-tier rows in the
/// first-launch wizard and the Settings → Security section. Two
/// bulleted columns: what the tier protects against (green check
/// icon), and what it explicitly does not protect against (red cross
/// icon). The whole point is that a user reading a wizard row knows
/// what they're getting into before they pick it — "Plaintext" is not
/// a hidden choice, and "Paranoid" is not sold as bulletproof against
/// weak user passwords.
///
/// The widget is storage-agnostic — callers pass localized strings
/// in. Keeping the dialog ignorant of any particular tier means it
/// can also be reused for any other feature that wants an honest
/// "what this does / doesn't do" explainer.
class AppInfoDialog extends StatelessWidget {
  const AppInfoDialog({
    super.key,
    required this.title,
    required this.protectsAgainst,
    required this.doesNotProtectAgainst,
    this.extraNotes,
  });

  /// Section title — usually the feature / tier name.
  final String title;

  /// Bullets rendered with a green check icon. Each string is one
  /// threat this feature / tier defends against.
  final List<String> protectsAgainst;

  /// Bullets rendered with a red cross icon. Each string is one
  /// threat this feature / tier does **not** defend against — the
  /// explicit acknowledgement that security is not total.
  final List<String> doesNotProtectAgainst;

  /// Optional free-form paragraph shown under the two lists. Use for
  /// caveats that don't fit a single bullet (e.g. "requires TPM2",
  /// "biometric is a shortcut, not a factor").
  final String? extraNotes;

  /// Show the dialog. Returns after user dismisses.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<String> protectsAgainst,
    required List<String> doesNotProtectAgainst,
    String? extraNotes,
  }) {
    return AppDialog.show<void>(
      context,
      builder: (_) => AppInfoDialog(
        title: title,
        protectsAgainst: protectsAgainst,
        doesNotProtectAgainst: doesNotProtectAgainst,
        extraNotes: extraNotes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (protectsAgainst.isNotEmpty) ...[
            _sectionHeader(
              context,
              l10n.infoDialogProtectsHeader,
              icon: Icons.check_circle_outline,
              color: AppTheme.green,
            ),
            const SizedBox(height: 6),
            ...protectsAgainst.map(
              (b) => _bullet(b, Icons.check, AppTheme.green),
            ),
            const SizedBox(height: 14),
          ],
          if (doesNotProtectAgainst.isNotEmpty) ...[
            _sectionHeader(
              context,
              l10n.infoDialogDoesNotProtectHeader,
              icon: Icons.block,
              color: AppTheme.red,
            ),
            const SizedBox(height: 6),
            ...doesNotProtectAgainst.map(
              (b) => _bullet(b, Icons.close, AppTheme.red),
            ),
          ],
          if (extraNotes != null) ...[
            const SizedBox(height: 14),
            Text(
              extraNotes!,
              style: TextStyle(
                fontSize: AppFonts.sm,
                color: AppTheme.fgDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
      actions: [
        AppDialogAction.primary(
          label: l10n.ok,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String label, {
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: AppFonts.md,
            color: AppTheme.fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _bullet(String text, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
            ),
          ),
        ],
      ),
    );
  }
}
