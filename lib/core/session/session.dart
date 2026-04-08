import 'package:uuid/uuid.dart';

import '../../utils/platform.dart';
import '../ssh/ssh_config.dart';

/// Authentication type for a session.
enum AuthType { password, key, keyWithPassword }

/// Session authentication — extends [SshAuth] with UI-facing [authType].
class SessionAuth extends SshAuth {
  final AuthType authType;

  const SessionAuth({
    this.authType = AuthType.password,
    super.password,
    super.keyPath,
    super.keyData,
    super.passphrase,
  });

  @override
  SessionAuth copyWith({
    AuthType? authType,
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
  }) => SessionAuth(
    authType: authType ?? this.authType,
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
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          passphrase == other.passphrase;

  @override
  int get hashCode =>
      Object.hash(authType, password, keyPath, keyData, passphrase);
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

  /// True when session was imported without credentials (e.g. via QR code).
  /// Automatically set to false when auth is filled in via [copyWith].
  final bool incomplete;

  Session({
    String? id,
    required this.label,
    this.folder = '',
    required this.server,
    this.auth = const SessionAuth(),
    DateTime? createdAt,
    DateTime? updatedAt,
    this.incomplete = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // --- Convenience accessors (keep call sites short) ---
  String get host => server.host;
  int get port => server.port;
  String get user => server.user;
  AuthType get authType => auth.authType;
  String get password => auth.password;
  String get keyPath => auth.keyPath;
  String get keyData => auth.keyData;
  String get passphrase => auth.passphrase;

  /// Validate required fields. Returns error message or null.
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
    bool? incomplete,
  }) {
    final newAuth = auth ?? this.auth;
    // Auto-reset incomplete when credentials are filled in
    final newIncomplete = incomplete ?? (this.incomplete && !newAuth.hasAuth);
    return Session(
      id: id,
      label: label ?? this.label,
      folder: folder ?? this.folder,
      server: server ?? this.server,
      auth: newAuth,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      incomplete: newIncomplete,
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
        password: password,
        keyPath: auth.keyPath,
        keyData: keyData,
        passphrase: passphrase,
      ),
      incomplete: incomplete,
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
    'key_path': keyPath,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    if (incomplete) 'incomplete': true,
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
          incomplete == other.incomplete;

  @override
  int get hashCode => Object.hash(id, label, folder, server, auth, incomplete);

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
      incomplete: json['incomplete'] as bool? ?? false,
    );
  }
}
