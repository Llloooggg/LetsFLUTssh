import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('ConnectionManager', () {
    late ConnectionManager manager;

    setUp(() {
      manager = ConnectionManager(knownHosts: KnownHostsManager());
    });

    tearDown(() {
      manager.dispose();
    });

    test('starts with empty connections list', () {
      expect(manager.connections, isEmpty);
    });

    test('get returns null for unknown id', () {
      expect(manager.get('nonexistent'), isNull);
    });

    test('onChange stream fires', () async {
      var fired = false;
      final sub = manager.onChange.listen((_) => fired = true);
      // Force a notification by disconnectAll
      manager.disconnectAll();
      await Future.delayed(Duration.zero);
      expect(fired, isTrue);
      await sub.cancel();
    });

    test('disconnect unknown id does nothing', () {
      // Should not throw
      manager.disconnect('nonexistent');
      expect(manager.connections, isEmpty);
    });

    test('disconnectAll clears all connections', () {
      manager.disconnectAll();
      expect(manager.connections, isEmpty);
    });

    test('dispose calls disconnectAll', () {
      final mgr = ConnectionManager(knownHosts: KnownHostsManager());
      mgr.dispose();
      // After dispose, connections should be empty
      expect(mgr.connections, isEmpty);
    });
  });

  group('Connection model', () {
    test('default state is disconnected', () {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );
      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.isConnected, isFalse);
      expect(conn.sshConnection, isNull);
    });

    test('isConnected returns true for connected state', () {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        state: SSHConnectionState.connected,
      );
      expect(conn.isConnected, isTrue);
    });

    test('isConnected returns false for connecting state', () {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        state: SSHConnectionState.connecting,
      );
      expect(conn.isConnected, isFalse);
    });

    test('state can be modified', () {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );
      conn.state = SSHConnectionState.connected;
      expect(conn.isConnected, isTrue);
    });
  });
}
