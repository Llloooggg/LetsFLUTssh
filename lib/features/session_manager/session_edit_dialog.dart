import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/import/key_file_helper.dart';
import '../../core/security/ssh_key.dart';
import '../../core/session/port_forwards_dao.dart';
import '../../widgets/shortcut_registry.dart';
import '../../core/session/session.dart';
import '../../core/ssh/port_forward_rule.dart';
import '../../core/ssh/ssh_config.dart';
import '../../core/tags/tag.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/tag_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_picker_chip.dart';
import '../../widgets/dropdown_select_button.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/styled_form_field.dart';
import '../../widgets/tag_color.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart';
import '../../utils/secret_controller.dart';
import '../tags/tag_assign_dialog.dart';
import 'session_forwards_tab.dart';

// Per-tab UI extracted into part siblings — auth / connection /
// options each own their tab build chain. The dialog state stays
// in this file; the part files extend it via `extension on
// _SessionEditDialogState` so library-private fields stay reachable
// without going through a public surface.
part 'session_edit_dialog_auth.dart';
part 'session_edit_dialog_connection.dart';
part 'session_edit_dialog_options.dart';

/// Result of the session edit dialog.
sealed class SessionDialogResult {}

/// User chose "Save" or "Save & Connect".
class SaveResult extends SessionDialogResult {
  final Session session;
  final bool connect;

  /// Port-forward rules entered in the Forwarding tab. The caller is
  /// responsible for diffing against the persisted set and writing
  /// the delta — see `session_panel._handleDialogResult`. Empty when
  /// the dialog was for a quick-connect / new session that never
  /// touched the tab.
  final List<PortForwardRule> forwards;

  /// Per-slot dirty bits. Only fields the user actually typed into
  /// during this dialog session land in the DB; untouched secret
  /// columns keep whatever they had before so editing the label
  /// never accidentally wipes a stored password.
  final bool passwordDirty;
  final bool keyDataDirty;
  final bool passphraseDirty;

  SaveResult(
    this.session, {
    this.connect = false,
    this.forwards = const [],
    this.passwordDirty = false,
    this.keyDataDirty = false,
    this.passphraseDirty = false,
  });
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

  /// In-memory rule list backing the Forwarding tab. Hydrated from
  /// the store on init when editing; the new-session path starts
  /// empty. Persisted by the caller after a successful Save via
  /// the SaveResult.forwards field — same contract as the session
  /// itself (the dialog never writes to the store directly).
  List<PortForwardRule> _forwards = const [];

  /// ProxyJump editor state.
  ///
  /// Three exclusive modes:
  /// - `none` — direct connection, both selectors empty.
  /// - `saved` — reference an existing saved session by id.
  /// - `custom` — type a one-off `user@host:port` override.
  ///
  /// All three controllers persist independently so flipping the
  /// mode dropdown does not destroy partially typed values.
  _ProxyMode _proxyMode = _ProxyMode.none;
  String? _proxyViaSessionId;
  late final TextEditingController _proxyHostCtrl;
  late final TextEditingController _proxyPortCtrl;
  late final TextEditingController _proxyUserCtrl;

  /// Backing state for the Options-tab Record-session toggle.
  /// Hydrated from `Session.extras['record']` on init (default false
  /// so a fresh session is opt-out by default — privacy-first).
  bool _recordEnabled = false;

  /// Per-slot dirty bits. Flipped to `true` the first time the user
  /// types into / changes the corresponding secret field. The dialog
  /// hands these to the caller via `SaveResult` so the save path can
  /// skip the credential columns the user didn't touch — editing a
  /// label never wipes a stored password.
  bool _passwordDirty = false;
  bool _keyDataDirty = false;
  bool _passphraseDirty = false;

  /// Set the moment `dispose()` starts wiping the secret controllers
  /// so the listeners we attached in `initState` short-circuit
  /// before they call `setState` on a tearing-down State.
  bool _disposing = false;
  VoidCallback? _passwordListener;
  VoidCallback? _keyDataListener;
  VoidCallback? _passphraseListener;

  bool get _isEditing => widget.session != null;

  /// Whether a key from the store is selected.
  bool get _hasStoreKey => _selectedKeyId.isNotEmpty;

  /// Derive auth type from what the user filled in *or* from the
  /// per-slot `hasStoredX` flags so an edit pass that doesn't touch
  /// the secret fields keeps the saved authType (a key-only session
  /// stays key-only even if the user only changed the host). Also
  /// honours legacy in-memory plaintext on `widget.session.auth` —
  /// older callers (and tests) still pass populated `password` /
  /// `keyData` directly.
  AuthType get _derivedAuthType {
    final saved = widget.session?.auth;
    final hasPassword =
        _passwordCtrl.text.isNotEmpty ||
        (saved?.hasStoredPassword ?? false) ||
        (saved?.password.isNotEmpty ?? false);
    final hasKey =
        _hasStoreKey ||
        _keyPathCtrl.text.trim().isNotEmpty ||
        _keyDataCtrl.text.trim().isNotEmpty ||
        (saved?.hasStoredKeyData ?? false) ||
        (saved?.keyData.isNotEmpty ?? false);
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
    // Secret-bearing controllers start empty even on edit — the
    // existing password / private key / passphrase live in the
    // database and cross FRB only via `db_sessions_stage_secrets`,
    // which never hands the bytes back to Dart. The UI shows a
    // "[Saved]" badge next to the field when the corresponding
    // `hasStoredX` flag on the session is true; the user has to
    // type a new value to change the secret, leaving the field
    // blank to keep the existing one intact.
    _passwordCtrl = TextEditingController();
    _keyPathCtrl = TextEditingController(text: s?.keyPath ?? '');
    _keyDataCtrl = TextEditingController();
    _passphraseCtrl = TextEditingController();
    // Mark each secret slot dirty the first time the user touches
    // it. Save consults these to decide whether the corresponding
    // column is part of the partial-update DB write — leaving a
    // field blank on edit therefore preserves the stored secret
    // instead of clearing it. The `_disposing` guard short-circuits
    // the listener once `dispose()` starts wiping the controllers
    // (`wipeAndClear` mutates `text` which fires this listener after
    // the framework has already torn down the State).
    _passwordListener = () {
      if (_disposing || _passwordDirty) return;
      setState(() => _passwordDirty = true);
    };
    _keyDataListener = () {
      if (_disposing || _keyDataDirty) return;
      setState(() => _keyDataDirty = true);
    };
    _passphraseListener = () {
      if (_disposing || _passphraseDirty) return;
      setState(() => _passphraseDirty = true);
    };
    _passwordCtrl.addListener(_passwordListener!);
    _keyDataCtrl.addListener(_keyDataListener!);
    _passphraseCtrl.addListener(_passphraseListener!);
    // Auto-expand the inline-PEM section on edit when the saved
    // session is keyData-bearing — we never see the bytes themselves
    // (controller stays empty), but the per-slot flag tells us the
    // user picked the inline-key path last time. Legacy callers
    // (and tests) still pass populated `keyData` plaintext directly,
    // so accept that too.
    _showKeyText =
        (s?.auth.hasStoredKeyData ?? false) || (s?.keyData.isNotEmpty ?? false);
    _selectedKeyId = s?.keyId ?? '';
    if (_selectedKeyId.isNotEmpty) {
      _resolveKeyLabel();
    }
    // ProxyJump editor state — initialise mode + controllers from the
    // session being edited, falling back to "none" / empty for new
    // sessions.
    _proxyHostCtrl = TextEditingController(text: s?.viaOverride?.host ?? '');
    _proxyPortCtrl = TextEditingController(
      text: s?.viaOverride != null ? '${s!.viaOverride!.port}' : '22',
    );
    _proxyUserCtrl = TextEditingController(text: s?.viaOverride?.user ?? '');
    if (s?.viaSessionId != null) {
      _proxyMode = _ProxyMode.saved;
      _proxyViaSessionId = s!.viaSessionId;
    } else if (s?.viaOverride != null) {
      _proxyMode = _ProxyMode.custom;
    }
    _recordEnabled = s?.extrasBool('record') ?? false;
    if (s != null) {
      _loadForwards(s.id);
    }
  }

  /// Hydrate the in-memory rule list from the store. Only called for
  /// edited sessions — new sessions never have rules until the user
  /// adds one in the Forwarding tab.
  Future<void> _loadForwards(String sessionId) async {
    final loaded = await loadPortForwards(sessionId);
    if (!mounted) return;
    setState(() => _forwards = loaded);
  }

  /// Look up the key label from the store for display. Pulls the
  /// metadata-only listing — only `label` is rendered, so the PEM
  /// bytes never need to materialise on the Dart heap for this
  /// resolve step.
  Future<void> _resolveKeyLabel() async {
    final store = ref.read(sshKeysProvider.notifier);
    final metadata = await store.loadAllMetadata();
    final entry = metadata[_selectedKeyId];
    if (entry != null && mounted) {
      setState(() => _selectedKeyLabel = entry.label);
    }
  }

  @override
  void dispose() {
    _disposing = true;
    // Detach the dirty-bit listeners explicitly before `wipeAndClear`
    // mutates the controller text — otherwise the listener would
    // fire `setState` on a tearing-down State and trip the
    // `_lifecycleState != defunct` framework assertion.
    if (_passwordListener != null) {
      _passwordCtrl.removeListener(_passwordListener!);
    }
    if (_keyDataListener != null) {
      _keyDataCtrl.removeListener(_keyDataListener!);
    }
    if (_passphraseListener != null) {
      _passphraseCtrl.removeListener(_passphraseListener!);
    }
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
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    super.dispose();
  }

  Session _buildSession() {
    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);
    final viaSessionId = _proxyMode == _ProxyMode.saved
        ? _proxyViaSessionId
        : null;
    final viaOverride = _proxyMode == _ProxyMode.custom
        ? ProxyJumpOverride(
            host: _proxyHostCtrl.text.trim(),
            port: int.tryParse(_proxyPortCtrl.text.trim()) ?? 22,
            user: _proxyUserCtrl.text.trim(),
          )
        : null;
    // Merge the record-toggle into extras. `null` clears the key so
    // a session that started as opt-in then went back to opt-out
    // does not leave a `false` entry behind cluttering the bag.
    final recordDelta = <String, Object?>{
      'record': _recordEnabled ? true : null,
    };
    Session built;
    if (_isEditing) {
      built = widget.session!.copyWith(
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
        viaSessionId: viaSessionId,
        viaOverride: viaOverride,
      );
    } else {
      built = Session(
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
        viaSessionId: viaSessionId,
        viaOverride: viaOverride,
      );
    }
    return built.withExtras(recordDelta);
  }

  bool _validateAuth() {
    final saved = widget.session?.auth;
    final hasPassword =
        _passwordCtrl.text.isNotEmpty ||
        (saved?.hasStoredPassword ?? false) ||
        (saved?.password.isNotEmpty ?? false);
    final hasKey =
        _hasStoreKey ||
        _keyPathCtrl.text.trim().isNotEmpty ||
        _keyDataCtrl.text.trim().isNotEmpty ||
        (saved?.hasStoredKeyData ?? false) ||
        (saved?.keyData.isNotEmpty ?? false);

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
    Navigator.of(context).pop(
      SaveResult(
        _buildSession(),
        connect: connect,
        forwards: _forwards,
        passwordDirty: _passwordDirty,
        keyDataDirty: _keyDataDirty,
        passphraseDirty: _passphraseDirty,
      ),
    );
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
                          Offstage(
                            offstage: _tabIndex != 3,
                            child: SessionForwardsTab(
                              rules: _forwards,
                              onChanged: (next) =>
                                  setState(() => _forwards = next),
                            ),
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
      // Four Expanded tabs — each one caps content at a quarter of the
      // bar width and truncates via ellipsis if the translation overflows.
      child: Row(
        children: [
          Expanded(child: _buildTab(0, Icons.dns, S.of(context).connection)),
          Expanded(child: _buildTab(1, Icons.shield, S.of(context).auth)),
          Expanded(child: _buildTab(2, Icons.folder, S.of(context).options)),
          Expanded(
            child: _buildTab(3, Icons.swap_horiz, S.of(context).portForwarding),
          ),
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

  /// Re-renders the dialog from a per-tab extension method.
  /// `State.setState` is `@protected` so extensions on
  /// `_SessionEditDialogState` cannot call it directly; this wrapper
  /// keeps the rebuild path inside the class while letting the
  /// connection / auth / options part files mutate the same fields.
  void rebuild(VoidCallback fn) => setState(fn);
}
