import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('SSHConnectionState', () {
    test('has all states', () {
      expect(SSHConnectionState.values.length, 3);
      expect(SSHConnectionState.values, contains(SSHConnectionState.disconnected));
      expect(SSHConnectionState.values, contains(SSHConnectionState.connecting));
      expect(SSHConnectionState.values, contains(SSHConnectionState.connected));
    });
  });

  group('Connection', () {
    late Connection conn;

    setUp(() {
      conn = Connection(
        id: 'test-id',
        label: 'My Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: '10.0.0.1', user: 'root')),
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
  });
}
