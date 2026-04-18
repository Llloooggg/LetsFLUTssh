import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';

import '../../utils/logger.dart';
import 'linux/fprintd_client.dart';

/// Why biometric unlock is unavailable. Distinguishes "no hardware"
/// from "hardware but nothing enrolled" so the UI can show a tooltip
/// that tells the user what to fix — instead of just hiding the
/// option and leaving them guessing.
enum BiometricUnavailableReason {
  /// OS has no biometric backend at all, or `local_auth` threw.
  platformUnsupported,

  /// Device reports no biometric hardware (most Windows desktops,
  /// older Android tablets, Linux without a supported fingerprint
  /// reader).
  noSensor,

  /// Hardware is present but the user hasn't enrolled a fingerprint
  /// or face — e.g. a Windows Hello PIN without a bio credential, or
  /// a Linux reader with no fingers registered via `fprintd-enroll`.
  notEnrolled,

  /// The OS-level service that brokers biometric access is not
  /// installed or not reachable. Specific to Linux — `fprintd` is a
  /// system D-Bus daemon packaged separately from the kernel and is
  /// not present on minimal installs. Triggers the rung-3 (optional
  /// OS dep) install snippet in README.
  systemServiceMissing,
}

/// How the platform is protecting the cached DB key when biometrics
/// are active. Surfaced to the Settings UI so the user can tell
/// whether the key is bound to dedicated hardware (Secure Enclave /
/// Titan M / TPM) or to an OS software keystore.
///
/// This is orthogonal to [BiometricAvailability]: a non-null level is
/// only meaningful when availability is `null` (biometrics are active).
enum BiometricBackingLevel {
  /// Key is wrapped by dedicated crypto hardware — Secure Enclave on
  /// Apple, StrongBox / TEE on Android, TPM2 on Linux/Windows.
  hardware,

  /// Key is held by an OS software keystore (no dedicated hardware,
  /// or hardware present but not used for this key). Honestly labelled
  /// so the user understands the guarantee is weaker than a hardware
  /// backing on a peer platform.
  software,
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
  final FprintdClient _fprintd;

  BiometricAuth({LocalAuthentication? auth, FprintdClient? fprintdClient})
    : _auth = auth ?? LocalAuthentication(),
      _fprintd = fprintdClient ?? FprintdClient();

  /// Convenience: true if [availability] returns null.
  Future<bool> isAvailable() async => (await availability()) == null;

  /// Describe how the current platform protects the cached DB key.
  ///
  /// Returns `null` when biometrics are unavailable on this platform
  /// entirely (Linux in the current build — follow-on commits wire
  /// the fprintd + TPM2 path). Otherwise returns the backing level
  /// that Settings surfaces next to the active biometric toggle.
  ///
  /// iOS / macOS report [BiometricBackingLevel.hardware] — Secure
  /// Enclave binding is enforced via `SecAccessControl` with
  /// `.biometryCurrentSet` (see `BiometricKeyVault.iosOptions` /
  /// `macOsOptions`). Android rides on `flutter_secure_storage`'s
  /// default EncryptedSharedPreferences until a dedicated Keystore
  /// + `BiometricPrompt.CryptoObject` plugin lands, so the level is
  /// reported as [BiometricBackingLevel.software] today. Windows is
  /// also reported as software until `KeyCredentialManager` replaces
  /// DPAPI.
  BiometricBackingLevel? backingLevel() {
    if (Platform.isIOS || Platform.isMacOS) {
      return BiometricBackingLevel.hardware;
    }
    if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
      // Linux currently rides on fprintd + libsecret — software-only.
      // A TPM2 seal layer added later will flip this to hardware when
      // the TPM path is actually wired into store/read.
      return BiometricBackingLevel.software;
    }
    return null;
  }

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
    if (Platform.isLinux) return _linuxAvailability();
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
  /// overlay). Ignored on Linux — `fprintd` renders its own prompt via
  /// whatever reader the kernel exposes; we only await the terminal
  /// `VerifyStatus` signal.
  Future<bool> authenticate(String reason) async {
    if (Platform.isLinux) return _fprintd.verify();
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

  /// Linux availability probe: walks the [FprintdClient] ladder so the
  /// Settings UI can surface a specific reason (daemon missing / reader
  /// absent / no finger enrolled) instead of a generic "unsupported".
  ///
  /// Order matters — `isServiceReachable` must succeed before
  /// `hasEnrolledFingers` is meaningful, and both of those run before
  /// we claim biometrics are ready. Any D-Bus error along the way
  /// collapses into `systemServiceMissing` so the README install
  /// snippet is surfaced rather than a raw protocol error.
  Future<BiometricAvailability> _linuxAvailability() async {
    try {
      if (!await _fprintd.isServiceReachable()) {
        return BiometricUnavailableReason.systemServiceMissing;
      }
      if (!await _fprintd.hasEnrolledFingers()) {
        return BiometricUnavailableReason.notEnrolled;
      }
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'Linux biometric probe failed: $e',
        name: 'BiometricAuth',
      );
      return BiometricUnavailableReason.systemServiceMissing;
    }
  }
}
