import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('SSHConfig', () {
    test('default port is 22', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.port, 22);
      expect(config.effectivePort, 22);
    });

    test('effectivePort returns 22 for zero or negative port', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', port: 0, user: 'root'));
      expect(config.effectivePort, 22);

      const negConfig =
          SSHConfig(server: ServerAddress(host: 'example.com', port: -1, user: 'root'));
      expect(negConfig.effectivePort, 22);
    });

    test('effectivePort returns custom port', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', port: 2222, user: 'root'));
      expect(config.effectivePort, 2222);
    });

    test('displayName format', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', port: 22, user: 'admin'));
      expect(config.displayName, 'admin@example.com:22');
    });

    test('displayName with custom port', () {
      const config =
          SSHConfig(server: ServerAddress(host: 'example.com', port: 2222, user: 'admin'));
      expect(config.displayName, 'admin@example.com:2222');
    });

    test('hasAuth returns false when no auth configured', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.hasAuth, isFalse);
    });

    test('hasAuth returns true with password', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'), auth: SshAuth(password: 'secret'));
      expect(config.hasAuth, isTrue);
    });

    test('hasAuth returns true with key path', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'), auth: SshAuth(keyPath: '/home/user/.ssh/id_rsa'));
      expect(config.hasAuth, isTrue);
    });

    test('hasAuth returns true with key data', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'), auth: SshAuth(keyData: '-----BEGIN RSA PRIVATE KEY-----'));
      expect(config.hasAuth, isTrue);
    });

    test('default keepAliveSec is 30', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.keepAliveSec, 30);
    });

    test('default timeoutSec is 10', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.timeoutSec, 10);
    });

    test('copyWith preserves unchanged fields', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', port: 2222, user: 'admin'), auth: SshAuth(password: 'pass', keyPath: '/key', keyData: 'PEM', passphrase: 'phrase'), keepAliveSec: 60, timeoutSec: 15);
      final copy = config.copyWith(server: config.server.copyWith(host: 'new.com'));
      expect(copy.host, 'new.com');
      expect(copy.port, 2222);
      expect(copy.user, 'admin');
      expect(copy.password, 'pass');
      expect(copy.keyPath, '/key');
      expect(copy.keyData, 'PEM');
      expect(copy.passphrase, 'phrase');
      expect(copy.keepAliveSec, 60);
      expect(copy.timeoutSec, 15);
    });

    test('copyWith changes specified fields', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      final copy = config.copyWith(server: config.server.copyWith(port: 3333, user: 'admin'), auth: config.auth.copyWith(password: 'new-pass'));
      expect(copy.host, 'example.com');
      expect(copy.port, 3333);
      expect(copy.user, 'admin');
      expect(copy.password, 'new-pass');
    });

    test('default password is empty', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.password, '');
    });

    test('default keyPath is empty', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.keyPath, '');
    });

    test('default keyData is empty', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.keyData, '');
    });

    test('default passphrase is empty', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.passphrase, '');
    });
  });

  group('SSH error types for SSHConnection', () {
    test('ConnectError thrown for disposed connection', () {
      const error = ConnectError('Connection disposed');
      expect(error.message, 'Connection disposed');
      expect(error, isA<SSHError>());
    });

    test('ConnectError with host info', () {
      const error = ConnectError('Failed to connect to example.com:22');
      expect(error.message, contains('example.com'));
      expect(error.message, contains('22'));
    });

    test('AuthError for authentication failure', () {
      const error = AuthError('Authentication failed for root@example.com');
      expect(error.message, contains('root'));
      expect(error.message, contains('example.com'));
    });

    test('HostKeyError for rejected host key', () {
      const error = HostKeyError(
        'Host key rejected for example.com:22 — accept the host key or check known_hosts',
      );
      expect(error.message, contains('Host key rejected'));
      expect(error.message, contains('known_hosts'));
    });

    test('AuthError for failed key file load', () {
      const error = AuthError('Failed to load SSH key file');
      expect(error.message, 'Failed to load SSH key file');
    });

    test('AuthError for failed PEM parsing', () {
      const error = AuthError('Failed to parse PEM key data');
      expect(error.message, 'Failed to parse PEM key data');
    });

    test('ConnectError for failed shell open', () {
      const error = ConnectError('Failed to open shell');
      expect(error.message, 'Failed to open shell');
    });

    test('ConnectError for not connected state', () {
      const error = ConnectError('Not connected');
      expect(error.message, 'Not connected');
    });

    test('userMessage strips SocketException prefix', () {
      const error =
          SSHError('connection failed', SocketException('Connection refused'));
      expect(error.userMessage, contains('connection failed'));
      expect(error.userMessage, contains('Connection refused'));
    });

    test('userMessage without cause returns message', () {
      const error = ConnectError('timeout');
      expect(error.userMessage, 'timeout');
    });

    test('userMessage with nested SSHError cause', () {
      const inner = AuthError('wrong password');
      const outer = ConnectError('connection failed', inner);
      expect(outer.userMessage, contains('connection failed'));
      expect(outer.userMessage, contains('wrong password'));
    });
  });
}

/// Minimal SocketException-like class for testing userMessage prefix stripping.
class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
  @override
  String toString() => 'SocketException: $message';
}
