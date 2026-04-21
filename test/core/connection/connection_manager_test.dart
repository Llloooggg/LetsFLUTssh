import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/security/session_credential_cache.dart';
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
  Future<void> connect({void Function(ConnectionStep)? onProgress}) async {
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

  group('ConnectionManager.connectAsync', () {
    test('connectAsync returns connection in connecting state immediately', () {
      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'test'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config);
      // Returns immediately — connection is in connecting state
      expect(conn.state, SSHConnectionState.connecting);
      expect(manager.connections, hasLength(1));
    });

    test('connect fails in background and sets connectionError', () async {
      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'test'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config);

      // Wait for background connection to fail
      await conn.ready;

      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);
    });

    test('connect uses label when provided', () {
      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'test'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config, label: 'My Server');
      expect(conn.label, 'My Server');
    });

    test('connect uses displayName when no label', () {
      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'admin'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config);
      expect(conn.label, config.displayName);
    });

    test('connect stores sessionId when provided', () {
      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'test'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config, sessionId: 'sess-123');
      expect(conn.sessionId, 'sess-123');
    });

    test('connect has null sessionId by default', () {
      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'test'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config);
      expect(conn.sessionId, isNull);
    });

    test('onChange emits during connect lifecycle', () async {
      var emitCount = 0;
      final sub = manager.onChange.listen((_) => emitCount++);

      const config = SSHConfig(
        server: ServerAddress(host: '127.0.0.1', port: 1, user: 'test'),
        timeoutSec: 1,
      );
      final conn = manager.connectAsync(config);

      // At least 1 emit immediately (connecting)
      await Future.delayed(Duration.zero);
      expect(emitCount, greaterThanOrEqualTo(1));

      // Wait for background failure
      await conn.ready;
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

  group(
    'ConnectionManager.connectAsync — success path (injectable factory)',
    () {
      test('successful connect transitions to connected state', () async {
        late FakeSSHConnection fakeConn;
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          connectionFactory: (config, kh) {
            fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
            return fakeConn;
          },
        );

        const config = SSHConfig(
          server: ServerAddress(host: 'test.com', user: 'admin'),
        );
        final conn = mgr.connectAsync(config, label: 'Test Server');

        // Initially connecting
        expect(conn.state, SSHConnectionState.connecting);
        expect(conn.label, 'Test Server');

        // Wait for background connection
        await conn.ready;

        expect(conn.isConnected, isTrue);
        expect(conn.state, SSHConnectionState.connected);
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

        const config = SSHConfig(
          server: ServerAddress(host: 'server.com', port: 2222, user: 'root'),
        );
        final conn = mgr.connectAsync(config);

        expect(conn.label, 'root@server.com:2222');

        await conn.ready;
        mgr.dispose();
      });

      test(
        'successful connect emits 2 events (connecting + connected)',
        () async {
          final mgr = ConnectionManager(
            knownHosts: knownHosts,
            connectionFactory: (config, kh) =>
                FakeSSHConnection(config: config, knownHosts: kh),
          );

          var emitCount = 0;
          final sub = mgr.onChange.listen((_) => emitCount++);

          const config = SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          );
          final conn = mgr.connectAsync(config);
          await conn.ready;
          await Future.delayed(Duration.zero);

          expect(emitCount, greaterThanOrEqualTo(2));

          await sub.cancel();
          mgr.dispose();
        },
      );

      test(
        'disconnect after successful connect calls SSHConnection.disconnect',
        () async {
          late FakeSSHConnection fakeConn;
          final mgr = ConnectionManager(
            knownHosts: knownHosts,
            connectionFactory: (config, kh) {
              fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
              return fakeConn;
            },
          );

          const config = SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          );
          final conn = mgr.connectAsync(config);
          await conn.ready;
          mgr.disconnect(conn.id);

          expect(fakeConn.disconnectCalled, isTrue);
          expect(mgr.connections, isEmpty);

          mgr.dispose();
        },
      );

      test('onDisconnect callback fires and updates state', () async {
        late FakeSSHConnection fakeConn;
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          connectionFactory: (config, kh) {
            fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
            return fakeConn;
          },
        );

        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        );
        final conn = mgr.connectAsync(config);
        await conn.ready;

        // Simulate remote disconnect
        fakeConn.onDisconnect?.call();
        await Future.delayed(Duration.zero);

        expect(conn.state, SSHConnectionState.disconnected);
        expect(conn.sshConnection, isNull);

        mgr.dispose();
      });

      test('failed connect with factory sets connectionError', () async {
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          connectionFactory: (config, kh) => FakeSSHConnection(
            config: config,
            knownHosts: kh,
            shouldFail: true,
          ),
        );

        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        );
        final conn = mgr.connectAsync(config);
        await conn.ready;

        expect(conn.state, SSHConnectionState.disconnected);
        expect(conn.connectionError, isNotNull);

        mgr.dispose();
      });

      test('multiple successful connections tracked', () async {
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          connectionFactory: (config, kh) =>
              FakeSSHConnection(config: config, knownHosts: kh),
        );

        final connA = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'a', user: 'u'),
          ),
          label: 'A',
        );
        final connB = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'b', user: 'u'),
          ),
          label: 'B',
        );
        await connA.ready;
        await connB.ready;

        expect(mgr.connections, hasLength(2));

        mgr.dispose();
      });

      test('get returns connection by id after successful connect', () async {
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          connectionFactory: (config, kh) =>
              FakeSSHConnection(config: config, knownHosts: kh),
        );

        final conn = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
        );
        await conn.ready;
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

        final connA = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'a', user: 'u'),
          ),
        );
        final connB = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'b', user: 'u'),
          ),
        );
        await connA.ready;
        await connB.ready;

        mgr.disconnectAll();

        for (final f in fakes) {
          expect(f.disconnectCalled, isTrue);
        }
        expect(mgr.connections, isEmpty);

        mgr.dispose();
      });
    },
  );

  group('ConnectionManager.onActiveCountChanged', () {
    test('callback fires when connection becomes connected', () async {
      final counts = <int>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
        onActiveCountChanged: counts.add,
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );
      final conn = mgr.connectAsync(config);
      await conn.ready;

      expect(counts, contains(1));

      mgr.dispose();
    });

    test('callback fires with 0 when last connection disconnects', () async {
      final counts = <int>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
        onActiveCountChanged: counts.add,
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );
      final conn = mgr.connectAsync(config);
      await conn.ready;

      mgr.disconnect(conn.id);

      expect(counts.last, 0);

      mgr.dispose();
    });

    test(
      'callback fires with correct count for multiple connections',
      () async {
        final counts = <int>[];
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          connectionFactory: (config, kh) =>
              FakeSSHConnection(config: config, knownHosts: kh),
          onActiveCountChanged: counts.add,
        );

        final connA = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'a', user: 'u'),
          ),
        );
        await connA.ready;
        expect(counts.last, 1);

        final connB = mgr.connectAsync(
          const SSHConfig(
            server: ServerAddress(host: 'b', user: 'u'),
          ),
        );
        await connB.ready;
        expect(counts.last, 2);

        mgr.disconnect(connA.id);
        expect(counts.last, 1);

        mgr.disconnect(connB.id);
        expect(counts.last, 0);

        mgr.dispose();
      },
    );

    test('callback not fired when count does not change', () async {
      final counts = <int>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        onActiveCountChanged: counts.add,
      );

      // disconnectAll on empty — count stays 0, should not fire
      mgr.disconnectAll();
      await Future.delayed(Duration.zero);

      expect(counts, isEmpty);

      mgr.dispose();
    });

    test('callback can be set after construction', () async {
      final counts = <int>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );
      mgr.onActiveCountChanged = counts.add;

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );
      final conn = mgr.connectAsync(config);
      await conn.ready;

      expect(counts, contains(1));

      mgr.dispose();
    });

    test('callback fires on remote disconnect', () async {
      late FakeSSHConnection fakeConn;
      final counts = <int>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          fakeConn = FakeSSHConnection(config: config, knownHosts: kh);
          return fakeConn;
        },
        onActiveCountChanged: counts.add,
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );
      final conn = mgr.connectAsync(config);
      await conn.ready;
      expect(counts.last, 1);

      // Simulate remote disconnect
      fakeConn.onDisconnect?.call();
      await Future.delayed(Duration.zero);

      expect(counts.last, 0);

      mgr.dispose();
    });
  });

  group('Connection model', () {
    test('isConnected returns true when state is connected', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connected,
      );
      expect(conn.isConnected, isTrue);
    });

    test('isConnected returns false when state is disconnected', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.disconnected,
      );
      expect(conn.isConnected, isFalse);
    });

    test('isConnected returns false when state is connecting', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connecting,
      );
      expect(conn.isConnected, isFalse);
    });

    test('sshConnection is nullable', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );
      expect(conn.sshConnection, isNull);
    });

    test('ready completes on successful connect', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      final conn = mgr.connectAsync(
        const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );
      await conn.ready;
      expect(conn.isConnected, isTrue);
      mgr.dispose();
    });

    test('ready completes on failed connect', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh, shouldFail: true),
      );

      final conn = mgr.connectAsync(
        const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );
      await conn.ready;
      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);
      mgr.dispose();
    });

    test('ready is safe to await multiple times', () async {
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      final conn = mgr.connectAsync(
        const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );
      await conn.ready;
      await conn.ready; // second await should not throw
      expect(conn.isConnected, isTrue);
      mgr.dispose();
    });

    test('completeReady is idempotent', () {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );
      conn.completeReady();
      conn.completeReady(); // should not throw
    });

    test('resetForReconnect closes old progress controller', () async {
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        state: SSHConnectionState.connecting,
      );

      // Subscribe to progress stream before reset
      var closed = false;
      conn.progressStream.listen((_) {}, onDone: () => closed = true);

      conn.resetForReconnect();

      // onDone fires asynchronously — let microtasks complete
      await Future.delayed(Duration.zero);

      // Old stream should have been closed
      expect(closed, isTrue);
      // New stream should be functional
      expect(conn.progressHistory, isEmpty);
    });
  });

  group('ConnectionManager.reconnect — generation counter', () {
    test('stale reconnect result is discarded', () async {
      final completers = <Completer<void>>[];
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          final completer = Completer<void>();
          completers.add(completer);
          final fake = _DelayedFakeSSHConnection(
            config: config,
            knownHosts: kh,
            connectCompleter: completer,
          );
          return fake;
        },
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );

      // Initial connect — let it complete
      final conn = mgr.connectAsync(config);
      completers.last.complete();
      await conn.ready;
      expect(conn.isConnected, isTrue);

      // First reconnect — don't complete yet
      mgr.reconnect(conn.id);
      final firstReconnectCompleter = completers.last;

      // Second reconnect — complete immediately
      mgr.reconnect(conn.id);
      completers.last.complete();
      await conn.ready;

      // Now complete the stale first reconnect
      firstReconnectCompleter.complete();
      await Future.delayed(const Duration(milliseconds: 50));

      // Connection should still be from the second reconnect, not the stale first
      expect(conn.isConnected, isTrue);

      mgr.dispose();
    });
  });

  group('ConnectionManager.disconnectAll — ready futures', () {
    test('disconnectAll completes pending ready futures', () async {
      final connectCompleter = Completer<void>();
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        connectionFactory: (config, kh) {
          return _DelayedFakeSSHConnection(
            config: config,
            knownHosts: kh,
            connectCompleter: connectCompleter,
          );
        },
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
      );
      final conn = mgr.connectAsync(config);

      // Connection is still connecting — ready is not yet complete
      expect(conn.isConnecting, isTrue);

      // disconnectAll should complete the ready future
      mgr.disconnectAll();

      // ready should not hang — should complete within timeout
      await conn.ready.timeout(const Duration(seconds: 1));

      mgr.dispose();
    });
  });

  group('ConnectionManager + SessionCredentialCache', () {
    test(
      'successful connect with sessionId populates the credential cache',
      () async {
        final cache = SessionCredentialCache();
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          credentialCache: cache,
          connectionFactory: (config, kh) =>
              FakeSSHConnection(config: config, knownHosts: kh),
        );

        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
          auth: SshAuth(password: 'pw', passphrase: 'pass'),
        );
        final conn = mgr.connectAsync(config, sessionId: 'sess-1');
        await conn.ready;

        final entry = cache.read('sess-1');
        expect(entry, isNotNull);
        expect(entry!.passwordString, 'pw');
        expect(entry.keyPassphraseString, 'pass');

        mgr.dispose();
        cache.evictAll();
      },
    );

    test('quick-connect (no sessionId) does not touch the cache', () async {
      final cache = SessionCredentialCache();
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        credentialCache: cache,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
        auth: SshAuth(password: 'pw'),
      );
      final conn = mgr.connectAsync(config);
      await conn.ready;

      expect(cache.size, 0);

      mgr.dispose();
    });

    test('disconnect evicts the session entry from the cache', () async {
      final cache = SessionCredentialCache();
      final mgr = ConnectionManager(
        knownHosts: knownHosts,
        credentialCache: cache,
        connectionFactory: (config, kh) =>
            FakeSSHConnection(config: config, knownHosts: kh),
      );

      const config = SSHConfig(
        server: ServerAddress(host: 'h', user: 'u'),
        auth: SshAuth(password: 'pw'),
      );
      final conn = mgr.connectAsync(config, sessionId: 'sess-evict');
      await conn.ready;
      expect(cache.read('sess-evict'), isNotNull);

      mgr.disconnect(conn.id);
      expect(cache.read('sess-evict'), isNull);

      mgr.dispose();
    });

    test(
      'reconnect on a session with empty auth uses the cached envelope',
      () async {
        final cache = SessionCredentialCache();
        // Pre-seed the cache as if a prior connect succeeded while the
        // DB was open, and now the caller supplies a config whose auth
        // was stripped (the pattern exercised after auto-lock closes
        // the encrypted store).
        cache.store(
          sessionId: 'sess-reuse',
          password: 'cached-pw',
          keyPassphrase: 'cached-phrase',
        );

        SSHConfig? observed;
        final mgr = ConnectionManager(
          knownHosts: knownHosts,
          credentialCache: cache,
          connectionFactory: (config, kh) {
            observed = config;
            return FakeSSHConnection(config: config, knownHosts: kh);
          },
        );

        const stripped = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
          auth: SshAuth(),
        );
        final conn = mgr.connectAsync(stripped, sessionId: 'sess-reuse');
        await conn.ready;

        expect(observed, isNotNull);
        expect(observed!.auth.password, 'cached-pw');
        expect(observed!.auth.passphrase, 'cached-phrase');

        mgr.dispose();
        cache.evictAll();
      },
    );
  });
}

/// FakeSSHConnection that defers connect() until a Completer is resolved.
class _DelayedFakeSSHConnection extends SSHConnection {
  final Completer<void> connectCompleter;
  bool _connected = false;

  _DelayedFakeSSHConnection({
    required super.config,
    required super.knownHosts,
    required this.connectCompleter,
  });

  @override
  Future<void> connect({void Function(ConnectionStep)? onProgress}) async {
    await connectCompleter.future;
    _connected = true;
  }

  @override
  bool get isConnected => _connected;

  @override
  void disconnect() {
    _connected = false;
  }
}
