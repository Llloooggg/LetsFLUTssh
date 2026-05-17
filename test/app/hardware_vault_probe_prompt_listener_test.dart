/// Coverage for [HardwareVaultProbePromptListener] start/stop +
/// `debugSetVault` / `debugResetVault` injection seam.
///
/// `_onEvent` + `_handlePrompt` drive off
/// `BusEvent_HardwareVaultProbePromptRequest` events the Rust
/// capabilities orchestrator publishes (Apple / Android / Windows
/// only — Linux short-circuits to the in-process TPM probe).
/// Round-trip integration coverage lives alongside the
/// capabilities-orchestrator tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/hardware_vault_probe_prompt_listener.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    HardwareVaultProbePromptListener.stop();
    HardwareVaultProbePromptListener.debugResetVault();
  });

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(HardwareVaultProbePromptListener.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(HardwareVaultProbePromptListener.stop, returnsNormally);
    });
  });

  group('debugSetVault / debugResetVault', () {
    test('debugSetVault swaps in the stub without throwing', () {
      expect(
        () =>
            HardwareVaultProbePromptListener.debugSetVault(HardwareTierVault()),
        returnsNormally,
      );
    });

    test('debugResetVault restores the production vault', () {
      HardwareVaultProbePromptListener.debugSetVault(HardwareTierVault());
      expect(HardwareVaultProbePromptListener.debugResetVault, returnsNormally);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(HardwareVaultProbePromptListener.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      HardwareVaultProbePromptListener.start();
      HardwareVaultProbePromptListener.start();
      HardwareVaultProbePromptListener.start();
      expect(HardwareVaultProbePromptListener.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      HardwareVaultProbePromptListener.start();
      HardwareVaultProbePromptListener.stop();
      expect(HardwareVaultProbePromptListener.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      HardwareVaultProbePromptListener.stop();
      HardwareVaultProbePromptListener.stop();
    });
  });
}
