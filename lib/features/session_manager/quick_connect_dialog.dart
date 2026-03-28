import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/ssh/ssh_config.dart';
import '../../utils/platform.dart';

/// Quick Connect dialog — host, port, user, password, key file/text.
class QuickConnectDialog extends StatefulWidget {
  const QuickConnectDialog({super.key});

  /// Show the dialog and return SSHConfig if user confirms.
  static Future<SSHConfig?> show(BuildContext context) {
    return showDialog<SSHConfig>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
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
          IconButton(
            onPressed: () => setState(() => _keyPathCtrl.clear()),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear key file',
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick Connect'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Host + Port row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Host *',
                          hintText: '192.168.1.1',
                          prefixIcon: Icon(Icons.dns),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                        autofocus: true,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _portCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final port = int.tryParse(v ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return '1-65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // User
                TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username *',
                    hintText: 'root',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Password
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                ),
                const SizedBox(height: 12),

                // Key file
                _buildKeyFileButton(),
                const SizedBox(height: 8),

                // Toggle key text
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showKeyText = !_showKeyText),
                    icon: Icon(
                      _showKeyText
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                    ),
                    label: Text(
                      _showKeyText ? 'Hide PEM text' : 'Paste PEM key text',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),

                // Key text (PEM)
                if (_showKeyText) ...[
                  TextFormField(
                    controller: _keyDataCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Key Text (PEM)',
                      hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Passphrase
                TextFormField(
                  controller: _passphraseCtrl,
                  decoration: InputDecoration(
                    labelText: 'Key Passphrase',
                    prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassphrase
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setState(
                          () => _obscurePassphrase = !_obscurePassphrase),
                    ),
                  ),
                  obscureText: _obscurePassphrase,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.login),
          label: const Text('Connect'),
        ),
      ],
    );
  }
}
