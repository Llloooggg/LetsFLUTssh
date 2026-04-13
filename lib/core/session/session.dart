import 'package:uuid/uuid.dart';

import '../../utils/platform.dart';
import '../ssh/ssh_config.dart';

/// Authentication type for a session.
enum AuthType { password, key, keyWithPassword }

/// Session authentication — extends [SshAuth] with UI-facing [authType].
class SessionAuth extends SshAuth {
  final AuthType authType;

  /// Reference to a key in the central key store. Empty = not set.
  final String keyId;

  const SessionAuth({
    this.authType = AuthType.password,
    this.keyId = '',
    super.password,
    super.keyPath,
    super.keyData,
    super.passphrase,
  });

  @override
  SessionAuth copyWith({
    AuthType? authType,
    String? keyId,
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
  }) => SessionAuth(
    authType: authType ?? this.authType,
    keyId: keyId ?? this.keyId,
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
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          passphrase == other.passphrase;

  @override
  int get hashCode =>
      Object.hash(authType, keyId, password, keyPath, keyData, passphrase);
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

  Session({
    String? id,
    required this.label,
    this.folder = '',
    required this.server,
    this.auth = const SessionAuth(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

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

  /// True if session has credentials (password, keyData, keyPath, or keyId).
  bool get hasCredentials =>
      password.isNotEmpty ||
      keyData.isNotEmpty ||
      keyId.isNotEmpty ||
      keyPath.isNotEmpty;

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
  }) {
    return Session(
      id: id,
      label: label ?? this.label,
      folder: folder ?? this.folder,
      server: server ?? this.server,
      auth: auth ?? this.auth,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

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
          auth == other.auth;

  @override
  int get hashCode => Object.hash(id, label, folder, server, auth);

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
    );
  }
}
