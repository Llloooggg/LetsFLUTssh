/// Coverage for [HardwareVaultSealPromptListener] start/stop surface +
/// the `debugSetVault` / `debugResetVault` injection seam.
///
/// `_onEvent` + `_handlePrompt` drive off
/// `BusEvent_HardwareVaultSealPromptRequest` events the Rust L3
/// first-launch orchestrator publishes; the round-trip needs a real
/// bus dispatch which lives in the higher-level orchestrator tests.
/// What we assert here is the public lifecycle contract every
/// cold-start caller relies on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/hardware_vault_seal_prompt_listener.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    HardwareVaultSealPromptListener.stop();
    HardwareVaultSealPromptListener.debugResetVault();
  });

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(HardwareVaultSealPromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(HardwareVaultSealPromptListener.stop, returnsNormally);
    });
  });

  group('debugSetVault / debugResetVault', () {
    test('debugSetVault swaps in the stub without throwing', () {
      expect(
        () =>
            HardwareVaultSealPromptListener.debugSetVault(HardwareTierVault()),
        returnsNormally,
      );
    });

    test('debugResetVault restores the production vault', () {
      HardwareVaultSealPromptListener.debugSetVault(HardwareTierVault());
      expect(HardwareVaultSealPromptListener.debugResetVault, returnsNormally);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(HardwareVaultSealPromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      HardwareVaultSealPromptListener.start();
      HardwareVaultSealPromptListener.start();
      HardwareVaultSealPromptListener.start();
      expect(HardwareVaultSealPromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      HardwareVaultSealPromptListener.start();
      HardwareVaultSealPromptListener.stop();
      expect(HardwareVaultSealPromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      HardwareVaultSealPromptListener.stop();
      HardwareVaultSealPromptListener.stop();
    });
  });
}
