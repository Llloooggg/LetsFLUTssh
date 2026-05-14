import 'dart:async';

import '../core/bus/app_bus.dart';
import '../core/security/secure_key_storage.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/capabilities_orchestrator.dart' as rust_orch;
import '../src/rust/api/security_capabilities.dart' show DbKeyringProbeResult;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `KeychainProbePromptRequest` events by running the
/// `SecureKeyStorage.probe()` write-read-delete round-trip
/// through `lfs_os_security::secure_key_storage` and dispatching
/// the typed `DbKeyringProbeResult` enum back via FRB. Rust maps
/// the enum to the canonical wire name when feeding the
/// prompt registry — Dart never touches the string form.
///
/// The Rust capabilities orchestrator publishes the request
/// through the bus; this Dart-side subscriber drives the probe
/// because the round-trip happens UI-side anyway (the user
/// is waiting on the wizard / Settings card render at the same
/// time) and routing the result back through one bus event keeps
/// the Rust orchestrator's `tokio::join!` snapshot composable
/// with the other parallel probes.
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState` alongside the other prompt listeners.
class KeychainProbePromptListener {
  KeychainProbePromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;
  static SecureKeyStorage _storage = SecureKeyStorage();

  /// Inject a stub probe for tests. Production uses the default
  /// SecureKeyStorage.
  static void debugSetStorage(SecureKeyStorage storage) {
    _storage = storage;
  }

  static void debugResetStorage() {
    _storage = SecureKeyStorage();
  }

  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'KeychainProbePromptListener subscribe failed: $e',
        name: 'KeychainProbe',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_KeychainProbePromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_KeychainProbePromptRequest event,
  ) async {
    DbKeyringProbeResult result = DbKeyringProbeResult.probeFailed;
    try {
      result = await _storage.probe();
    } catch (e) {
      AppLogger.instance.log(
        'KeychainProbePromptListener probe failed: $e',
        name: 'KeychainProbe',
        level: LogLevel.warn,
      );
    }
    try {
      rust_orch.keychainProbePromptResolve(
        promptId: event.promptId,
        result: result,
      );
    } catch (e) {
      AppLogger.instance.log(
        'keychainProbePromptResolve dispatch failed: $e',
        name: 'KeychainProbe',
        level: LogLevel.warn,
      );
    }
  }
}
