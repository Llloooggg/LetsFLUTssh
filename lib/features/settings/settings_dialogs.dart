part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings dialogs — export password, import data
// ═══════════════════════════════════════════════════════════════════

// ── Export password dialog ──

class _ExportPasswordDialog extends StatelessWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;

  const _ExportPasswordDialog({
    required this.passwordCtrl,
    required this.confirmCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).exportData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.of(context).setMasterPasswordHint,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          const SizedBox(height: 16),
          _styledPasswordField(passwordCtrl, S.of(context).masterPassword),
          const SizedBox(height: 8),
          _styledPasswordField(confirmCtrl, S.of(context).confirmPassword),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).export_,
          onTap: () {
            if (passwordCtrl.text.isEmpty) return;
            if (passwordCtrl.text != confirmCtrl.text) {
              Toast.show(
                context,
                message: S.of(context).passwordsDoNotMatch,
                level: ToastLevel.warning,
              );
              return;
            }
            Navigator.pop(context, passwordCtrl.text);
          },
        ),
      ],
    );
  }

  static Widget _styledPasswordField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: AppTheme.inputDecoration(labelText: label),
    );
  }
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
