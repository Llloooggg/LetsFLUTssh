/// SSH connection configuration model.
///
/// Mirrors LetsGOssh ConnConfig — host, port, user, auth params.
class SSHConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String keyPath;
  final String keyData; // raw PEM text
  final String passphrase;
  final int keepAliveSec;
  final int timeoutSec;

  const SSHConfig({
    required this.host,
    this.port = 22,
    required this.user,
    this.password = '',
    this.keyPath = '',
    this.keyData = '',
    this.passphrase = '',
    this.keepAliveSec = 30,
    this.timeoutSec = 10,
  });

  /// Validate required fields. Returns error message or null.
  String? validate() {
    if (host.trim().isEmpty) return 'Host is required';
    if (port < 1 || port > 65535) return 'Port must be 1-65535';
    if (user.trim().isEmpty) return 'Username is required';
    if (keepAliveSec < 0) return 'Keep-alive must be non-negative';
    if (timeoutSec < 1) return 'Timeout must be at least 1 second';
    return null;
  }

  /// True if any auth method is configured.
  bool get hasAuth =>
      password.isNotEmpty ||
      keyPath.isNotEmpty ||
      keyData.isNotEmpty;

  /// Effective port (default 22).
  int get effectivePort => port > 0 ? port : 22;

  /// Display string for UI.
  String get displayName => '$user@$host:$effectivePort';

  SSHConfig copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
    int? keepAliveSec,
    int? timeoutSec,
  }) {
    return SSHConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      keyPath: keyPath ?? this.keyPath,
      keyData: keyData ?? this.keyData,
      passphrase: passphrase ?? this.passphrase,
      keepAliveSec: keepAliveSec ?? this.keepAliveSec,
      timeoutSec: timeoutSec ?? this.timeoutSec,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SSHConfig &&
          host == other.host &&
          port == other.port &&
          user == other.user &&
          password == other.password &&
          keyPath == other.keyPath &&
          keyData == other.keyData &&
          passphrase == other.passphrase &&
          keepAliveSec == other.keepAliveSec &&
          timeoutSec == other.timeoutSec;

  @override
  int get hashCode => Object.hash(
        host, port, user, password, keyPath,
        keyData, passphrase, keepAliveSec, timeoutSec,
      );
}
