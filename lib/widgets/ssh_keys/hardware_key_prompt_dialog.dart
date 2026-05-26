import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../security/secure_password_field.dart';

/// Result of a [HardwareKeyPromptDialog]. `cancelled` is `true` when
/// the user dismissed the dialog before tapping the device; `pin` is
/// the PIN entered when the credential requires user verification —
/// `null` when the credential is touch-only.
class HardwareKeyPromptResult {
  final String? pin;
  final bool cancelled;

  const HardwareKeyPromptResult({this.pin, this.cancelled = false});
}

/// Modal that prompts the user to tap their hardware key (and, when
/// the credential carries user-verification, enter a PIN). Used by
/// the SSH connect dispatch when the resolved key is `sk-*`.
///
/// Visual contract mirrors `unlock_dialog.dart` so the security-
/// related affordances read the same way across the app: dim header,
/// neutral body copy, single primary action.
class HardwareKeyPromptDialog extends StatefulWidget {
  /// Human-readable label of the hardware key being polled. Used by
  /// the device-name line of the body copy.
  final String deviceName;

  /// When `true`, render a PIN field; the user MUST enter a PIN
  /// before the primary action becomes enabled.
  final bool requiresPin;

  const HardwareKeyPromptDialog({
    super.key,
    required this.deviceName,
    required this.requiresPin,
  });

  /// Show the dialog. Returns `null` when the route was popped
  /// without an explicit choice (e.g. system back gesture); the
  /// connect path treats `null` and `cancelled = true` the same way.
  static Future<HardwareKeyPromptResult?> show(
    BuildContext context, {
    required String deviceName,
    required bool requiresPin,
  }) {
    return AppDialog.show<HardwareKeyPromptResult>(
      context,
      builder: (_) => HardwareKeyPromptDialog(
        deviceName: deviceName,
        requiresPin: requiresPin,
      ),
    );
  }

  @override
  State<HardwareKeyPromptDialog> createState() =>
      _HardwareKeyPromptDialogState();
}

class _HardwareKeyPromptDialogState extends State<HardwareKeyPromptDialog> {
  final _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = widget.requiresPin ? _pinCtrl.text : null;
    if (widget.requiresPin && (pin == null || pin.isEmpty)) {
      return;
    }
    Navigator.of(
      context,
    ).pop(HardwareKeyPromptResult(pin: pin, cancelled: false));
  }

  void _cancel() {
    Navigator.of(context).pop(const HardwareKeyPromptResult(cancelled: true));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.hardwareKeyTapPrompt,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.usb, size: 28, color: AppTheme.accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.deviceName,
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            s.skKeyRequiresDevice,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          if (widget.requiresPin) ...[
            const SizedBox(height: AppSpacing.lg),
            SecurePasswordField(
              controller: _pinCtrl,
              decoration: InputDecoration(labelText: s.hardwareKeyPin),
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        AppButton.cancel(onTap: _cancel),
        AppButton.primary(label: s.ok, onTap: _submit),
      ],
    );
  }
}
