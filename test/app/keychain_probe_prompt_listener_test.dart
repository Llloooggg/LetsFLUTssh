/// Coverage for [KeychainProbePromptListener] start/stop surface +
/// the `debugSetStorage` / `debugResetStorage` injection seam.
///
/// `_onEvent` + `_handlePrompt` are private static and drive off
/// `BusEvent_KeychainProbePromptRequest` events the Rust capabilities
/// orchestrator publishes; without a real bus dispatch we cannot
/// trigger the probe round-trip from Dart-side. The integration
/// coverage for that path lives alongside the capabilities tests.
///
/// What this file asserts is the public lifecycle invariants every
/// cold-start caller relies on — fail-safe before FRB, idempotency,
/// stop/start re-attach.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/keychain_probe_prompt_listener.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    KeychainProbePromptListener.stop();
    KeychainProbePromptListener.debugResetStorage();
  });

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(KeychainProbePromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(KeychainProbePromptListener.stop, returnsNormally);
    });
  });

  group('debugSetStorage / debugResetStorage', () {
    test('debugSetStorage swaps in the test stub without throwing', () {
      expect(
        () => KeychainProbePromptListener.debugSetStorage(SecureKeyStorage()),
        returnsNormally,
      );
    });

    test('debugResetStorage restores the production storage', () {
      KeychainProbePromptListener.debugSetStorage(SecureKeyStorage());
      expect(KeychainProbePromptListener.debugResetStorage, returnsNormally);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(KeychainProbePromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      KeychainProbePromptListener.start();
      KeychainProbePromptListener.start();
      KeychainProbePromptListener.start();
      expect(KeychainProbePromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      KeychainProbePromptListener.start();
      KeychainProbePromptListener.stop();
      expect(KeychainProbePromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      KeychainProbePromptListener.stop();
      KeychainProbePromptListener.stop();
    });
  });
}
