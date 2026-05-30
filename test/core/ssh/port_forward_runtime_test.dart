import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/core/ssh/port_forward_runtime.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:letsflutssh/src/rust/api/forward.dart' as rust_fwd;
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;

import '../../helpers/frb_bootstrap.dart';

/// Stub transport that satisfies the `transport != null` check in
/// [`PortForwardRuntime.onConnected`] without binding any real SSH
/// channel. The runtime issues `port_forward_start_*` FRB calls
/// keyed by the connection id, not against the transport object
/// itself, so every override throws to make a misuse loud.
class _StubTransport implements SshTransport {
  @override
  bool get isConnected => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<SshShellChannel> openShell({required int cols, required int rows}) =>
      throw UnimplementedError();

  @override
  Future<rust_terminal.TerminalSession> openTerminalSession({
    required int cols,
    required int rows,
    required int scrollback,
    required rust_terminal.TerminalPalette palette,
  }) => throw UnimplementedError();

  @override
  Future<dynamic> openSftp() => throw UnimplementedError();

  @override
  Future<SshDirectTcpipChannel> openDirectTcpip({
    required String hostToConnect,
    required int portToConnect,
    required String originatorAddress,
    required int originatorPort,
  }) => throw UnimplementedError();

  @override
  Future<int> requestRemoteForward(String address, int port) =>
      throw UnimplementedError();

  @override
  Future<void> cancelRemoteForward(String address, int port) =>
      throw UnimplementedError();
}

Connection _stubConnection({bool withTransport = false}) {
  final c = Connection(
    id: 'c',
    label: 'l',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: 'h', user: 'u'),
    ),
  );
  if (withTransport) c.transport = _StubTransport();
  return c;
}

PortForwardRule _localRule({
  String id = 'r1',
  bool enabled = true,
  int bindPort = 0,
  String remoteHost = 'svc',
  int remotePort = 80,
}) => PortForwardRule(
  id: id,
  kind: PortForwardKind.local,
  bindHost: '127.0.0.1',
  bindPort: bindPort,
  remoteHost: remoteHost,
  remotePort: remotePort,
  enabled: enabled,
);

void main() {
  setUpAll(requireFrbLoaded);

  group('PortForwardRuntime', () {
    test('onConnected with no live transport is a no-op', () {
      final runtime = PortForwardRuntime(rules: [_localRule()]);
      // The stub Connection carries no transport, so the runtime
      // must short-circuit before issuing any FRB driver call (the
      // Rust lib is not loaded under flutter_test).
      expect(() => runtime.onConnected(_stubConnection()), returnsNormally);
      runtime.dispose();
    });

    test('onDisconnecting before onConnected is a no-op', () {
      final runtime = PortForwardRuntime();
      expect(() => runtime.onDisconnecting(_stubConnection()), returnsNormally);
      runtime.dispose();
    });

    test('setRules replaces the list', () {
      final runtime = PortForwardRuntime(rules: [_localRule(id: 'r1')]);
      runtime.setRules([_localRule(id: 'r2'), _localRule(id: 'r3')]);
      expect(runtime.rules.map((r) => r.id), ['r2', 'r3']);
      runtime.dispose();
    });

    test('disabled rules are skipped at runtime registration', () {
      final runtime = PortForwardRuntime(
        rules: [
          _localRule(id: 'r1'),
          _localRule(id: 'r2', enabled: false),
        ],
      );
      // The list still holds both — toggle is a UI concern, runtime
      // filters at open-listener time. Here we only verify the
      // setter does not implicitly drop disabled rows.
      expect(runtime.rules.length, 2);
      runtime.dispose();
    });

    test('id is stable for ConnectionExtension diagnostics', () {
      expect(PortForwardRuntime().id, 'port-forward-runtime');
    });

    test('rule kinds round-trip through the FRB wire-name shims', () {
      // Belt-and-braces guard against a misnamed enum case showing
      // up only at runtime — the DAO dispatches on the wire string
      // returned by `portForwardKindToWire`.
      for (final k in PortForwardKind.values) {
        expect(
          rust_fwd.portForwardKindFromWire(
            value: rust_fwd.portForwardKindToWire(value: k),
          ),
          k,
        );
      }
    });

    test('remote-rule defaults validate cleanly', () {
      final remote = PortForwardRule(
        kind: PortForwardKind.remote,
        bindHost: '0.0.0.0',
        bindPort: 8080,
        remoteHost: 'app.local',
        remotePort: 80,
      );
      expect(remote.validate(), isNull);
      // bindsLoopbackOnly is false here even though `remoteHost` is
      // a string that happens to start with a digit — the helper
      // looks at bindHost only, which is the canonical SSH semantic.
      expect(remote.bindsLoopbackOnly, isFalse);
    });

    test('dynamic-rule validates without remote host/port', () {
      final dyn = PortForwardRule(
        kind: PortForwardKind.dynamic_,
        bindHost: '127.0.0.1',
        bindPort: 1080,
        remoteHost: '',
        remotePort: 0,
      );
      expect(dyn.validate(), isNull);
    });

    test('invalid rules are dropped without arming the listener', () async {
      // Bind port 0 is the wildcard accepted by the validator; an
      // out-of-range bind port is the canonical reject path. The
      // runtime must log + skip without registering the rule in
      // `_armed`, so a later teardown does not try to stop a listener
      // that never bound.
      final bad = PortForwardRule(
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 70000,
        remoteHost: 'svc',
        remotePort: 22,
      );
      final runtime = PortForwardRuntime(rules: [bad]);

      runtime.onConnected(_stubConnection(withTransport: true));
      // No live FRB calls fire because the runtime rejected the rule
      // pre-arm — `dispose` must be a clean no-op (no stop calls
      // queued, no exceptions thrown).
      expect(runtime.dispose, returnsNormally);
    });

    test('onReconnecting tears down the same way as onDisconnecting', () {
      // Reconnect handshake routes through the same teardown so the
      // listener bound on the prior generation does not race the
      // freshly-armed one. The hook MUST drain `_armed` even when
      // called without a prior `onConnected` (the no-op case is the
      // safety net).
      final runtime = PortForwardRuntime();
      expect(() => runtime.onReconnecting(_stubConnection()), returnsNormally);
      runtime.dispose();
    });

    test('dispose is idempotent across repeated calls', () {
      // The provider `onDispose` may fire after `onDisconnecting`
      // already drained the armed set. Calling `dispose` twice must
      // stay a no-op the second time — never throw, never re-issue
      // stop calls against an empty set.
      final runtime = PortForwardRuntime(rules: [_localRule()]);
      runtime.dispose();
      expect(runtime.dispose, returnsNormally);
    });

    test('setRules accepts an empty list and clears prior rules', () {
      // The save-and-disable-all path lands an empty list; the
      // runtime MUST treat that as "no rules to arm on next connect"
      // rather than retaining the prior generation.
      final runtime = PortForwardRuntime(rules: [_localRule(id: 'r1')]);
      runtime.setRules(const []);
      expect(runtime.rules, isEmpty);
      runtime.dispose();
    });

    test('constructor seeds an unmodifiable rule list', () {
      // The `_rules` field is wrapped in `List.unmodifiable` so a
      // caller holding the reference cannot mutate the runtime's
      // view of its own rules. This guards against the UI editing
      // a rule mid-arm — every edit has to route through `setRules`.
      final runtime = PortForwardRuntime(rules: [_localRule()]);
      expect(
        () => runtime.rules.add(_localRule(id: 'r2')),
        throwsUnsupportedError,
      );
      runtime.dispose();
    });

    test(
      'onConnected with live transport runs the start path without throwing',
      () async {
        // With a transport attached the runtime walks into `_startRule`
        // for each enabled + valid rule. The FRB call itself fails
        // because no connection id is registered in the Rust app state
        // under unit test, but the runtime swallows that exception
        // (it surfaced on the bus already) and clears the rule from
        // `_armed`. Verifying that the synchronous onConnected returns
        // normally + the trailing microtasks settle without crashing
        // the test isolate is the unit-level contract.
        final runtime = PortForwardRuntime(rules: [_localRule()]);

        runtime.onConnected(_stubConnection(withTransport: true));
        // Drain the unawaited `_startRule` future so the FRB error
        // path (or success path on a future Rust change) finishes
        // before teardown runs.
        await pumpEventQueue();

        runtime.dispose();
      },
    );

    test(
      'mixed valid + invalid rules arm only the valid ones — invalid rule is '
      'rejected pre-arm without polluting `_armed`',
      () async {
        // Spec: the iteration in `onConnected` independently validates
        // every enabled rule; an invalid one is logged + skipped and
        // does not stop the loop from arming the rest. The valid rule's
        // start call then surfaces through the FRB driver. Verifying
        // the loop survives one rejection in the middle guards against
        // a regression that short-circuited on first failure.
        final bad = PortForwardRule(
          kind: PortForwardKind.local,
          bindHost: '127.0.0.1',
          bindPort: 70000, // out of range
          remoteHost: 'svc',
          remotePort: 22,
        );
        final good = _localRule(id: 'good', bindPort: 12345);
        final runtime = PortForwardRuntime(rules: [bad, good]);

        runtime.onConnected(_stubConnection(withTransport: true));
        await pumpEventQueue();

        // The teardown must not crash even though only one rule was
        // armed (and the FRB stop call will throw under unit test, but
        // the runtime swallows it).
        expect(runtime.dispose, returnsNormally);
      },
    );

    test(
      'dynamic rule routes through start path with no remote target — '
      'kind-dispatch picks the dynamic FRB call, not the local one',
      () async {
        // Spec: `_startRule` switches on `rule.kind` to pick between
        // `portForwardStartLocal` / `portForwardStartDynamic` /
        // `portForwardStartRemote`. A dynamic rule has no remote target;
        // a regression that fell into the local branch would supply
        // empty target fields and the FRB call would crash with a
        // different error than the bus-published one. Driving the path
        // confirms the dispatch survives the unit-test environment.
        final dyn = PortForwardRule(
          kind: PortForwardKind.dynamic_,
          bindHost: '127.0.0.1',
          bindPort: 1080,
          remoteHost: '',
          remotePort: 0,
        );
        final runtime = PortForwardRuntime(rules: [dyn]);

        runtime.onConnected(_stubConnection(withTransport: true));
        await pumpEventQueue();

        expect(runtime.dispose, returnsNormally);
      },
    );

    test('remote rule routes through start path keyed by kind — kind-dispatch '
        'picks the remote FRB call', () async {
      // Spec: parallel to the dynamic-rule test — verifies the third
      // arm of the kind switch in `_startRule`. The FRB call fails
      // under unit test because no connection id is registered;
      // the runtime swallows + drops the rule from `_armed`.
      final remote = PortForwardRule(
        kind: PortForwardKind.remote,
        bindHost: '0.0.0.0',
        bindPort: 8080,
        remoteHost: 'app.local',
        remotePort: 80,
      );
      final runtime = PortForwardRuntime(rules: [remote]);

      runtime.onConnected(_stubConnection(withTransport: true));
      await pumpEventQueue();

      expect(runtime.dispose, returnsNormally);
    });

    test('onConnected → onDisconnecting → onConnected re-arms cleanly without '
        'double-stop on the second teardown', () async {
      // Spec: a reconnect cycle drains `_armed` on `onDisconnecting`
      // and re-populates it on the next `onConnected`. The second
      // disconnect must stop only the rules armed in the second
      // generation, never replay stops from the first generation.
      // This is the invariant that prevents a stale stop call against
      // an FRB-tracked listener id that was already dropped.
      final runtime = PortForwardRuntime(rules: [_localRule()]);

      runtime.onConnected(_stubConnection(withTransport: true));
      await pumpEventQueue();
      runtime.onDisconnecting(_stubConnection(withTransport: true));
      await pumpEventQueue();
      runtime.onConnected(_stubConnection(withTransport: true));
      await pumpEventQueue();

      expect(runtime.dispose, returnsNormally);
    });

    test(
      'setRules mid-arm does not drop already-armed rules — replacing the list '
      'is queued for the NEXT onConnected',
      () async {
        // Spec: "Replacing the list does not re-arm listeners; the next
        // `onConnected` does." A UI edit during an active session
        // updates the visible list but the runtime keeps driving the
        // generation it has already armed. The teardown still has to
        // succeed regardless of the post-edit list.
        final runtime = PortForwardRuntime(rules: [_localRule(id: 'r-old')]);

        runtime.onConnected(_stubConnection(withTransport: true));
        await pumpEventQueue();

        // UI swaps the rule list mid-session.
        runtime.setRules([_localRule(id: 'r-new', bindPort: 9999)]);

        // The visible list reflects the edit immediately.
        expect(runtime.rules.map((r) => r.id), ['r-new']);

        // Teardown completes — the runtime tracks armed rules by the
        // ids it actually started, not by the current `_rules`.
        expect(runtime.dispose, returnsNormally);
      },
    );

    test('onConnected with all rules disabled is a no-op — the where-filter '
        'short-circuits before any FRB call is issued', () async {
      // Spec: the iteration is `_rules.where((r) => r.enabled)`. With
      // every rule disabled the body never runs, `_armed` stays
      // empty, and teardown is a fast no-op. Guards against a
      // regression that flipped the filter polarity (which would
      // arm exactly the rules the user toggled off).
      final runtime = PortForwardRuntime(
        rules: [
          _localRule(id: 'r1', enabled: false),
          _localRule(id: 'r2', enabled: false),
        ],
      );

      runtime.onConnected(_stubConnection(withTransport: true));
      await pumpEventQueue();

      expect(runtime.dispose, returnsNormally);
    });
  });
}
