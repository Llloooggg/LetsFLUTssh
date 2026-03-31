import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/hover_region.dart';
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
/// In create mode, shows 3 buttons: Cancel | Save | Connect
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
  String? _keyError;
  TextEditingController? _autoCompleteCtrl;
  int _tabIndex = 0;

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

  Session _buildSession() {
    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);
    if (_isEditing) {
      return widget.session!.copyWith(
        label: _labelCtrl.text.trim(),
        group: _groupCtrl.text.trim(),
        server: widget.session!.server.copyWith(
          host: _hostCtrl.text.trim(),
          port: int.tryParse(_portCtrl.text.trim()) ?? 22,
          user: _userCtrl.text.trim(),
        ),
        auth: widget.session!.auth.copyWith(
          authType: _authType,
          password: _passwordCtrl.text,
          keyPath: keyPath,
          keyData: _keyDataCtrl.text.trim(),
          passphrase: _passphraseCtrl.text,
        ),
      );
    }
    return Session(
      label: _labelCtrl.text.trim(),
      group: _groupCtrl.text.trim(),
      server: ServerAddress(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 22,
        user: _userCtrl.text.trim(),
      ),
      auth: SessionAuth(
        authType: _authType,
        password: _passwordCtrl.text,
        keyPath: keyPath,
        keyData: _keyDataCtrl.text.trim(),
        passphrase: _passphraseCtrl.text,
      ),
    );
  }

  SSHConfig _buildConfig() {
    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);
    return SSHConfig(
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
  }

  bool _validateAuth() {
    final needsKey = _authType == AuthType.key || _authType == AuthType.keyWithPassword;
    if (needsKey) {
      final hasKey = _keyPathCtrl.text.trim().isNotEmpty ||
          _keyDataCtrl.text.trim().isNotEmpty;
      if (!hasKey) {
        setState(() {
          _keyError = 'Provide a key file or paste PEM text';
          _tabIndex = 1;
        });
        return false;
      }
    }
    setState(() => _keyError = null);
    return true;
  }

  void _connectOnly() {
    if (!_validateAuth()) return;
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(ConnectOnlyResult(_buildConfig()));
  }

  void _save() {
    if (!_validateAuth()) return;
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(SaveResult(_buildSession()));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bg1,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              _buildTabBar(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      _buildConnectionTab(),
                      _buildAuthTab(),
                      _buildOptionsTab(),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Text(
            _isEditing ? 'Edit Connection' : 'New Connection',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg,
            ),
          ),
          const Spacer(),
          AppIconButton(
            icon: Icons.close,
            onTap: () => Navigator.of(context).pop(),
            size: 13,
            boxSize: 22,
          ),
        ],
      ),
    );
  }

  // ── Tab bar ──

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          _buildTab(0, Icons.dns, 'Connection'),
          _buildTab(1, Icons.shield, 'Auth'),
          _buildTab(2, Icons.folder, 'Options'),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final active = _tabIndex == index;
    return HoverRegion(
      onTap: () => setState(() => _tabIndex = index),
      builder: (hovered) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: !active && hovered ? AppTheme.hover : Colors.transparent,
          border: active
              ? Border(bottom: BorderSide(color: AppTheme.accent, width: 2))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: active ? AppTheme.fg : AppTheme.fgFaint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active ? AppTheme.fg : AppTheme.fgFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Connection tab ──

  Widget _buildConnectionTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _styledField('Session Name', _labelCtrl, hint: 'My Server'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _styledField('Host *', _hostCtrl,
                  hint: '192.168.1.1',
                  validator: _requiredValidator),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: _styledField('Port', _portCtrl,
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
        _styledField('Username *', _userCtrl,
            hint: 'root', validator: _requiredValidator),
        const SizedBox(height: 12),
        _buildGroupField(),
      ],
    );
  }

  Widget _buildGroupField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Group'),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _groupCtrl.text),
          optionsBuilder: (value) {
            if (value.text.isEmpty) return widget.existingGroups;
            return widget.existingGroups.where(
              (g) => g.toLowerCase().contains(value.text.toLowerCase()),
            );
          },
          onSelected: (value) => _groupCtrl.text = value,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            if (_autoCompleteCtrl != controller) {
              _autoCompleteCtrl = controller;
              controller.text = _groupCtrl.text;
              controller.addListener(() => _groupCtrl.text = controller.text);
            }
            return _StyledInput(
              controller: controller,
              focusNode: focusNode,
              hint: 'Production/Web',
            );
          },
        ),
      ],
    );
  }

  // ── Auth tab ──

  Widget _buildAuthTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAuthTypeSelector(),
        const SizedBox(height: 12),
        ..._buildAuthFields(),
      ],
    );
  }

  Widget _buildAuthTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Method'),
        Row(
          children: [
            Expanded(child: _authButton(AuthType.password, Icons.shield, 'Password')),
            const SizedBox(width: 8),
            Expanded(child: _authButton(AuthType.key, Icons.vpn_key, 'SSH Key')),
            const SizedBox(width: 8),
            Expanded(child: _authButton(AuthType.keyWithPassword, Icons.enhanced_encryption, 'Key+Pass')),
          ],
        ),
      ],
    );
  }

  Widget _authButton(AuthType type, IconData icon, String label) {
    final active = _authType == type;
    return GestureDetector(
      onTap: () => setState(() => _authType = type),
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppTheme.selection : AppTheme.bg3,
          border: Border.all(color: active ? AppTheme.accent : AppTheme.borderLight),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: active ? AppTheme.accent : AppTheme.fgDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active ? AppTheme.accent : AppTheme.fgDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAuthFields() {
    return [
      if (_authType == AuthType.password || _authType == AuthType.keyWithPassword)
        _buildPasswordField(),
      if (_authType == AuthType.key || _authType == AuthType.keyWithPassword)
        ..._buildKeyFields(),
    ];
  }

  Widget _buildPasswordField() {
    return _styledField('Password *', _passwordCtrl,
        hint: '••••••••',
        validator: _requiredValidator,
        obscure: _obscurePassword,
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          child: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
            size: 12,
            color: AppTheme.fgFaint,
          ),
        ));
  }

  List<Widget> _buildKeyFields() {
    return [
      const SizedBox(height: 12),
      _buildKeyPathField(),
      if (_keyError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _keyError!,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: AppTheme.red,
            ),
          ),
        ),
      const SizedBox(height: 8),
      _buildPemToggle(),
      if (_showKeyText) _buildPemTextField(),
      const SizedBox(height: 12),
      _buildPassphraseField(),
    ];
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

  Widget _buildKeyPathField() {
    final hasKey = _keyPathCtrl.text.trim().isNotEmpty;
    final fileName = hasKey ? p.basename(_keyPathCtrl.text.trim()) : null;

    final button = OutlinedButton.icon(
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
    );

    final row = Row(
      children: [
        Expanded(child: button),
        if (hasKey)
          AppIconButton(
            icon: Icons.close,
            onTap: () => setState(() => _keyPathCtrl.clear()),
            tooltip: 'Clear key file',
            size: 18,
          ),
      ],
    );

    if (!isDesktopPlatform) return row;

    return DropTarget(
      onDragEntered: (_) => setState(() => _keyDragging = true),
      onDragExited: (_) => setState(() => _keyDragging = false),
      onDragDone: (details) {
        setState(() => _keyDragging = false);
        final files = details.files;
        if (files.isNotEmpty) {
          final path = files.first.path;
          final pemContent = KeyFileHelper.tryReadPemKey(path);
          if (pemContent != null) {
            setState(() {
              _keyDataCtrl.text = pemContent;
              _showKeyText = true;
            });
            return;
          }
          setState(() => _keyPathCtrl.text = path);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          border: _keyDragging
              ? Border.all(color: AppTheme.accent, width: 2)
              : null,
        ),
        child: _keyDragging
            ? SizedBox(
                height: 48,
                child: Center(
                  child: Text('Drop key file here',
                      style: TextStyle(color: AppTheme.accent)),
                ),
              )
            : row,
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
    return _styledField('Key Passphrase', _passphraseCtrl,
        hint: 'Optional',
        obscure: _obscurePassphrase,
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
          child: Icon(
            _obscurePassphrase ? Icons.visibility : Icons.visibility_off,
            size: 12,
            color: AppTheme.fgFaint,
          ),
        ),
        validator: (v) {
          if (v != null && v.isNotEmpty) {
            final hasKey = _keyPathCtrl.text.trim().isNotEmpty ||
                _keyDataCtrl.text.trim().isNotEmpty;
            if (!hasKey) return 'Provide a key file or PEM text first';
          }
          return null;
        });
  }

  // ── Options tab ──

  Widget _buildOptionsTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Text(
          'No additional options yet',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            color: AppTheme.fgFaint,
          ),
        ),
      ],
    );
  }

  // ── Footer ──

  Widget _buildFooter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _footerButton('Cancel', onTap: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          if (_isEditing)
            _footerButton('Save', bg: AppTheme.accent, fg: Colors.white, onTap: _save)
          else ...[
            _footerButton('Save', bg: AppTheme.bg4, fg: AppTheme.fg, onTap: _save),
            const SizedBox(width: 8),
            _footerButton('Connect', bg: AppTheme.accent, fg: Colors.white, onTap: _connectOnly),
          ],
        ],
      ),
    );
  }

  Widget _footerButton(String label, {Color? bg, Color? fg, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: EdgeInsets.symmetric(horizontal: bg != null ? 16 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: bg != null ? FontWeight.w500 : null,
            color: fg ?? AppTheme.fgDim,
          ),
        ),
      ),
    );
  }

  // ── Styled field helper ──

  static String? _requiredValidator(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;

  Widget _styledField(
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
        _FieldLabel(label),
        _StyledInput(
          controller: controller,
          hint: hint,
          obscure: obscure,
          suffixIcon: suffixIcon,
          keyboardType: keyboardType,
          validator: validator,
        ),
      ],
    );
  }
}

/// Uppercase field label.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: AppTheme.fgFaint,
        ),
      ),
    );
  }
}

/// Styled text input matching the mockup.
class _StyledInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hint;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _StyledInput({
    required this.controller,
    this.focusNode,
    this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 11,
        color: AppTheme.fg,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
          color: AppTheme.fgFaint,
        ),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppTheme.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppTheme.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppTheme.red),
        ),
        errorStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          color: AppTheme.red,
          height: 1.2,
        ),
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: suffixIcon,
              )
            : null,
        suffixIconConstraints: const BoxConstraints(maxHeight: 30),
      ),
    );
  }
}
