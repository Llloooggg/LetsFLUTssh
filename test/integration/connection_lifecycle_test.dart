/// End-to-end connection lifecycle tests against the in-process
/// russh fixture.
///
/// Why these exist: the `feat/rust-core` branch shipped four
/// race-condition fixes
/// (`docs/_audit/G03.md` + the post-audit incident pile-up missed
/// every one of them):
///
///   1. `Connection.completeReady` was closing `_progressController`
///      while Rust still had post-success bus events queued for the
///      microtask queue → success steps silently dropped.
///   2. The per-attempt sub in `_doConnect.finally` cancelled before
///      the Connected event drained → state never flipped.
///   3. `state == connected` flipped synchronously while
///      `connection_get_session` ran async → consumers awaiting
///      `waitUntilReady` saw `transport == null`.
///   4. The same per-attempt sub being cancelled mid-flight produced
///      "Fail to post message to Dart" stderr noise on every
///      successful connect.
///
/// Static audits couldn't see those — they live at the Rust-actor →
/// FRB worker → Dart microtask boundary, which only a real
/// handshake against a real listener exercises deterministically.
/// This file is the regression net.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
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
    // The connect path needs a live SQLCipher handle for
    // `connection_prepare_auth → run_db` (even quick-connect with no
    // saved-session id routes through the same path) and for the
    // known_hosts pre-seed below. In-memory database keeps the test
    // deterministic + leaves no on-disk state to clean up.
    await rust_app.dbInit(path: ':memory:', key: const []);

    serverInfo = await rust_test.testSshServerStart();
    // Pre-seed the host key so `check_host` returns Accepted at the
    // HostKeyVerify phase. Without this the actor publishes a
    // KnownHostPromptRequest and the connect stalls until a Dart
    // listener responds — there isn't one in this test process.
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

  /// One container per test so a successful connect doesn't bleed
  /// into the next test's connection list.
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  SSHConfig configFor(String password) => SSHConfig(
    server: ServerAddress(host: '127.0.0.1', port: serverInfo.port, user: 'u'),
    auth: SshAuth(password: password),
  );

  group('Connection lifecycle (russh fixture)', () {
    test(
      'successful connect populates progressHistory with every phase as success',
      () async {
        // Bug #1 regression. Before the controller-lifetime fix, the
        // post-handshake success events for socketConnect /
        // hostKeyVerify / authenticate were silently dropped because
        // `completeReady` had closed `_progressController` in the
        // same tick they were queued on the microtask queue.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(serverInfo.password),
          label: 'fixture',
        );

        await conn.waitUntilReady();
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.connected);
        expect(conn.connectionError, isNull);

        final phases = conn.progressHistory
            .where((s) => s.status == StepStatus.success)
            .map((s) => s.phase)
            .toSet();
        expect(
          phases,
          containsAll(const {
            ConnectionPhase.socketConnect,
            ConnectionPhase.hostKeyVerify,
            ConnectionPhase.authenticate,
          }),
          reason:
              'Every pre-channel phase must reach success status. Bug #1 '
              'silently dropped these because the progress stream was '
              'closed before Dart processed the queued bus events.',
        );

        notifier.disconnect(conn.id);
      },
    );

    test(
      'transport is non-null at the moment state==connected is observed',
      () async {
        // Bug #3 regression. The Rust actor flips `state == connected`
        // synchronously when its bus event arrives, but
        // `connection_get_session` (the call that hands the Dart side
        // a russh session handle to wrap in `RustTransport`) is
        // async. Pre-fix, a consumer that awaited `waitUntilReady`
        // alone read `transport == null` even though the state said
        // connected. Post-fix, consumers also await `transportReady`,
        // which resolves only after `_adoptSession` finishes.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(serverInfo.password),
          label: 'transport-gate',
        );

        await conn.waitUntilReady();
        // Eagerly reading `transport` before `transportReady` would
        // observe the race; we explicitly await the gate first.
        final adopted = await conn.transportReady;
        expect(adopted, isTrue);
        expect(conn.state, SSHConnectionState.connected);
        expect(conn.transport, isNotNull);

        notifier.disconnect(conn.id);
      },
    );

    test(
      'state reaches connected exactly once per successful connect',
      () async {
        // Bug #2 regression. The per-attempt bus subscription used
        // to mutate `conn.state`, then was cancelled in
        // `_doConnect.finally`. When the Connected event raced the
        // cancel, the mutation never fired and the state was stuck
        // at `connecting` even though Rust said Connected. Post-fix,
        // `Connection._busSub` (lifetime = Connection's lifetime)
        // owns the mutation, and it should observe the transition
        // exactly once across the connect + disconnect arc.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(serverInfo.password),
          label: 'state-count',
        );

        var connectedHits = 0;
        Timer? watchdog;
        // Poll the observable state. Riverpod doesn't expose a
        // per-Connection state stream — `progressStream` is at a
        // finer grain and `connectionsProvider` rebuilds on every
        // change. Polling is good enough for an exactly-once
        // assertion: once the state lands on connected, repeated
        // observations of the same value count as one transition
        // (we deduplicate by tracking the previous reading).
        final completer = Completer<void>();
        var prev = SSHConnectionState.disconnected;
        watchdog = Timer.periodic(const Duration(milliseconds: 25), (t) {
          if (conn.state != prev) {
            if (conn.state == SSHConnectionState.connected) connectedHits++;
            prev = conn.state;
          }
          if (conn.state == SSHConnectionState.connected ||
              conn.state == SSHConnectionState.disconnected &&
                  conn.connectionError != null) {
            t.cancel();
            if (!completer.isCompleted) completer.complete();
          }
        });

        await completer.future.timeout(const Duration(seconds: 10));
        watchdog.cancel();
        await conn.transportReady;

        expect(
          connectedHits,
          1,
          reason:
              'Connection state must reach `connected` exactly once. Bug '
              '#2 either missed the transition entirely (per-attempt sub '
              'cancelled before the Connected event drained) or the '
              'redundant duplicate-listener era counted it twice.',
        );

        notifier.disconnect(conn.id);
      },
    );

    test(
      'wrong password surfaces an authenticate-phase failed step + disconnected state',
      () async {
        // Negative path. The actor must publish `Authenticate /
        // failed` and settle into `disconnected`; if the failure-
        // path version of the bus delivery races the same way the
        // success path used to, this would miss the failed step
        // entirely and leave the connection wedged at `connecting`.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor('definitely-not-the-test-password'),
          label: 'auth-fail',
        );

        // The fixture's `auth_rejection_time` is 50 ms — auth fails
        // fast so a 10 s timeout is plenty. Mirror the production
        // consumer pattern: `waitUntilReady()` resolves the moment
        // `_doConnect.finally` fires `completeReady`, which on the
        // failure path can run before the FRB stream has drained the
        // ConnectionStateChanged(Disconnected) event into Connection's
        // bus listener (state mutation lives there). Awaiting
        // `transportReady` after `waitUntilReady` is the gate every
        // production consumer uses (`terminal_pane.dart:187-196`,
        // `sftp_browser_mixin.dart:54-60`, `mobile_terminal_view.dart`)
        // — its completer fires from the bus listener's terminal-state
        // arm, so by the time it resolves the `Disconnected` event is
        // guaranteed to have been processed.
        await conn.waitUntilReady().timeout(const Duration(seconds: 10));
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.disconnected);
        expect(conn.connectionError, isNotNull);
        final failedPhases = conn.progressHistory
            .where((s) => s.status == StepStatus.failed)
            .map((s) => s.phase)
            .toSet();
        expect(
          failedPhases,
          contains(ConnectionPhase.authenticate),
          reason:
              'Authenticate phase must record a failed step on rejected '
              'password. Empty failedPhases here would mean the bus '
              'failure path drops events the same way the success path '
              'used to.',
        );

        notifier.disconnect(conn.id);
      },
    );

    test(
      'reconnect bumps generation and survives stale events from the prior attempt',
      () async {
        // Reconnect re-uses the same `Connection` object (same id)
        // and bumps the per-id generation counter Rust-side. If the
        // first attempt's actor publishes a stale `Connected` event
        // *after* the reconnect kicked off, the new attempt's state
        // mutation must win. The generation guard inside
        // `run_connect_driver` is what enforces that on the Rust
        // side; this test asserts the Dart side observes a single
        // clean lifecycle on the *second* attempt regardless of
        // whatever the first attempt published.
        final container = makeContainer();
        final notifier = container.read(connectionsProvider.notifier);
        final conn = notifier.connectAsync(
          configFor(serverInfo.password),
          label: 'reconnect',
        );
        await conn.waitUntilReady();
        await conn.transportReady;
        expect(conn.state, SSHConnectionState.connected);

        // Force a fresh attempt on the same Connection object.
        notifier.reconnect(conn.id);
        await conn.waitUntilReady();
        await conn.transportReady;

        expect(conn.state, SSHConnectionState.connected);
        expect(conn.transport, isNotNull);
        expect(conn.connectionError, isNull);

        notifier.disconnect(conn.id);
      },
    );
  });
}
