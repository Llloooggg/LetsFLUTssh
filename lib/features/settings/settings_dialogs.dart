part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings dialogs — export password, import data
// ═══════════════════════════════════════════════════════════════════

// ── Export password dialog ──

/// Password dialog for archive export.
///
/// Allowing an empty password is intentional: the user sometimes wants a
/// plain ZIP they can inspect or import without master password prompts.
/// Submitting with both fields empty pops a confirmation first so the user
/// acknowledges that the archive will ship unencrypted — anyone with the
/// file gets every saved password and private key in plain text.
class _ExportPasswordDialog extends StatefulWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;

  const _ExportPasswordDialog({
    required this.passwordCtrl,
    required this.confirmCtrl,
  });

  @override
  State<_ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<_ExportPasswordDialog> {
  bool _mismatch = false;

  @override
  void initState() {
    super.initState();
    widget.passwordCtrl.addListener(_clearMismatch);
    widget.confirmCtrl.addListener(_clearMismatch);
  }

  @override
  void dispose() {
    // Controllers are owned by the caller — only unregister our listeners.
    widget.passwordCtrl.removeListener(_clearMismatch);
    widget.confirmCtrl.removeListener(_clearMismatch);
    super.dispose();
  }

  void _clearMismatch() {
    if (_mismatch) setState(() => _mismatch = false);
  }

  Future<void> _submit() async {
    final pw = widget.passwordCtrl.text;
    final confirm = widget.confirmCtrl.text;

    // Empty + empty → offer an unencrypted export after confirmation.
    if (pw.isEmpty && confirm.isEmpty) {
      final proceed = await _confirmUnencrypted(context);
      if (!mounted) return;
      if (proceed) {
        Navigator.pop(context, '');
      }
      return;
    }

    if (pw != confirm) {
      setState(() => _mismatch = true);
      return;
    }

    Navigator.pop(context, pw);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.exportData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.setMasterPasswordHint,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          const SizedBox(height: 16),
          _styledPasswordField(
            widget.passwordCtrl,
            l10n.masterPassword,
            error: _mismatch,
          ),
          const SizedBox(height: 8),
          _styledPasswordField(
            widget.confirmCtrl,
            l10n.confirmPassword,
            error: _mismatch,
          ),
          if (_mismatch) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.passwordsDoNotMatch,
                style: TextStyle(
                  fontSize: AppFonts.sm,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: l10n.export_, onTap: _submit),
      ],
    );
  }

  static Widget _styledPasswordField(
    TextEditingController ctrl,
    String label, {
    bool error = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: label).copyWith(
        enabledBorder: error
            ? OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.red, width: 1),
              )
            : null,
        focusedBorder: error
            ? OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.red, width: 1.5),
              )
            : null,
      ),
    );
  }
}

/// Warn the user that the archive will be exported without encryption.
/// Returns true if the user chose to proceed.
Future<bool> _confirmUnencrypted(BuildContext context) async {
  final l10n = S.of(context);
  final confirmed = await AppDialog.show<bool>(
    context,
    builder: (ctx) => AppDialog(
      title: l10n.exportWithoutPassword,
      content: Text(
        l10n.exportWithoutPasswordWarning,
        style: TextStyle(
          fontSize: AppFonts.md,
          color: Theme.of(ctx).colorScheme.error,
        ),
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(ctx, false)),
        AppDialogAction.primary(
          label: l10n.continueWithoutPassword,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// ── Import password dialog ──

class _ImportPasswordDialog extends StatefulWidget {
  final TextEditingController passwordCtrl;

  const _ImportPasswordDialog({required this.passwordCtrl});

  @override
  State<_ImportPasswordDialog> createState() => _ImportPasswordDialogState();
}

class _ImportPasswordDialogState extends State<_ImportPasswordDialog> {
  // NOTE: Do NOT dispose widget.passwordCtrl here — it is owned by the parent
  // widget and will be disposed by the parent. Disposing it here causes
  // "TextEditingController used after being disposed" errors when the parent
  // tries to clear or reuse the controller after the dialog closes.

  @override
  void initState() {
    super.initState();
    widget.passwordCtrl.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    widget.passwordCtrl.removeListener(_onPasswordChanged);
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.of(context).enterMasterPasswordPrompt,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.passwordCtrl,
            obscureText: true,
            autofocus: true,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            decoration: AppTheme.inputDecoration(
              labelText: S.of(context).masterPassword,
            ),
            onSubmitted: (v) {
              if (v.isNotEmpty) {
                Navigator.pop(context, v);
              }
            },
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).nextStep,
          enabled: widget.passwordCtrl.text.isNotEmpty,
          onTap: () {
            if (widget.passwordCtrl.text.isEmpty) return;
            Navigator.pop(context, widget.passwordCtrl.text);
          },
        ),
      ],
    );
  }
}

// ── Master password dialogs ──

class _SetMasterPasswordDialog extends StatelessWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;

  const _SetMasterPasswordDialog({
    required this.passwordCtrl,
    required this.confirmCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.setMasterPassword,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.masterPasswordWarning,
            style: TextStyle(
              fontSize: AppFonts.md,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          _passwordField(passwordCtrl, l10n.newPassword),
          const SizedBox(height: 8),
          _passwordField(confirmCtrl, l10n.confirmPassword),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: l10n.ok,
          onTap: () {
            final password = passwordCtrl.text;
            if (password.length < 8) {
              Toast.show(
                context,
                message: l10n.passwordTooShort,
                level: ToastLevel.warning,
              );
              return;
            }
            if (password != confirmCtrl.text) {
              Toast.show(
                context,
                message: l10n.passwordsDoNotMatch,
                level: ToastLevel.warning,
              );
              return;
            }
            Navigator.pop(context, password);
          },
        ),
      ],
    );
  }

  static Widget _passwordField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: label),
    );
  }
}

class _ChangeMasterPasswordDialog extends StatelessWidget {
  final TextEditingController currentCtrl;
  final TextEditingController newCtrl;
  final TextEditingController confirmCtrl;

  const _ChangeMasterPasswordDialog({
    required this.currentCtrl,
    required this.newCtrl,
    required this.confirmCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.changeMasterPassword,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _passwordField(currentCtrl, l10n.currentPassword),
          const SizedBox(height: 8),
          _passwordField(newCtrl, l10n.newPassword),
          const SizedBox(height: 8),
          _passwordField(confirmCtrl, l10n.confirmPassword),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: l10n.ok,
          onTap: () {
            if (currentCtrl.text.isEmpty) return;
            final newPw = newCtrl.text;
            if (newPw.length < 8) {
              Toast.show(
                context,
                message: l10n.passwordTooShort,
                level: ToastLevel.warning,
              );
              return;
            }
            if (newPw != confirmCtrl.text) {
              Toast.show(
                context,
                message: l10n.passwordsDoNotMatch,
                level: ToastLevel.warning,
              );
              return;
            }
            Navigator.pop(context, (current: currentCtrl.text, newPw: newPw));
          },
        ),
      ],
    );
  }

  static Widget _passwordField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: label),
    );
  }
}

class _EnableBiometricDialog extends StatelessWidget {
  final TextEditingController currentCtrl;

  const _EnableBiometricDialog({required this.currentCtrl});

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.biometricUnlockTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.biometricUnlockSubtitle,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: currentCtrl,
            obscureText: true,
            autofocus: true,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            decoration: AppTheme.inputDecoration(
              labelText: l10n.currentPassword,
            ),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: l10n.ok,
          onTap: () {
            if (currentCtrl.text.isEmpty) return;
            Navigator.pop(context, currentCtrl.text);
          },
        ),
      ],
    );
  }
}

class _RemoveMasterPasswordDialog extends StatelessWidget {
  final TextEditingController passwordCtrl;

  const _RemoveMasterPasswordDialog({required this.passwordCtrl});

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.removeMasterPassword,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.confirmRemoveMasterPassword,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordCtrl,
            obscureText: true,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            decoration: AppTheme.inputDecoration(
              labelText: l10n.currentPassword,
            ),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: l10n.ok,
          onTap: () {
            if (passwordCtrl.text.isEmpty) return;
            Navigator.pop(context, passwordCtrl.text);
          },
        ),
      ],
    );
  }
}
