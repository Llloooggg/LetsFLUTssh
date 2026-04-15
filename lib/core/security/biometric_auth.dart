import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';

import '../../utils/logger.dart';

/// Thin wrapper around [LocalAuthentication] for the optional biometric
/// unlock of master-password mode.
///
/// **Threat model**: biometrics is a UX shortcut, not a new cryptographic
/// layer — the master-password-derived KEK is the real secret, the
/// biometric gate only decides whether to reveal the cached key to the
/// process. A device without hardware biometrics, or one where the user
/// hasn't enrolled any, has [isAvailable] return false and the feature
/// hides itself in settings.
class BiometricAuth {
  final LocalAuthentication _auth;

  BiometricAuth({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  /// Whether this device has biometric hardware *and* at least one
  /// enrolled biometric (fingerprint / face / iris). Linux is always
  /// false — `local_auth` has no Linux backend. Windows depends on
  /// Windows Hello being configured.
  Future<bool> isAvailable() async {
    if (Platform.isLinux) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e) {
      AppLogger.instance.log(
        'Biometric availability probe failed: $e',
        name: 'BiometricAuth',
      );
      return false;
    }
  }

  /// Prompt the user for biometric confirmation. Returns true on success,
  /// false on cancel / fail / unavailable. [reason] is shown in the system
  /// prompt where the platform surfaces it (Android dialog, iOS Face ID
  /// overlay).
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Biometric authenticate failed: $e',
        name: 'BiometricAuth',
      );
      return false;
    }
  }
}
