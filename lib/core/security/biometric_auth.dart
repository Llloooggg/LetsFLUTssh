import 'dart:async' show TimeoutException;
import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';

import '../../utils/logger.dart';
import 'linux/fprintd_client.dart';
import 'linux/tpm_client.dart';
import 'windows/winbio_probe.dart';

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
/// unlock on T1+password and T2+password. Paranoid does not expose a
/// biometric shortcut by design — see ARCHITECTURE §3.6 → Biometric
/// unlock for the rationale.
///
/// **Threat model**: biometrics is a UX shortcut, not a new cryptographic
/// layer — the tier's user-typed secret is the real gate, the biometric
/// slot only decides whether to reveal the cached key without requiring
/// the user to retype.
class BiometricAuth {
  final LocalAuthentication _auth;
  final FprintdClient _fprintd;
  final TpmClient _tpm;
  final WinBioProbe _winbio;

  BiometricAuth({
    LocalAuthentication? auth,
    FprintdClient? fprintdClient,
    TpmClient? tpmClient,
    WinBioProbe? winbioProbe,
  }) : _auth = auth ?? LocalAuthentication(),
       _fprintd = fprintdClient ?? FprintdClient(),
       _tpm = tpmClient ?? TpmClient(),
       _winbio = winbioProbe ?? const WinBioProbe();

  /// Convenience: true if [availability] returns null.
  Future<bool> isAvailable() async => (await availability()) == null;

  /// Describe how the current platform protects the cached DB key.
  ///
  /// Returns `null` when biometrics are unavailable on this platform
  /// entirely. Otherwise returns the backing level Settings surfaces
  /// next to the active biometric toggle.
  ///
  /// Probe is async because Linux needs a live TPM2 probe (file
  /// existence + `tpm2 getcap` round-trip) to decide hardware vs
  /// software. iOS / macOS report [BiometricBackingLevel.hardware]
  /// unconditionally — Secure Enclave binding is enforced via
  /// `SecAccessControl` with `.biometryCurrentSet`. Android rides on
  /// `flutter_secure_storage`'s default EncryptedSharedPreferences
  /// until a dedicated Keystore + `BiometricPrompt.CryptoObject`
  /// plugin lands, so the level is reported as
  /// [BiometricBackingLevel.software] today. Windows is reported as
  /// software here; the hw-vault plugin's `backingLevel` method call
  /// returns `hardware_tpm` when CNG's Platform Crypto Provider
  /// backed the primary key, and the Settings UI prefers that more
  /// specific answer when T2 is the active tier. Linux upgrades to
  /// hardware whenever a TPM2 device + `tpm2-tools`
  /// binary are both reachable — otherwise the fprintd + libsecret
  /// path is honestly labelled software.
  Future<BiometricBackingLevel?> backingLevel() async {
    if (Platform.isIOS || Platform.isMacOS) {
      return BiometricBackingLevel.hardware;
    }
    if (Platform.isAndroid || Platform.isWindows) {
      return BiometricBackingLevel.software;
    }
    if (Platform.isLinux) {
      return await _tpm.isAvailable()
          ? BiometricBackingLevel.hardware
          : BiometricBackingLevel.software;
    }
    return null;
  }

  /// Probe the platform for biometric hardware + enrollment. Returns
  /// null when biometric unlock is ready to use, or a
  /// [BiometricUnavailableReason] describing why it isn't.
  ///
  /// Windows caveat: `canCheckBiometrics` + a non-empty
  /// `getAvailableBiometrics` only signal that Windows Hello is
  /// configured — which is satisfied by a PIN alone. Two safeguards
  /// apply:
  ///
  ///   1. The enrolled list is filtered for a real bio type
  ///      (fingerprint, face, iris, strong). A PIN-only Hello device
  ///      therefore falls to [BiometricUnavailableReason.notEnrolled].
  ///   2. An extra `winbio.dll` probe enumerates the *physical*
  ///      biometric sensors attached to the host — local_auth has
  ///      been observed returning `BiometricType.strong` on Hello
  ///      PIN-only setups depending on the build, so the Dart-side
  ///      filter alone isn't enough. Zero units → the hardware isn't
  ///      there; the toggle must not light up, regardless of what
  ///      UserConsentVerifier claims. The probe is a straight
  ///      `WinBioEnumBiometricUnits(factor=FINGERPRINT|FACIAL|IRIS)`
  ///      + `WinBioFree` — no prompts, no side effects, runs on every
  ///      Windows SKU we ship to.
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
      if (Platform.isWindows) {
        final units = await _winbio.countBiometricUnits();
        if (units == 0) {
          AppLogger.instance.log(
            'WinBio reports zero biometric units; demoting Hello to noSensor',
            name: 'BiometricAuth',
          );
          return BiometricUnavailableReason.noSensor;
        }
      }
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'Biometric availability probe failed: $e',
        name: 'BiometricAuth',
      );
      return BiometricUnavailableReason.platformUnsupported;
    }
  }

  /// How long to wait for the system biometric prompt before giving up
  /// and falling the caller back to the password field. 45 s is well
  /// past a normal fingerprint/face unlock (<5 s) but short enough
  /// that a hung prompt doesn't look like a frozen app. After Android
  /// Doze / App-Standby releases the process, `local_auth`'s
  /// `authenticate` sometimes never completes — the platform channel
  /// silently drops the reply while the native prompt is still
  /// visible. Without this cap the Dart future hangs forever and the
  /// lock screen appears frozen on resume.
  static const Duration _authTimeout = Duration(seconds: 45);

  /// Prompt the user for biometric confirmation. Returns true on success,
  /// false on cancel / fail / unavailable / timeout. [reason] is shown
  /// in the system prompt where the platform surfaces it (Android
  /// dialog, iOS Face ID overlay). Ignored on Linux — `fprintd`
  /// renders its own prompt via whatever reader the kernel exposes;
  /// we only await the terminal `VerifyStatus` signal.
  Future<bool> authenticate(String reason) async {
    if (Platform.isLinux) return _fprintd.verify();
    try {
      return await _auth
          .authenticate(
            localizedReason: reason,
            biometricOnly: true,
            persistAcrossBackgrounding: true,
          )
          .timeout(_authTimeout);
    } on TimeoutException {
      AppLogger.instance.log(
        'Biometric authenticate timed out after '
        '${_authTimeout.inSeconds}s; falling back to password prompt',
        name: 'BiometricAuth',
      );
      return false;
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
