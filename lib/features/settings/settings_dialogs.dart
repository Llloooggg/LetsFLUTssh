part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings dialogs — export password, import data
// ═══════════════════════════════════════════════════════════════════

/// Shared obscured text field used by every password dialog in this file.
///
/// Extracted so the export (with mismatch-error border), import, set, change
/// and remove flows don't re-spell the same [TextField] + [AppTheme]
/// decoration five times.
Widget _passwordTextField(
  TextEditingController ctrl,
  String label, {
  bool error = false,
  bool autofocus = false,
  ValueChanged<String>? onSubmitted,
  FocusNode? focusNode,
  TextInputAction? textInputAction,
}) {
  return TextField(
    controller: ctrl,
    focusNode: focusNode,
    obscureText: true,
    autofocus: autofocus,
    textInputAction: textInputAction,
    style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
    onSubmitted: onSubmitted,
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
  late final _chain = FormSubmitChain(length: 2, onSubmit: _submit);

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
    _chain.dispose();
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
          _passwordTextField(
            widget.passwordCtrl,
            l10n.masterPassword,
            error: _mismatch,
            focusNode: _chain.nodeAt(0),
            textInputAction: _chain.actionAt(0),
            onSubmitted: _chain.handlerAt(0),
          ),
          const SizedBox(height: 8),
          _passwordTextField(
            widget.confirmCtrl,
            l10n.confirmPassword,
            error: _mismatch,
            focusNode: _chain.nodeAt(1),
            textInputAction: _chain.actionAt(1),
            onSubmitted: _chain.handlerAt(1),
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
  late final _chain = FormSubmitChain(length: 1, onSubmit: _submit);

  @override
  void initState() {
    super.initState();
    widget.passwordCtrl.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    widget.passwordCtrl.removeListener(_onPasswordChanged);
    _chain.dispose();
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  void _submit() {
    if (widget.passwordCtrl.text.isEmpty) return;
    Navigator.pop(context, widget.passwordCtrl.text);
  }

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
          _passwordTextField(
            widget.passwordCtrl,
            S.of(context).masterPassword,
            autofocus: true,
            focusNode: _chain.nodeAt(0),
            textInputAction: _chain.actionAt(0),
            onSubmitted: _chain.handlerAt(0),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).nextStep,
          enabled: widget.passwordCtrl.text.isNotEmpty,
          onTap: _submit,
        ),
      ],
    );
  }
}

// ── Master password dialogs ──

class _SetMasterPasswordDialog extends StatefulWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;

  const _SetMasterPasswordDialog({
    required this.passwordCtrl,
    required this.confirmCtrl,
  });

  @override
  State<_SetMasterPasswordDialog> createState() =>
      _SetMasterPasswordDialogState();
}

class _SetMasterPasswordDialogState extends State<_SetMasterPasswordDialog> {
  late final _chain = FormSubmitChain(length: 2, onSubmit: _submit);

  @override
  void dispose() {
    _chain.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = S.of(context);
    final password = widget.passwordCtrl.text;
    // Master password must be non-empty — length and complexity are
    // the user's choice.
    if (password.isEmpty) return;
    if (password != widget.confirmCtrl.text) {
      Toast.show(
        context,
        message: l10n.passwordsDoNotMatch,
        level: ToastLevel.warning,
      );
      return;
    }
    Navigator.pop(context, password);
  }

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
          _passwordTextField(
            widget.passwordCtrl,
            l10n.newPassword,
            focusNode: _chain.nodeAt(0),
            textInputAction: _chain.actionAt(0),
            onSubmitted: _chain.handlerAt(0),
          ),
          PasswordStrengthMeter(controller: widget.passwordCtrl),
          const SizedBox(height: 8),
          _passwordTextField(
            widget.confirmCtrl,
            l10n.confirmPassword,
            focusNode: _chain.nodeAt(1),
            textInputAction: _chain.actionAt(1),
            onSubmitted: _chain.handlerAt(1),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: l10n.ok, onTap: _submit),
      ],
    );
  }
}

class _ChangeMasterPasswordDialog extends StatefulWidget {
  final TextEditingController currentCtrl;
  final TextEditingController newCtrl;
  final TextEditingController confirmCtrl;

  const _ChangeMasterPasswordDialog({
    required this.currentCtrl,
    required this.newCtrl,
    required this.confirmCtrl,
  });

  @override
  State<_ChangeMasterPasswordDialog> createState() =>
      _ChangeMasterPasswordDialogState();
}

class _ChangeMasterPasswordDialogState
    extends State<_ChangeMasterPasswordDialog> {
  late final _chain = FormSubmitChain(length: 3, onSubmit: _submit);

  @override
  void dispose() {
    _chain.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = S.of(context);
    if (widget.currentCtrl.text.isEmpty) return;
    final newPw = widget.newCtrl.text;
    // New master password must be non-empty — length and complexity
    // are the user's choice.
    if (newPw.isEmpty) return;
    if (newPw != widget.confirmCtrl.text) {
      Toast.show(
        context,
        message: l10n.passwordsDoNotMatch,
        level: ToastLevel.warning,
      );
      return;
    }
    Navigator.pop(context, (current: widget.currentCtrl.text, newPw: newPw));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.changeMasterPassword,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _passwordTextField(
            widget.currentCtrl,
            l10n.currentPassword,
            focusNode: _chain.nodeAt(0),
            textInputAction: _chain.actionAt(0),
            onSubmitted: _chain.handlerAt(0),
          ),
          const SizedBox(height: 8),
          _passwordTextField(
            widget.newCtrl,
            l10n.newPassword,
            focusNode: _chain.nodeAt(1),
            textInputAction: _chain.actionAt(1),
            onSubmitted: _chain.handlerAt(1),
          ),
          PasswordStrengthMeter(controller: widget.newCtrl),
          const SizedBox(height: 8),
          _passwordTextField(
            widget.confirmCtrl,
            l10n.confirmPassword,
            focusNode: _chain.nodeAt(2),
            textInputAction: _chain.actionAt(2),
            onSubmitted: _chain.handlerAt(2),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: l10n.ok, onTap: _submit),
      ],
    );
  }
}

class _EnableBiometricDialog extends StatefulWidget {
  final TextEditingController currentCtrl;

  const _EnableBiometricDialog({required this.currentCtrl});

  @override
  State<_EnableBiometricDialog> createState() => _EnableBiometricDialogState();
}

class _EnableBiometricDialogState extends State<_EnableBiometricDialog> {
  late final _chain = FormSubmitChain(length: 1, onSubmit: _submit);

  @override
  void dispose() {
    _chain.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.currentCtrl.text.isEmpty) return;
    Navigator.pop(context, widget.currentCtrl.text);
  }

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
          _passwordTextField(
            widget.currentCtrl,
            l10n.currentPassword,
            autofocus: true,
            focusNode: _chain.nodeAt(0),
            textInputAction: _chain.actionAt(0),
            onSubmitted: _chain.handlerAt(0),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: l10n.ok, onTap: _submit),
      ],
    );
  }
}

class _RemoveMasterPasswordDialog extends StatefulWidget {
  final TextEditingController passwordCtrl;

  const _RemoveMasterPasswordDialog({required this.passwordCtrl});

  @override
  State<_RemoveMasterPasswordDialog> createState() =>
      _RemoveMasterPasswordDialogState();
}

class _RemoveMasterPasswordDialogState
    extends State<_RemoveMasterPasswordDialog> {
  late final _chain = FormSubmitChain(length: 1, onSubmit: _submit);

  @override
  void dispose() {
    _chain.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.passwordCtrl.text.isEmpty) return;
    Navigator.pop(context, widget.passwordCtrl.text);
  }

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
          _passwordTextField(
            widget.passwordCtrl,
            l10n.currentPassword,
            focusNode: _chain.nodeAt(0),
            textInputAction: _chain.actionAt(0),
            onSubmitted: _chain.handlerAt(0),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: l10n.ok, onTap: _submit),
      ],
    );
  }
}
