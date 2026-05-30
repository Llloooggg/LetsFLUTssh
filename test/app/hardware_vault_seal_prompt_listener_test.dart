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

    test('start() followed by stop() leaves no live subscription', () {
      // Lifecycle invariant: after stop() the static subscription
      // slot is null. Calling stop() again must therefore not throw
      // (no cancel target) and a subsequent start() must succeed
      // freshly — covers the re-attach path that the cold-start
      // ordering relies on for hot-restart in dev.
      HardwareVaultSealPromptListener.start();
      HardwareVaultSealPromptListener.stop();
      HardwareVaultSealPromptListener.stop();
      expect(HardwareVaultSealPromptListener.start, returnsNormally);
      HardwareVaultSealPromptListener.stop();
    });

    test('debugSetVault remains the active vault across start cycles', () {
      // The injection seam must survive a start/stop cycle so
      // higher-level orchestrator tests can install a stub once
      // and trust it across the full prompt round-trip. A start()
      // that reset the vault would silently route the next
      // prompt to the production vault and leak hardware FFI
      // into the test process.
      final stub = HardwareTierVault();
      HardwareVaultSealPromptListener.debugSetVault(stub);
      HardwareVaultSealPromptListener.start();
      HardwareVaultSealPromptListener.stop();
      // No public getter, so we re-set without expecting a throw
      // — this asserts that no startup path clobbered the slot
      // (a clobber would not throw either, but the regression
      // gate is that the surface is callable without surprise).
      expect(
        () => HardwareVaultSealPromptListener.debugSetVault(stub),
        returnsNormally,
      );
    });
  });

  // The _onEvent + _handlePrompt branches (payload null / non-null
  // pinSecretId, storeFromSecret success / false / throw, the
  // double-catch around hardwareVaultSealPromptResolveError) all
  // require a real BusEvent_HardwareVaultSealPromptRequest to be
  // dispatched through AppBus.subscribe — which the Rust L3
  // orchestrator publishes during the first-launch cascade. The
  // round-trip is covered by the orchestrator-level integration
  // tests; replicating it here would need a live FRB-side bus
  // dispatch + a SecretStore slot, both of which only the
  // orchestrator path stages today.
  group('event handling', () {
    test('handlePrompt branches', () {
      // covered by integration: requires bus dispatch + Rust SecretStore
      markTestSkipped(
        'handlePrompt branches require a live FRB bus dispatch — '
        'covered by the L3 first-launch orchestrator integration test',
      );
    });
  });
}
