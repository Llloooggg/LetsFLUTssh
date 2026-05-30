/// Auth-composition + connect-branch tests against the in-process
/// russh fixture, focused on the arms `connection_lifecycle_test.dart`
/// and `session_connect_end_to_end_test.dart` leave uncovered in
/// `connections_notifier_auth.dart`:
///
///   * the `DbPreparedAuthRef_Pubkey` arm of `_authFromConfig` —
///     quick-connect with inline private-key PEM (`keyData`), staged
///     into the SecretStore Rust-side and handed to the russh driver
///     as a `SshAuthPubkeyRef`.
///   * the `DbPreparedAuthRef_Password` arm via quick-connect (no
///     `sessionId`) — the composer's quick-connect fallback walk.
///   * the empty-auth `hardware-key prompt skipped (FRB / no navigator)`
///     short-circuit in `_resolveHardwareKeyPin` (keyId empty → null).
///
/// The fixture's `auth_publickey` accepts ANY public key (it asserts
/// the auth phase wires up, not a cryptographic identity), so a freshly
/// generated ed25519 key drives the pubkey arm end-to-end. A real
/// handshake is the only thing that proves the composed
/// `SshAuthPubkeyRef` actually reaches the russh client and the auth
/// phase flips to success — a mock would assert the Dart switch arm and
/// nothing past it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/keys.dart' as rust_keys;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;

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

  ServerAddress address() =>
      ServerAddress(host: '127.0.0.1', port: serverInfo.port, user: 'u');

  group('connections_notifier_auth — quick-connect pubkey arm', () {
    test(
      'inline ed25519 keyData composes a pubkey ref and authenticates',
      () async {
        // Generate a real unencrypted ed25519 key so the composer's
        // `DbPrepareAuthInput.keyData` path stages the private PEM into
        // the SecretStore and routes through `DbPreparedAuthRef_Pubkey`
        // → `SshAuthPubkeyRef`. The fixture accepts any pubkey, so a
        // clean auth-phase success here proves the composed ref reached
        // the russh client and was offered.
        final key = await rust_keys.keysGenerateEd25519(comment: 'lfs-test');
        expect(key.privatePem, contains('PRIVATE KEY'));

        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          SSHConfig(
            server: address(),
            // No sessionId, no keyId — the pure inline-keyData
            // quick-connect path. Empty keyId also exercises the
            // `_resolveHardwareKeyPin` empty-keyId short-circuit
            // (returns null before any DB read).
            auth: SshAuth(keyData: key.privatePem),
          ),
          label: 'pubkey-quick',
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.connected);
        expect(conn.connectionError, isNull);
        final authOk = conn.progressHistory.any(
          (s) =>
              s.phase == ConnectionPhase.authenticate &&
              s.status == StepStatus.success,
        );
        expect(
          authOk,
          isTrue,
          reason:
              'The composed SshAuthPubkeyRef must drive the authenticate '
              'phase to success — a failure here means the inline keyData '
              'never reached the russh client as a usable pubkey offer.',
        );

        notifier.disconnect(conn.id);
      },
    );

    test('a malformed inline private key fails the connect cleanly', () async {
      // The composer must reject a non-PEM `keyData` rather than hang
      // — the connect settles into `disconnected` with an error, not a
      // wedged `connecting`. (The fixture never sees a pubkey offer
      // because the key never parses Dart/Rust-side.)
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        SSHConfig(
          server: address(),
          auth: const SshAuth(keyData: 'not-a-real-private-key'),
        ),
        label: 'pubkey-malformed',
      );

      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      await conn.transportReady;

      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);

      notifier.disconnect(conn.id);
    });
  });

  group('connections_notifier_auth — quick-connect password arm', () {
    test(
      'quick-connect password composes a password ref and authenticates',
      () async {
        // No sessionId → the composer takes the quick-connect fallback
        // walk (no saved-session columns to read) and stages the
        // password bytes, returning `DbPreparedAuthRef_Password` →
        // `SshAuthPasswordRef`. Distinct from
        // `session_connect_end_to_end_test.dart`, which drives the
        // SAVED-session column read path.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          SSHConfig(
            server: address(),
            auth: SshAuth(password: serverInfo.password),
          ),
          label: 'password-quick',
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.connected);
        expect(conn.transport, isNotNull);
        final authOk = conn.progressHistory.any(
          (s) =>
              s.phase == ConnectionPhase.authenticate &&
              s.status == StepStatus.success,
        );
        expect(authOk, isTrue);

        notifier.disconnect(conn.id);
      },
    );

    test(
      'transient secrets are evicted by the time the connect settles',
      () async {
        // `_authFromConfig` records every SecretStore id the composer
        // staged into `conn.transientSecretIds`; `_evictTransientSecrets`
        // drops them (and clears the set) the moment the Connected bus
        // event lands, before `transportReady` resolves. Awaiting the
        // gate and finding the set empty proves the staged per-attempt
        // password secret was cleaned up rather than leaked across the
        // connection's lifetime.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          SSHConfig(
            server: address(),
            auth: SshAuth(password: serverInfo.password),
          ),
          label: 'transient-ids',
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.connected);
        // Quick-connect carries no stable session id — proves the
        // composer took the quick-connect fallback walk, not the
        // saved-session column read exercised elsewhere.
        expect(conn.sessionId, isNull);
        expect(
          conn.transientSecretIds,
          isEmpty,
          reason:
              'Per-attempt secrets must be evicted once the connect '
              'settles so they do not outlive the attempt.',
        );

        notifier.disconnect(conn.id);
      },
    );

    test('a wrong password settles into disconnected with an error', () async {
      // Negative quick-connect path — `_authFromConfig` still composes
      // `DbPreparedAuthRef_Password` → `SshAuthPasswordRef`, but the
      // fixture's `auth_password` handler rejects it and the
      // connection's bus listener flips state to disconnected with
      // a non-null `connectionError`. Covers the quick-connect arm's
      // failure path independent of the saved-session test in
      // `session_connect_end_to_end_test.dart`.
      final container = makeContainer();
      final notifier = container.read(connectionsProvider.notifier);
      final conn = notifier.connectAsync(
        SSHConfig(
          server: address(),
          auth: const SshAuth(password: 'wrong-password'),
        ),
        label: 'password-wrong',
      );

      await conn.waitUntilReady().timeout(const Duration(seconds: 15));
      await conn.transportReady;

      expect(conn.state, SSHConnectionState.disconnected);
      expect(conn.connectionError, isNotNull);

      notifier.disconnect(conn.id);
    });
  });

  group('connections_notifier_auth — agent short-circuit', () {
    test(
      'useAgent skips the composer and the connect attempt settles',
      () async {
        // Contract — `_authFromConfig` short-circuits on `auth.useAgent`
        // BEFORE calling `connectionPrepareAuth`, returning
        // `const SshAuthAgent()` directly. The russh fixture has no
        // matching agent socket so the auth phase fails; what's
        // load-bearing here is that the connect attempt SETTLES
        // (state != connecting) without hanging — proves the agent
        // arm wires through `busConnectArgs` and into the actor.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          SSHConfig(server: address(), auth: const SshAuth(useAgent: true)),
          label: 'agent-short-circuit',
        );

        await conn.waitUntilReady().timeout(const Duration(seconds: 15));
        await conn.transportReady;

        // The fixture has no agent socket so a clean settle is the
        // expected outcome — `connecting` would mean the auth-method
        // dispatch is wedged.
        expect(conn.state, isNot(SSHConnectionState.connecting));

        notifier.disconnect(conn.id);
      },
    );
  });
}
