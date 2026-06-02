/// Regression net for the proactive transport-death detection.
///
/// Why this exists: when a host sleeps with an active SSH session the
/// socket dies but nothing calls `disconnect`, so the actor used to
/// stay `Connected` over a corpse — the next channel open then
/// surfaced a raw `channel closed` to the user. `run_transport_monitor`
/// (Rust) now polls the russh handle and flips the actor to
/// `Disconnected` on its own. This test drives the real handshake
/// against the in-process fixture, then kills the server's established
/// session WITHOUT a client-side disconnect, and asserts the connection
/// flips to disconnected proactively — the boundary a static check
/// can't see (Rust actor → monitor task → FRB worker → Dart microtask).
///
/// Lives in its own file because the assertion needs
/// `testSshServerStopAll` to tear the live session down mid-test;
/// `flutter test` runs each file in its own isolate, so that does not
/// disturb the other integration suites' shared fixtures.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;

  setUpAll(() async {
    await requireFrbLoaded();
    // The connect path routes through `connection_prepare_auth → run_db`
    // and the known_hosts pre-seed needs a live handle. In-memory keeps
    // it deterministic with no on-disk state to clean up.
    await rust_app.dbInit(path: ':memory:', key: const []);

    serverInfo = await rust_test.testSshServerStart();
    // Pre-seed the host key so HostKeyVerify returns Accepted without a
    // prompt (no Dart listener answers one in this test process).
    await rust_db.dbKnownHostsUpsertByHostPort(
      host: '127.0.0.1',
      port: serverInfo.port,
      keyType: serverInfo.hostPubkeyAlgorithm,
      keyBase64: serverInfo.hostPubkeyB64,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  });

  tearDownAll(() async {
    rust_test.testSshServerStopAll();
    await rust_app.dbClose();
  });

  test(
    'a transport dying without teardown flips the connected session to disconnected',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(connectionsProvider.notifier);

      final conn = notifier.connectAsync(
        SSHConfig(
          server: ServerAddress(
            host: '127.0.0.1',
            port: serverInfo.port,
            user: 'u',
          ),
          auth: SshAuth(password: serverInfo.password),
        ),
        label: 'transport-death',
      );

      await _waitForState(
        conn,
        SSHConnectionState.connected,
        const Duration(seconds: 10),
      );
      expect(conn.state, SSHConnectionState.connected);
      await conn.transportReady;

      // Kill the server's established session WITHOUT a client-side
      // disconnect — the sleeping-laptop case. The russh client loop
      // sees the dropped socket, its handle closes, and the Rust
      // transport monitor must flip the actor to disconnected within
      // its poll interval.
      rust_test.testSshServerStopAll();

      await _waitForState(
        conn,
        SSHConnectionState.disconnected,
        const Duration(seconds: 15),
      );
      expect(
        conn.state,
        SSHConnectionState.disconnected,
        reason:
            'A silently-dead transport must be detected proactively by the '
            'connection monitor, not left Connected over a corpse until the '
            'next channel open fails with a raw `channel closed`.',
      );
      // No teardown was issued — the flip came from the monitor, and a
      // dropped session leaves no live transport behind.
      expect(conn.transport, isNull);
    },
  );
}

/// Poll the observable connection state until it reaches [target] or
/// [timeout] elapses. `connectionsProvider` has no per-`Connection`
/// state stream, so polling on event-loop turns (each `await` yields
/// so the FRB bus events drain) is the established pattern here.
Future<void> _waitForState(
  Connection conn,
  SSHConnectionState target,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (conn.state != target) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Connection state did not reach $target within $timeout '
        '(still ${conn.state}).',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
