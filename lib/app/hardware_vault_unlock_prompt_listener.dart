import 'dart:async';

import '../core/bus/app_bus.dart';
import '../core/security/hardware_tier_vault.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `HardwareVaultUnlockPromptRequest` events by calling the
/// existing Dart `HardwareTierVault.read(pin)` helper.
///
/// The vault helper fans out per-platform:
/// - Linux: `tpm2-tools` shell-out (now Rust-side via the
///   `TpmClient` FRB wrapper).
/// - Apple / Android / Windows: `MethodChannel` invocation
///   into the platform vault (Secure Enclave / StrongBox /
///   WinBio-backed TPM).
///
/// The Rust L3 tier-unlock orchestrator publishes the request
/// through the bus; this subscriber owns the platform call
/// because `MethodChannel` is a Flutter primitive without a
/// Rust analogue and the per-platform vault APIs all sit
/// behind plugins.
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState` alongside the other prompt listeners.
class HardwareVaultUnlockPromptListener {
  HardwareVaultUnlockPromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;
  static HardwareTierVault _vault = HardwareTierVault();

  /// Inject a stub vault for tests. Production uses the default
  /// HardwareTierVault.
  static void debugSetVault(HardwareTierVault vault) {
    _vault = vault;
  }

  static void debugResetVault() {
    _vault = HardwareTierVault();
  }

  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'HardwareVaultUnlockPromptListener subscribe failed: $e',
        name: 'HardwareVaultUnlock',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_HardwareVaultUnlockPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  /// Run the platform vault unlock + dispatch the typed
  /// response. Plugin-level exceptions surface as
  /// `resolveError`; missing-key / wrong-PIN cases surface as
  /// `resolveWrong`.
  static Future<void> _handlePrompt(
    rust_bus.BusEvent_HardwareVaultUnlockPromptRequest event,
  ) async {
    final id = event.promptId;
    try {
      final unsealed = await _vault.read(event.pin);
      if (unsealed == null || unsealed.isEmpty) {
        rust_orch.hardwareVaultUnlockPromptResolveWrong(promptId: id);
      } else {
        rust_orch.hardwareVaultUnlockPromptResolve(
          promptId: id,
          bytes: unsealed,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareVaultUnlockPromptListener vault.read failed: $e',
        name: 'HardwareVaultUnlock',
        level: LogLevel.warn,
      );
      try {
        rust_orch.hardwareVaultUnlockPromptResolveError(
          promptId: id,
          message: e.toString(),
        );
      } catch (dispatchErr) {
        AppLogger.instance.log(
          'hardwareVaultUnlockPromptResolveError dispatch failed: $dispatchErr',
          name: 'HardwareVaultUnlock',
          level: LogLevel.warn,
        );
      }
    }
  }
}
