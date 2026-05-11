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
import '../../src/rust/api/db.dart' as rust_db;
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

  /// WebDAV transport tuple — non-null when the user selected
  /// [SessionKind.webdav] in the kind picker. The caller upserts the
  /// `webdav_session_details` row and stages the password into
  /// SecretStore (only when `passwordDirty` is set + the typed
  /// password is non-empty so editing a label never clobbers a
  /// stored token). Null for SSH sessions.
  final WebDavSaveData? webdavData;

  /// S3 transport tuple — non-null when the user selected
  /// [SessionKind.s3] in the kind picker. The caller upserts the
  /// `s3_session_details` row and stages the secret access key
  /// into SecretStore (only when `passwordDirty` is set + the
  /// typed secret is non-empty so editing a label never clobbers
  /// a stored secret). Null for SSH / WebDAV sessions.
  final S3SaveData? s3Data;

  SaveResult(
    this.session, {
    this.connect = false,
    this.forwards = const [],
    this.passwordDirty = false,
    this.keyDataDirty = false,
    this.passphraseDirty = false,
    this.webdavData,
    this.s3Data,
  });
}

/// WebDAV transport tuple captured by the session edit dialog. Mirrors
/// the columns on `webdav_session_details` plus the dialog-local
/// password slot so the caller can stage the secret into SecretStore.
/// Password bytes never sit on the session model itself — they cross
/// the FRB boundary through `secretsPut` keyed by
/// `dbWebdavSessionDetailsSecretId(sessionId:)`.
class WebDavSaveData {
  final String baseUrl;
  final String username;

  /// One of `'basic'`, `'digest'`, `'bearer'`. The connect path parses
  /// this into the typed `lfs_core::webdav::AuthMethod`.
  final String authMethod;

  /// Optional SHA-256 self-signed certificate pin. Empty / null means
  /// the connect path falls back to the system trust store.
  final String? selfSignedFingerprint;

  /// Password / bearer token typed in the Auth tab. Always carried
  /// alongside `passwordDirty`; the caller only stages it into
  /// SecretStore when the dirty bit is set so untouched edits keep
  /// the previously stored secret intact.
  final String password;
  final bool passwordDirty;

  WebDavSaveData({
    required this.baseUrl,
    required this.username,
    required this.authMethod,
    required this.selfSignedFingerprint,
    required this.password,
    required this.passwordDirty,
  });
}

/// S3 transport tuple captured by the session edit dialog. Mirrors
/// the columns on `s3_session_details` plus the dialog-local secret
/// slot so the caller can stage the secret into SecretStore. Secret
/// bytes never sit on the session model — they cross the FRB
/// boundary through `secretsPut` keyed by
/// `dbS3SessionDetailsSecretId(sessionId:)`.
class S3SaveData {
  final String accessKeyId;
  final String region;
  final String endpoint;
  final bool pathStyle;
  final String defaultBucket;
  final String defaultPrefix;

  /// Secret access key typed in the Auth tab. Always carried
  /// alongside `passwordDirty`; the caller only stages it into
  /// SecretStore when the dirty bit is set so untouched edits keep
  /// the previously stored secret intact.
  final String secretAccessKey;
  final bool passwordDirty;

  S3SaveData({
    required this.accessKeyId,
    required this.region,
    required this.endpoint,
    required this.pathStyle,
    required this.defaultBucket,
    required this.defaultPrefix,
    required this.secretAccessKey,
    required this.passwordDirty,
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

  /// Selected transport. Set from `widget.session.kind` on edit;
  /// new sessions default to SSH. The kind picker lives at the top
  /// of the Connection tab; toggling to WebDAV swaps the host /
  /// port / proxy fields for the WebDAV-specific base URL / auth
  /// method / username / self-signed pin block.
  SessionKind _kind = SessionKind.ssh;

  /// WebDAV transport-config controllers. Hydrated from the
  /// `webdav_session_details` join row on edit (async — the dialog
  /// renders an inline loader until [_loadingWebDav] flips false) and
  /// left empty for fresh sessions or for an SSH→WebDAV flip without
  /// a saved row.
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _fingerprintCtrl;
  String _webdavAuthMethod = 'basic';
  bool _loadingWebDav = false;

  /// S3 transport-config controllers. Hydrated from the
  /// `s3_session_details` join row on edit (async — the dialog
  /// renders the same inline loader as the WebDAV path until
  /// [_loadingS3] flips false). Left empty for fresh sessions or
  /// for a non-S3→S3 flip without a saved row.
  late final TextEditingController _accessKeyIdCtrl;
  late final TextEditingController _regionCtrl;
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _defaultBucketCtrl;
  late final TextEditingController _defaultPrefixCtrl;
  bool _s3PathStyleEnabled = false;
  bool _loadingS3 = false;

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
    _kind = s?.kind ?? SessionKind.ssh;
    _baseUrlCtrl = TextEditingController();
    _fingerprintCtrl = TextEditingController();
    _accessKeyIdCtrl = TextEditingController();
    _regionCtrl = TextEditingController();
    _endpointCtrl = TextEditingController();
    _defaultBucketCtrl = TextEditingController();
    _defaultPrefixCtrl = TextEditingController();
    if (s != null) {
      _loadForwards(s.id);
      if (s.kind == SessionKind.webdav) {
        _loadingWebDav = true;
        _loadWebDavDetails(s.id);
      }
      if (s.kind == SessionKind.s3) {
        _loadingS3 = true;
        _loadS3Details(s.id);
      }
    }
  }

  /// Pull the S3 transport tuple from the join table and populate
  /// the dialog controllers. Runs async because the FRB DAO call is
  /// async-on-blocking-pool; the dialog renders the same inline
  /// loader the WebDAV path uses while in flight. A missing row is
  /// fine — the user can fill the fields and a fresh
  /// `s3_session_details` row is upserted on save.
  Future<void> _loadS3Details(String sessionId) async {
    try {
      final detail = await rust_db.dbS3SessionDetailsGet(sessionId: sessionId);
      if (!mounted) return;
      setState(() {
        if (detail != null) {
          _accessKeyIdCtrl.text = detail.accessKeyId;
          _regionCtrl.text = detail.region;
          _endpointCtrl.text = detail.endpoint;
          _defaultBucketCtrl.text = detail.defaultBucket;
          _defaultPrefixCtrl.text = detail.defaultPrefix;
          _s3PathStyleEnabled = detail.pathStyle;
        }
        _loadingS3 = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingS3 = false);
    }
  }

  /// Pull the WebDAV transport tuple from the join table and populate
  /// the dialog controllers. Runs async because the FRB DAO call is
  /// async-on-blocking-pool; the dialog renders a small loader while
  /// in flight so the user sees something. A missing row is fine —
  /// the user can fill the fields and a fresh `webdav_session_details`
  /// row is upserted on save.
  Future<void> _loadWebDavDetails(String sessionId) async {
    try {
      final detail = await rust_db.dbWebdavSessionDetailsGet(
        sessionId: sessionId,
      );
      if (!mounted) return;
      setState(() {
        if (detail != null) {
          _baseUrlCtrl.text = detail.baseUrl;
          _userCtrl.text = detail.username;
          _webdavAuthMethod = detail.authMethod;
          _fingerprintCtrl.text = detail.selfSignedFingerprint ?? '';
        }
        _loadingWebDav = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWebDav = false);
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
    _baseUrlCtrl.dispose();
    _fingerprintCtrl.dispose();
    _accessKeyIdCtrl.dispose();
    _regionCtrl.dispose();
    _endpointCtrl.dispose();
    _defaultBucketCtrl.dispose();
    _defaultPrefixCtrl.dispose();
    super.dispose();
  }

  Session _buildSession() {
    final keyPath = _keyPathCtrl.text.trim().replaceFirst('~', homeDirectory);
    // ProxyJump only applies to SSH transports — flipping the kind
    // to WebDAV / S3 drops any leftover proxy state so a session
    // that started as SSH-via-bastion does not carry the override
    // after conversion.
    final viaSessionId =
        (_kind == SessionKind.ssh && _proxyMode == _ProxyMode.saved)
        ? _proxyViaSessionId
        : null;
    final viaOverride =
        (_kind == SessionKind.ssh && _proxyMode == _ProxyMode.custom)
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
    final ServerAddress server;
    if (_kind == SessionKind.webdav) {
      server = _serverFromBaseUrl();
    } else if (_kind == SessionKind.s3) {
      server = _serverFromS3Endpoint();
    } else {
      server = ServerAddress(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 22,
        user: _userCtrl.text.trim(),
      );
    }
    Session built;
    if (_isEditing) {
      built = widget.session!.copyWith(
        label: _labelCtrl.text.trim(),
        folder: _folderCtrl.text.trim(),
        kind: _kind,
        server: server,
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
        kind: _kind,
        server: server,
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

  /// Derive the SSH-shaped [ServerAddress] for a WebDAV session.
  /// The host/port columns on `sessions` stay populated so legacy
  /// SQL filters keep working; the live transport routes off
  /// `kind = 'webdav'` and reads the full URL from
  /// `webdav_session_details`. `Uri.parse` accepts malformed input —
  /// the validator catches that ahead of save, this helper just
  /// degrades gracefully when called from a benign code path.
  ServerAddress _serverFromBaseUrl() {
    final raw = _baseUrlCtrl.text.trim();
    Uri? parsed;
    try {
      parsed = Uri.parse(raw);
    } on FormatException {
      parsed = null;
    }
    final host = parsed?.host ?? '';
    final hasPort = (parsed?.hasPort ?? false);
    final scheme = parsed?.scheme.toLowerCase() ?? '';
    final int port;
    if (hasPort) {
      port = parsed!.port;
    } else if (scheme == 'https') {
      port = 443;
    } else if (scheme == 'http') {
      port = 80;
    } else {
      port = 0;
    }
    return ServerAddress(host: host, port: port, user: _userCtrl.text.trim());
  }

  /// Derive the SSH-shaped [ServerAddress] for an S3 session.
  /// `host` carries the endpoint host (or `s3.<region>.amazonaws.com`
  /// when no explicit endpoint is set) and `port` carries the
  /// scheme-default port. The live transport routes off
  /// `kind = 's3'` and reads the full tuple from
  /// `s3_session_details`; this projection keeps legacy SQL
  /// filters working.
  ServerAddress _serverFromS3Endpoint() {
    final raw = _endpointCtrl.text.trim();
    String host = '';
    int port = 443;
    if (raw.isNotEmpty) {
      Uri? parsed;
      try {
        parsed = Uri.parse(raw);
      } on FormatException {
        parsed = null;
      }
      host = parsed?.host ?? '';
      if (parsed?.hasPort ?? false) {
        port = parsed!.port;
      } else if (parsed?.scheme.toLowerCase() == 'http') {
        port = 80;
      }
    } else {
      final region = _regionCtrl.text.trim().isEmpty
          ? 'us-east-1'
          : _regionCtrl.text.trim();
      host = 's3.$region.amazonaws.com';
    }
    return ServerAddress(
      host: host,
      port: port,
      user: _accessKeyIdCtrl.text.trim(),
    );
  }

  bool _validateAuth() {
    if (_kind == SessionKind.webdav) return _validateWebDavAuth();
    if (_kind == SessionKind.s3) return _validateS3Auth();
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

  /// S3-specific auth predicate. The dialog requires an access key
  /// id (visible on the Connection tab) plus a secret access key
  /// (Auth tab, stored or freshly typed). The connect path
  /// short-circuits without the secret since SigV4 cannot be
  /// signed without it.
  bool _validateS3Auth() {
    final hasAccessKey = _accessKeyIdCtrl.text.trim().isNotEmpty;
    if (!hasAccessKey) {
      setState(() {
        _authError = S.of(context).providePasswordOrKey;
        _tabIndex = 0;
      });
      return false;
    }
    final hasSecret =
        _passwordCtrl.text.isNotEmpty ||
        (widget.session?.auth.hasStoredPassword ?? false);
    if (!hasSecret) {
      setState(() {
        _authError = S.of(context).providePasswordOrKey;
        _tabIndex = 1;
      });
      return false;
    }
    setState(() => _authError = null);
    return true;
  }

  /// WebDAV-specific auth predicate. Basic / digest need a username +
  /// a password (or one already in SecretStore); bearer treats the
  /// password slot as the token. The base-URL check sits in
  /// [_tabWithFirstError] so a malformed URL routes the user to the
  /// Connection tab; this method only handles the credential side.
  bool _validateWebDavAuth() {
    final hasPassword =
        _passwordCtrl.text.isNotEmpty ||
        (widget.session?.auth.hasStoredPassword ?? false);
    if (!hasPassword) {
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
    if (_kind == SessionKind.webdav) {
      // Connection tab (0): base URL, username
      if (_webDavBaseUrlValidator(_baseUrlCtrl.text) != null) return 0;
      if (_requiredValidator(_userCtrl.text) != null) return 0;
      // Auth tab (1): credentials
      return 1;
    }
    if (_kind == SessionKind.s3) {
      // Connection tab (0): access key id is the only field that
      // gates connect. Region + endpoint + default bucket are all
      // optional from the validator's perspective — empty values
      // either fall back (`us-east-1`, AWS default endpoint) or
      // force the `s3://bucket/key` shorthand at path-parse time.
      if (_requiredValidator(_accessKeyIdCtrl.text) != null) return 0;
      return 1;
    }
    // Connection tab (0): host, port, username
    if (_requiredValidator(_hostCtrl.text) != null) return 0;
    final port = int.tryParse(_portCtrl.text);
    if (port == null || port < 1 || port > 65535) return 0;
    if (_requiredValidator(_userCtrl.text) != null) return 0;
    // Auth tab (1): credentials
    return 1;
  }

  /// Validator for the WebDAV base-URL field. Required + must parse
  /// as an `http://` / `https://` absolute URL. Returned message is
  /// rendered inline under the field by the form framework.
  String? _webDavBaseUrlValidator(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return S.of(context).errWebDavBaseUrlRequired;
    Uri? parsed;
    try {
      parsed = Uri.parse(value);
    } on FormatException {
      parsed = null;
    }
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return S.of(context).errWebDavBaseUrlInvalid;
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return S.of(context).errWebDavBaseUrlInvalid;
    }
    return null;
  }

  void _save({bool connect = false}) {
    final formOk = _formKey.currentState!.validate();
    if (!formOk) {
      setState(() => _tabIndex = _tabWithFirstError());
      return;
    }
    if (!_validateAuth()) return;
    final session = _buildSession();
    final webdav = _kind == SessionKind.webdav
        ? WebDavSaveData(
            baseUrl: _baseUrlCtrl.text.trim(),
            username: _userCtrl.text.trim(),
            authMethod: _webdavAuthMethod,
            selfSignedFingerprint: _fingerprintCtrl.text.trim().isEmpty
                ? null
                : _fingerprintCtrl.text.trim(),
            password: _passwordCtrl.text,
            passwordDirty: _passwordDirty,
          )
        : null;
    final s3 = _kind == SessionKind.s3
        ? S3SaveData(
            accessKeyId: _accessKeyIdCtrl.text.trim(),
            region: _regionCtrl.text.trim(),
            endpoint: _endpointCtrl.text.trim(),
            pathStyle: _s3PathStyleEnabled,
            defaultBucket: _defaultBucketCtrl.text.trim(),
            defaultPrefix: _defaultPrefixCtrl.text.trim(),
            secretAccessKey: _passwordCtrl.text,
            passwordDirty: _passwordDirty,
          )
        : null;
    Navigator.of(context).pop(
      SaveResult(
        session,
        connect: connect,
        forwards: _forwards,
        passwordDirty: _passwordDirty,
        keyDataDirty: _keyDataDirty,
        passphraseDirty: _passphraseDirty,
        webdavData: webdav,
        s3Data: s3,
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
                      padding: const EdgeInsets.all(AppSpacing.lg),
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
            const SizedBox(width: AppSpacing.xxs),
            // Flexible + ellipsis so long translations truncate
            // inside the tab rather than breaking the Row.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.interFamily,
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
