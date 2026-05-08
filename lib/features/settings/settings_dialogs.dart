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
  return SecurePasswordField(
    controller: ctrl,
    focusNode: focusNode,
    autofocus: autofocus,
    textInputAction: textInputAction,
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
/// A non-empty password is required: the plain-ZIP `.lfs` shape carries
/// no integrity tag, so an unencrypted export cannot detect a tampered
/// entry on import. The import side still reads plain ZIPs from older
/// installs (backward-compatible read), but new exports only ship the
/// encrypted shape.
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

    // Empty password rejected on emit. The plain-ZIP `.lfs`
    // shape carries no integrity tag, so shipping one to a user
    // is functionally an unauthenticated export — readers cannot
    // detect a tampered entry. The import path still accepts
    // plain ZIPs from earlier installs (the wire shape stays
    // backward-compatible); export is the only side now refused.
    if (pw.isEmpty) {
      setState(() => _mismatch = true);
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
    return SecureScreenScope(
      child: AppDialog(
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
          AppButton.cancel(onTap: () => Navigator.pop(context)),
          AppButton.primary(label: l10n.export_, onTap: _submit),
        ],
      ),
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
    return SecureScreenScope(
      child: AppDialog(
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
          AppButton.cancel(onTap: () => Navigator.pop(context)),
          AppButton.primary(
            label: S.of(context).nextStep,
            enabled: widget.passwordCtrl.text.isNotEmpty,
            onTap: _submit,
          ),
        ],
      ),
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
    return SecureScreenScope(
      child: AppDialog(
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
          AppButton.cancel(onTap: () => Navigator.pop(context)),
          AppButton.primary(label: l10n.ok, onTap: _submit),
        ],
      ),
    );
  }
}
