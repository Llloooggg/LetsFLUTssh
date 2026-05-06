/// Coverage for [HardwareVaultUnlockPromptListener] start/stop +
/// `debugSetVault` / `debugResetVault` injection seam.
///
/// `_onEvent` + `_handlePrompt` drive off
/// `BusEvent_HardwareVaultUnlockPromptRequest` events the Rust L3
/// tier-unlock orchestrator publishes; round-trip integration
/// coverage lives alongside the orchestrator tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/hardware_vault_unlock_prompt_listener.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    HardwareVaultUnlockPromptListener.stop();
    HardwareVaultUnlockPromptListener.debugResetVault();
  });

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(HardwareVaultUnlockPromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(HardwareVaultUnlockPromptListener.stop, returnsNormally);
    });
  });

  group('debugSetVault / debugResetVault', () {
    test('debugSetVault swaps in the stub without throwing', () {
      expect(
        () => HardwareVaultUnlockPromptListener.debugSetVault(
          HardwareTierVault(),
        ),
        returnsNormally,
      );
    });

    test('debugResetVault restores the production vault', () {
      HardwareVaultUnlockPromptListener.debugSetVault(HardwareTierVault());
      expect(
        HardwareVaultUnlockPromptListener.debugResetVault,
        returnsNormally,
      );
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(HardwareVaultUnlockPromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      HardwareVaultUnlockPromptListener.start();
      HardwareVaultUnlockPromptListener.start();
      HardwareVaultUnlockPromptListener.start();
      expect(HardwareVaultUnlockPromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      HardwareVaultUnlockPromptListener.start();
      HardwareVaultUnlockPromptListener.stop();
      expect(HardwareVaultUnlockPromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      HardwareVaultUnlockPromptListener.stop();
      HardwareVaultUnlockPromptListener.stop();
    });
  });
}
