import 'dart:async';

import '../core/bus/app_bus.dart';
import '../core/security/hardware_tier_vault.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/capabilities_orchestrator.dart' as rust_orch;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `HardwareVaultProbePromptRequest` events by calling the
/// existing Dart `HardwareTierVault.probeDetail()` helper
/// (Apple / Android / Windows method-channel) and dispatching
/// the platform-specific reason code back via FRB.
///
/// Linux never publishes this event — the orchestrator
/// short-circuits the Linux branch and lets the in-process
/// TPM CLI probe fill the snapshot's `hardware_probe_code` at
/// the provider layer.
///
/// The Rust capabilities orchestrator publishes the request
/// through the bus; this subscriber owns the `MethodChannel`
/// call because the Flutter plugin already audits that entry
/// point and there are no parallel native plugins per platform.
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState` alongside the other prompt listeners.
class HardwareVaultProbePromptListener {
  HardwareVaultProbePromptListener._();

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
        'HardwareVaultProbePromptListener subscribe failed: $e',
        name: 'HardwareVaultProbe',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_HardwareVaultProbePromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_HardwareVaultProbePromptRequest event,
  ) async {
    String code = 'unknown';
    try {
      code = await _vault.probeDetail();
    } catch (e) {
      AppLogger.instance.log(
        'HardwareVaultProbePromptListener probeDetail failed: $e',
        name: 'HardwareVaultProbe',
        level: LogLevel.warn,
      );
    }
    try {
      rust_orch.hardwareVaultProbePromptResolve(
        promptId: event.promptId,
        code: code,
      );
    } catch (e) {
      AppLogger.instance.log(
        'hardwareVaultProbePromptResolve dispatch failed: $e',
        name: 'HardwareVaultProbe',
        level: LogLevel.warn,
      );
    }
  }
}
