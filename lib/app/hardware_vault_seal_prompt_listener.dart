import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/bus/app_bus.dart';
import '../core/security/hardware_tier_vault.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `HardwareVaultSealPromptRequest` events by calling the
/// existing Dart `HardwareTierVault.store(dbKey, pin)` helper.
///
/// Mirrors the unlock-prompt listener shape — the L3 first-launch
/// orchestrator generates a fresh DB key Rust-side, publishes the
/// seal-prompt request, and waits for this subscriber to write the
/// platform-vault blob. On success the orchestrator stages the
/// same bytes in the SecretStore + emits the unlock cascade.
class HardwareVaultSealPromptListener {
  HardwareVaultSealPromptListener._();

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
        'HardwareVaultSealPromptListener subscribe failed: $e',
        name: 'HardwareVaultSeal',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_HardwareVaultSealPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_HardwareVaultSealPromptRequest event,
  ) async {
    final id = event.promptId;
    // Take (atomic read-and-remove) the staged secrets out of
    // the SecretStore. The bytes never travelled inline through
    // the broadcast channel — only the opaque ids did, so this
    // is the first point where Dart actually sees the plaintext.
    // After this single hand-off the Rust side has nothing
    // pinned, and the Dart-heap residency is bounded by the
    // single store() call below.
    final dbKey = rust_app.secretsTake(id: event.dbKeySecretId);
    final pinSecretId = event.pinSecretId;
    String? pin;
    if (pinSecretId != null) {
      final pinBytes = rust_app.secretsTake(id: pinSecretId);
      pin = pinBytes.isEmpty ? null : utf8.decode(pinBytes);
    }
    try {
      final stored = await _vault.store(
        dbKey: Uint8List.fromList(dbKey),
        pin: pin,
      );
      if (stored) {
        rust_orch.hardwareVaultSealPromptResolve(promptId: id);
      } else {
        rust_orch.hardwareVaultSealPromptResolveError(
          promptId: id,
          message: 'hardware_vault_store_returned_false',
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareVaultSealPromptListener vault.store failed: $e',
        name: 'HardwareVaultSeal',
        level: LogLevel.warn,
      );
      try {
        rust_orch.hardwareVaultSealPromptResolveError(
          promptId: id,
          message: e.toString(),
        );
      } catch (dispatchErr) {
        AppLogger.instance.log(
          'hardwareVaultSealPromptResolveError dispatch failed: $dispatchErr',
          name: 'HardwareVaultSeal',
          level: LogLevel.warn,
        );
      }
    }
  }
}
