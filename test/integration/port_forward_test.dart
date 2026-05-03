/// Local-forward (-L) integration test against the russh fixture.
///
/// Wires a real SSH local-forward listener on the Rust side, asks
/// it to tunnel `bindPort` → `127.0.0.1:targetPort` through the
/// SSH transport, and asserts bytes round-trip through:
///
///   Dart TCP client (`bindPort`)
///     → Rust local-forward accept loop
///     → SSH `direct-tcpip` channel through the fixture
///     → fixture's `channel_open_direct_tcpip` handler (proxies
///       loopback hosts only — see `test_server.rs`)
///     → Dart TCP echo server (`targetPort`)
///
/// Remote-forward (-R) and dynamic-forward (-D / SOCKS5) are not
/// covered: -R requires the fixture to implement `tcpip_forward`
/// + accept inbound TCP and forward bytes to the client side,
/// and SOCKS5 stacks another protocol on top of the same
/// underlying tunnel that local-forward already exercises here.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/forward.dart' as rust_fwd;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;
  late ProviderContainer container;
  late Connection conn;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);

    serverInfo = await rust_test.testSshServerStart();
    await rust_db.dbKnownHostsUpsertByHostPort(
      host: '127.0.0.1',
      port: serverInfo.port,
      keyType: serverInfo.hostPubkeyAlgorithm,
      keyBase64: serverInfo.hostPubkeyB64,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    container = ProviderContainer();
    final notifier = container.read(connectionsProvider.notifier);
    conn = notifier.connectAsync(
      SSHConfig(
        server: ServerAddress(
          host: '127.0.0.1',
          port: serverInfo.port,
          user: 'u',
        ),
        auth: SshAuth(password: serverInfo.password),
      ),
      label: 'forward-test',
    );
    await conn.waitUntilReady();
    await conn.transportReady;
    expect(conn.state, SSHConnectionState.connected);
  });

  tearDownAll(() async {
    container.read(connectionsProvider.notifier).disconnect(conn.id);
    container.dispose();
    rust_test.testSshServerStopAll();
    await rust_app.dbClose();
  });

  group('Port forward (-L local)', () {
    test('bytes round-trip through the local-forward tunnel', () async {
      // 1. Stand up a tiny Dart-side TCP echo server. Bytes
      //    received → bytes echoed verbatim. This is the "target"
      //    the fixture's `channel_open_direct_tcpip` proxies the
      //    SSH channel onto.
      final echoServer = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(echoServer.close);
      final echoFutures = <Future<void>>[];
      echoServer.listen((socket) {
        echoFutures.add(() async {
          try {
            await socket.addStream(socket);
            await socket.flush();
            await socket.close();
          } catch (_) {}
        }());
      });
      final targetPort = echoServer.port;

      // 2. Pick a free bind port on the local side. `port: 0` tells
      //    the OS to assign one; we read it back so the test can
      //    connect to it.
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final bindPort = probe.port;
      await probe.close();

      // 3. Ask the Rust core to spin up the local-forward listener
      //    on `bindPort`, tunnelling to `127.0.0.1:targetPort`
      //    through `conn`'s SSH transport. The returned int is the
      //    actually-bound port (handy if we passed 0 above; we
      //    already know our value, so just sanity-check).
      const ruleId = 'port-forward-test-local';
      final boundPort = await rust_fwd.portForwardStartLocal(
        ruleId: ruleId,
        connectionId: conn.id,
        bindHost: '127.0.0.1',
        bindPort: bindPort,
        targetHost: '127.0.0.1',
        targetPort: targetPort,
      );
      expect(boundPort, bindPort);
      addTearDown(() async {
        await rust_fwd.portForwardStopLocal(ruleId: ruleId);
      });

      // The Rust accept loop runs in its own tokio task — give it
      // a microtask to start before we connect. Localhost so this
      // is fast.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 4. Open a Dart TCP socket to `bindPort`, send a payload,
      //    read the echo back, assert it matches.
      final client = await Socket.connect('127.0.0.1', bindPort);
      const payload = 'lfs-port-forward-roundtrip\n';
      client.write(payload);
      await client.flush();
      // Drain bytes until we see the full payload echoed (the
      // server keeps the channel open until our side closes — we
      // close after we've confirmed the round-trip).
      final received = <int>[];
      late StreamSubscription<List<int>> sub;
      final done = Completer<void>();
      sub = client.listen(
        (chunk) {
          received.addAll(chunk);
          if (String.fromCharCodes(received).contains(payload)) {
            sub.cancel();
            if (!done.isCompleted) done.complete();
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 10));
      await client.close();

      expect(String.fromCharCodes(received), payload);
    });

    test('portForwardStopLocal tears the listener down', () async {
      // After a stop, connecting to the bind port should fail with
      // `connection refused` — the Rust accept loop has been
      // aborted and the OS released the port.
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final bindPort = probe.port;
      await probe.close();

      const ruleId = 'port-forward-test-teardown';
      await rust_fwd.portForwardStartLocal(
        ruleId: ruleId,
        connectionId: conn.id,
        bindHost: '127.0.0.1',
        bindPort: bindPort,
        targetHost: '127.0.0.1',
        // Target port doesn't matter — we tear down before any
        // client connects through.
        targetPort: 1,
      );
      final stopped = await rust_fwd.portForwardStopLocal(ruleId: ruleId);
      expect(stopped, isTrue);

      // Give the OS a tick to actually release the port.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await expectLater(
        Socket.connect(
          '127.0.0.1',
          bindPort,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
