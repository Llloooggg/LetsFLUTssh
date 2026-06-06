part of 'session_edit_dialog.dart';

/// Result of the session edit dialog.
sealed class SessionDialogResult {}

/// User chose "Save" or "Save & Connect".
class SaveResult extends SessionDialogResult {
  final Session session;
  final bool connect;

  /// Port-forward rules entered in the port-forward rule editor. The caller
  /// is responsible for diffing against the persisted set and writing
  /// the delta — see `session_panel._handleDialogResult`. Empty when
  /// the dialog was for a quick-connect / new session that never
  /// opened the editor.
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
