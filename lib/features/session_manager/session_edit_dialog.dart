import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bordered_box.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/hover_region.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart';

const _kMonoFont = 'JetBrains Mono';

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
/// In edit mode, shows 3 buttons: Cancel | Save | Save & Connect
class SessionEditDialog extends StatefulWidget {
  final Session? session; // null = create new
  final String? defaultFolder;

  const SessionEditDialog({super.key, this.session, this.defaultFolder});

  /// Show dialog. Returns [SessionDialogResult] or null on cancel.
  static Future<SessionDialogResult?> show(
    BuildContext context, {
    Session? session,
    String? defaultFolder,
  }) {
    return showDialog<SessionDialogResult>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) =>
          SessionEditDialog(session: session, defaultFolder: defaultFolder),
    );
  }

  @override
  State<SessionEditDialog> createState() => _SessionEditDialogState();
}

class _SessionEditDialogState extends State<SessionEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _folderCtrl;
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
  String? _authError;
  int _tabIndex = 0;

  bool get _isEditing => widget.session != null;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _labelCtrl = TextEditingController(text: s?.label ?? '');
    _folderCtrl = TextEditingController(
      text: s?.folder ?? widget.defaultFolder ?? '',
    );
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
    _folderCtrl.dispose();
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
        folder: _folderCtrl.text.trim(),
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
      folder: _folderCtrl.text.trim(),
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
    final hasPassword = _passwordCtrl.text.isNotEmpty;
    final hasKey =
        _keyPathCtrl.text.trim().isNotEmpty ||
        _keyDataCtrl.text.trim().isNotEmpty;

    String? error;
    switch (_authType) {
      case AuthType.password:
        // Password field has its own required validator.
        break;
      case AuthType.key:
        if (!hasKey) error = 'Provide a key file or paste PEM text';
      case AuthType.keyWithPassword:
        if (!hasPassword && !hasKey) {
          error = 'Provide a password, key file, or PEM text';
        }
    }

    if (error != null) {
      setState(() {
        _authError = error;
        _tabIndex = 1;
      });
      return false;
    }
    setState(() => _authError = null);
    return true;
  }

  /// Determine which tab contains the first validation error and switch to it.
  int _tabWithFirstError() {
    // Connection tab (0): host, port, username
    if (_requiredValidator(_hostCtrl.text) != null) return 0;
    final port = int.tryParse(_portCtrl.text);
    if (port == null || port < 1 || port > 65535) return 0;
    if (_requiredValidator(_userCtrl.text) != null) return 0;
    // Auth tab (1): password when required
    return 1;
  }

  void _connectOnly() {
    if (!_validateAuth()) return;
    if (!_formKey.currentState!.validate()) {
      setState(() => _tabIndex = _tabWithFirstError());
      return;
    }
    Navigator.of(context).pop(ConnectOnlyResult(_buildConfig()));
  }

  void _save({bool connect = false}) {
    if (!_validateAuth()) return;
    if (!_formKey.currentState!.validate()) {
      setState(() => _tabIndex = _tabWithFirstError());
      return;
    }
    Navigator.of(context).pop(SaveResult(_buildSession(), connect: connect));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bg1,
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
    return AppDialogHeader(
      title: _isEditing
          ? S.of(context).editConnection
          : S.of(context).newConnection,
      onClose: () => Navigator.of(context).pop(),
    );
  }

  // ── Tab bar ──

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(border: AppTheme.borderBottom),
      child: Row(
        children: [
          _buildTab(0, Icons.dns, S.of(context).connection),
          _buildTab(1, Icons.shield, S.of(context).auth),
          _buildTab(2, Icons.folder, S.of(context).options),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final active = _tabIndex == index;
    return HoverRegion(
      onTap: () => setState(() => _tabIndex = index),
      builder: (hovered) => Container(
        height: AppTheme.controlHeightLg,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: !active && hovered ? AppTheme.hover : Colors.transparent,
          border: active
              ? Border(bottom: BorderSide(color: AppTheme.accent, width: 2))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: active ? AppTheme.fg : AppTheme.fgFaint,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppFonts.sm,
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
        _styledField(
          S.of(context).sessionName,
          _labelCtrl,
          hint: S.of(context).hintMyServer,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _styledField(
                S.of(context).hostRequired,
                _hostCtrl,
                hint: S.of(context).hintHost,
                validator: _requiredValidator,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: _styledField(
                S.of(context).port,
                _portCtrl,
                hint: S.of(context).hintPort,
                keyboardType: TextInputType.number,
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
        _styledField(
          S.of(context).usernameRequired,
          _userCtrl,
          hint: S.of(context).hintUsername,
          validator: _requiredValidator,
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
        if (_authError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _authError!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.xs,
                  color: AppTheme.red,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _buildPasswordField(),
        const SizedBox(height: 12),
        ..._buildKeyFields(),
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
            Expanded(
              child: _authButton(AuthType.password, Icons.shield, 'Password'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _authButton(AuthType.key, Icons.vpn_key, 'SSH Key'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _authButton(
                AuthType.keyWithPassword,
                Icons.swap_horiz,
                'Both',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _authButton(AuthType type, IconData icon, String label) {
    final active = _authType == type;
    return GestureDetector(
      onTap: () => setState(() => _authType = type),
      child: AppBorderedBox(
        height: AppTheme.controlHeightMd,
        alignment: Alignment.center,
        color: active ? AppTheme.selection : AppTheme.bg3,
        borderColor: active ? AppTheme.accent : AppTheme.borderLight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 11,
              color: active ? AppTheme.accent : AppTheme.fgDim,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppFonts.sm,
                fontWeight: FontWeight.w500,
                color: active ? AppTheme.accent : AppTheme.fgDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    final required = _authType == AuthType.password;
    return _styledField(
      required ? 'Password *' : 'Password',
      _passwordCtrl,
      hint: '••••••••',
      validator: required ? _requiredValidator : null,
      obscure: _obscurePassword,
      suffixIcon: GestureDetector(
        onTap: () => setState(() => _obscurePassword = !_obscurePassword),
        child: Icon(
          _obscurePassword ? Icons.visibility : Icons.visibility_off,
          size: 12,
          color: AppTheme.fgFaint,
        ),
      ),
    );
  }

  List<Widget> _buildKeyFields() {
    return [
      _buildKeyPathField(),
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
          borderRadius: AppTheme.radiusSm,
        ),
        child: _keyDragging
            ? SizedBox(
                height: AppTheme.itemHeightLg,
                child: Center(
                  child: Text(
                    'Drop key file here',
                    style: TextStyle(color: AppTheme.accent),
                  ),
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

  Widget _buildPemTextField() {
    return TextFormField(
      controller: _keyDataCtrl,
      decoration: InputDecoration(
        hintText: S.of(context).hintPemKey,
        hintStyle: TextStyle(
          fontFamily: _kMonoFont,
          fontSize: AppFonts.xs,
          color: AppTheme.fgFaint,
        ),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      ),
      maxLines: 5,
      style: AppFonts.mono(fontSize: AppFonts.xs),
    );
  }

  Widget _buildPassphraseField() {
    return _styledField(
      S.of(context).keyPassphrase,
      _passphraseCtrl,
      hint: S.of(context).hintOptional,
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
          final hasKey =
              _keyPathCtrl.text.trim().isNotEmpty ||
              _keyDataCtrl.text.trim().isNotEmpty;
          if (!hasKey) return S.of(context).provideKeyFirst;
        }
        return null;
      },
    );
  }

  // ── Options tab ──

  Widget _buildOptionsTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Text(
          S.of(context).noAdditionalOptionsYet,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppFonts.sm,
            color: AppTheme.fgFaint,
          ),
        ),
      ],
    );
  }

  // ── Footer ──

  Widget _buildFooter() {
    return AppDialogFooter(
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.of(context).pop()),
        if (_isEditing) ...[
          AppDialogAction.secondary(label: S.of(context).save, onTap: _save),
          AppDialogAction.primary(
            label: S.of(context).saveAndConnect,
            onTap: () => _save(connect: true),
          ),
        ] else ...[
          AppDialogAction.secondary(label: S.of(context).save, onTap: _save),
          AppDialogAction.primary(
            label: S.of(context).connect,
            onTap: _connectOnly,
          ),
        ],
      ],
    );
  }

  // ── Styled field helper ──

  String? Function(String?) get _requiredValidator =>
      (v) => v == null || v.trim().isEmpty ? S.of(context).required : null;

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
          fontSize: AppFonts.xs,
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
  final String? hint;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _StyledInput({
    required this.controller,
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
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        fontFamily: _kMonoFont,
        fontSize: AppFonts.sm,
        color: AppTheme.fg,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: _kMonoFont,
          fontSize: AppFonts.sm,
          color: AppTheme.fgFaint,
        ),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.red),
        ),
        errorStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.xs,
          color: AppTheme.red,
          height: 1.2,
        ),
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: suffixIcon,
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
          maxHeight: AppTheme.controlHeightMd,
        ),
      ),
    );
  }
}
