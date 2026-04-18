import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';

import '../../utils/logger.dart';

/// Why biometric unlock is unavailable. Distinguishes "no hardware"
/// from "hardware but nothing enrolled" so the UI can show a tooltip
/// that tells the user what to fix — instead of just hiding the
/// option and leaving them guessing.
enum BiometricUnavailableReason {
  /// OS has no biometric backend at all (Linux, or `local_auth` threw).
  platformUnsupported,

  /// Device reports no biometric hardware (most Windows desktops,
  /// older Android tablets).
  noSensor,

  /// Hardware is present but the user hasn't enrolled a fingerprint
  /// or face — e.g. a Windows Hello PIN without a bio credential.
  notEnrolled,
}

/// Availability probe result — either [BiometricUnavailableReason] or
/// null meaning "available". A dedicated type keeps the settings UI
/// from mis-using `null` vs `false` as overlapping "no" states.
typedef BiometricAvailability = BiometricUnavailableReason?;

/// Thin wrapper around [LocalAuthentication] for the optional biometric
/// unlock of master-password mode.
///
/// **Threat model**: biometrics is a UX shortcut, not a new cryptographic
/// layer — the master-password-derived KEK is the real secret, the
/// biometric gate only decides whether to reveal the cached key to the
/// process.
class BiometricAuth {
  final LocalAuthentication _auth;

  BiometricAuth({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  /// Convenience: true if [availability] returns null.
  Future<bool> isAvailable() async => (await availability()) == null;

  /// Probe the platform for biometric hardware + enrollment. Returns
  /// null when biometric unlock is ready to use, or a
  /// [BiometricUnavailableReason] describing why it isn't.
  ///
  /// Windows caveat: `canCheckBiometrics` + a non-empty
  /// `getAvailableBiometrics` only signal that Windows Hello is
  /// configured — which is satisfied by a PIN alone. We additionally
  /// filter the enrolled list for a real bio type (fingerprint, face,
  /// iris, strong) so a PIN-only Hello device is correctly reported
  /// as [BiometricUnavailableReason.notEnrolled] instead of claiming
  /// biometrics work.
  Future<BiometricAvailability> availability() async {
    if (Platform.isLinux) return BiometricUnavailableReason.platformUnsupported;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricUnavailableReason.noSensor;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return BiometricUnavailableReason.notEnrolled;
      final enrolled = await _auth.getAvailableBiometrics();
      final hasRealBiometric = enrolled.any(
        (t) =>
            t == BiometricType.fingerprint ||
            t == BiometricType.face ||
            t == BiometricType.iris ||
            t == BiometricType.strong,
      );
      if (!hasRealBiometric) return BiometricUnavailableReason.notEnrolled;
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'Biometric availability probe failed: $e',
        name: 'BiometricAuth',
      );
      return BiometricUnavailableReason.platformUnsupported;
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
