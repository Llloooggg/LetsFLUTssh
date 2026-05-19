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
import '../../src/rust/api/app.dart' as rust_app;
import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/s3.dart' as rust_s3;
import '../../src/rust/api/sessions.dart' as rust_sessions;
import '../../src/rust/api/webdav.dart' as rust_webdav;
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_picker_chip.dart';
import '../../widgets/dropdown_select_button.dart';
import '../../widgets/enclave_ssh_dialog.dart';
import '../../widgets/hardware_key_badge.dart';
import '../../widgets/hello_ssh_dialog.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/keystore_ssh_dialog.dart';
import '../../widgets/pkcs11_import_dialog.dart';
import '../../widgets/styled_form_field.dart';
import '../../widgets/tag_color.dart';
import '../../widgets/toast.dart';
import '../../widgets/tpm_ssh_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart';
import '../../utils/secret_controller.dart';
import '../tags/tag_manager_dialog.dart';
import 'session_forwards_tab.dart';
import 'session_port_validator.dart';

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

  /// Tag ids the user has marked assigned in the More options tag
  /// picker. The caller diffs this against the current
  /// `session_tags` rows and links / unlinks the delta after the
  /// session row commits. For new sessions the join row didn't
  /// exist yet — same diff path applies (every selected id becomes
  /// a fresh link). `null` (legacy) means "leave assignments
  /// untouched"; an empty set means "user removed every tag".
  final Set<String>? pendingTagIds;

  SaveResult(
    this.session, {
    this.connect = false,
    this.forwards = const [],
    this.passwordDirty = false,
    this.keyDataDirty = false,
    this.passphraseDirty = false,
    this.webdavData,
    this.s3Data,
    this.pendingTagIds,
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

  /// Optional trusted server certificate (PEM — one or more
  /// `-----BEGIN CERTIFICATE-----` blocks). Added as an additional
  /// root CA in the connect path so self-signed endpoints validate
  /// without OS-trust-store changes. Null / empty falls back to the
  /// system trust store.
  final String? trustedCertPem;

  /// Last-resort escape hatch — flip every certificate / hostname
  /// check off (`reqwest::ClientBuilder::danger_accept_invalid_certs`
  /// + `danger_accept_invalid_hostnames`). The dialog renders an
  /// explicit MITM warning before letting the user enable it.
  final bool insecureSkipVerify;

  /// Password / bearer token typed in the Auth section. Always
  /// carried alongside `passwordDirty`; the caller only stages it
  /// into SecretStore when the dirty bit is set so untouched edits
  /// keep the previously stored secret intact.
  final String password;
  final bool passwordDirty;

  WebDavSaveData({
    required this.baseUrl,
    required this.username,
    required this.authMethod,
    required this.trustedCertPem,
    required this.insecureSkipVerify,
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

  /// Optional trusted server certificate (PEM — one or more
  /// `-----BEGIN CERTIFICATE-----` blocks). Mirrors the WebDAV
  /// field; lets users connect to a self-signed S3-compatible
  /// endpoint (MinIO on a private network, internal Ceph) without
  /// OS-trust-store changes.
  final String? trustedCertPem;

  /// Last-resort skip-all-cert-verification toggle. The dialog
  /// renders an explicit MITM warning before letting the user
  /// enable it.
  final bool insecureSkipVerify;

  /// Secret access key typed in the Auth section. Always carried
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
    required this.trustedCertPem,
    required this.insecureSkipVerify,
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

  /// Collapsible state for the Advanced section at the bottom of
  /// the single-form layout. Collapsed by default so first-time
  /// session creation reads as a compact 6-8-field form; the user
  /// opens Advanced only when they need tags, port forwarding (SSH)
  /// or the record-session toggle (SSH).
  bool _advancedExpanded = false;

  /// Selected key from the central key store.
  String _selectedKeyId = '';
  String _selectedKeyLabel = '';

  /// `true` when the user picked "Use system ssh-agent" on the Auth
  /// tab. Defers every credential lookup to the running agent (Unix
  /// `$SSH_AUTH_SOCK`, Windows OpenSSH named pipe / Pageant) so the
  /// dialog needs no password / key fields. Hydrated from
  /// `widget.session?.auth.authType == AuthType.agent` on edit;
  /// fresh sessions default to `false`. The mobile build keeps the
  /// toggle visible but disabled — the agent endpoint is desktop-only.
  bool _useAgent = false;

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

  /// In-memory tag-id selection backing the More options tag
  /// picker. Edit-mode dialogs hydrate from `sessionTagsProvider`
  /// inside [_loadInitialTags]; new-session dialogs start empty.
  /// The save path returns this set verbatim in [SaveResult] so the
  /// caller can diff against the persisted set and link / unlink
  /// the delta — same buffering pattern the port-forward rule
  /// editor uses.
  Set<String> _pendingTagIds = <String>{};

  /// `true` once the edit-mode hydration has finished resolving the
  /// session's current tag links into [_pendingTagIds]. Gates the
  /// picker render so a fresh `setState` after the async load does
  /// not race a user tap against the empty initial state.
  bool _pendingTagsLoaded = false;

  /// `true` after the user toggles any chip in the inline tag
  /// picker. Until then the save path emits `pendingTagIds = null`
  /// so the caller leaves the persisted `session_tags` rows alone
  /// — same "don't write what the user didn't touch" discipline the
  /// password / key / passphrase dirty bits use.
  bool _pendingTagsTouched = false;

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

  /// Shared trusted-cert PEM textarea — drives both WebDAV and S3
  /// transports. The save path reads the value into the relevant
  /// `*SaveData` only for the active kind; flipping the kind picker
  /// keeps the typed PEM in memory (per-kind controllers would lose
  /// it on flip, which felt punishing on a paste).
  late final TextEditingController _trustedCertPemCtrl;

  /// Shared "trust any certificate" toggle — drives both WebDAV
  /// and S3 transports. Hidden behind an explicit MITM warning the
  /// user has to acknowledge before the save commits.
  bool _insecureSkipVerify = false;
  String _webdavAuthMethod = 'basic';
  bool _loadingWebDav = false;

  /// Wire values the WebDAV auth-method chip-group surfaces. Used to
  /// gate the hydration step in [_loadWebDavDetails] so a legacy row
  /// with an empty or unrecognised `auth_method` falls back to the
  /// constructor default (`basic`) instead of leaving every chip
  /// unselected.
  static const _webDavAuthMethodWireValues = {'basic', 'digest', 'bearer'};

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

  /// Whether SecretStore already holds a staged WebDAV / S3 password
  /// for the session being edited. Set by `_loadWebDavDetails` /
  /// `_loadS3Details` via a `secretsHas` probe — the `hasStoredX`
  /// flags on `SessionAuth` only cover the SSH credential triplet
  /// (which lives on `ssh_session_details` for the v16 schema split),
  /// so non-SSH kinds need a parallel signal to render the
  /// "[Saved] type to change" hint in the credential field.
  bool _nonSshSecretStaged = false;

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
    // ssh-agent selection wins over every other slot — the connect
    // path defers to the agent and ignores the (unset) key / password
    // columns, so the persisted authType has to match what the
    // dispatch arm will read on the next dial.
    if (_useAgent) return AuthType.agent;
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
    _useAgent = s?.auth.authType == AuthType.agent;
    // ProxyJump editor state — initialise mode + controllers from the
    // session being edited, falling back to "none" / empty for new
    // sessions.
    _proxyHostCtrl = TextEditingController(text: s?.viaOverride?.host ?? '');
    _proxyPortCtrl = TextEditingController(
      text: s?.viaOverride != null ? '${s!.viaOverride!.port}' : '22',
    );
    _proxyUserCtrl = TextEditingController(text: s?.viaOverride?.user ?? '');
    if (s?.viaSessionId != null) {
      // Re-edit cycle: the stored proxy target may have been deleted
      // between dialog opens. Resolve it against the live session list
      // before pinning `_proxyMode.saved` — when the target is gone,
      // fall to `none` so the dropdown does not render an empty
      // "saved" selection with no value beside it.
      final liveSessions = ref.read(sessionProvider);
      final stillExists = liveSessions.any((row) => row.id == s!.viaSessionId);
      if (stillExists) {
        _proxyMode = _ProxyMode.saved;
        _proxyViaSessionId = s!.viaSessionId;
      } else {
        _proxyMode = _ProxyMode.none;
      }
    } else if (s?.viaOverride != null) {
      _proxyMode = _ProxyMode.custom;
    }
    _recordEnabled = s?.extrasBool('record') ?? false;
    _kind = s?.kind ?? SessionKind.ssh;
    _baseUrlCtrl = TextEditingController();
    _trustedCertPemCtrl = TextEditingController();
    _accessKeyIdCtrl = TextEditingController();
    _regionCtrl = TextEditingController();
    _endpointCtrl = TextEditingController();
    _defaultBucketCtrl = TextEditingController();
    _defaultPrefixCtrl = TextEditingController();
    if (s != null) {
      _loadForwards(s.id);
      _loadInitialTags(s.id);
      if (s.kind == SessionKind.webdav) {
        _loadingWebDav = true;
        _loadWebDavDetails(s.id);
      }
      if (s.kind == SessionKind.s3) {
        _loadingS3 = true;
        _loadS3Details(s.id);
      }
    } else {
      // New session — no DB row to hydrate from, the picker can
      // render immediately against an empty selection.
      _pendingTagsLoaded = true;
    }
  }

  /// Hydrate the in-memory tag selection from the persisted
  /// `session_tags` rows for an edited session. Routes through the
  /// `sessionTagsProvider` family so dialog widget tests can stub
  /// the result without bootstrapping a real DB; the live provider
  /// just forwards to `rust_db.dbTagsListForSession`. The picker
  /// stays in "loading" state until the future resolves so a fresh
  /// setState after the async load does not race a user tap against
  /// the empty initial state.
  Future<void> _loadInitialTags(String sessionId) async {
    try {
      final tags = await ref.read(sessionTagsProvider(sessionId).future);
      if (!mounted) return;
      setState(() {
        _pendingTagIds = {for (final t in tags) t.id};
        _pendingTagsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingTagsLoaded = true);
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
      // Probe SecretStore for an already-staged secret access key so
      // the dialog can show the "[Saved] type to change" hint on the
      // credential field. The SSH-side `auth.hasStoredPassword` flag
      // only covers `ssh_session_details` rows — non-SSH secrets live
      // under `dbS3SessionDetailsSecretId` and never trip that flag.
      final hasSecret = rust_app.secretsHas(
        id: rust_db.dbS3SessionDetailsSecretId(sessionId: sessionId),
      );
      if (!mounted) return;
      setState(() {
        if (detail != null) {
          _accessKeyIdCtrl.text = detail.accessKeyId;
          _regionCtrl.text = detail.region;
          _endpointCtrl.text = detail.endpoint;
          _defaultBucketCtrl.text = detail.defaultBucket;
          _defaultPrefixCtrl.text = detail.defaultPrefix;
          _s3PathStyleEnabled = detail.pathStyle;
          _trustedCertPemCtrl.text = detail.trustedCertPem ?? '';
          _insecureSkipVerify = detail.insecureSkipVerify;
        }
        _nonSshSecretStaged = hasSecret;
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
      // Probe SecretStore for an already-staged password / bearer
      // token so the credential field on the Auth section can render
      // the "[Saved] type to change" hint. The SSH-side
      // `auth.hasStoredPassword` flag only covers `ssh_session_details`
      // rows — WebDAV secrets live under
      // `dbWebdavSessionDetailsSecretId` and never trip that flag.
      final hasSecret = rust_app.secretsHas(
        id: rust_db.dbWebdavSessionDetailsSecretId(sessionId: sessionId),
      );
      if (!mounted) return;
      setState(() {
        if (detail != null) {
          _baseUrlCtrl.text = detail.baseUrl;
          _userCtrl.text = detail.username;
          // Legacy rows may have an empty / unrecognised authMethod —
          // keep the constructor default (`basic`) in that case so
          // none of the chips render unselected. Only overwrite when
          // the stored value is one of the wire variants the editor
          // exposes (`basic` / `digest` / `bearer`).
          if (_webDavAuthMethodWireValues.contains(detail.authMethod)) {
            _webdavAuthMethod = detail.authMethod;
          }
          _trustedCertPemCtrl.text = detail.trustedCertPem ?? '';
          _insecureSkipVerify = detail.insecureSkipVerify;
        }
        _nonSshSecretStaged = hasSecret;
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
    final store = ref.read(sshKeysMutatorProvider);
    final metadata = await store.loadAllMetadata();
    // The dialog can close while the metadata fetch is in flight (user
    // hits Cancel, navigates away). Bail before `setState` if the State
    // already disposed.
    if (!mounted) return;
    final entry = metadata[_selectedKeyId];
    if (entry == null) return;
    setState(() => _selectedKeyLabel = entry.label);
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
    _trustedCertPemCtrl.dispose();
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
    // ssh-agent path owns the credential — the agent dispatches every
    // signature, so the per-row key / password slots stay empty on
    // save. Without this the `_derivedAuthType == agent` flip would
    // leak a stale `_selectedKeyId` / typed password into the row,
    // hiding behind the agent flag without anyone seeing it.
    final String resolvedKeyId = _useAgent ? '' : _selectedKeyId;
    final String resolvedPassword = _useAgent ? '' : _passwordCtrl.text;
    final String resolvedKeyPath = _useAgent ? '' : keyPath;
    final String resolvedKeyData = _useAgent ? '' : _keyDataCtrl.text.trim();
    final String resolvedPassphrase = _useAgent ? '' : _passphraseCtrl.text;
    final resolvedLabel = _resolveLabel(server);
    Session built;
    if (_isEditing) {
      built = widget.session!.copyWith(
        label: resolvedLabel,
        folder: _folderCtrl.text.trim(),
        kind: _kind,
        server: server,
        auth: widget.session!.auth.copyWith(
          authType: _derivedAuthType,
          keyId: resolvedKeyId,
          password: resolvedPassword,
          keyPath: resolvedKeyPath,
          keyData: resolvedKeyData,
          passphrase: resolvedPassphrase,
        ),
        viaSessionId: viaSessionId,
        viaOverride: viaOverride,
      );
    } else {
      built = Session(
        label: resolvedLabel,
        folder: _folderCtrl.text.trim(),
        kind: _kind,
        server: server,
        auth: SessionAuth(
          authType: _derivedAuthType,
          keyId: resolvedKeyId,
          password: resolvedPassword,
          keyPath: resolvedKeyPath,
          keyData: resolvedKeyData,
          passphrase: resolvedPassphrase,
        ),
        viaSessionId: viaSessionId,
        viaOverride: viaOverride,
      );
    }
    return built.withExtras(recordDelta);
  }

  /// Resolve the label to persist. Honours an explicit typed value
  /// verbatim; falls back to the kind-specific anchor when the user
  /// left the field empty (the dialog's inline placeholder advertised
  /// the auto-derive source). Default-bucket / URL host / SSH host
  /// each surface as a human-readable identifier the session tree
  /// can render without going through the kind-aware
  /// `Session.displayName` derivation chain on every render.
  String _resolveLabel(ServerAddress server) {
    final typed = _labelCtrl.text.trim();
    if (typed.isNotEmpty) return typed;
    if (_kind == SessionKind.s3) {
      final bucket = _defaultBucketCtrl.text.trim();
      if (bucket.isNotEmpty) return bucket;
    }
    if (_kind == SessionKind.webdav) {
      final host = server.host.trim();
      if (host.isNotEmpty) return host;
    }
    return server.host.trim();
  }

  /// Derive the SSH-shaped [ServerAddress] for a WebDAV session.
  /// Host/port come from the Rust-side
  /// `webdav::server_address_from_base_url`; user is the Dart-side
  /// form-draft credential. The host/port columns on `sessions`
  /// stay populated so legacy SQL filters keep working; the live
  /// transport routes off `kind = 'webdav'` and reads the full URL
  /// from `webdav_session_details`.
  ServerAddress _serverFromBaseUrl() {
    final fields = rust_webdav.webdavServerAddressFromBaseUrl(
      baseUrl: _baseUrlCtrl.text,
    );
    return ServerAddress(
      host: fields.host,
      port: fields.port,
      user: _userCtrl.text.trim(),
    );
  }

  /// Derive the SSH-shaped [ServerAddress] for an S3 session.
  /// Host/port come from the Rust-side
  /// `s3::server_address_from_s3_endpoint` (canonical AWS endpoint
  /// when the user did not supply an explicit `endpoint`); the
  /// live transport reads the full tuple from `s3_session_details`.
  ServerAddress _serverFromS3Endpoint() {
    final fields = rust_s3.s3ServerAddressFromEndpoint(
      endpoint: _endpointCtrl.text,
      region: _regionCtrl.text,
    );
    return ServerAddress(
      host: fields.host,
      port: fields.port,
      user: _accessKeyIdCtrl.text.trim(),
    );
  }

  bool _validateAuth() {
    if (_kind == SessionKind.webdav) return _validateWebDavAuth();
    if (_kind == SessionKind.s3) return _validateS3Auth();
    // ssh-agent path needs no password / key — the running agent
    // owns the credential, so the predicate short-circuits.
    if (_useAgent) {
      setState(() => _authError = null);
      return true;
    }
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
      setState(() => _authError = S.of(context).providePasswordOrKey);
      return false;
    }
    setState(() => _authError = null);
    return true;
  }

  /// S3-specific auth predicate. The dialog requires both halves
  /// of the SigV4 credential pair: access key id (top of form on
  /// the Connection section) and secret access key (Authentication
  /// section, stored or freshly typed). The connect path short-
  /// circuits without the secret since SigV4 cannot be signed
  /// without it.
  bool _validateS3Auth() {
    final hasAccessKey = _accessKeyIdCtrl.text.trim().isNotEmpty;
    if (!hasAccessKey) {
      setState(() => _authError = S.of(context).providePasswordOrKey);
      return false;
    }
    final hasSecret = _passwordCtrl.text.isNotEmpty || _nonSshSecretStaged;
    if (!hasSecret) {
      setState(() => _authError = S.of(context).providePasswordOrKey);
      return false;
    }
    setState(() => _authError = null);
    return true;
  }

  /// WebDAV-specific auth predicate. Basic / digest need a username
  /// + a password (or one already in SecretStore); bearer treats the
  /// password slot as the token. The base-URL `_webDavBaseUrlValidator`
  /// fires inline through the `Form.validate` pipeline; this method
  /// only handles the credential side.
  bool _validateWebDavAuth() {
    final hasPassword = _passwordCtrl.text.isNotEmpty || _nonSshSecretStaged;
    if (!hasPassword) {
      setState(() => _authError = S.of(context).providePasswordOrKey);
      return false;
    }
    setState(() => _authError = null);
    return true;
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
      // Single-form layout — every field is on one scrollable
      // page, so the inline `errorText` already paints the failing
      // field red and the user can scroll to it. The Toast is the
      // global heads-up that fires regardless of which scroll
      // position they pressed Save from.
      Toast.show(
        context,
        message: S.of(context).errFillRequiredFields,
        level: ToastLevel.warning,
      );
      return;
    }
    if (!_validateAuth()) {
      // `_validateAuth` already sets `_authError`, rendered as a
      // red banner above the Authentication section. Surface the
      // same global Toast so the rejection is visible regardless
      // of where the user scrolled.
      Toast.show(
        context,
        message: S.of(context).errFillRequiredFields,
        level: ToastLevel.warning,
      );
      return;
    }
    final session = _buildSession();
    final trustedPem = _trustedCertPemCtrl.text.trim().isEmpty
        ? null
        : _trustedCertPemCtrl.text.trim();
    final webdav = _kind == SessionKind.webdav
        ? WebDavSaveData(
            baseUrl: _baseUrlCtrl.text.trim(),
            username: _userCtrl.text.trim(),
            authMethod: _webdavAuthMethod,
            trustedCertPem: trustedPem,
            insecureSkipVerify: _insecureSkipVerify,
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
            trustedCertPem: trustedPem,
            insecureSkipVerify: _insecureSkipVerify,
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
        // Only carry the picker selection forward when the user
        // actually interacted with it — leaves untouched sessions
        // (the overwhelmingly common case) free of an extra
        // `dbTagsListForSession` round-trip on save and preserves
        // the existing tag rows for edits that only touched non-tag
        // fields. Matches the password / key / passphrase
        // dirty-bit discipline elsewhere in this dialog.
        pendingTagIds: _pendingTagsTouched ? _pendingTagIds : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
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
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildIdentityBlock(),
                          const SizedBox(height: AppSpacing.xl),
                          _SectionHeader(label: l10n.connection),
                          const SizedBox(height: AppSpacing.sm),
                          _buildConnectionBlock(),
                          const SizedBox(height: AppSpacing.xl),
                          _SectionHeader(label: l10n.sectionAuthentication),
                          const SizedBox(height: AppSpacing.sm),
                          _buildAuthBlock(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildAdvancedExpander(l10n),
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

  // ── Advanced collapsible expander ──

  /// Header row + animated body for the Advanced section. Collapsed
  /// by default — the user only opens this when they need a niche
  /// knob (tags / port forwarding / record-session toggle). Header
  /// is a tap target; chevron flips on expand. The body is wrapped
  /// in `AnimatedSize` so the form height transitions smoothly
  /// without a sudden layout jump.
  Widget _buildAdvancedExpander(S l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        HoverRegion(
          onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
          builder: (hovered) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: hovered ? AppTheme.hover : Colors.transparent,
              borderRadius: AppTheme.radiusSm,
            ),
            child: Row(
              children: [
                Icon(
                  _advancedExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: AppTheme.fgFaint,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.moreOptions.toUpperCase(),
                  style: AppFonts.inter(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgFaint,
                    fontWeight: FontWeight.w600,
                  ).copyWith(letterSpacing: 0.8),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.topCenter,
          child: _advancedExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _buildAdvancedBlock(),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Footer ──

  /// Three buttons stacked full-width: primary "Save & Connect" on top,
  /// secondary "Save" below it, plain "Cancel" at the bottom. The
  /// connect-after-save path is the common case so it owns the top
  /// slot; rename-only / host-tweak edits land on Save without going
  /// through a popup. Cancel reads as the lightweight escape — no
  /// accent, no fill.
  ///
  /// The previous compact `Save & Connect ▾` split-button hid the
  /// "Save only" action behind a chevron popup; user feedback was
  /// that the popup made the save-without-connect path feel demoted
  /// for what is a routine intent.
  Widget _buildFooter() {
    final l10n = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: AppTheme.borderTop),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: AppButton.primary(
              label: l10n.saveAndConnect,
              onTap: () => _save(connect: true),
              fullWidth: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: AppButton.secondary(
              label: l10n.save,
              onTap: _save,
              fullWidth: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: AppButton.cancel(
              onTap: () => Navigator.of(context).pop(),
              fullWidth: true,
            ),
          ),
        ],
      ),
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

  /// Flip the active session kind. The single-form layout reshapes
  /// the Connection / Authentication sections in place — no tabs
  /// to hide or re-focus.
  void _switchKind(SessionKind next) {
    setState(() => _kind = next);
  }
}

/// Section header for the single-form dialog. Uppercase + faint
/// tint matches the visual weight of `FieldLabel`, so a section
/// reads as a heavier divider than a per-field label without
/// fighting the form's primary input rhythm. A thin top border
/// above the label seats the section visually distinct from the
/// preceding block without taking a full divider's worth of
/// vertical space.
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: AppTheme.borderTop),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        label.toUpperCase(),
        style: AppFonts.inter(
          fontSize: AppFonts.xs,
          color: AppTheme.fgFaint,
          fontWeight: FontWeight.w600,
        ).copyWith(letterSpacing: 0.8),
      ),
    );
  }
}
