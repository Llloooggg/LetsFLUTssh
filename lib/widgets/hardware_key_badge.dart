import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Hardware-bound (FIDO2)" pill rendered next to FIDO2 sk-* SSH key
/// rows. Used by the standalone key manager list and the session-edit
/// "Key from manager" picker so corp users with mixed software /
/// hardware key stores can tell at a glance which row is which.
///
/// Visual contract mirrors `Pkcs11Badge` / `EnclaveBadge` / `HelloBadge`
/// / `TpmBadge` / `KeystoreBadge` so a row carrying multiple badges
/// reads consistently regardless of which list surface renders it.
class HardwareKeyBadge extends StatelessWidget {
  final String label;
  const HardwareKeyBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.16),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.usb, size: 12, color: AppTheme.accent),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppFonts.inter(
              fontSize: AppFonts.xxs,
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
