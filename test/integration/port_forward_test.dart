/// Port-forward (-L / -R / -D) integration coverage against the
/// russh fixture.
///
/// All three primitives end up funnelling bytes through the same
/// underlying SSH `direct-tcpip` (or `forwarded-tcpip` for `-R`)
/// channel + a TCP socket on either end. The shape of each test:
///
///   `-L` local-forward
///     Dart TCP client (`bindPort`)
///       → Rust local-forward accept loop
///       → SSH `direct-tcpip` channel through the fixture
///       → fixture's `channel_open_direct_tcpip` (loopback only)
///       → Dart TCP echo server (`targetPort`)
///
///   `-R` remote-forward
///     Dart TCP client (server-side bound port)
///       → fixture's `tcpip_forward` accept loop
///       → SSH `forwarded-tcpip` channel back to the client
///       → Rust `RemoteForwardHandle` bridge task
///       → Dart TCP echo server (local `targetPort`)
///
///   `-D` dynamic / SOCKS5
///     Dart SOCKS5 client (CONNECT 127.0.0.1:targetPort)
///       → Rust SOCKS5 listener (`spawn_socks5_listener`)
///       → SSH `direct-tcpip` channel through the fixture
///       → fixture's `channel_open_direct_tcpip` (loopback only)
///       → Dart TCP echo server (`targetPort`)
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

  group('Port forward (-R remote)', () {
    test('bytes round-trip through the remote-forward tunnel', () async {
      // Dart-side echo server: the Rust client-side bridge in
      // `RemoteForwardHandle` opens a fresh TCP connection here
      // for every inbound `forwarded-tcpip` channel.
      final echoServer = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(echoServer.close);
      echoServer.listen((socket) {
        socket.addStream(socket).then((_) async {
          await socket.flush();
          await socket.close();
        }, onError: (Object _) {});
      });
      final targetPort = echoServer.port;

      // Ask the server (fixture) to bind a fresh OS-assigned port
      // and forward inbound TCP back through the SSH session. The
      // fixture's `tcpip_forward` mutates *port to the actually-
      // bound port, russh ships that back, and `start_remote`
      // returns it to us as `boundPort`.
      const ruleId = 'port-forward-test-remote';
      final boundPort = await rust_fwd.portForwardStartRemote(
        ruleId: ruleId,
        connectionId: conn.id,
        bindHost: '127.0.0.1',
        bindPort: 0,
        targetHost: '127.0.0.1',
        targetPort: targetPort,
      );
      expect(boundPort, isPositive);
      addTearDown(() async {
        await rust_fwd.portForwardStopRemote(ruleId: ruleId);
      });

      // The fixture's accept loop runs in its own tokio task —
      // give it a microtask to start before we connect.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Connect to the server-side bound port. Same process here
      // (the fixture is in-proc), so 127.0.0.1:boundPort is the
      // listener `tcpip_forward` opened.
      final client = await Socket.connect('127.0.0.1', boundPort);
      const payload = 'lfs-port-forward-remote-roundtrip\n';
      client.write(payload);
      await client.flush();
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

    test('portForwardStopRemote releases the server-side listener', () async {
      // Stand up + tear down without any inbound connection. Post-
      // stop, connecting to `boundPort` must fail because the
      // fixture's `cancel_tcpip_forward` aborts the listener task,
      // which drops the `TcpListener` and frees the OS port.
      const ruleId = 'port-forward-test-remote-teardown';
      final boundPort = await rust_fwd.portForwardStartRemote(
        ruleId: ruleId,
        connectionId: conn.id,
        bindHost: '127.0.0.1',
        bindPort: 0,
        targetHost: '127.0.0.1',
        // Target port is irrelevant — we never let an inbound
        // connection reach the bridge.
        targetPort: 1,
      );
      expect(boundPort, isPositive);

      final stopped = await rust_fwd.portForwardStopRemote(ruleId: ruleId);
      expect(stopped, isTrue);

      // Give the cancel round-trip + OS port release a tick.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await expectLater(
        Socket.connect(
          '127.0.0.1',
          boundPort,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('Port forward (-D dynamic / SOCKS5)', () {
    test('CONNECT round-trips through the SOCKS5 listener', () async {
      // The same fixture-side `channel_open_direct_tcpip` handler
      // -L exercises is what -D ends up driving once the SOCKS5
      // CONNECT handshake resolves to a `direct-tcpip` open.
      final echoServer = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(echoServer.close);
      echoServer.listen((socket) {
        socket.addStream(socket).then((_) async {
          await socket.flush();
          await socket.close();
        }, onError: (Object _) {});
      });
      final targetPort = echoServer.port;

      const ruleId = 'port-forward-test-socks5';
      final boundPort = await rust_fwd.portForwardStartDynamic(
        ruleId: ruleId,
        connectionId: conn.id,
        bindHost: '127.0.0.1',
        bindPort: 0,
      );
      expect(boundPort, isPositive);
      addTearDown(() async {
        await rust_fwd.portForwardStopDynamic(ruleId: ruleId);
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Dart-side SOCKS5 client speaking just enough RFC 1928 to
      // negotiate NO_AUTH and CONNECT to 127.0.0.1:targetPort.
      // The Rust listener's reply BND.* fields are zero — clients
      // ignore them for CONNECT-over-SSH, so we only validate the
      // status byte.
      final socks = await Socket.connect('127.0.0.1', boundPort);
      // Greeting: VER=0x05, NMETHODS=1, METHOD=NO_AUTH(0x00).
      socks.add(<int>[0x05, 0x01, 0x00]);
      await socks.flush();

      final reader = StreamIterator<List<int>>(socks);
      final greetReply = await _readExact(reader, 2);
      expect(greetReply[0], 0x05);
      expect(greetReply[1], 0x00, reason: 'NO_AUTH must be selected');

      // CONNECT request: VER=0x05, CMD=CONNECT, RSV, ATYP=IPv4,
      // 127.0.0.1, port (big-endian).
      socks.add(<int>[
        0x05,
        0x01,
        0x00,
        0x01,
        127,
        0,
        0,
        1,
        (targetPort >> 8) & 0xff,
        targetPort & 0xff,
      ]);
      await socks.flush();

      // Reply: 10 bytes for IPv4 BND. Last 6 are BND.ADDR + BND.PORT.
      final connectReply = await _readExact(reader, 10);
      expect(connectReply[0], 0x05);
      expect(
        connectReply[1],
        0x00,
        reason:
            'CONNECT must succeed (REP=0x00); fixture rejects '
            'non-loopback only — target is 127.0.0.1',
      );

      // Past this point the socket is a transparent byte pipe.
      const payload = 'lfs-port-forward-dynamic-roundtrip\n';
      socks.add(payload.codeUnits);
      await socks.flush();

      // Drain the rest of the stream until we see the echoed
      // payload — every byte after the 10-byte SOCKS5 reply is
      // fixture-side echo.
      final received = <int>[];
      while (await reader.moveNext()) {
        received.addAll(reader.current);
        if (String.fromCharCodes(received).contains(payload)) break;
      }
      await socks.close();

      expect(String.fromCharCodes(received), payload);
    });
  });
}

/// Read exactly `n` bytes from a [StreamIterator] of byte chunks.
/// SOCKS5 control frames are small + fixed-width — the iterator
/// adapter avoids the multi-event listen plumbing the -L test uses
/// and keeps the assertion code linear.
Future<List<int>> _readExact(StreamIterator<List<int>> reader, int n) async {
  final buf = <int>[];
  while (buf.length < n) {
    if (!await reader.moveNext()) {
      throw StateError('socks5 reply: stream closed before $n bytes');
    }
    buf.addAll(reader.current);
  }
  // If the iterator delivered more than we asked for, the spillover
  // belongs to the next read — but SOCKS5 control frames are tiny
  // and arrive on their own packet here, so we just trim.
  return buf.sublist(0, n);
}
