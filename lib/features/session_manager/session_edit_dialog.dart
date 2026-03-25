import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../utils/platform.dart';

/// Result of the session edit dialog.
sealed class SessionDialogResult {}

/// User chose "Connect" (without saving).
class ConnectOnlyResult extends SessionDialogResult {
  final SSHConfig config;
  ConnectOnlyResult(this.config);
}

/// User chose "Save" or "Save & Connect".
class SaveResult extends SessionDialogResult {
  final Session session;
  final bool connect;
  SaveResult(this.session, {this.connect = false});
}

/// Dialog for creating or editing a session.
/// In create mode, shows 3 buttons: Cancel | Connect | Save & Connect
/// In edit mode, shows 2 buttons: Cancel | Save
class SessionEditDialog extends StatefulWidget {
  final Session? session; // null = create new
  final List<String> existingGroups;
  final String? defaultGroup;

  const SessionEditDialog({
    super.key,
    this.session,
    this.existingGroups = const [],
    this.defaultGroup,
  });

  /// Show dialog. Returns [SessionDialogResult] or null on cancel.
  static Future<SessionDialogResult?> show(
    BuildContext context, {
    Session? session,
    List<String> existingGroups = const [],
    String? defaultGroup,
  }) {
    return showDialog<SessionDialogResult>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => SessionEditDialog(
        session: session,
        existingGroups: existingGroups,
        defaultGroup: defaultGroup,
      ),
    );
  }

  @override
  State<SessionEditDialog> createState() => _SessionEditDialogState();
}

class _SessionEditDialogState extends State<SessionEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _keyPathCtrl;
  late final TextEditingController _keyDataCtrl;
  late final TextEditingController _passphraseCtrl;
  late AuthType _authType;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
  bool _showKeyText = false;
  bool _keyDragging = false;
  TextEditingController? _autoCompleteCtrl;

  bool get _isEditing => widget.session != null;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _labelCtrl = TextEditingController(text: s?.label ?? '');
    _groupCtrl = TextEditingController(text: s?.group ?? widget.defaultGroup ?? '');
    _hostCtrl = TextEditingController(text: s?.host ?? '');
    _portCtrl = TextEditingController(text: '${s?.port ?? 22}');
    _userCtrl = TextEditingController(text: s?.user ?? '');
    _passwordCtrl = TextEditingController(text: s?.password ?? '');
    _keyPathCtrl = TextEditingController(text: s?.keyPath ?? '');
    _keyDataCtrl = TextEditingController(text: s?.keyData ?? '');
    _passphraseCtrl = TextEditingController(text: s?.passphrase ?? '');
    _authType = s?.authType ?? AuthType.password;
    _showKeyText = (s?.keyData ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _groupCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _keyPathCtrl.dispose();
    _keyDataCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  SSHConfig _buildConfig() {
    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);
    return SSHConfig(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      user: _userCtrl.text.trim(),
      password: _passwordCtrl.text,
      keyPath: keyPath,
      keyData: _keyDataCtrl.text.trim(),
      passphrase: _passphraseCtrl.text,
    );
  }

  Session _buildSession() {
    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);
    if (_isEditing) {
      return widget.session!.copyWith(
        label: _labelCtrl.text.trim(),
        group: _groupCtrl.text.trim(),
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 22,
        user: _userCtrl.text.trim(),
        authType: _authType,
        password: _passwordCtrl.text,
        keyPath: keyPath,
        keyData: _keyDataCtrl.text.trim(),
        passphrase: _passphraseCtrl.text,
      );
    }
    return Session(
      label: _labelCtrl.text.trim(),
      group: _groupCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      user: _userCtrl.text.trim(),
      authType: _authType,
      password: _passwordCtrl.text,
      keyPath: keyPath,
      keyData: _keyDataCtrl.text.trim(),
      passphrase: _passphraseCtrl.text,
    );
  }

  void _connectOnly() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(ConnectOnlyResult(_buildConfig()));
  }

  void _saveAndConnect() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(SaveResult(_buildSession(), connect: true));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(SaveResult(_buildSession()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Session' : 'New Session'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabelField(),
                const SizedBox(height: 12),
                _buildGroupField(),
                const SizedBox(height: 16),
                _buildHostPortRow(),
                const SizedBox(height: 12),
                _buildUserField(),
                const SizedBox(height: 16),
                _buildAuthTypeSelector(),
                const SizedBox(height: 12),
                ..._buildAuthFields(),
              ],
            ),
          ),
        ),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildLabelField() {
    return TextFormField(
      controller: _labelCtrl,
      decoration: const InputDecoration(
        labelText: 'Label',
        hintText: 'My Server',
        prefixIcon: Icon(Icons.label),
      ),
      autofocus: true,
    );
  }

  Widget _buildGroupField() {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _groupCtrl.text),
      optionsBuilder: (value) {
        if (value.text.isEmpty) return widget.existingGroups;
        return widget.existingGroups.where(
          (g) => g.toLowerCase().contains(value.text.toLowerCase()),
        );
      },
      onSelected: (value) => _groupCtrl.text = value,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // Sync with our controller — only add listener once
        if (_autoCompleteCtrl != controller) {
          _autoCompleteCtrl = controller;
          controller.text = _groupCtrl.text;
          controller.addListener(() => _groupCtrl.text = controller.text);
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Group',
            hintText: 'Production/Web',
            prefixIcon: Icon(Icons.folder),
          ),
        );
      },
    );
  }

  Widget _buildHostPortRow() {
    return Row(
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
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _portCtrl,
            decoration: const InputDecoration(labelText: 'Port'),
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
    );
  }

  Widget _buildUserField() {
    return TextFormField(
      controller: _userCtrl,
      decoration: const InputDecoration(
        labelText: 'Username *',
        hintText: 'root',
        prefixIcon: Icon(Icons.person),
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _buildAuthTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Authentication', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        SegmentedButton<AuthType>(
          segments: const [
            ButtonSegment(value: AuthType.password, label: Text('Password'), icon: Icon(Icons.lock, size: 16)),
            ButtonSegment(value: AuthType.key, label: Text('Key'), icon: Icon(Icons.vpn_key, size: 16)),
            ButtonSegment(value: AuthType.keyWithPassword, label: Text('Key+Pass'), icon: Icon(Icons.enhanced_encryption, size: 16)),
          ],
          selected: {_authType},
          onSelectionChanged: (v) => setState(() => _authType = v.first),
        ),
      ],
    );
  }

  List<Widget> _buildAuthFields() {
    return [
      // Password (for password and keyWithPassword)
      if (_authType == AuthType.password || _authType == AuthType.keyWithPassword)
        _buildPasswordField(),

      // Key fields (for key and keyWithPassword)
      if (_authType == AuthType.key || _authType == AuthType.keyWithPassword)
        ..._buildKeyFields(),
    ];
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      obscureText: _obscurePassword,
    );
  }

  List<Widget> _buildKeyFields() {
    return [
      const SizedBox(height: 12),
      _buildKeyPathField(),
      const SizedBox(height: 8),
      _buildPemToggle(),
      if (_showKeyText) _buildPemTextField(),
      const SizedBox(height: 12),
      _buildPassphraseField(),
    ];
  }

  Widget _buildKeyPathField() {
    if (isDesktopPlatform) {
      return _buildDesktopKeyPathField();
    }
    // Mobile: key file path field without drag&drop
    return TextFormField(
      controller: _keyPathCtrl,
      decoration: const InputDecoration(
        labelText: 'Key File Path',
        hintText: '/path/to/key',
        prefixIcon: Icon(Icons.vpn_key),
      ),
    );
  }

  Widget _buildDesktopKeyPathField() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _keyDragging = true),
      onDragExited: (_) => setState(() => _keyDragging = false),
      onDragDone: (details) {
        setState(() => _keyDragging = false);
        final files = details.files;
        if (files.isNotEmpty) {
          final path = files.first.path;
          // If the file looks like a PEM key, read its contents into keyData
          final file = File(path);
          if (file.existsSync() && file.lengthSync() < 32768) {
            final content = file.readAsStringSync();
            if (content.contains('PRIVATE KEY')) {
              setState(() {
                _keyDataCtrl.text = content;
                _showKeyText = true;
              });
              return;
            }
          }
          // Otherwise just set the path
          setState(() => _keyPathCtrl.text = path);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: _keyDragging
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
              : null,
        ),
        child: TextFormField(
          controller: _keyPathCtrl,
          decoration: InputDecoration(
            labelText: 'Key File',
            hintText: '~/.ssh/id_rsa',
            prefixIcon: const Icon(Icons.vpn_key),
            suffixText: _keyDragging ? 'Drop here' : null,
          ),
        ),
      ),
    );
  }

  Widget _buildPemToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _showKeyText = !_showKeyText),
        icon: Icon(_showKeyText ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16),
        label: Text(
          _showKeyText ? 'Hide PEM text' : 'Paste PEM key text',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildPemTextField() {
    return TextFormField(
      controller: _keyDataCtrl,
      decoration: const InputDecoration(
        labelText: 'Key Text (PEM)',
        hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
        alignLabelWithHint: true,
      ),
      maxLines: 5,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    );
  }

  Widget _buildPassphraseField() {
    return TextFormField(
      controller: _passphraseCtrl,
      decoration: InputDecoration(
        labelText: 'Key Passphrase',
        prefixIcon: const Icon(Icons.password),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassphrase ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
        ),
      ),
      obscureText: _obscurePassphrase,
    );
  }

  List<Widget> _buildActions() {
    if (_isEditing) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      OutlinedButton(
        onPressed: _connectOnly,
        child: const Text('Connect'),
      ),
      FilledButton(
        onPressed: _saveAndConnect,
        child: const Text('Save & Connect'),
      ),
    ];
  }
}
