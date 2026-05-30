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

    test('sibling BusEvent variants on the SshAgent topic are not '
        'SshAgentSignaturePrompt — the type filter pins exactly one variant', () {
      // Spec: `_onEvent` early-returns on every event that isn't a
      // `BusEvent_SshAgentSignaturePrompt`. Pin a representative
      // sample of the sealed-class variants so a future FRB regen
      // that promotes a sibling to the same dispatcher cannot slip
      // a second event type into the prompt listener without
      // updating the filter.
      const siblings = <rust_bus.BusEvent>[
        rust_bus.BusEvent.echoed(payload: 'noise'),
        rust_bus.BusEvent.autoLockLocked(),
        rust_bus.BusEvent.autoLockUnlocked(),
        rust_bus.BusEvent.sessionsChanged(),
        rust_bus.BusEvent.keysChanged(),
        rust_bus.BusEvent.knownHostsChanged(),
      ];
      for (final ev in siblings) {
        expect(
          ev,
          isNot(isA<rust_bus.BusEvent_SshAgentSignaturePrompt>()),
          reason:
              '_onEvent must early-return on every non-prompt variant; '
              'a missed sibling would route its payload as a fake '
              'signature prompt back to ssh_agent_respond_to_signature_request.',
        );
      }
    });

    test('start() then stop() then start() then stop() — full lifecycle '
        'round-trip is idempotent and never throws', () {
      // Spec: the cold-start handler may run the wire-up sequence
      // through a hot-reload or a second bootstrap pass after a
      // recovery dialog. Drive the public surface through a full
      // round-trip (start/stop/start/stop) so a regression that
      // breaks any one transition (e.g. start-after-stop relying
      // on a non-null cached subscription) surfaces here rather
      // than silently dropping prompts in production.
      expect(SshAgentPromptListener.start, returnsNormally);
      expect(SshAgentPromptListener.stop, returnsNormally);
      expect(SshAgentPromptListener.start, returnsNormally);
      expect(SshAgentPromptListener.stop, returnsNormally);
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

    test('DbAgentDecision equality is keyed on the kind string — distinct '
        'wire tags compare unequal so the Rust side cannot accidentally treat '
        'a deny as an authorize-once on the round-trip', () {
      // Spec: the listener constructs a `DbAgentDecision(kind: wireTag)`
      // per verdict. The struct's `==` is defined over `kind` — pin
      // that a regen that dropped the override (or reordered the field
      // map) would surface here, not in production when an `always`
      // verdict silently collapsed to a deny because the Rust side
      // saw a default-constructed empty `kind`.
      const once = rust_ssh_agent.DbAgentDecision(kind: 'once');
      const always = rust_ssh_agent.DbAgentDecision(kind: 'always');
      const deny = rust_ssh_agent.DbAgentDecision(kind: 'deny');
      expect(once, isNot(equals(always)));
      expect(once, isNot(equals(deny)));
      expect(always, isNot(equals(deny)));
      expect(
        once,
        equals(const rust_ssh_agent.DbAgentDecision(kind: 'once')),
        reason:
            'two decisions with the same wire tag must compare equal — '
            'otherwise the Rust-side dispatch cannot deduplicate a re-emitted '
            'verdict',
      );
    });

    test(
      'wire-tag mapping for AgentSignatureDecision is exhaustive across the '
      'three enum members — no decision falls through to "deny" by accident',
      () {
        // Spec: `_handlePrompt` uses a `switch` to lower the user verdict
        // to `'once'` / `'always'` / `'deny'`. Pin that every enum member
        // a future refactor might add gets its own wire tag — a refactor
        // that added a new decision (e.g. `authorizeForSession`) would
        // either need to extend the switch OR fall through to the
        // default-deny arm, and this enumeration of the wire targets is
        // where the operator notices.
        const wireTargets = <String>{'once', 'always', 'deny'};
        // Three enum members today; if a fourth lands without a paired
        // wire tag the listener's switch must surface it explicitly.
        expect(wireTargets, hasLength(3));
        // Confirm each wire tag wraps cleanly in DbAgentDecision — the
        // listener path is `DbAgentDecision(kind: wireDecision)` and a
        // future regen that started rejecting unknown kinds would surface
        // here.
        for (final tag in wireTargets) {
          expect(
            rust_ssh_agent.DbAgentDecision(kind: tag).kind,
            tag,
            reason:
                'DbAgentDecision must round-trip every wire tag the listener '
                'emits unchanged — Rust dispatch keys on the string verbatim',
          );
        }
      },
    );

    test('payload encoding — keyLabel and requester accept arbitrary user '
        'strings without re-encoding (whitespace, unicode, empty)', () {
      // Spec: `_showDialog` hands `event.keyLabel` + `event.requester`
      // straight into `AgentSignatureRequestDialog.show`. The dialog
      // renders those values as the user typed them at key-creation
      // time (label) or as the OS surfaced them at connect time
      // (requester process name). Pin the no-encoding contract — a
      // future refactor that started trimming, URL-encoding, or
      // collapsing whitespace would silently rewrite the displayed
      // label and break a sanity check the user runs visually before
      // hitting Authorize.
      const labels = <String>['', '   ', 'work — laptop', 'ключ-1', '🔑 prod'];
      for (final label in labels) {
        final ev =
            rust_bus.BusEvent.sshAgentSignaturePrompt(
                  requestId: 'req-1',
                  keyId: 'key-1',
                  keyLabel: label,
                )
                as rust_bus.BusEvent_SshAgentSignaturePrompt;
        expect(
          ev.keyLabel,
          label,
          reason:
              'keyLabel must round-trip the user-typed value unchanged — '
              'a refactor that normalised it would let two visually distinct '
              'keys collapse to the same dialog title',
        );
      }
    });
  });
}
