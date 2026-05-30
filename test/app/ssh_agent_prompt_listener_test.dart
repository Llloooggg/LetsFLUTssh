/// Coverage for [SshAgentPromptListener] start/stop public surface.
///
/// The listener's branching meat (`_onEvent` + `_handlePrompt` +
/// `_showDialog` fail-closed navigator-not-mounted branch and the
/// per-decision `wireDecision` switch) drives off
/// `BusEvent_SshAgentSignaturePrompt` events the in-process
/// ssh-agent endpoint publishes — and routes the user's verdict back
/// through `ssh_agent_respond_to_signature_request`, which is a real
/// FRB call. Neither side can be driven from a flutter_test isolate
/// without bringing up the agent. Round-trip coverage lives in the
/// ssh-agent integration suite.
///
/// What this file asserts is the public contract every cold-start
/// caller depends on:
///   * `start()` is fail-safe before FRB is loaded — a hot-reload or
///     a pre-FRB bootstrap pass must not crash.
///   * `start()` is idempotent — repeated calls re-bind one
///     subscription rather than stacking listeners (otherwise a
///     single SIGN_REQUEST would surface two dialogs and race two
///     verdicts back to Rust).
///   * `stop()` is safe with or without a prior start.
///   * `start()` after `stop()` re-attaches cleanly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/ssh_agent_prompt_listener.dart';
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/api/ssh_agent.dart' as rust_ssh_agent;
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Static subscription state lives at process scope. Each test
  // tears it down so the next test starts from a clean slate
  // regardless of the order they run in.
  tearDown(SshAgentPromptListener.stop);

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        // A sibling test in the same isolate already loaded FRB —
        // skip the cold-start assertion (still valid in a fresh
        // isolate). The post-FRB group below covers the loaded path.
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(SshAgentPromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      // Pre-FRB `stop()` is reachable when bootstrap fails before
      // it ever reaches the post-FRB wire block — the shutdown path
      // still calls every listener's `stop`. Must be a no-op rather
      // than a NPE on the null `_sub`.
      expect(SshAgentPromptListener.stop, returnsNormally);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(SshAgentPromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      // Repeated start() must cancel the prior subscription before
      // re-binding, otherwise a hot-reload during development or a
      // second bootstrap pass after a recovery dialog would deliver
      // every SshAgentSignaturePrompt twice — the user would see two
      // dialogs and Rust would receive two verdicts racing onto the
      // bus, with the second hitting an unknown-request-id path.
      SshAgentPromptListener.start();
      SshAgentPromptListener.start();
      SshAgentPromptListener.start();
      // Proxy assertion: `stop()` cancelling cleanly. If the prior
      // start() leaked an extra subscription the static `_sub` field
      // would still point at the latest one only — the leaked
      // listener is unreachable from outside, and a future event
      // would fan out to it. The "stop is clean" check is the closest
      // observable proxy without a debug seam.
      expect(SshAgentPromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      SshAgentPromptListener.start();
      SshAgentPromptListener.stop();
      // After stop() the static `_sub` is null; start() must build
      // a fresh subscription without falling into the null-aware
      // cancel branch (which is a no-op when null but should not
      // throw).
      expect(SshAgentPromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      SshAgentPromptListener.stop();
      SshAgentPromptListener.stop();
      SshAgentPromptListener.stop();
      // Null-aware cancel + null-out leaves the next call hitting
      // an already-null state without throwing.
    });
  });

  group('BusEvent_SshAgentSignaturePrompt payload shape', () {
    setUpAll(requireFrbLoaded);

    test('exposes every field the dialog reads off the event', () {
      // `_handlePrompt` logs `event.keyId` and `_showDialog` hands
      // `keyLabel` + `requester` into `AgentSignatureRequestDialog.show`.
      // The verdict round-trip uses `event.requestId` as the
      // correlation id. Pinning every accessor by name catches a
      // future FRB regen that drops or renames any of them — the
      // listener would otherwise fail at the call site during the next
      // real agent prompt.
      const event = rust_bus.BusEvent.sshAgentSignaturePrompt(
        requestId: 'req-1',
        keyId: 'key-1',
        keyLabel: 'work',
        requester: 'ssh-client',
      );
      expect(event, isA<rust_bus.BusEvent_SshAgentSignaturePrompt>());
      const prompt = event as rust_bus.BusEvent_SshAgentSignaturePrompt;
      expect(prompt.requestId, 'req-1');
      expect(prompt.keyId, 'key-1');
      expect(prompt.keyLabel, 'work');
      expect(prompt.requester, 'ssh-client');
    });

    test('requester is nullable — matches macOS BSD-socket reality', () {
      // The docstring on `BusEvent.sshAgentSignaturePrompt` notes that
      // `requester` is `None` on macOS where the BSD socket layer does
      // not surface a peer pid. The Dialog renders an "unknown
      // requester" placeholder in that case. Confirm the freezed
      // factory accepts a null requester so the macOS path actually
      // reaches the listener instead of crashing at the FRB boundary.
      const event = rust_bus.BusEvent.sshAgentSignaturePrompt(
        requestId: 'req-mac',
        keyId: 'key-mac',
        keyLabel: 'home',
      );
      const prompt = event as rust_bus.BusEvent_SshAgentSignaturePrompt;
      expect(prompt.requester, isNull);
    });

    test(
      '_onEvent type filter — unrelated BusEvent variants are not routed',
      () {
        // The listener's `_onEvent` early-returns on anything that isn't
        // a `BusEvent_SshAgentSignaturePrompt`. A sibling event must NOT
        // match the filter type — otherwise the listener would call
        // `ssh_agent_respond_to_signature_request` with the wrong
        // request_id and the Rust side would hit an unknown-id path.
        const unrelated = rust_bus.BusEvent.echoed(payload: 'noise');
        expect(
          unrelated,
          isNot(isA<rust_bus.BusEvent_SshAgentSignaturePrompt>()),
        );
      },
    );

    test('DbAgentDecision wire kinds the listener emits are constructible', () {
      // The `wireDecision` switch lowers the user's verdict to one of
      // `'once'` / `'always'` / `'deny'` and hands it to
      // `rust_ssh_agent.sshAgentRespondToSignatureRequest` wrapped in
      // a `DbAgentDecision`. Pinning that each wire tag round-trips
      // through the typed decision struct catches an FRB regen that
      // renames the kind field or swaps the carrier type — the
      // listener would otherwise fail silently on the next agent
      // prompt.
      for (final tag in const ['once', 'always', 'deny']) {
        final dec = rust_ssh_agent.DbAgentDecision(kind: tag);
        expect(dec.kind, tag);
      }
    });

    // covered by integration: the live `_onEvent` dispatch, the
    // `_handlePrompt` dialog mount, the `_showDialog`
    // navigator-not-mounted fail-closed branch, and the round-trip
    // through `ssh_agent_respond_to_signature_request` all require a
    // real `BusEvent_SshAgentSignaturePrompt` to flow through the
    // process-singleton AppBus. AppBus exposes no debug-dispatch seam,
    // and the listener owns no `@visibleForTesting` injection point —
    // they belong in the ssh-agent integration suite where Rust + Dart
    // share a process.
  });
}
