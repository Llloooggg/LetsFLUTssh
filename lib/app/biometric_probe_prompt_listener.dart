import 'dart:async';

import 'package:local_auth/local_auth.dart';

import '../core/bus/app_bus.dart';
import '../src/rust/api/biometric_probe_prompt.dart' as rust_bio;
import '../src/rust/api/bus.dart' as rust_bus;
import '../utils/logger.dart';

/// Subscribes to the `SecurityPrompt` bus topic and resolves
/// `BiometricProbePromptRequest` events by calling
/// `local_auth.canCheckBiometrics` + an enrolment check, then
/// dispatching the typed response back via FRB.
///
/// Per Decision 1 + Decision 2 in
/// `docs/RUST_MIGRATION_REMAINING.md`: the C5 capabilities
/// cache actor publishes the request through the bus; the
/// Dart subscriber owns the `local_auth` plugin call (no
/// mature Rust crate covers every target platform's API).
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState` alongside the other prompt listeners.
class BiometricProbePromptListener {
  BiometricProbePromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;
  static LocalAuthentication _auth = LocalAuthentication();

  /// Inject a stub `local_auth` for tests. Production passes
  /// the real instance through the implicit default.
  static void debugSetAuth(LocalAuthentication auth) {
    _auth = auth;
  }

  static void debugResetAuth() {
    _auth = LocalAuthentication();
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
        'BiometricProbePromptListener subscribe failed: $e',
        name: 'BiometricProbe',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_BiometricProbePromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  /// Handle a single biometric probe: ask local_auth whether
  /// hardware can check biometrics + has an enrolment, dispatch
  /// the typed response. Failures map to `available=false` with
  /// a per-platform classifier code so the capabilities cache
  /// actor branches without parsing strings.
  static Future<void> _handlePrompt(
    rust_bus.BusEvent_BiometricProbePromptRequest event,
  ) async {
    bool available = false;
    String classifierCode = '';
    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) {
        classifierCode = 'plugin_returned_false';
      } else {
        final enrolments = await _auth.getAvailableBiometrics();
        if (enrolments.isEmpty) {
          classifierCode = 'no_enrolment';
        } else {
          available = true;
        }
      }
    } catch (e) {
      // local_auth throws PlatformException with a code that
      // varies per platform; surface the message verbatim so
      // a support trace pins which platform branch tripped.
      classifierCode = 'plugin_error: $e';
      AppLogger.instance.log(
        'BiometricProbePromptListener.canCheckBiometrics failed: $e',
        name: 'BiometricProbe',
        level: LogLevel.warn,
      );
    }
    try {
      rust_bio.biometricProbePromptResolve(
        promptId: event.promptId,
        available: available,
        classifierCode: classifierCode,
      );
    } catch (e) {
      AppLogger.instance.log(
        'biometricProbePromptResolve dispatch failed: $e',
        name: 'BiometricProbe',
        level: LogLevel.warn,
      );
    }
  }
}
