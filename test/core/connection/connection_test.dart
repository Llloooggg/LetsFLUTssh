import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('SSHConnectionState', () {
    test('contains expected states', () {
      expect(
        SSHConnectionState.values,
        contains(SSHConnectionState.disconnected),
      );
      expect(
        SSHConnectionState.values,
        contains(SSHConnectionState.connecting),
      );
      expect(SSHConnectionState.values, contains(SSHConnectionState.connected));
    });
  });

  group('Connection', () {
    late Connection conn;

    setUp(() {
      conn = Connection(
        id: 'test-id',
        label: 'My Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
      );
    });

    test('defaults to disconnected state', () {
      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.sshConnection, isNull);
    });

    test('isConnected returns true only when connected', () {
      expect(conn.isConnected, isFalse);

      conn.state = SSHConnectionState.connecting;
      expect(conn.isConnected, isFalse);

      conn.state = SSHConnectionState.connected;
      expect(conn.isConnected, isTrue);

      conn.state = SSHConnectionState.disconnected;
      expect(conn.isConnected, isFalse);
    });

    test('stores config and label', () {
      expect(conn.id, 'test-id');
      expect(conn.label, 'My Server');
      expect(conn.sshConfig.host, '10.0.0.1');
      expect(conn.sshConfig.user, 'root');
    });

    test('sessionId defaults to null', () {
      expect(conn.sessionId, isNull);
    });

    test('stores sessionId when provided', () {
      final connWithSession = Connection(
        id: 'test-2',
        label: 'Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        sessionId: 'session-abc',
      );
      expect(connWithSession.sessionId, 'session-abc');
    });

    test('sshConfig can be updated', () {
      const newConfig = SSHConfig(
        server: ServerAddress(host: '192.168.1.1', user: 'admin'),
      );
      conn.sshConfig = newConfig;
      expect(conn.sshConfig.host, '192.168.1.1');
      expect(conn.sshConfig.user, 'admin');
    });

    test('clearCachedCredentials drops the cached passphrase reference', () {
      conn.cachedPassphrase = 'do-not-retain-me';
      expect(conn.cachedPassphrase, isNotNull);

      conn.clearCachedCredentials();

      // Dart String immutability means the original bytes may linger
      // until GC, but every reference this Connection owned is gone —
      // which is all the language allows.
      expect(conn.cachedPassphrase, isNull);
    });
  });
}
