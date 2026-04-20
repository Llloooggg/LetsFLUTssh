import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/first_launch_banner_provider.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// One-shot dialog shown once after the first-launch auto-setup
/// lands on a tier. Tells the user what the app just decided, and
/// surfaces the hardware-upgrade path (or the reason it is not
/// available) so the choice does not feel like a silent black-box
/// decision.
///
/// Dismiss closes the dialog and clears the state provider — the
/// signal is per-launch only, so a restart never re-opens it. The
/// auto-setup only runs on the very first launch (no DB file),
/// which is what gates the banner from coming back.
class FirstLaunchSecurityDialog extends StatelessWidget {
  const FirstLaunchSecurityDialog({
    super.key,
    required this.data,
    required this.onOpenSettings,
  });

  final FirstLaunchBannerData data;
  final VoidCallback onOpenSettings;

  /// Convenience show helper — non-dismissible barrier so the user
  /// has to acknowledge the security state before interacting with
  /// anything else.
  static Future<void> show(
    BuildContext context, {
    required FirstLaunchBannerData data,
    required VoidCallback onOpenSettings,
  }) {
    return AppDialog.show<void>(
      context,
      barrierDismissible: false,
      builder: (_) =>
          FirstLaunchSecurityDialog(data: data, onOpenSettings: onOpenSettings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);

    final primaryLine = l10n.firstLaunchSecurityBody;

    final upgradeLine = data.hardwareUpgradeAvailable
        ? l10n.firstLaunchSecurityUpgradeAvailable
        : _unavailableCopy(l10n, data.hardwareUnavailableReason);

    return AppDialog(
      title: l10n.firstLaunchSecurityTitle,
      dismissible: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: AppTheme.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  primaryLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.fg,
                  ),
                ),
              ),
            ],
          ),
          if (upgradeLine != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bg2,
                borderRadius: AppTheme.radiusSm,
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    data.hardwareUpgradeAvailable
                        ? Icons.lightbulb_outline
                        : Icons.info_outline,
                    size: 18,
                    color: AppTheme.fgDim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      upgradeLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.fgDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (data.hardwareUpgradeAvailable)
          AppDialogAction(
            label: l10n.firstLaunchSecurityOpenSettings,
            onTap: () {
              Navigator.of(context).pop();
              onOpenSettings();
            },
          ),
        AppDialogAction.primary(
          label: l10n.firstLaunchSecurityDismiss,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static String? _unavailableCopy(S l10n, HardwareUnavailableReason? reason) {
    // If the reason is null, the caller had no hardware-upgrade
    // context at all (e.g. T1 auto-setup on a platform where we
    // don't want to pitch T2 at all) — skip the second paragraph.
    if (reason == null) return null;
    switch (reason) {
      case HardwareUnavailableReason.noSecureEnclave:
        return l10n.firstLaunchSecurityHardwareUnavailableApple;
      case HardwareUnavailableReason.noTpm:
        return l10n.firstLaunchSecurityHardwareUnavailableWindows;
      case HardwareUnavailableReason.noTpm2Tools:
        return l10n.firstLaunchSecurityHardwareUnavailableLinux;
      case HardwareUnavailableReason.noAndroidKeystoreHardware:
        return l10n.firstLaunchSecurityHardwareUnavailableAndroid;
      case HardwareUnavailableReason.generic:
        return l10n.firstLaunchSecurityHardwareUnavailableGeneric;
    }
  }
}
