import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/security/master_password.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';

/// Full-screen unlock dialog shown at startup when master password is enabled.
///
/// Non-dismissible — the user must enter the correct password or reset.
/// Returns the derived encryption key on success, or null if reset was chosen.
class UnlockDialog extends StatefulWidget {
  final MasterPasswordManager manager;

  const UnlockDialog({super.key, required this.manager});

  /// Show the unlock dialog and return the derived key.
  ///
  /// Returns `null` if the user chose to reset (forgot password).
  static Future<Uint8List?> show(
    BuildContext context, {
    required MasterPasswordManager manager,
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => UnlockDialog(manager: manager),
    );
  }

  @override
  State<UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<UnlockDialog> {
  final _passwordCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  bool _wrongPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordCtrl.wipeAndClear();
    _passwordCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;

    setState(() {
      _busy = true;
      _wrongPassword = false;
    });

    // Single PBKDF2 run: verify + derive in one isolate spawn so
    // unlock latency is not doubled on mid-tier mobiles.
    final key = await widget.manager.verifyAndDerive(password);

    if (!mounted) return;

    if (key == null) {
      setState(() {
        _busy = false;
        _wrongPassword = true;
      });
      _passwordCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _passwordCtrl.text.length,
      );
      _focusNode.requestFocus();
      return;
    }

    Navigator.of(context).pop(key);
  }

  Future<void> _forgotPassword() async {
    final confirmed = await _showResetConfirmation();
    if (confirmed != true || !mounted) return;

    await widget.manager.reset();
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }

  Future<bool?> _showResetConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = S.of(ctx);
        return AlertDialog(
          title: Text(l10n.forgotPassword),
          content: Text(
            l10n.forgotPasswordWarning,
            style: TextStyle(color: AppTheme.fgDim),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.resetAndDeleteCredentials),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.masterPassword,
                  style: TextStyle(
                    fontSize: AppFonts.xl,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.enterMasterPassword,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    color: AppTheme.fgDim,
                  ),
                ),
                const SizedBox(height: 20),
                if (_wrongPassword) ...[
                  Text(
                    l10n.wrongMasterPassword,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: AppFonts.sm,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _passwordCtrl,
                  focusNode: _focusNode,
                  obscureText: _obscure,
                  enabled: !_busy,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_busy) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.derivingKey,
                    style: TextStyle(
                      fontSize: AppFonts.sm,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _unlock,
                      child: Text(l10n.unlock),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _forgotPassword,
                    child: Text(
                      l10n.forgotPassword,
                      style: TextStyle(
                        fontSize: AppFonts.sm,
                        color: AppTheme.fgDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
