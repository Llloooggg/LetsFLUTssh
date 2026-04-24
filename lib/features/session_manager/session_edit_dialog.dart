import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/security/key_store.dart';
import '../../core/shortcut_registry.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../core/tags/tag.dart';
import '../../providers/key_provider.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/dropdown_select_button.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/styled_form_field.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart';
import '../../utils/secret_controller.dart';
import '../tags/tag_assign_dialog.dart';

/// Result of the session edit dialog.
sealed class SessionDialogResult {}

/// User chose "Save" or "Save & Connect".
class SaveResult extends SessionDialogResult {
  final Session session;
  final bool connect;
  SaveResult(this.session, {this.connect = false});
}

/// Dialog for creating or editing a session.
/// Shows 3 buttons: Cancel | Save | Save & Connect
class SessionEditDialog extends ConsumerStatefulWidget {
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
  ConsumerState<SessionEditDialog> createState() => _SessionEditDialogState();
}

class _SessionEditDialogState extends ConsumerState<SessionEditDialog> {
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
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
  bool _showKeyText = false;
  bool _keyDragging = false;
  String? _authError;
  int _tabIndex = 0;

  /// Selected key from the central key store.
  String _selectedKeyId = '';
  String _selectedKeyLabel = '';

  bool get _isEditing => widget.session != null;

  /// Whether a key from the store is selected.
  bool get _hasStoreKey => _selectedKeyId.isNotEmpty;

  /// Derive auth type from what the user actually filled in.
  AuthType get _derivedAuthType {
    final hasPassword = _passwordCtrl.text.isNotEmpty;
    final hasKey =
        _hasStoreKey ||
        _keyPathCtrl.text.trim().isNotEmpty ||
        _keyDataCtrl.text.trim().isNotEmpty;
    if (hasPassword && hasKey) return AuthType.keyWithPassword;
    if (hasKey) return AuthType.key;
    return AuthType.password;
  }

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
    _showKeyText = (s?.keyData ?? '').isNotEmpty;
    _selectedKeyId = s?.keyId ?? '';
    if (_selectedKeyId.isNotEmpty) {
      _resolveKeyLabel();
    }
  }

  /// Look up the key label from the store for display.
  Future<void> _resolveKeyLabel() async {
    final store = ref.read(keyStoreProvider);
    final entry = await store.get(_selectedKeyId);
    if (entry != null && mounted) {
      setState(() => _selectedKeyLabel = entry.label);
    }
  }

  @override
  void dispose() {
    // Secret-bearing controllers — overwrite with null bytes and
    // clear before disposing so the Dart-heap residency window for
    // the typed password / PEM body / passphrase ends at dialog
    // close, not whenever the next GC cycle reclaims the immutable
    // String. Matches the wipe discipline ExpandableTierCard +
    // SecurityPasswordField already follow.
    _passwordCtrl.wipeAndClear();
    _keyDataCtrl.wipeAndClear();
    _passphraseCtrl.wipeAndClear();
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
          authType: _derivedAuthType,
          keyId: _selectedKeyId,
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
        authType: _derivedAuthType,
        keyId: _selectedKeyId,
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
        _hasStoreKey ||
        _keyPathCtrl.text.trim().isNotEmpty ||
        _keyDataCtrl.text.trim().isNotEmpty;

    if (!hasPassword && !hasKey) {
      setState(() {
        _authError = S.of(context).providePasswordOrKey;
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
    // Auth tab (1): credentials
    return 1;
  }

  void _save({bool connect = false}) {
    final formOk = _formKey.currentState!.validate();
    if (!formOk) {
      setState(() => _tabIndex = _tabWithFirstError());
      return;
    }
    if (!_validateAuth()) return;
    Navigator.of(context).pop(SaveResult(_buildSession(), connect: connect));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bg1,
      insetPadding: const EdgeInsets.all(24),
      child: CallbackShortcuts(
        bindings: AppShortcutRegistry.instance.buildCallbackMap({
          AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
        }),
        child: Focus(
          autofocus: true,
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
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: _tabIndex != 0,
                            child: _buildConnectionTab(),
                          ),
                          Offstage(
                            offstage: _tabIndex != 1,
                            child: _buildAuthTab(),
                          ),
                          Offstage(
                            offstage: _tabIndex != 2,
                            child: _buildOptionsTab(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
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
      // Three Expanded tabs so Russian / German labels never push the
      // third tab past the modal edge. Each tab caps its content at a
      // third of the bar width and truncates with ellipsis if the
      // translation still overflows that slot.
      child: Row(
        children: [
          Expanded(child: _buildTab(0, Icons.dns, S.of(context).connection)),
          Expanded(child: _buildTab(1, Icons.shield, S.of(context).auth)),
          Expanded(child: _buildTab(2, Icons.folder, S.of(context).options)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: !active && hovered ? AppTheme.hover : Colors.transparent,
          border: active
              ? Border(bottom: BorderSide(color: AppTheme.accent, width: 2))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: active ? AppTheme.fg : AppTheme.fgFaint,
            ),
            const SizedBox(width: 6),
            // Flexible + ellipsis so long translations truncate
            // inside the tab rather than breaking the Row.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.sm,
                  fontWeight: FontWeight.w500,
                  color: active ? AppTheme.fg : AppTheme.fgFaint,
                ),
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
        StyledFormField(
          label: S.of(context).sessionName,
          controller: _labelCtrl,
          hint: S.of(context).hintMyServer,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StyledFormField(
                label: S.of(context).hostRequired,
                controller: _hostCtrl,
                hint: S.of(context).hintHost,
                validator: _requiredValidator,
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
        ),
      ],
    );
  }

  // ── Auth tab ──

  Widget _buildAuthTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_authError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
        _buildPasswordField(),
        const SizedBox(height: 16),
        _buildOrDivider(),
        const SizedBox(height: 16),
        ..._buildKeyFields(),
      ],
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppTheme.borderLight)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            S.of(context).authOrDivider,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppTheme.fgFaint,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.borderLight)),
      ],
    );
  }

  Widget _buildPasswordField() {
    return StyledFormField(
      label: S.of(context).password,
      controller: _passwordCtrl,
      hint: '••••••••',
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
      _buildKeyStoreSelector(),
      const SizedBox(height: 12),
      if (!_hasStoreKey) ...[
        _buildKeyPathField(),
        const SizedBox(height: 8),
        _buildPemToggle(),
        if (_showKeyText) _buildPemTextField(),
        const SizedBox(height: 12),
      ],
      _buildPassphraseField(),
    ];
  }

  Widget _buildKeyStoreSelector() {
    final s = S.of(context);
    final keys = ref.watch(sshKeysProvider);

    return keys.when(
      data: (keyList) {
        if (keyList.isEmpty && !_hasStoreKey) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _hasStoreKey
                      ? _buildSelectedKeyChip()
                      : _buildKeyPickerButton(s, keyList),
                ),
              ],
            ),
            if (_hasStoreKey)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _buildOrDividerLabel(),
                    style: TextStyle(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgFaint,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  String _buildOrDividerLabel() =>
      '${S.of(context).selectFromKeyStore}: $_selectedKeyLabel';

  Widget _buildKeyPickerButton(S s, List<SshKeyEntry> keyList) {
    return DropdownSelectButton(
      icon: Icons.vpn_key,
      label: s.selectFromKeyStore,
      onTap: keyList.isEmpty ? null : () => _showKeyPicker(keyList),
    );
  }

  Widget _buildSelectedKeyChip() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.vpn_key, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedKeyLabel,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fg,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: () => setState(() {
              _selectedKeyId = '';
              _selectedKeyLabel = '';
            }),
            tooltip: S.of(context).clearKeyFile,
            size: 18,
          ),
        ],
      ),
    );
  }

  Future<void> _showKeyPicker(List<SshKeyEntry> keys) async {
    final selected = await showDialog<SshKeyEntry>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.of(context).selectFromKeyStore),
        children: keys
            .map(
              (k) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, k),
                child: ListTile(
                  leading: Icon(
                    Icons.vpn_key,
                    size: 16,
                    color: k.isGenerated ? AppTheme.accent : AppTheme.fgDim,
                  ),
                  title: Text(k.label),
                  subtitle: Text(
                    k.keyType,
                    style: TextStyle(fontSize: AppFonts.xs),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedKeyId = selected.id;
        _selectedKeyLabel = selected.label;
        // Clear manual key fields when selecting from store
        _keyPathCtrl.clear();
        _keyDataCtrl.clear();
        _showKeyText = false;
      });
    }
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: S.of(context).selectKeyFile,
      allowMultiple: false,
      type: FileType.any,
    );
    if (!mounted) return;
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

    final button = DropdownSelectButton(
      icon: hasKey ? Icons.vpn_key : Icons.folder_open,
      label: fileName ?? S.of(context).selectKeyFile,
      onTap: _pickKeyFile,
      showChevron: false,
    );

    final row = Row(
      children: [
        Expanded(child: button),
        if (hasKey)
          AppIconButton(
            icon: Icons.close,
            onTap: () => setState(() => _keyPathCtrl.clear()),
            tooltip: S.of(context).clearKeyFile,
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
                    S.of(context).dropKeyFileHere,
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
      child: AppButton(
        label: _showKeyText
            ? S.of(context).hidePemText
            : S.of(context).pastePemKeyText,
        icon: _showKeyText
            ? Icons.keyboard_arrow_up
            : Icons.keyboard_arrow_down,
        onTap: () => setState(() => _showKeyText = !_showKeyText),
        dense: true,
      ),
    );
  }

  Widget _buildPemTextField() {
    return TextFormField(
      controller: _keyDataCtrl,
      decoration: InputDecoration(
        hintText: S.of(context).hintPemKey,
        hintStyle: AppFonts.mono(
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
      // PEM body is a private key — force every IME "learn what
      // the user typed" knob off so pasted / typed key material
      // does not end up in the OS autocorrect / predictive-text /
      // spellcheck personalised-learning dictionary. Multi-line,
      // so `obscureText` is not an option; the hardening flags are.
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textCapitalization: TextCapitalization.none,
      style: AppFonts.mono(fontSize: AppFonts.xs),
    );
  }

  Widget _buildPassphraseField() {
    return StyledFormField(
      label: S.of(context).keyPassphrase,
      controller: _passphraseCtrl,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [_buildTagsSection()],
    );
  }

  /// Tags option row — label on the left, action on the right,
  /// assigned chips on their own row below. Keeps the form's label +
  /// control rhythm predictable so new option rows (dropdowns,
  /// toggles) can be appended without the Options tab looking like a
  /// list of centred orphan buttons. The old layout stacked the
  /// label, chips and a full-width button vertically, which left a
  /// lot of whitespace on the right and visually centred the button
  /// against that whitespace — the "теги и кнопка висят по центру"
  /// complaint.
  Widget _buildTagsSection() {
    final s = S.of(context);
    return _OptionRow(
      label: s.tags,
      trailing: _isEditing
          ? _ManageTagsButton(sessionId: widget.session!.id)
          : null,
      detail: _isEditing
          ? _EditingSessionTagsChips(sessionId: widget.session!.id)
          : Text(
              s.saveSessionToAssignTags,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppFonts.xs,
                color: AppTheme.fgFaint,
              ),
            ),
    );
  }

  // ── Footer ──

  Widget _buildFooter() {
    return AppDialogFooter(
      actions: [
        AppButton.cancel(onTap: () => Navigator.of(context).pop()),
        AppButton.secondary(label: S.of(context).save, onTap: _save),
        AppButton.primary(
          label: S.of(context).saveAndConnect,
          onTap: () => _save(connect: true),
        ),
      ],
    );
  }

  // ── Styled field helper ──

  String? Function(String?) get _requiredValidator =>
      (v) => v == null || v.trim().isEmpty ? S.of(context).required : null;
}

/// Form row for the Options tab. Label on the left, a trailing action
/// widget on the right (typically a compact button), and an optional
/// [detail] block rendered full-width below the label/action line.
/// Adding a second option row (e.g. a dropdown) is a one-line drop-in
/// that preserves the column alignment instead of stacking orphan
/// buttons against the left edge.
class _OptionRow extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final Widget? detail;

  const _OptionRow({required this.label, this.trailing, this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppFonts.sm,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.fg,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: detail!),
          ],
        ],
      ),
    );
  }
}

/// Compact "Manage tags" button for the trailing slot of
/// [_OptionRow]. Intrinsic width so it doesn't stretch to fill the
/// row and look centred against whitespace.
class _ManageTagsButton extends ConsumerWidget {
  final String sessionId;

  const _ManageTagsButton({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return AppButton.secondary(
      label: s.manageTags,
      icon: Icons.label_outline,
      dense: true,
      onTap: () async {
        await TagAssignDialog.showForSession(context, sessionId: sessionId);
        // The dialog applies changes directly; invalidate to refresh.
        ref.invalidate(sessionTagsProvider(sessionId));
      },
    );
  }
}

/// Chips-only render of the session's assigned tags — the trailing
/// "Manage" control lives in the [_OptionRow] header so the chips
/// take the full detail width without a competing button below them.
class _EditingSessionTagsChips extends ConsumerWidget {
  final String sessionId;

  const _EditingSessionTagsChips({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final tagsAsync = ref.watch(sessionTagsProvider(sessionId));
    return tagsAsync.when(
      loading: () => const SizedBox(
        height: 16,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (tags) {
        if (tags.isEmpty) {
          return Text(
            s.noTagsAssigned,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.xs,
              color: AppTheme.fgFaint,
            ),
          );
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final tag in tags) _tagChip(tag)],
        );
      },
    );
  }

  Widget _tagChip(Tag tag) {
    final color = tag.colorValue ?? AppTheme.fgDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            tag.name,
            style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fg),
          ),
        ],
      ),
    );
  }
}
