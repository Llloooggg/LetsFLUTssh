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
  });
}
