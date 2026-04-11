import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/ssh/ssh_config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/styled_form_field.dart';
import '../../utils/platform.dart';

/// Quick Connect — shown as a bottom sheet.
class QuickConnectDialog extends StatefulWidget {
  const QuickConnectDialog({super.key});

  /// Show the bottom sheet and return SSHConfig if user confirms.
  static Future<SSHConfig?> show(BuildContext context) {
    return showModalBottomSheet<SSHConfig>(
      context: context,
      backgroundColor: AppTheme.bg1,
      isScrollControlled: true,
      builder: (_) => const QuickConnectDialog(),
    );
  }

  @override
  State<QuickConnectDialog> createState() => _QuickConnectDialogState();
}

class _QuickConnectDialogState extends State<QuickConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _keyPathCtrl = TextEditingController();
  final _keyDataCtrl = TextEditingController();
  final _passphraseCtrl = TextEditingController();

  bool _showKeyText = false;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _keyPathCtrl.dispose();
    _keyDataCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);

    final config = SSHConfig(
      server: ServerAddress(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 22,
        user: _userCtrl.text.trim(),
      ),
      auth: SshAuth(
        password: _passwordCtrl.text,
        keyPath: keyPath,
        keyData: _keyDataCtrl.text.trim(),
        passphrase: _passphraseCtrl.text,
      ),
    );

    Navigator.of(context).pop(config);
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: S.of(context).selectKeyFile,
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final pemContent = KeyFileHelper.tryReadPemKey(path);
    if (pemContent != null) {
      setState(() {
        _keyDataCtrl.text = pemContent;
        _showKeyText = true;
      });
    } else {
      setState(() => _keyPathCtrl.text = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.bg4,
                    borderRadius: AppTheme.radiusSm,
                  ),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    S.of(context).quickConnect,
                    style: AppFonts.inter(
                      fontSize: AppFonts.lg,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.fgBright,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Fields
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Host + Port
                    Row(
                      children: [
                        Expanded(
                          child: StyledFormField(
                            label: S.of(context).hostRequired,
                            controller: _hostCtrl,
                            hint: S.of(context).hintHost,
                            validator: _requiredValidator,
                            fixedHeight: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 80,
                          child: StyledFormField(
                            label: S.of(context).port,
                            controller: _portCtrl,
                            hint: S.of(context).hintPort,
                            keyboardType: TextInputType.number,
                            fixedHeight: true,
                            validator: (v) {
                              final port = int.tryParse(v ?? '');
                              if (port == null || port < 1 || port > 65535) {
                                return S.of(context).portRange;
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StyledFormField(
                      label: S.of(context).usernameRequired,
                      controller: _userCtrl,
                      hint: S.of(context).hintUsername,
                      validator: _requiredValidator,
                      fixedHeight: true,
                    ),
                    const SizedBox(height: 12),
                    StyledFormField(
                      label: S.of(context).password,
                      controller: _passwordCtrl,
                      hint: S.of(context).hintPassword,
                      obscure: _obscurePassword,
                      fixedHeight: true,
                      suffixIcon: GestureDetector(
                        onTap: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        child: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 12,
                          color: AppTheme.fgFaint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildKeyFileButton(),
                    const SizedBox(height: 8),
                    _buildPemToggle(),
                    if (_showKeyText) ...[
                      TextFormField(
                        controller: _keyDataCtrl,
                        decoration: InputDecoration(
                          labelText: S.of(context).keyTextPem,
                          hintText: S.of(context).hintPemKey,
                          alignLabelWithHint: true,
                        ),
                        maxLines: 5,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFonts.sm,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    StyledFormField(
                      label: S.of(context).keyPassphrase,
                      controller: _passphraseCtrl,
                      hint: S.of(context).hintOptional,
                      obscure: _obscurePassphrase,
                      fixedHeight: true,
                      suffixIcon: GestureDetector(
                        onTap: () => setState(
                          () => _obscurePassphrase = !_obscurePassphrase,
                        ),
                        child: Icon(
                          _obscurePassphrase
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 12,
                          color: AppTheme.fgFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: AppTheme.controlHeightXl,
                          alignment: Alignment.center,
                          color: AppTheme.bg3,
                          child: Text(
                            S.of(context).cancel,
                            style: AppFonts.inter(
                              fontSize: AppFonts.md,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.fgDim,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _submit,
                        child: Container(
                          height: AppTheme.controlHeightXl,
                          alignment: Alignment.center,
                          color: AppTheme.accent,
                          child: Text(
                            S.of(context).connect,
                            style: AppFonts.inter(
                              fontSize: AppFonts.md,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyFileButton() {
    final hasKey = _keyPathCtrl.text.trim().isNotEmpty;
    final fileName = hasKey ? p.basename(_keyPathCtrl.text.trim()) : null;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickKeyFile,
            icon: Icon(hasKey ? Icons.vpn_key : Icons.folder_open, size: 18),
            label: Text(
              fileName ?? S.of(context).selectKeyFile,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        if (hasKey)
          AppIconButton(
            icon: Icons.close,
            onTap: () => setState(() => _keyPathCtrl.clear()),
            tooltip: S.of(context).clearKeyFile,
            size: 18,
          ),
      ],
    );
  }

  Widget _buildPemToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _showKeyText = !_showKeyText),
        icon: Icon(
          _showKeyText ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 16,
        ),
        label: Text(
          _showKeyText
              ? S.of(context).hidePemText
              : S.of(context).pastePemKeyText,
          style: TextStyle(fontSize: AppFonts.md),
        ),
      ),
    );
  }

  String? Function(String?) get _requiredValidator =>
      (v) => v == null || v.trim().isEmpty ? S.of(context).required : null;
}
