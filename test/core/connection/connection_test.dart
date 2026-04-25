import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_extension.dart';
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

  group('Connection.extensions', () {
    Connection makeConn() => Connection(
      id: 'c',
      label: 'l',
      sshConfig: const SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      ),
    );

    test('addExtension is idempotent and preserves order', () {
      final conn = makeConn();
      final a = _RecordingExtension(id: 'a');
      final b = _RecordingExtension(id: 'b');
      conn.addExtension(a);
      conn.addExtension(b);
      conn.addExtension(a);
      expect(conn.extensions.map((e) => e.id), ['a', 'b']);
    });

    test('removeExtension drops the registration', () {
      final conn = makeConn();
      final a = _RecordingExtension(id: 'a');
      conn.addExtension(a);
      conn.removeExtension(a);
      conn.notifyExtensionsConnected();
      expect(a.events, isEmpty);
    });

    test('hooks fire in registration order', () {
      final conn = makeConn();
      final a = _RecordingExtension(id: 'a');
      final b = _RecordingExtension(id: 'b');
      conn.addExtension(a);
      conn.addExtension(b);

      conn.notifyExtensionsConnected();
      conn.notifyExtensionsReconnecting();
      conn.notifyExtensionsDisconnecting();

      expect(a.events, ['connected', 'reconnecting', 'disconnecting']);
      expect(b.events, ['connected', 'reconnecting', 'disconnecting']);
    });

    test('a throwing extension does not block the rest', () {
      final conn = makeConn();
      final bad = _ThrowingExtension();
      final good = _RecordingExtension(id: 'good');
      conn.addExtension(bad);
      conn.addExtension(good);
      // No exception escapes.
      conn.notifyExtensionsConnected();
      expect(good.events, ['connected']);
    });

    test('extension may deregister itself during a hook', () {
      final conn = makeConn();
      final ext = _SelfRemovingExtension();
      conn.addExtension(ext);
      conn.notifyExtensionsConnected();
      expect(conn.extensions, isEmpty);
    });
  });
}

class _RecordingExtension implements ConnectionExtension {
  _RecordingExtension({required this.id});
  @override
  final String id;
  final events = <String>[];
  @override
  void onConnected(Connection connection) => events.add('connected');
  @override
  void onDisconnecting(Connection connection) => events.add('disconnecting');
  @override
  void onReconnecting(Connection connection) => events.add('reconnecting');
}

class _ThrowingExtension implements ConnectionExtension {
  @override
  String get id => 'throw';
  @override
  void onConnected(Connection connection) =>
      throw StateError('extension blew up');
  @override
  void onDisconnecting(Connection connection) {}
  @override
  void onReconnecting(Connection connection) {}
}

class _SelfRemovingExtension implements ConnectionExtension {
  @override
  String get id => 'self';
  @override
  void onConnected(Connection connection) => connection.removeExtension(this);
  @override
  void onDisconnecting(Connection connection) {}
  @override
  void onReconnecting(Connection connection) {}
}
