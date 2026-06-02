import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/secret_controller.dart';
import '../core/app_button.dart';
import '../core/app_icon_button.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';

/// Result of a [CredentialPromptDialog]: the typed secret bytes plus
/// whether the user asked to keep it for the rest of the session.
/// `null` (the dialog's pop value) means the user cancelled.
class CredentialPromptResult {
  const CredentialPromptResult({required this.secret, required this.remember});

  final List<int> secret;
  final bool remember;
}

/// Mid-connect credential overlay. The Rust connect actor pauses the
/// handshake and fires a `CredentialPromptRequest` when a private-key
/// passphrase (or, later, a password) is needed but was never saved;
/// [CredentialPromptListener] surfaces this dialog and feeds the typed
/// secret back over FRB so the handshake resumes.
///
/// The dialog never persists the secret itself — it hands the bytes to
/// the Rust side, which stages them in the SecretStore for this connect
/// (and, when [CredentialPromptResult.remember] is set, for the rest of
/// the session so a reconnect skips the prompt). Plaintext discipline:
/// the controller is wiped on dispose.
class CredentialPromptDialog extends StatefulWidget {
  const CredentialPromptDialog({
    super.key,
    required this.isPassphrase,
    this.sessionLabel,
  });

  /// `true` → passphrase to decrypt the key; `false` → session password.
  final bool isPassphrase;

  /// Optional session label for the caption (the saved session's name).
  final String? sessionLabel;

  static Future<CredentialPromptResult?> show(
    BuildContext context, {
    required bool isPassphrase,
    String? sessionLabel,
  }) {
    return showDialog<CredentialPromptResult?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CredentialPromptDialog(
        isPassphrase: isPassphrase,
        sessionLabel: sessionLabel,
      ),
    );
  }

  @override
  State<CredentialPromptDialog> createState() => _CredentialPromptDialogState();
}

class _CredentialPromptDialogState extends State<CredentialPromptDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _remember = false;

  @override
  void dispose() {
    _ctrl.wipeAndClear();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.isEmpty) return;
    // Hand the bytes to the caller (which forwards them to Rust); the
    // controller is wiped in dispose right after this pop.
    Navigator.of(context).pop(
      CredentialPromptResult(
        secret: utf8.encode(_ctrl.text),
        remember: _remember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);
    final title = widget.isPassphrase
        ? l10n.credentialPromptPassphraseTitle
        : l10n.credentialPromptPasswordTitle;
    final hint = widget.sessionLabel != null && widget.sessionLabel!.isNotEmpty
        ? l10n.credentialPromptHintForSession(widget.sessionLabel!)
        : l10n.credentialPromptHint;
    final inputLabel = widget.isPassphrase ? l10n.passphrase : l10n.password;
    return SecureScreenScope(
      child: PopScope(
        canPop: false,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    widget.isPassphrase ? Icons.key : Icons.password,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFonts.xl,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFonts.md,
                      color: AppTheme.fgDim,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SecurePasswordField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    obscureText: _obscure,
                    keyboardType: TextInputType.visiblePassword,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: inputLabel,
                      border: const OutlineInputBorder(),
                      suffixIcon: AppIconButton(
                        icon: _obscure
                            ? Icons.visibility_off
                            : Icons.visibility,
                        dense: true,
                        onTap: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                    title: Text(
                      l10n.credentialPromptRememberSession,
                      style: TextStyle(
                        fontSize: AppFonts.sm,
                        color: AppTheme.fgDim,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(
                          label: l10n.cancel,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppButton.primary(
                          label: l10n.connect,
                          onTap: _submit,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
