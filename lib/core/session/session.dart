import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../utils/platform.dart';
import '../ssh/ssh_config.dart';

/// Authentication type for a session.
enum AuthType { password, key, keyWithPassword }

/// One-off ProxyJump override — used when the user wants to bounce
/// through a host that is **not** a saved session. All three fields
/// are required as a unit; the loader treats a partial override as
/// absent.
///
/// Saved-session bastions take precedence: when [Session.viaSessionId]
/// is non-null, this override is ignored. Document this so the
/// session-edit dialog can surface a warning when the user fills both
/// at once.
class ProxyJumpOverride {
  final String host;
  final int port;
  final String user;

  const ProxyJumpOverride({
    required this.host,
    this.port = 22,
    required this.user,
  });

  Map<String, dynamic> toJson() => {'host': host, 'port': port, 'user': user};

  factory ProxyJumpOverride.fromJson(Map<String, dynamic> json) =>
      ProxyJumpOverride(
        host: json['host'] as String,
        port: json['port'] as int? ?? 22,
        user: json['user'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyJumpOverride &&
          host == other.host &&
          port == other.port &&
          user == other.user;

  @override
  int get hashCode => Object.hash(host, port, user);
}

/// Session authentication — extends [SshAuth] with UI-facing [authType].
class SessionAuth extends SshAuth {
  final AuthType authType;

  /// Reference to a key in the central key store. Empty = not set.
  final String keyId;

  /// Credentials exist in persistent storage even when the in-memory
  /// [password] / [keyData] / [passphrase] fields are empty. Set by the
  /// DB loader when the cache is populated without decrypted secrets
  /// (so plaintext secrets don't sit on the Dart heap) — the list UI
  /// still needs to know whether a session has credentials to decide
  /// whether to flag it as incomplete.
  final bool hasStoredSecret;

  const SessionAuth({
    this.authType = AuthType.password,
    this.keyId = '',
    this.hasStoredSecret = false,
    super.password,
    super.keyPath,
    super.keyData,
    super.passphrase,
  });

  @override
  SessionAuth copyWith({
    AuthType? authType,
    String? keyId,
    bool? hasStoredSecret,
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
  }) => SessionAuth(
    authType: authType ?? this.authType,
    keyId: keyId ?? this.keyId,
    hasStoredSecret: hasStoredSecret ?? this.hasStoredSecret,
    password: password ?? this.password,
    keyPath: keyPath ?? this.keyPath,
    keyData: keyData ?? this.keyData,
    passphrase: passphrase ?? this.passphrase,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionAuth &&
          authType == other.authType &&
          keyId == other.keyId &&
          hasStoredSecret == other.hasStoredSecret &&
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          passphrase == other.passphrase;

  @override
  int get hashCode => Object.hash(
    authType,
    keyId,
    hasStoredSecret,
    password,
    keyPath,
    keyData,
    passphrase,
  );
}

/// SSH session model — stored as JSON, credentials in encrypted storage.
class Session {
  final String id;
  final String label;
  final String folder; // path like "Production/Web"
  final ServerAddress server;
  final SessionAuth auth;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Free-form key-value bag persisted into `Sessions.extras` as JSON.
  ///
  /// Use [extrasBool] / [extrasStr] / [extrasInt] for typed reads and
  /// [withExtras] to produce a copy with a delta merged in. Anything
  /// load-bearing (auth, port forwards, proxy jump) gets its own
  /// columns; this is the escape hatch for feature flags that don't
  /// justify a migration on their own (recording toggle, layout
  /// hints, etc.).
  final Map<String, Object?> extras;

  /// ProxyJump bastion — id of another saved session whose SSH client
  /// opens a `forwardLocal` channel that this session uses as its
  /// transport. Null = direct connect.
  ///
  /// Takes precedence over [viaOverride]. Set together they imply
  /// the user is migrating away from a one-off override; the loader
  /// honours [viaSessionId] and ignores the override.
  final String? viaSessionId;

  /// One-off ProxyJump override — used when the user does not have
  /// the bastion as a saved session. Ignored when [viaSessionId] is
  /// non-null. See [ProxyJumpOverride] for the unit-set rule.
  final ProxyJumpOverride? viaOverride;

  Session({
    String? id,
    required this.label,
    this.folder = '',
    required this.server,
    this.auth = const SessionAuth(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, Object?>? extras,
    this.viaSessionId,
    this.viaOverride,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       extras = Map.unmodifiable(extras ?? const <String, Object?>{});

  /// True when this session bounces through a bastion before reaching
  /// [host]:[port]. UI uses this to surface a "via X" subtitle.
  bool get hasProxyJump => viaSessionId != null || viaOverride != null;

  // --- Convenience accessors (keep call sites short) ---
  String get host => server.host;
  int get port => server.port;
  String get user => server.user;
  AuthType get authType => auth.authType;
  String get keyId => auth.keyId;
  String get password => auth.password;
  String get keyPath => auth.keyPath;
  String get keyData => auth.keyData;
  String get passphrase => auth.passphrase;

  // --- Extras helpers ---
  bool? extrasBool(String key) {
    final v = extras[key];
    return v is bool ? v : null;
  }

  String? extrasStr(String key) {
    final v = extras[key];
    return v is String ? v : null;
  }

  int? extrasInt(String key) {
    final v = extras[key];
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  /// Return a copy with [delta] merged into [extras]. A `null` value
  /// removes the key (so callers can clear feature flags without
  /// resorting to a sentinel string). Keeps `updatedAt` fresh via
  /// [copyWith].
  Session withExtras(Map<String, Object?> delta) {
    final merged = Map<String, Object?>.from(extras);
    delta.forEach((k, v) {
      if (v == null) {
        merged.remove(k);
      } else {
        merged[k] = v;
      }
    });
    return copyWith(extras: merged);
  }

  /// True if session has credentials — either carried in this instance
  /// (password/keyData/keyPath/keyId) or known to exist in persistent
  /// storage ([SessionAuth.hasStoredSecret]). The store's cached list
  /// strips plaintext secrets on load; without the stored-secret flag
  /// this getter would mistakenly mark every embedded-key session as
  /// incomplete after an app restart.
  bool get hasCredentials =>
      password.isNotEmpty ||
      keyData.isNotEmpty ||
      keyId.isNotEmpty ||
      keyPath.isNotEmpty ||
      auth.hasStoredSecret;

  /// True if session has all required fields (host, port, user, and credentials).
  bool get isValid =>
      host.trim().isNotEmpty &&
      port >= 1 &&
      port <= 65535 &&
      user.trim().isNotEmpty &&
      hasCredentials;

  /// Validate minimum required fields for storage. Returns error message or null.
  ///
  /// Unlike [isValid], this does NOT require credentials — a session can be
  /// stored without credentials and completed later. Use [isValid] to check
  /// if the session is ready to connect.
  String? validate() {
    if (host.trim().isEmpty) return 'Host is required';
    if (port < 1 || port > 65535) return 'Port must be 1-65535';
    if (user.trim().isEmpty) return 'Username is required';
    return null;
  }

  /// Display string: "label (user@host)" or "user@host" if no label.
  String get displayName =>
      label.isNotEmpty ? '$label ($user@$host)' : '$user@$host:$port';

  /// Full folder path with label for tree display.
  String get fullPath => folder.isNotEmpty ? '$folder/$label' : label;

  /// Convert to SSHConfig for connecting.
  SSHConfig toSSHConfig() {
    final String expandedKeyPath;
    if (keyPath == '~') {
      expandedKeyPath = homeDirectory;
    } else if (keyPath.startsWith('~/')) {
      expandedKeyPath = '$homeDirectory${keyPath.substring(1)}';
    } else {
      expandedKeyPath = keyPath;
    }
    return SSHConfig(
      server: server,
      auth: SshAuth(
        password: password,
        keyPath: expandedKeyPath,
        keyData: keyData,
        passphrase: passphrase,
      ),
    );
  }

  Session copyWith({
    String? label,
    String? folder,
    ServerAddress? server,
    SessionAuth? auth,
    Map<String, Object?>? extras,
    Object? viaSessionId = _unsetVia,
    Object? viaOverride = _unsetVia,
  }) {
    return Session(
      id: id,
      label: label ?? this.label,
      folder: folder ?? this.folder,
      server: server ?? this.server,
      auth: auth ?? this.auth,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      extras: extras ?? this.extras,
      viaSessionId: identical(viaSessionId, _unsetVia)
          ? this.viaSessionId
          : viaSessionId as String?,
      viaOverride: identical(viaOverride, _unsetVia)
          ? this.viaOverride
          : viaOverride as ProxyJumpOverride?,
    );
  }

  // Sentinel that lets `copyWith` distinguish "caller did not pass
  // this argument" from "caller passed null to clear it" — both
  // viaSessionId and viaOverride need to be clearable independently
  // from "leave unchanged".
  static const Object _unsetVia = Object();

  /// Create a duplicate with new ID and "(copy)" suffix.
  Session duplicate() {
    return Session(
      label: label.isNotEmpty ? '$label (copy)' : '',
      folder: folder,
      server: ServerAddress(host: host, port: port, user: user),
      auth: SessionAuth(
        authType: auth.authType,
        keyId: keyId,
        password: password,
        keyPath: auth.keyPath,
        keyData: keyData,
        passphrase: passphrase,
      ),
    );
  }

  /// Serialize without secrets — safe for plaintext JSON storage.
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'folder': folder,
    'host': host,
    'port': port,
    'user': user,
    'auth_type': authType.name,
    if (keyId.isNotEmpty) 'key_id': keyId,
    'key_path': keyPath,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    if (extras.isNotEmpty) 'extras': extras,
    if (viaSessionId != null) 'via_session_id': viaSessionId,
    if (viaOverride != null) 'via_override': viaOverride!.toJson(),
  };

  /// Serialize with secrets — for encrypted export only.
  Map<String, dynamic> toJsonWithCredentials() => {
    ...toJson(),
    'password': password,
    'key_data': keyData,
    'passphrase': passphrase,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          id == other.id &&
          label == other.label &&
          folder == other.folder &&
          server == other.server &&
          auth == other.auth &&
          viaSessionId == other.viaSessionId &&
          viaOverride == other.viaOverride &&
          _extrasEqual(extras, other.extras);

  @override
  int get hashCode => Object.hash(
    id,
    label,
    folder,
    server,
    auth,
    viaSessionId,
    viaOverride,
    // Map.hashCode is identity-based — fold the entries instead so
    // two sessions with logically equal `extras` hash equal too.
    Object.hashAllUnordered(
      extras.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _extrasEqual(Map<String, Object?> a, Map<String, Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      folder: json['folder'] as String? ?? json['group'] as String? ?? '',
      server: ServerAddress(
        host: json['host'] as String,
        port: json['port'] as int? ?? 22,
        user: json['user'] as String,
      ),
      auth: SessionAuth(
        authType: AuthType.values.firstWhere(
          (e) => e.name == json['auth_type'],
          orElse: () => AuthType.password,
        ),
        keyId: json['key_id'] as String? ?? '',
        password: json['password'] as String? ?? '',
        keyPath: json['key_path'] as String? ?? '',
        keyData: json['key_data'] as String? ?? '',
        passphrase: json['passphrase'] as String? ?? '',
      ),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      extras: _decodeExtras(json['extras']),
      viaSessionId: json['via_session_id'] as String?,
      viaOverride: json['via_override'] is Map<String, dynamic>
          ? ProxyJumpOverride.fromJson(
              json['via_override'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Decode the persisted `extras` payload tolerantly: accepts a
  /// `Map<String, dynamic>` (modern import path), a JSON-encoded
  /// string (DB load path through `mappers.dart`), and treats
  /// anything malformed as empty so a corrupt blob can never block
  /// the session from loading.
  static Map<String, Object?> _decodeExtras(Object? raw) {
    if (raw == null) return const <String, Object?>{};
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String) {
      if (raw.isEmpty) return const <String, Object?>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } on FormatException {
        // Corrupt JSON in the column — fall through to empty.
      }
    }
    return const <String, Object?>{};
  }
}
