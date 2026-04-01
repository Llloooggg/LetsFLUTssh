import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/ssh/ssh_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../utils/platform.dart';

/// Quick Connect — shown as a bottom sheet.
class QuickConnectDialog extends StatefulWidget {
  const QuickConnectDialog({super.key});

  /// Show the bottom sheet and return SSHConfig if user confirms.
  static Future<SSHConfig?> show(BuildContext context) {
    return showModalBottomSheet<SSHConfig>(
      context: context,
      backgroundColor: AppTheme.bg1,
      shape: const RoundedRectangleBorder(),
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

    final keyPath = _keyPathCtrl.text.trim().replaceFirst(
      '~',
      homeDirectory,
    );

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
    final result = await FilePicker.platform.pickFiles();
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
                    'Quick Connect',
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
                          child: _field('Host *', _hostCtrl,
                              hint: '192.168.1.1', validator: _requiredValidator),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 80,
                          child: _field('Port', _portCtrl,
                              hint: '22',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                final port = int.tryParse(v ?? '');
                                if (port == null || port < 1 || port > 65535) {
                                  return '1-65535';
                                }
                                return null;
                              }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field('Username *', _userCtrl,
                        hint: 'root', validator: _requiredValidator),
                    const SizedBox(height: 12),
                    _field('Password', _passwordCtrl,
                        hint: '••••••••',
                        obscure: _obscurePassword,
                        suffixIcon: GestureDetector(
                          onTap: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          child: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 12,
                            color: AppTheme.fgFaint,
                          ),
                        )),
                    const SizedBox(height: 12),
                    _buildKeyFileButton(),
                    const SizedBox(height: 8),
                    _buildPemToggle(),
                    if (_showKeyText) ...[
                      TextFormField(
                        controller: _keyDataCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Key Text (PEM)',
                          hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 5,
                        style: TextStyle(
                            fontFamily: 'monospace', fontSize: AppFonts.sm),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _field('Key Passphrase', _passphraseCtrl,
                        hint: 'Optional',
                        obscure: _obscurePassphrase,
                        suffixIcon: GestureDetector(
                          onTap: () => setState(
                              () => _obscurePassphrase = !_obscurePassphrase),
                          child: Icon(
                            _obscurePassphrase
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 12,
                            color: AppTheme.fgFaint,
                          ),
                        )),
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
                          height: 38,
                          alignment: Alignment.center,
                          color: AppTheme.bg3,
                          child: Text(
                            'Cancel',
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
                          height: 38,
                          alignment: Alignment.center,
                          color: AppTheme.accent,
                          child: Text(
                            'Connect',
                            style: AppFonts.inter(
                              fontSize: AppFonts.md,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
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
              fileName ?? 'Select Key File',
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
            tooltip: 'Clear key file',
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
          _showKeyText
              ? Icons.keyboard_arrow_up
              : Icons.keyboard_arrow_down,
          size: 16,
        ),
        label: Text(
          _showKeyText ? 'Hide PEM text' : 'Paste PEM key text',
          style: TextStyle(fontSize: AppFonts.md),
        ),
      ),
    );
  }

  static String? _requiredValidator(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppTheme.fgFaint,
            ),
          ),
        ),
        SizedBox(
          height: 30,
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            validator: validator,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: AppFonts.sm,
              color: AppTheme.fg,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: AppFonts.sm,
                color: AppTheme.fgFaint,
              ),
              filled: true,
              fillColor: AppTheme.bg3,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.accent),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.red),
              ),
              suffixIcon: suffixIcon != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: suffixIcon,
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(maxHeight: 30),
            ),
          ),
        ),
      ],
    );
  }
}
