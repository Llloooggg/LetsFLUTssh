import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/keychain_pepper_prompt.dart' as rust_pepper;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `KeychainPepperPromptRequest` events by pulling the
/// `letsflutssh_l2_pepper` value from `flutter_secure_storage`
/// and dispatching the typed response back via FRB.
///
/// The Rust L2 verify actor publishes the request through the
/// bus; this subscriber owns the keychain plugin call because
/// the Flutter plugin already audits that entry point and
/// there is no native Rust crate covering every target
/// platform's keychain backend.
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState` after the navigator + secure-storage
/// providers are mounted; the subscription survives unlock
/// cycles because the bus is a process singleton.
class KeychainPepperPromptListener {
  KeychainPepperPromptListener._();

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
        'KeychainPepperPromptListener subscribe failed: $e',
        name: 'L2Gate',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_KeychainPepperPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  /// Handle a single pepper prompt: read keychain entry, decode
  /// base64, dispatch the typed response. On any failure
  /// (entry missing / read threw / base64 bad), dispatch an
  /// empty `Vec` which the Rust resolver maps to `None` —
  /// caller routes through the L2 reset path.
  static Future<void> _handlePrompt(
    rust_bus.BusEvent_KeychainPepperPromptRequest event,
  ) async {
    List<int> bytes = const <int>[];
    try {
      final pepperB64 = await _storage.read(key: 'letsflutssh_l2_pepper');
      if (pepperB64 != null && pepperB64.isNotEmpty) {
        bytes = base64.decode(pepperB64);
      }
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPepperPromptListener.read failed: $e',
        name: 'L2Gate',
        level: LogLevel.warn,
      );
    }
    try {
      rust_pepper.keychainPepperPromptResolve(
        promptId: event.promptId,
        pepperBytes: bytes,
      );
    } catch (e) {
      AppLogger.instance.log(
        'keychainPepperPromptResolve dispatch failed: $e',
        name: 'L2Gate',
        level: LogLevel.warn,
      );
    }
  }
}
