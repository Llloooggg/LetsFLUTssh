/// SSH server address — host, port, user.
class ServerAddress {
  final String host;
  final int port;
  final String user;

  const ServerAddress({
    required this.host,
    this.port = 22,
    required this.user,
  });

  /// Effective port (default 22).
  int get effectivePort => port > 0 ? port : 22;

  /// Display string for UI.
  String get displayName => '$user@$host:$effectivePort';

  ServerAddress copyWith({
    String? host,
    int? port,
    String? user,
  }) => ServerAddress(
    host: host ?? this.host,
    port: port ?? this.port,
    user: user ?? this.user,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerAddress &&
          host == other.host &&
          port == other.port &&
          user == other.user;

  @override
  int get hashCode => Object.hash(host, port, user);
}

/// SSH authentication credentials.
class SshAuth {
  final String password;
  final String keyPath;
  final String keyData; // raw PEM text
  final String passphrase;

  const SshAuth({
    this.password = '',
    this.keyPath = '',
    this.keyData = '',
    this.passphrase = '',
  });

  /// True if any auth method is configured.
  bool get hasAuth =>
      password.isNotEmpty ||
      keyPath.isNotEmpty ||
      keyData.isNotEmpty;

  SshAuth copyWith({
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
  }) => SshAuth(
    password: password ?? this.password,
    keyPath: keyPath ?? this.keyPath,
    keyData: keyData ?? this.keyData,
    passphrase: passphrase ?? this.passphrase,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshAuth &&
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          passphrase == other.passphrase;

  @override
  int get hashCode => Object.hash(password, keyPath, keyData, passphrase);
}

/// SSH connection configuration model.
///
/// Mirrors LetsGOssh ConnConfig — server address, auth, session behavior.
class SSHConfig {
  final ServerAddress server;
  final SshAuth auth;
  final int keepAliveSec;
  final int timeoutSec;

  const SSHConfig({
    required this.server,
    this.auth = const SshAuth(),
    this.keepAliveSec = 30,
    this.timeoutSec = 10,
  });

  // --- Convenience accessors (keep call sites short) ---
  String get host => server.host;
  int get port => server.port;
  String get user => server.user;
  int get effectivePort => server.effectivePort;
  String get displayName => server.displayName;
  String get password => auth.password;
  String get keyPath => auth.keyPath;
  String get keyData => auth.keyData;
  String get passphrase => auth.passphrase;
  bool get hasAuth => auth.hasAuth;

  /// Validate required fields. Returns error message or null.
  String? validate() {
    if (host.trim().isEmpty) return 'Host is required';
    if (port < 1 || port > 65535) return 'Port must be 1-65535';
    if (user.trim().isEmpty) return 'Username is required';
    if (keepAliveSec < 0) return 'Keep-alive must be non-negative';
    if (timeoutSec < 1) return 'Timeout must be at least 1 second';
    return null;
  }

  SSHConfig copyWith({
    ServerAddress? server,
    SshAuth? auth,
    int? keepAliveSec,
    int? timeoutSec,
  }) {
    return SSHConfig(
      server: server ?? this.server,
      auth: auth ?? this.auth,
      keepAliveSec: keepAliveSec ?? this.keepAliveSec,
      timeoutSec: timeoutSec ?? this.timeoutSec,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SSHConfig &&
          server == other.server &&
          auth == other.auth &&
          keepAliveSec == other.keepAliveSec &&
          timeoutSec == other.timeoutSec;

  @override
  int get hashCode => Object.hash(server, auth, keepAliveSec, timeoutSec);
}
