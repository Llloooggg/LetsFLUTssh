/// SSH server address — host, port, user.
class ServerAddress {
  final String host;
  final int port;
  final String user;

  const ServerAddress({required this.host, this.port = 22, required this.user});

  /// Effective port (default 22).
  int get effectivePort => port > 0 ? port : 22;

  /// Display string for UI.
  String get displayName => '$user@$host:$effectivePort';

  ServerAddress copyWith({String? host, int? port, String? user}) =>
      ServerAddress(
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
///
/// `keyId` carries a reference to a row in the manager's key store —
/// the connect path stages the private PEM bytes from Rust directly
/// into the SecretStore by id, so the bytes do not need to round-
/// trip through `keyData` on the Dart heap. `keyData` stays as the
/// transport for inline / quick-connect / legacy paths that have no
/// stored row to stage from.
class SshAuth {
  final String password;
  final String keyPath;
  final String keyData; // raw PEM text
  final String keyId;
  final String passphrase;

  /// `true` when the session defers to a system ssh-agent (Unix
  /// `$SSH_AUTH_SOCK`, Windows OpenSSH named pipe / Pageant) for
  /// every signature. Set by [Session.toSSHConfig] when the saved
  /// row's [AuthType] is `agent`; the connect path short-circuits
  /// to [SshAuthAgent] before the auth composer runs so no key /
  /// password column has to be populated.
  final bool useAgent;

  const SshAuth({
    this.password = '',
    this.keyPath = '',
    this.keyData = '',
    this.keyId = '',
    this.passphrase = '',
    this.useAgent = false,
  });

  /// True if any auth method is configured.
  bool get hasAuth =>
      useAgent ||
      password.isNotEmpty ||
      keyPath.isNotEmpty ||
      keyData.isNotEmpty ||
      keyId.isNotEmpty;

  SshAuth copyWith({
    String? password,
    String? keyPath,
    String? keyData,
    String? keyId,
    String? passphrase,
    bool? useAgent,
  }) => SshAuth(
    password: password ?? this.password,
    keyPath: keyPath ?? this.keyPath,
    keyData: keyData ?? this.keyData,
    keyId: keyId ?? this.keyId,
    passphrase: passphrase ?? this.passphrase,
    useAgent: useAgent ?? this.useAgent,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshAuth &&
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          keyId == other.keyId &&
          passphrase == other.passphrase &&
          useAgent == other.useAgent;

  @override
  int get hashCode =>
      Object.hash(password, keyPath, keyData, keyId, passphrase, useAgent);
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

  /// Validate required fields for a freshly-edited config.
  ///
  /// Form-level "is the empty / range basics" check that the
  /// session-edit dialog runs before submit. The architectural
  /// rule "validation belongs Rust-side" carves out
  /// "form-level field validation for empty/format checks before
  /// submission" (CLAUDE.md → conventions). The fields covered
  /// here are pure UI-form constraints (required text non-empty,
  /// integer in range); the deeper "is this a runnable SSH
  /// config" check happens Rust-side on actual connect. Keeping
  /// the validator Dart-side keeps the dialog's per-keystroke
  /// feedback synchronous.
  String? validate() {
    if (host.trim().isEmpty) return 'Host is required';
    if (port < 1 || port > 65535) return 'Port must be 1-65535';
    if (user.trim().isEmpty) return 'Username is required';
    if (!hasAuth) return 'Password or SSH key is required';
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
