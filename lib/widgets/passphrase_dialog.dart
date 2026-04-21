import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_dialog.dart';
import 'secure_password_field.dart';

/// Result from passphrase dialog.
class PassphraseResult {
  final String passphrase;
  final bool remember;

  const PassphraseResult({required this.passphrase, required this.remember});
}

/// Dialog prompting user for SSH key passphrase during connection.
///
/// Shown when an encrypted key is encountered without a stored passphrase.
/// Returns [PassphraseResult] on submit, null on cancel.
class PassphraseDialog {
  /// Show passphrase prompt and return result or null if cancelled.
  static Future<PassphraseResult?> show(
    BuildContext context, {
    required String host,
    int? attempt,
  }) {
    return AppDialog.show<PassphraseResult>(
      context,
      barrierDismissible: false,
      builder: (ctx) => _PassphraseDialogWidget(host: host, attempt: attempt),
    );
  }
}

class _PassphraseDialogWidget extends StatefulWidget {
  final String host;
  final int? attempt;

  const _PassphraseDialogWidget({required this.host, this.attempt});

  @override
  State<_PassphraseDialogWidget> createState() =>
      _PassphraseDialogWidgetState();
}

class _PassphraseDialogWidgetState extends State<_PassphraseDialogWidget> {
  final _controller = TextEditingController();
  bool _remember = true;
  bool _obscure = true;

  @override
  void dispose() {
    _controller.wipeAndClear();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.isEmpty) return;
    Navigator.pop(
      context,
      PassphraseResult(passphrase: text, remember: _remember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isRetry = widget.attempt != null && widget.attempt! > 1;

    return AppDialog(
      title: s.passphraseRequired,
      dismissible: false,
      maxWidth: 400,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.passphrasePrompt(widget.host),
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          if (isRetry) ...[
            const SizedBox(height: 8),
            Text(
              s.passphraseWrong,
              style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.red),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: AppTheme.controlHeightSm,
            child: SecurePasswordField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                hintText: s.passphrase,
                hintStyle: TextStyle(
                  color: AppTheme.fgDim,
                  fontSize: AppFonts.sm,
                ),
                filled: true,
                fillColor: AppTheme.bg3,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(
                    color: isRetry ? AppTheme.red : AppTheme.borderLight,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.accent),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                    color: AppTheme.fgDim,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: Checkbox(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: GestureDetector(
                  onTap: () => setState(() => _remember = !_remember),
                  child: Text(
                    s.rememberPassphrase,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(label: s.unlock, onTap: _submit),
      ],
    );
  }
}
