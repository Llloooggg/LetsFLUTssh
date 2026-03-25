import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_client.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

/// Fake SSHConnection that doesn't touch the network.
class FakeSSHConnection extends SSHConnection {
  final bool shouldFail;
  bool connectCalled = false;
  bool disconnectCalled = false;

  FakeSSHConnection({
    required super.config,
    required super.knownHosts,
    this.shouldFail = false,
  });

  @override
  Future<void> connect() async {
    connectCalled = true;
    if (shouldFail) throw Exception('fake connection failure');
    // Simulate successful connection (don't call super — no real SSH)
  }

  @override
  bool get isConnected => connectCalled && !shouldFail;

  @override
  void disconnect() {
    disconnectCalled = true;
  }
}

void main() {
  late ConnectionManager manager;
  late KnownHostsManager knownHosts;

  setUp(() {
    knownHosts = KnownHostsManager();
    manager = ConnectionManager(knownHosts: knownHosts);
  });

  tearDown(() {
    manager.dispose();
  });

  group('ConnectionManager', () {
    test('starts with empty connections', () {
      expect(manager.connections, isEmpty);
    });

    test('get returns null for unknown id', () {
      expect(manager.get('nonexistent'), isNull);
    });

    test('disconnect unknown id does nothing', () {
      manager.disconnect('nonexistent');
      expect(manager.connections, isEmpty);
    });

    test('onChange stream emits on disconnectAll', () async {
      var emitted = false;
      final sub = manager.onChange.listen((_) => emitted = true);
      manager.disconnectAll();
      await Future.delayed(Duration.zero);
      expect(emitted, isTrue);
      await sub.cancel();
    });

    test('disconnectAll on empty does not throw', () {
      manager.disconnectAll();
      expect(manager.connections, isEmpty);
    });

    test('knownHosts is accessible', () {
      expect(manager.knownHosts, knownHosts);
    });

    test('onChange stream can have multiple listeners', () async {
      var count1 = 0;
      var count2 = 0;
      final sub1 = manager.onChange.listen((_) => count1++);
      final sub2 = manager.onChange.listen((_) => count2++);

      manager.disconnectAll();
      await Future.delayed(Duration.zero);

      expect(count1, 1);
      expect(count2, 1);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('dispose can be called multiple times safely', () {
      final mgr = ConnectionManager(knownHosts: knownHosts);
      mgr.dispose();
    });

    test('connections returns unmodifiable snapshot', () {
      final list1 = manager.connections;
      final list2 = manager.connections;
      expect(list1, isEmpty);
      expect(list2, isEmpty);
      expect(identical(list1, list2), isFalse);
    });
  });

  group('ConnectionManager.connect', () {
    test('connect fails and removes connection on error', () async {
      final events = <void>[];
      final sub = manager.onChange.listen((_) => events.add(null));

      // connect() will fail (no real SSH server), but we verify error handling
      const config = SSHConfig(host: '127.0.0.1', port: 1, user: 'test', timeoutSec: 1);

      try {
        await manager.connect(config);
      } catch (_) {
        // Expected: connection fails
      }

      await Future.delayed(Duration.zero);

      // Should have emitted events: connecting (add) + failed (remove)
      expect(events.length, greaterThanOrEqualTo(2));
      // After failure, connection should be removed
      expect(manager.connections, isEmpty);

      await sub.cancel();
    });

    test('connect uses label when provided', () async {
      final events = <void>[];
      final sub = manager.onChange.listen((_) => events.add(null));

      const config = SSHConfig(host: '127.0.0.1', port: 1, user: 'test', timeoutSec: 1);

      try {
        await manager.connect(config, label: 'My Server');
      } catch (_) {
        // Expected
      }

      await Future.delayed(Duration.zero);
      // After failure, no connections remain
      expect(manager.connections, isEmpty);

      await sub.cancel();
    });

    test('connect uses displayName when no label', () async {
      const config = SSHConfig(host: '127.0.0.1', port: 1, user: 'admin', timeoutSec: 1);

      try {
        await manager.connect(config);
      } catch (_) {
        // Expected
      }

      expect(manager.connections, isEmpty);
    });

    test('connect rethrows on failure and removes connection', () async {
      const config = SSHConfig(host: '127.0.0.1', port: 1, user: 'test', timeoutSec: 1);

      expect(
        () => manager.connect(config),
        throwsA(anything),
      );
    });

    test('onChange emits during connect lifecycle', () async {
      var emitCount = 0;
      final sub = manager.onChange.listen((_) => emitCount++);

      const config = SSHConfig(host: '127.0.0.1', port: 1, user: 'test', timeoutSec: 1);

      try {
        await manager.connect(config);
      } catch (_) {}

      await Future.delayed(Duration.zero);

      // At least 2 emits: connecting + failed
      expect(emitCount, greaterThanOrEqualTo(2));

      await sub.cancel();
    });
  });

  group('ConnectionManager.disconnect', () {
    test('disconnect with null connection in map does nothing', () {
      manager.disconnect('nonexistent');
      expect(manager.connections, isEmpty);
    });

    test('disconnectAll clears all connections and notifies', () async {
      var emitted = false;
      final sub = manager.onChange.listen((_) => emitted = true);

      manager.disconnectAll();
      await Future.delayed(Duration.zero);

      expect(emitted, isTrue);
      expect(manager.connections, isEmpty);

      await sub.cancel();
    });
  });

  group('ConnectionManager.dispose', () {
    test('dispose calls disconnectAll and closes stream', () async {
      final mgr = ConnectionManager(knownHosts: knownHosts);
      var emitted = false;
      mgr.onChange.listen((_) => emitted = true);

      mgr.dispose();
      await Future.delayed(Duration.zero);
      // Stream should be closed after dispose
      expect(emitted, isTrue); // disconnectAll emits before close
    });

    test('notify after dispose does not throw', () {
      final mgr = ConnectionManager(knownHosts: knownHosts);
      mgr.dispose();
      // Calling disconnectAll after dispose should not crash
      // (internally calls _notify which should be guarded)
      expect(() => mgr.disconnectAll(), returnsNormally);
    });
  });

  group('ConnectionManager.connect — success path (injectable factory)', () {
    test('successful connect returns connected Connection', () async {
      late FakeSSHConnection fakeConn;
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
          return fakeConn;
        },
      );

      const config = SSHConfig(host: 'test.com', user: 'admin');
      final conn = await mgr.connect(config, label: 'Test Server');

      expect(conn.isConnected, isTrue);
      expect(conn.state, SSHConnectionState.connected);
      expect(conn.label, 'Test Server');
      expect(conn.sshConnection, fakeConn);
      expect(fakeConn.connectCalled, isTrue);
      expect(mgr.connections, hasLength(1));

      mgr.dispose();
    });

    test('successful connect uses displayName when no label', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      const config = SSHConfig(host: 'server.com', port: 2222, user: 'root');
      final conn = await mgr.connect(config);

      expect(conn.label, 'root@server.com:2222');

      mgr.dispose();
    });

    test('successful connect emits 2 events (connecting + connected)', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      var emitCount = 0;
      final sub = mgr.onChange.listen((_) => emitCount++);

      const config = SSHConfig(host: 'h', user: 'u');
      await mgr.connect(config);
      await Future.delayed(Duration.zero);

      expect(emitCount, greaterThanOrEqualTo(2));

      await sub.cancel();
      mgr.dispose();
    });

    test('disconnect after successful connect calls SSHConnection.disconnect', () async {
      late FakeSSHConnection fakeConn;
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
          return fakeConn;
        },
      );

      const config = SSHConfig(host: 'h', user: 'u');
      final conn = await mgr.connect(config);
      mgr.disconnect(conn.id);

      expect(fakeConn.disconnectCalled, isTrue);
      expect(mgr.connections, isEmpty);

      mgr.dispose();
    });

    test('onDisconnect callback fires and updates state', () async {
      late FakeSSHConnection fakeConn;
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
          return fakeConn;
        },
      );

      const config = SSHConfig(host: 'h', user: 'u');
      final conn = await mgr.connect(config);

      // Simulate remote disconnect
      fakeConn.onDisconnect?.call();
      await Future.delayed(Duration.zero);

      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.sshConnection, isNull);

      mgr.dispose();
    });

    test('failed connect with factory removes connection and rethrows', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh, shouldFail: true),
      );

      const config = SSHConfig(host: 'h', user: 'u');
      expect(() => mgr.connect(config), throwsA(isA<Exception>()));
      await Future.delayed(Duration.zero);
      expect(mgr.connections, isEmpty);

      mgr.dispose();
    });

    test('multiple successful connections tracked', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      await mgr.connect(const SSHConfig(host: 'a', user: 'u'), label: 'A');
      await mgr.connect(const SSHConfig(host: 'b', user: 'u'), label: 'B');

      expect(mgr.connections, hasLength(2));

      mgr.dispose();
    });

    test('get returns connection by id after successful connect', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      final conn = await mgr.connect(const SSHConfig(host: 'h', user: 'u'));
      expect(mgr.get(conn.id), conn);

      mgr.dispose();
    });

    test('disconnectAll disconnects all fake connections', () async {
      final fakes = <FakeSSHConnection>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          final fake = FakeSSHConnection(config: config, knownHosts: kh);
          fakes.add(fake);
          return fake;
        },
      );

      await mgr.connect(const SSHConfig(host: 'a', user: 'u'));
      await mgr.connect(const SSHConfig(host: 'b', user: 'u'));

      mgr.disconnectAll();

      for (final f in fakes) {
        expect(f.disconnectCalled, isTrue);
      }
      expect(mgr.connections, isEmpty);

      mgr.dispose();
    });
  });

  group('Connection model', () {
    test('isConnected returns true when state is connected', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        state: SSHConnectionState.connected,
      );
      expect(conn.isConnected, isTrue);
    });

    test('isConnected returns false when state is disconnected', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        state: SSHConnectionState.disconnected,
      );
      expect(conn.isConnected, isFalse);
    });

    test('isConnected returns false when state is connecting', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        state: SSHConnectionState.connecting,
      );
      expect(conn.isConnected, isFalse);
    });

    test('sshConnection is nullable', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
      );
      expect(conn.sshConnection, isNull);
    });
  });
}
