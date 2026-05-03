/// Known-hosts TOFU prompt-flow integration tests.
///
/// These exercise the round-trip the production app drives via
/// `lib/app/host_key_prompt_listener.dart`: the Rust connect actor
/// publishes `BusEvent::KnownHostPromptRequest` when an offered
/// host key is Unknown / Changed, the Dart side surfaces a dialog,
/// the user's choice goes back through `BusCommand::
/// KnownHostPromptResponse`, and the actor either proceeds or fails
/// HostKeyVerify accordingly. The unit-test layer never exercises
/// this round-trip — it requires a real handshake against a real
/// server publishing real host-key events.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/bus/app_bus.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
    serverInfo = await rust_test.testSshServerStart();
  });

  tearDownAll(() async {
    rust_test.testSshServerStop();
    await rust_app.dbClose();
  });

  /// Wipe known_hosts between tests so each one starts from a known
  /// state — the Unknown / Changed branch depends on what's already
  /// in the table.
  setUp(() async {
    await rust_db.dbKnownHostsClearAll();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  SSHConfig configFor(String password) => SSHConfig(
    server: ServerAddress(host: '127.0.0.1', port: serverInfo.port, user: 'u'),
    auth: SshAuth(password: password),
  );

  /// Spawn an auto-responder that handles the next
  /// [BusEvent_KnownHostPromptRequest] for [host:port] by replying
  /// `accepted` and then unsubscribes. Mirrors the production flow
  /// in `lib/app/host_key_prompt_listener.dart` minus the dialog.
  StreamSubscription<BusEvent> autoRespondToPrompt({
    required String host,
    required int port,
    required bool accepted,
    Completer<rust_bus.BusKnownHostPromptKind>? observedKind,
  }) {
    late StreamSubscription<rust_bus.BusEvent> sub;
    sub = AppBus.instance.subscribe(rust_bus.BusTopic.knownHosts).listen((
      event,
    ) {
      if (event is rust_bus.BusEvent_KnownHostPromptRequest &&
          event.host == host &&
          event.port == port) {
        observedKind?.complete(event.kind);
        AppBus.instance.dispatch(
          rust_bus.BusCommand.knownHostPromptResponse(
            promptId: event.promptId,
            accepted: accepted,
          ),
        );
        sub.cancel();
      }
    });
    return sub;
  }

  group('Known-hosts TOFU prompt flow', () {
    test(
      'Unknown host: prompt fires, accept proceeds, row lands in known_hosts',
      () async {
        final kindObs = Completer<rust_bus.BusKnownHostPromptKind>();
        final responder = autoRespondToPrompt(
          host: '127.0.0.1',
          port: serverInfo.port,
          accepted: true,
          observedKind: kindObs,
        );
        addTearDown(responder.cancel);

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(serverInfo.password),
          label: 'tofu-accept',
        );
        await conn.waitUntilReady();
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.connected);
        // Confirm the prompt actually fired with `NewHost` kind —
        // a regression that swallowed the Unknown classification
        // would still let the connect succeed via the Accept
        // response, but the kind would not match.
        final kind = await kindObs.future.timeout(const Duration(seconds: 1));
        expect(kind, rust_bus.BusKnownHostPromptKind.newHost);

        // The actor accepts → row should land in `known_hosts` so a
        // reconnect would skip the prompt entirely.
        final row = await rust_db.dbKnownHostsGetByHostPort(
          host: '127.0.0.1',
          port: serverInfo.port,
        );
        expect(row, isNotNull);
        expect(row!.keyBase64, serverInfo.hostPubkeyB64);

        notifier.disconnect(conn.id);
      },
    );

    test('Unknown host: prompt fires, reject fails HostKeyVerify', () async {
      final responder = autoRespondToPrompt(
        host: '127.0.0.1',
        port: serverInfo.port,
        accepted: false,
      );
      addTearDown(responder.cancel);

      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        configFor(serverInfo.password),
        label: 'tofu-reject',
      );
      await conn.waitUntilReady().timeout(const Duration(seconds: 10));
      await conn.transportReady;

      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);
      // `known_hosts` must remain empty on rejection — accepting
      // and persisting only happens for `accepted: true`.
      final row = await rust_db.dbKnownHostsGetByHostPort(
        host: '127.0.0.1',
        port: serverInfo.port,
      );
      expect(row, isNull);

      notifier.disconnect(conn.id);
    });

    test(
      'Key changed: pre-seeded wrong key surfaces a `KeyChanged` prompt',
      () async {
        // Seed a fake key that does NOT match the fixture's
        // generated host key. The actor should detect the mismatch
        // and publish `KnownHostPromptRequest` with the
        // `KeyChanged` kind.
        await rust_db.dbKnownHostsUpsertByHostPort(
          host: '127.0.0.1',
          port: serverInfo.port,
          keyType: serverInfo.hostPubkeyAlgorithm,
          keyBase64: 'AAAAAAAAfakekeyfakekeyfakekey',
          addedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

        final kindObs = Completer<rust_bus.BusKnownHostPromptKind>();
        final responder = autoRespondToPrompt(
          host: '127.0.0.1',
          port: serverInfo.port,
          accepted: true,
          observedKind: kindObs,
        );
        addTearDown(responder.cancel);

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(serverInfo.password),
          label: 'tofu-key-changed',
        );
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));
        await conn.transportReady;

        expect(
          await kindObs.future.timeout(const Duration(seconds: 1)),
          rust_bus.BusKnownHostPromptKind.keyChanged,
        );
        expect(conn.state, SSHConnectionState.connected);

        // Accept-on-key-changed must overwrite the stored key with
        // the actually-offered one — otherwise the next reconnect
        // would re-prompt forever.
        final row = await rust_db.dbKnownHostsGetByHostPort(
          host: '127.0.0.1',
          port: serverInfo.port,
        );
        expect(row, isNotNull);
        expect(row!.keyBase64, serverInfo.hostPubkeyB64);

        notifier.disconnect(conn.id);
      },
    );
  });
}
