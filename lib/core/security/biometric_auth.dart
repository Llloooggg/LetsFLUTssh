import 'dart:async' show TimeoutException;
import 'dart:io' show Platform;

import 'package:meta/meta.dart' show visibleForTesting;

import '../../src/rust/api/fprintd.dart' as rust_fprintd;
import '../../src/rust/api/os_security.dart' as rust_os;
import '../../src/rust/api/tpm.dart' as rust_tpm;
import '../../utils/logger.dart';

/// Why biometric unlock is unavailable. Distinguishes "no hardware"
/// from "hardware but nothing enrolled" so the UI can show a tooltip
/// that tells the user what to fix — instead of just hiding the
/// option and leaving them guessing.
enum BiometricUnavailableReason {
  /// OS has no biometric backend at all, or the platform probe threw.
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

/// Map a Rust `DbBiometricAvailability` variant onto its
/// [BiometricUnavailableReason] equivalent (or `null` for the
/// "available" variant). Pulled out of `_rustAvailability` so the
/// 6-way mapping can be exercised against every variant without
/// booting the Rust biometric probe — the platform side of the
/// switch is the same Rust binary on every host, so coverage of the
/// mapping is the only Dart-side honest test there is.
///
/// `Probe(reason)` is a Rust-side error indicator (e.g. WinRT call
/// failed); the helper logs the message and falls back to
/// [BiometricUnavailableReason.platformUnsupported] so the UI
/// surfaces a single "biometric unreachable" branch instead of
/// leaking platform diagnostic strings.
BiometricAvailability mapRustBiometricAvailability(
  rust_os.DbBiometricAvailability r,
) {
  return switch (r) {
    rust_os.DbBiometricAvailability_Available() => null,
    rust_os.DbBiometricAvailability_PlatformUnsupported() =>
      BiometricUnavailableReason.platformUnsupported,
    rust_os.DbBiometricAvailability_NoSensor() =>
      BiometricUnavailableReason.noSensor,
    rust_os.DbBiometricAvailability_NotEnrolled() =>
      BiometricUnavailableReason.notEnrolled,
    rust_os.DbBiometricAvailability_SystemServiceMissing() =>
      BiometricUnavailableReason.systemServiceMissing,
    rust_os.DbBiometricAvailability_Probe(:final field0) => () {
      AppLogger.instance.log(
        'Biometric probe error: $field0',
        name: 'BiometricAuth',
      );
      return BiometricUnavailableReason.platformUnsupported;
    }(),
  };
}

/// Thin wrapper around the platform biometric backend for the optional
/// biometric unlock on T1+password and T2+password. Paranoid does not
/// expose a biometric shortcut by design — see ARCHITECTURE §3.6 →
/// Biometric unlock for the rationale.
///
/// **Threat model**: biometrics is a UX shortcut, not a new cryptographic
/// layer — the tier's user-typed secret is the real gate, the biometric
/// slot only decides whether to reveal the cached key without requiring
/// the user to retype.
///
/// Routing:
/// - **Apple (iOS + macOS) / Windows / Android** — Rust crate
///   `lfs_os_security::biometric_auth` over FRB. Apple uses
///   `LAContext` via objc2; Windows uses `UserConsentVerifier`;
///   Android calls `BiometricPrompt` directly via JNI. Same
///   `BiometricUnavailableReason` shape on every backend.
/// - **Linux** — direct FRB call into
///   `lfs_core::platform::linux::fprintd` (`zbus`-driven D-Bus
///   walk inside Rust). Splits "daemon missing" / "reader absent"
///   / "no finger enrolled" so the UI can surface a specific
///   reason instead of collapsing them into a generic
///   "unsupported".
class BiometricAuth {
  /// Linux fprintd / TPM probes are FRB calls into Rust; tests
  /// override these function pointers with deterministic answers
  /// instead of bootstrapping the native lib.
  final Future<bool> Function() _fprintdReachable;
  final Future<bool> Function() _fprintdHasEnrolled;
  final Future<bool> Function() _fprintdVerify;
  final Future<bool> Function() _tpmAvailable;

  BiometricAuth({
    @visibleForTesting Future<bool> Function()? fprintdReachable,
    @visibleForTesting Future<bool> Function()? fprintdHasEnrolled,
    @visibleForTesting Future<bool> Function()? fprintdVerify,
    @visibleForTesting Future<bool> Function()? tpmAvailable,
  }) : _fprintdReachable =
           fprintdReachable ?? rust_fprintd.fprintdIsServiceReachable,
       _fprintdHasEnrolled =
           fprintdHasEnrolled ?? rust_fprintd.fprintdHasEnrolledFingers,
       _fprintdVerify = fprintdVerify ?? _defaultFprintdVerify,
       _tpmAvailable = tpmAvailable ?? _defaultTpmAvailable;

  static const int _fprintdVerifyTimeoutMs = 30000;

  static Future<bool> _defaultFprintdVerify() =>
      rust_fprintd.fprintdVerify(timeoutMs: _fprintdVerifyTimeoutMs);

  static Future<bool> _defaultTpmAvailable() async {
    // `tpmProbe` accepts `null` for binary / device / timeoutMs and
    // applies the canonical lfs_core defaults; passing Dart-side
    // literals would duplicate the platform defaults across the FRB
    // boundary.
    final result = await rust_tpm.tpmProbe();
    return result == rust_tpm.DbTpmProbeResult.available;
  }

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
  /// `lfs_os_security::android::keystore` which gates wrap-keys with
  /// `setUserAuthenticationRequired` + `setIsStrongBoxBacked` when
  /// available, so the level is reported as
  /// [BiometricBackingLevel.software] here and the T2 hw-vault
  /// surfaces the more specific StrongBox answer separately.
  /// Windows is reported as software; the hw-vault probe returns
  /// `hardware_tpm` when CNG's Platform Crypto Provider backed the
  /// primary key, and the Settings UI prefers that more specific
  /// answer when T2 is the active tier. Linux upgrades to hardware
  /// whenever a TPM2 device + `tpm2-tools` binary are both reachable
  /// — otherwise the fprintd + libsecret path is honestly labelled
  /// software.
  ///
  /// Every call goes through to the Rust-owned probes (TPM CLI
  /// round-trip on Linux, constant on every other platform) so the
  /// answer can never drift from a Rust-side state change. Callers
  /// are the Settings card and the unlock-path probe; both fire at
  /// human cadence, not in a tight loop.
  Future<BiometricBackingLevel?> backingLevel() async {
    if (Platform.isIOS || Platform.isMacOS) {
      return BiometricBackingLevel.hardware;
    }
    if (Platform.isAndroid || Platform.isWindows) {
      return BiometricBackingLevel.software;
    }
    if (Platform.isLinux) {
      return await _tpmAvailable()
          ? BiometricBackingLevel.hardware
          : BiometricBackingLevel.software;
    }
    return null;
  }

  /// Probe the platform for biometric hardware + enrollment. Returns
  /// null when biometric unlock is ready to use, or a
  /// [BiometricUnavailableReason] describing why it isn't.
  ///
  /// Windows accepts the `UserConsentVerifier` answer at face value
  /// — a Hello-PIN-only setup is a valid OS-gated biometric overlay
  /// the user can flip into, so demoting to "no sensor" because no
  /// physical reader is attached would block a usable shortcut.
  ///
  /// Every call dispatches to Rust (LAContext / WinRT /
  /// BiometricManager / fprintd via FRB) so a fresh enrolment, a
  /// reader plugged in mid-session, or a tier transition shows up on
  /// the very next read without a Dart-side invalidator. Call sites
  /// are user-paced (Settings rebuild + connect dialog open + unlock
  /// path); no tight-loop caller exists.
  Future<BiometricAvailability> availability() async {
    if (Platform.isLinux) return _linuxAvailability();
    if (Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isAndroid) {
      return _rustAvailability();
    }
    return BiometricUnavailableReason.platformUnsupported;
  }

  /// Apple / Windows / Android availability via the platform's
  /// biometric availability probe — routes through
  /// `lfs_os_security::biometric_auth`. Apple uses
  /// `LAContext.canEvaluatePolicy`; Windows uses
  /// `UserConsentVerifier.CheckAvailabilityAsync`; Android calls
  /// `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)` via JNI.
  /// Each maps platform-specific status codes to the same
  /// structured `BiometricUnavailableReason` the Settings UI renders.
  Future<BiometricAvailability> _rustAvailability() async {
    try {
      final result = await rust_os.osSecurityBiometricAvailability();
      return mapRustBiometricAvailability(result);
    } catch (e) {
      AppLogger.instance.log(
        'Biometric availability (Rust) failed: $e',
        name: 'BiometricAuth',
      );
      return BiometricUnavailableReason.platformUnsupported;
    }
  }

  /// How long to wait for the system biometric prompt before giving up
  /// and falling the caller back to the password field. 45 s is well
  /// past a normal fingerprint/face unlock (<5 s) but short enough
  /// that a hung prompt doesn't look like a frozen app. After Android
  /// Doze / App-Standby releases the process, the platform call
  /// sometimes never completes — the system prompt is still visible
  /// but the underlying Promise/Future never resolves. Without this
  /// cap the Dart future hangs forever and the lock screen appears
  /// frozen on resume.
  static const Duration _authTimeout = Duration(seconds: 45);

  /// Prompt the user for biometric confirmation. Returns true on success,
  /// false on cancel / fail / unavailable / timeout. [reason] is shown
  /// in the system prompt where the platform surfaces it (Android
  /// dialog, iOS Face ID overlay, Windows Hello banner). Ignored on
  /// Linux — `fprintd` renders its own prompt via whatever reader the
  /// kernel exposes; we only await the terminal `VerifyStatus` signal.
  Future<bool> authenticate(String reason) async {
    if (Platform.isLinux) return _fprintdVerify();
    if (Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isAndroid) {
      try {
        return await rust_os
            .osSecurityBiometricAuthenticate(reason: reason)
            .timeout(_authTimeout);
      } on TimeoutException {
        AppLogger.instance.log(
          'Native biometric authenticate timed out after '
          '${_authTimeout.inSeconds}s; falling back to password prompt',
          name: 'BiometricAuth',
          level: LogLevel.warn,
        );
        return false;
      } catch (e) {
        AppLogger.instance.log(
          'Native biometric authenticate (Rust) failed: $e',
          name: 'BiometricAuth',
        );
        return false;
      }
    }
    return false;
  }

  /// Linux availability probe: walks the FRB-driven fprintd ladder so
  /// the Settings UI can surface a specific reason (daemon missing /
  /// reader absent / no finger enrolled) instead of a generic
  /// "unsupported".
  ///
  /// Order matters — `isServiceReachable` must succeed before
  /// `hasEnrolledFingers` is meaningful, and both of those run before
  /// we claim biometrics are ready. Any D-Bus error along the way
  /// collapses into `systemServiceMissing` so the README install
  /// snippet is surfaced rather than a raw protocol error.
  Future<BiometricAvailability> _linuxAvailability() async {
    try {
      if (!await _fprintdReachable()) {
        return BiometricUnavailableReason.systemServiceMissing;
      }
      if (!await _fprintdHasEnrolled()) {
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
