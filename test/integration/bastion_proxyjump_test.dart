/// ProxyJump / bastion-routed connection integration tests.
///
/// Production behaviour: a target connection can pin a bastion
/// `Connection`; the Rust connect actor for the target waits for
/// the bastion to reach `Connected`, grabs its live `Arc<Session>`,
/// and routes the child handshake through `connect_*_via_proxy_*`.
/// `ConnectionsNotifier.disconnect` cascade-tears-down the bastion
/// when the child disconnects (the bastion is pinned to the child's
/// lifetime, not user-visible).
///
/// Two fixtures stand in for the bastion and target SSH endpoints —
/// the russh fixture binds 127.0.0.1:0 so two of them coexist on
/// disjoint ports.
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

  late rust_test.TestSshServerInfo bastionServer;
  late rust_test.TestSshServerInfo targetServer;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);

    // The fixture's `test_ssh_server_start` keeps a single-instance
    // slot — repeated calls stop the previous server. We can't use
    // it for two simultaneous endpoints. The shape of the work is
    // small enough to bypass: start one, snapshot its info, start
    // a second, snapshot. Both servers stay alive because each
    // start() spawns a fresh tokio task on the runtime; only the
    // FRB-side handle slot tracks the most recent. The earlier
    // server's accept loop keeps running until shutdown is
    // explicitly broadcast — and we never broadcast it for the
    // earlier one in this test, so both ports stay open.
    bastionServer = await rust_test.testSshServerStart();
    targetServer = await rust_test.testSshServerStart();

    // Pre-seed both host keys so the connect actor's HostKeyVerify
    // phase finds a match without prompting.
    await rust_db.dbKnownHostsUpsertByHostPort(
      host: '127.0.0.1',
      port: bastionServer.port,
      keyType: bastionServer.hostPubkeyAlgorithm,
      keyBase64: bastionServer.hostPubkeyB64,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await rust_db.dbKnownHostsUpsertByHostPort(
      host: '127.0.0.1',
      port: targetServer.port,
      keyType: targetServer.hostPubkeyAlgorithm,
      keyBase64: targetServer.hostPubkeyB64,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  });

  tearDownAll(() async {
    rust_test.testSshServerStopAll();
    await rust_app.dbClose();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('ProxyJump bastion lifecycle', () {
    test(
      'connect through a bastion: both reach Connected, target.bastion is wired',
      () async {
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);

        final bastion = notifier.connectAsync(
          SSHConfig(
            server: ServerAddress(
              host: '127.0.0.1',
              port: bastionServer.port,
              user: 'u',
            ),
            auth: SshAuth(password: bastionServer.password),
          ),
          label: 'bastion',
          internal: true,
        );
        await bastion.waitUntilReady();
        await bastion.transportReady;
        expect(bastion.state, SSHConnectionState.connected);

        final target = notifier.connectAsync(
          SSHConfig(
            server: ServerAddress(
              host: '127.0.0.1',
              port: targetServer.port,
              user: 'u',
            ),
            auth: SshAuth(password: targetServer.password),
          ),
          label: 'target',
          bastion: bastion,
        );
        await target.waitUntilReady();
        await target.transportReady;

        expect(target.state, SSHConnectionState.connected);
        expect(target.bastion, bastion);
        expect(target.connectionError, isNull);

        // Internal bastion stays out of the user-visible list.
        expect(notifier.connections, [target]);

        notifier.disconnect(target.id);
      },
    );

    test(
      'disconnecting the target cascades the pinned bastion teardown',
      () async {
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);

        final bastion = notifier.connectAsync(
          SSHConfig(
            server: ServerAddress(
              host: '127.0.0.1',
              port: bastionServer.port,
              user: 'u',
            ),
            auth: SshAuth(password: bastionServer.password),
          ),
          label: 'bastion-cascade',
          internal: true,
        );
        await bastion.waitUntilReady();
        await bastion.transportReady;

        final target = notifier.connectAsync(
          SSHConfig(
            server: ServerAddress(
              host: '127.0.0.1',
              port: targetServer.port,
              user: 'u',
            ),
            auth: SshAuth(password: targetServer.password),
          ),
          label: 'target-cascade',
          bastion: bastion,
        );
        await target.waitUntilReady();
        await target.transportReady;

        notifier.disconnect(target.id);

        // The cascade is synchronous in `_doConnect` — by the time
        // `disconnect(target)` returns, `disconnect(bastion)` has
        // also been invoked. Both ids are gone from the user-visible
        // list immediately.
        expect(notifier.get(target.id), isNull);
        expect(notifier.get(bastion.id), isNull);
        expect(notifier.connections, isEmpty);
      },
    );
  });
}
