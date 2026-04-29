import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/keychain_op_prompt.dart' as rust_op;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `KeychainOpPromptRequest` events by executing the matching
/// `flutter_secure_storage` op (read / contains / write / delete)
/// and dispatching the typed response back via FRB.
///
/// Rust actors compose the disk-side discipline (atomic write,
/// rollback, file deletes) and publish op prompts when they need
/// the keychain side; this subscriber owns the keychain plugin
/// call because the Flutter plugin already audits that entry
/// point and there is no native Rust crate covering every
/// target platform's keychain backend.
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState` alongside the other prompt listeners.
class KeychainOpPromptListener {
  KeychainOpPromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;
  static FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Inject a stub `flutter_secure_storage` for tests. Production
  /// passes the real instance through the implicit default.
  static void debugSetStorage(FlutterSecureStorage storage) {
    _storage = storage;
  }

  static void debugResetStorage() {
    _storage = const FlutterSecureStorage();
  }

  /// Idempotent — repeated calls re-bind to the same singleton
  /// subscription so a hot-reload or a second wire pass doesn't
  /// stack listeners.
  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'KeychainOpPromptListener subscribe failed: $e',
        name: 'KeychainOp',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_KeychainOpPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  /// Branch on the op wire name and execute the matching
  /// flutter_secure_storage call. Plugin failures map to
  /// `keychain_op_prompt_resolve_error` so the Rust actor can
  /// roll back any prior disk side-effect.
  static Future<void> _handlePrompt(
    rust_bus.BusEvent_KeychainOpPromptRequest event,
  ) async {
    final id = event.promptId;
    try {
      switch (event.opWireName) {
        case 'read':
          final value = await _storage.read(key: event.key);
          if (value == null || value.isEmpty) {
            rust_op.keychainOpPromptResolveAbsent(promptId: id);
          } else {
            // The L2 read path keeps the pepper as a base64 string
            // in the keychain slot; the existing Rust actor decodes
            // via the dedicated pepper-read registry, so this code
            // path mostly exists for symmetry / future op consumers
            // (the L2 setPassword / clear / isConfigured cutover
            // routes contains/write/delete here, not read).
            rust_op.keychainOpPromptResolve(
              promptId: id,
              bytes: value.codeUnits,
            );
          }
        case 'contains':
          final present = await _storage.containsKey(key: event.key);
          if (present) {
            rust_op.keychainOpPromptResolveContainsPresent(promptId: id);
          } else {
            rust_op.keychainOpPromptResolveAbsent(promptId: id);
          }
        case 'write':
          // Rust passes the value as base64 — store it verbatim
          // (the Dart-era code does the same), so the existing
          // pepper-read path keeps round-tripping.
          final b64 = event.valueB64 ?? '';
          await _storage.write(key: event.key, value: b64);
          rust_op.keychainOpPromptResolve(promptId: id, bytes: const <int>[]);
        case 'delete':
          await _storage.delete(key: event.key);
          rust_op.keychainOpPromptResolve(promptId: id, bytes: const <int>[]);
        default:
          rust_op.keychainOpPromptResolveError(
            promptId: id,
            message: 'unknown op_wire_name: ${event.opWireName}',
          );
      }
    } catch (e) {
      AppLogger.instance.log(
        'KeychainOpPromptListener op="${event.opWireName}" failed: $e',
        name: 'KeychainOp',
        level: LogLevel.warn,
      );
      try {
        rust_op.keychainOpPromptResolveError(
          promptId: id,
          message: e.toString(),
        );
      } catch (dispatchErr) {
        AppLogger.instance.log(
          'keychainOpPromptResolveError dispatch failed: $dispatchErr',
          name: 'KeychainOp',
          level: LogLevel.warn,
        );
      }
    }
  }
}
