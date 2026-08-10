import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../core/security/master_password.dart';
import '../../core/security/security_tier.dart';
import '../../providers/master_password_provider.dart';
import '../../providers/security_provider.dart';
import '../../utils/logger.dart';
import '../core/app_dialog.dart';
import '../core/toast.dart';

/// Modal dialog that lets the user change the tier password.
///
/// Flow:
/// 1. Prompt for current password (if one exists).
/// 2. Prompt for new password + confirmation.
/// 3. On submit, call the appropriate Rust API and show a snackbar.
///
/// [tier] selects the backend:
///   * `keychain` → `masterPassword.changePassword` (T1+password).
///   * `hardware` → `hardwareTierVault.changePin` (T2).
///   * `paranoid` → `masterPassword.changePassword` (T3).
///
/// [currentPassword] is the known current password when the user is
/// already authenticated (e.g. biometric unlock happened first).
/// When null the user must type it in.
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({
    required this.tier,
    this.currentPassword,
    super.key,
  });

  final SecurityTier tier;
  final String? currentPassword;

  static Future<bool?> show({
    required BuildContext context,
    required SecurityTier tier,
    String? currentPassword,
  }) async {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ChangePasswordDialog(tier: tier, currentPassword: currentPassword),
      ),
    );
  }

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _currentKey = TextEditingController();
  final _newKey = TextEditingController();
  final _confirmKey = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentKey.dispose();
    _newKey.dispose();
    _confirmKey.dispose();
    super.dispose();
  }

  bool get _needsCurrentPassword =>
      widget.currentPassword == null && widget.tier != SecurityTier.plaintext;

  Future<void> _submit() async {
    final l10n = S.of(context);
    final currentPassword = _needsCurrentPassword
        ? _currentKey.text.trim()
        : widget.currentPassword;
    final newPassword = _newKey.text;
    final confirmPassword = _confirmKey.text;

    // Validate
    if (newPassword != confirmPassword) {
      setState(() {
        _error = l10n.passwordsDoNotMatch;
      });
      return;
    }
    if (newPassword.isEmpty) {
      setState(() {
        _error = l10n.passwordRequired;
      });
      return;
    }
    if (_needsCurrentPassword &&
        (currentPassword == null || currentPassword == '')) {
      setState(() {
        _error = l10n.passwordConfirmationRequired;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final mp = ref.read(masterPasswordProvider);
      final vault = ref.read(hardwareTierVaultProvider);
      var success = false;

      switch (widget.tier) {
        case SecurityTier.keychain:
          // T1+password: change the keychain/password gate password.
          success = await _tryChangeMasterPassword(
            mp,
            currentPassword!,
            newPassword,
          );
        case SecurityTier.hardware:
          // T2: change the hardware-vault PIN.
          success = await vault.changePin(
            oldPin: currentPassword!,
            newPin: newPassword,
          );
        case SecurityTier.paranoid:
          // T3: change the paranoid master password.
          success = await _tryChangeMasterPassword(
            mp,
            currentPassword!,
            newPassword,
          );
        case SecurityTier.plaintext:
          // No password to change — shouldn't reach here.
          setState(() {
            _busy = false;
            _error = l10n.passwordChangeFailed;
          });
          return;
      }

      if (mounted) {
        if (success) {
          Toast.show(
            context,
            message: l10n.passwordChanged,
            level: ToastLevel.success,
          );
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _busy = false;
            _error = l10n.passwordChangeFailed;
          });
        }
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'Change password failed: $e',
        name: 'ChangePasswordDialog',
        error: e,
        stackTrace: st,
        level: LogLevel.error,
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.passwordChangeFailed;
        });
      }
    }
  }

  Future<bool> _tryChangeMasterPassword(
    MasterPasswordManager mp,
    String oldPassword,
    String newPassword,
  ) async {
    try {
      await mp.changePassword(
        Uint8List.fromList(oldPassword.codeUnits),
        Uint8List.fromList(newPassword.codeUnits),
      );
      return true;
    } on MasterPasswordException {
      return false;
    } catch (e) {
      return false;
    }
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final needsCurrentPassword = _needsCurrentPassword;

    return AppDialog(
      title: l10n.changePasswordTitle,
      actions: [
        AppButton.secondary(
          label: l10n.cancel,
          onTap: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          label: l10n.save,
          onTap: _busy ? null : _submit,
          loading: _busy,
        ),
      ],
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needsCurrentPassword) ...[
              _buildField(
                label: l10n.currentPassword,
                controller: _currentKey,
                hintText: l10n.enterCurrentPassword,
              ),
              const SizedBox(height: 16),
            ],
            _buildField(
              label: l10n.newPassword,
              controller: _newKey,
              hintText: l10n.enterNewPassword,
            ),
            const SizedBox(height: 16),
            _buildField(
              label: l10n.confirmPassword,
              controller: _confirmKey,
              hintText: l10n.confirmNewPassword,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
