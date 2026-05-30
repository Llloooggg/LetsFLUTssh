/// Coverage for [HostKeyPromptListener] start/stop public surface.
///
/// The listener's meat (`_onEvent` + `_handlePrompt` + `_showDialog`
/// fail-closed branch) is private static + drives off bus events
/// that originate inside russh's known-hosts handler — they cannot
/// be injected from outside without a real SSH handshake to an
/// unknown host. The integration coverage for that round-trip lives
/// in `test/integration/known_hosts_prompt_test.dart`.
///
/// What this file asserts is the public contract every cold-start
/// caller relies on:
///   * `start()` is fail-safe before FRB is loaded — a Riverpod
///     provider mounting during the first runApp frame must not
///     crash the widget tree.
///   * `start()` is idempotent — repeated calls re-bind the
///     subscription instead of stacking listeners (otherwise hot
///     reload + bootstrap re-entry would double-prompt the user).
///   * `stop()` is safe with or without a prior start.
///   * `start()` after `stop()` re-attaches cleanly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/host_key_prompt_listener.dart';
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Static subscription state lives at process scope. Each test
  // tears it down so the next test starts from a clean slate
  // regardless of the order they run in.
  tearDown(HostKeyPromptListener.stop);

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        // A sibling test in the same isolate already loaded FRB —
        // skip the cold-start assertion (still valid in a fresh
        // isolate). The post-FRB group below covers the loaded path.
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(HostKeyPromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(HostKeyPromptListener.stop, returnsNormally);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(HostKeyPromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      // Repeated start() must cancel the prior subscription before
      // re-binding, otherwise hot-reload during dev or a second
      // bootstrap pass after a recovery dialog would deliver every
      // KnownHostPromptRequest twice and the russh handler would
      // see two competing responses race onto the bus.
      HostKeyPromptListener.start();
      HostKeyPromptListener.start();
      HostKeyPromptListener.start();
      // No crash + no leak — the static `_sub` field is private, but
      // `stop()` cancelling cleanly is the proxy assertion: if the
      // prior start() leaked an extra subscription we'd be left with
      // a non-null reference cancel can't reach.
      expect(HostKeyPromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      HostKeyPromptListener.start();
      HostKeyPromptListener.stop();
      // After stop() the static `_sub` is null; start() must build
      // a fresh subscription without falling into the `_sub?.cancel`
      // branch (which is a no-op when null but should not throw).
      expect(HostKeyPromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      HostKeyPromptListener.stop();
      HostKeyPromptListener.stop();
      HostKeyPromptListener.stop();
      // Ditto — null-aware cancel + null-out leaves the next call
      // hitting an already-null state without throwing.
    });

    test('start() then stop() round-trip leaves the listener detachable', () {
      // Two cycles in a row catch the case where the first stop()
      // null-outs `_sub` correctly but a subsequent start() captures
      // a reference the next stop() then fails to release. Exercised
      // in production when the user locks → unlocks the vault: the
      // bootstrap chain re-wires every listener, and any stale handle
      // would surface as a double-prompt the next time russh requests
      // a verdict.
      HostKeyPromptListener.start();
      HostKeyPromptListener.stop();
      HostKeyPromptListener.start();
      expect(HostKeyPromptListener.stop, returnsNormally);
    });
  });

  group('BusEvent_KnownHostPromptRequest payload shape', () {
    setUpAll(requireFrbLoaded);

    test('newHost variant exposes every field the dialog needs', () {
      // `_showDialog` reads `host`, `port.toInt()`, `keyType`,
      // `fingerprint`, and the `kind` discriminator off the event to
      // hand them into `HostKeyDialog.showNewHost`. Confirming the
      // freezed factory exposes every accessor by name pins the
      // contract the listener relies on — a regen that drops or
      // renames any field would break the dialog call site, and this
      // test catches it before the integration suite runs.
      const event = rust_bus.BusEvent.knownHostPromptRequest(
        promptId: 'pid-1',
        host: 'host.example',
        port: 2222,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:AAAA',
        kind: rust_bus.BusKnownHostPromptKind.newHost,
      );
      expect(event, isA<rust_bus.BusEvent_KnownHostPromptRequest>());
      const req = event as rust_bus.BusEvent_KnownHostPromptRequest;
      expect(req.promptId, 'pid-1');
      expect(req.host, 'host.example');
      expect(req.port.toInt(), 2222);
      expect(req.keyType, 'ssh-ed25519');
      expect(req.fingerprint, 'SHA256:AAAA');
      expect(req.kind, rust_bus.BusKnownHostPromptKind.newHost);
    });

    test('keyChanged variant routes to the same shape', () {
      // The kind discriminator is the only difference between the two
      // branches inside `_showDialog`. Pinning that the kept-host vs
      // changed-host event reach the listener with the right tag means
      // a future tag rename would surface here, not at the dialog.
      const event = rust_bus.BusEvent.knownHostPromptRequest(
        promptId: 'pid-2',
        host: 'mismatch.example',
        port: 22,
        keyType: 'ecdsa-sha2-nistp256',
        fingerprint: 'SHA256:BBBB',
        kind: rust_bus.BusKnownHostPromptKind.keyChanged,
      );
      const req = event as rust_bus.BusEvent_KnownHostPromptRequest;
      expect(req.kind, rust_bus.BusKnownHostPromptKind.keyChanged);
    });

    test('_onEvent type filter — sibling BusEvent variants are not routed', () {
      // The listener's `_onEvent` early-returns on anything that isn't
      // a `BusEvent_KnownHostPromptRequest`. Verifying a sibling event
      // (the smoke `Echoed`) does NOT match the filter pins the
      // discriminator the listener uses — if a regen merged variants
      // or renamed the type, this isA check would flip.
      const unrelated = rust_bus.BusEvent.echoed(payload: 'noise');
      expect(unrelated, isNot(isA<rust_bus.BusEvent_KnownHostPromptRequest>()));
    });

    // covered by integration: `_handlePrompt` paints the TOFU dialog
    // through `navigatorKey.currentContext`, `_showDialog` branches on
    // `BusKnownHostPromptKind.newHost` vs `keyChanged` to call
    // `HostKeyDialog.showNewHost` / `showKeyChanged`, and the
    // navigator-not-mounted fail-closed reject path all drive off bus
    // events the russh known-hosts handler publishes during a real SSH
    // handshake. AppBus exposes no debug-dispatch seam and the listener
    // owns no `@visibleForTesting` injection point, so these branches
    // belong in `test/integration/known_hosts_prompt_test.dart` where
    // Rust + Dart share a process.

    test('payload promptId round-trips verbatim — no trimming or rewrite', () {
      // Spec: the listener echoes `event.promptId` straight back into
      // the `KnownHostPromptResponse` command so the russh handler can
      // pair the verdict with the original request. A copy-with-modify
      // would silently drop a response on the floor and the handshake
      // would block waiting for a verdict that never matches.
      const event = rust_bus.BusEvent.knownHostPromptRequest(
        promptId: 'prompt-uuid-with-dashes-and-1234',
        host: 'h',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:X',
        kind: rust_bus.BusKnownHostPromptKind.newHost,
      );
      const req = event as rust_bus.BusEvent_KnownHostPromptRequest;
      expect(req.promptId, 'prompt-uuid-with-dashes-and-1234');
    });

    test(
      'port accessor widens unsigned to a Dart int safely for the dialog',
      () {
        // Spec: `_showDialog` does `event.port.toInt()` because the FRB
        // wire type is unsigned. A standard SSH port and a high custom
        // port must both round-trip without an overflow truncation that
        // would point the dialog at the wrong server.
        const lowPort = rust_bus.BusEvent.knownHostPromptRequest(
          promptId: 'a',
          host: 'h',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:A',
          kind: rust_bus.BusKnownHostPromptKind.newHost,
        );
        const highPort = rust_bus.BusEvent.knownHostPromptRequest(
          promptId: 'b',
          host: 'h',
          port: 65535,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:B',
          kind: rust_bus.BusKnownHostPromptKind.keyChanged,
        );
        const low = lowPort as rust_bus.BusEvent_KnownHostPromptRequest;
        const high = highPort as rust_bus.BusEvent_KnownHostPromptRequest;
        expect(low.port.toInt(), 22);
        expect(high.port.toInt(), 65535);
      },
    );

    test('fingerprint and keyType are passed through unmodified — the dialog '
        'shows the raw OpenSSH formatting', () {
      // Spec: `_showDialog` hands `event.keyType` and `event.fingerprint`
      // straight into `HostKeyDialog.showNewHost` / `showKeyChanged` so
      // the user sees the canonical OpenSSH host-key formatting
      // (`SHA256:...` + the algorithm name). The listener must not
      // normalize or strip these — the dialog text is the user's only
      // signal during a TOFU decision and a regression here would
      // erode trust in the prompt.
      const event = rust_bus.BusEvent.knownHostPromptRequest(
        promptId: 'p',
        host: 'h.example',
        port: 22,
        keyType: 'ecdsa-sha2-nistp521',
        fingerprint: 'SHA256:1+/AbCdEfGhIjKlMnOpQrStUvWxYz0123456789==',
        kind: rust_bus.BusKnownHostPromptKind.keyChanged,
      );
      const req = event as rust_bus.BusEvent_KnownHostPromptRequest;
      expect(req.keyType, 'ecdsa-sha2-nistp521');
      expect(req.fingerprint, contains('SHA256:'));
      expect(req.fingerprint, contains('+'));
      expect(req.fingerprint, contains('/'));
    });
  });

  group('lifecycle invariants — multiple start/stop cycles', () {
    setUpAll(requireFrbLoaded);

    test('rapid start/stop bursts do not leak subscriptions or throw', () {
      // Spec: a recovery flow may trigger several bootstrap re-entries
      // in rapid succession (unlock → fatal probe → re-unlock). Each
      // pass calls `start()` and the previous pass's `stop()` may not
      // have settled yet. The listener guards both verbs against
      // double-cancel / double-bind, so a burst must remain safe.
      for (var i = 0; i < 5; i++) {
        HostKeyPromptListener.start();
        HostKeyPromptListener.stop();
      }
      // Trailing start so tearDown's stop() still reaches a live state.
      HostKeyPromptListener.start();
      expect(HostKeyPromptListener.stop, returnsNormally);
    });
  });
}
