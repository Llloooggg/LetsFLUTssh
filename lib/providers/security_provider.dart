import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/active_dbkey.dart';
import '../core/security/biometric_auth.dart';
import '../core/security/biometric_key_vault.dart';
import '../core/security/hardware_tier_vault.dart';
import '../core/security/keychain_password_gate.dart';
import '../core/security/secure_key_storage.dart';
import '../src/rust/api/app.dart' as rust_secrets;
import '../src/rust/api/security_capabilities.dart'
    show DbKeyringProbeResult, DbSecurityCapabilities;
import '../src/rust/api/tpm.dart' as rust_tpm;
import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import 'config_provider.dart';

/// Global [SecureKeyStorage] instance for OS keychain access.
final secureKeyStorageProvider = Provider<SecureKeyStorage>(
  (_) => SecureKeyStorage(),
);

/// Biometric authentication probe + prompt. Used by the optional
/// "unlock with biometrics" flow in master-password mode.
final biometricAuthProvider = Provider<BiometricAuth>((_) => BiometricAuth());

/// Biometric-scoped secure storage of the DB key — only populated when
/// the user opts in to biometric unlock; read at startup before the
/// master-password dialog.
final biometricKeyVaultProvider = Provider<BiometricKeyVault>(
  (_) => BiometricKeyVault(),
);

/// T1+pw keychain-password gate. Split-storage salted HMAC; fronts the
/// keychain-stored DB key with a short-password check dialog.
final keychainPasswordGateProvider = Provider<KeychainPasswordGate>(
  (_) => KeychainPasswordGate(),
);

/// T2 hardware-bound DB key vault (TPM2 on Linux, stubbed elsewhere
/// until per-platform plugins land).
final hardwareTierVaultProvider = Provider<HardwareTierVault>(
  (_) => HardwareTierVault(),
);

/// OS / hardware capabilities snapshot — served from the
/// persisted-cache in `config.json` (`security_probe_cache`) when
/// one exists, otherwise probed live and written back to the cache
/// so subsequent launches can skip the round-trip entirely.
///
/// Invalidation is explicit: the Settings "Re-check tier support"
/// button clears the cache + invalidates this provider; the
/// corruption-retry + wipe-restart paths do the same. Hosts where
/// the TPM / Secure Enclave / keychain state is stable across
/// launches therefore pay the probe cost exactly once per fresh
/// install (or never, if the user imports a per-host config that
/// already carries a cache — which we strip on export to prevent
/// exactly that stale-positive case).
///
/// The cache-miss write-back is Rust-side: `probeCapabilities()`
/// routes into `capabilities_orchestrator::run` which calls
/// `capabilities_cache::Cache::set`, which fires
/// `Event::SecurityCapabilitiesChanged`. The
/// `lfs_core::security::capabilities_persister` actor subscribes
/// and mirrors the snapshot back into the
/// `security_probe_cache` slot of `config.json`. Dart no longer
/// holds the persistence side-effect.
final securityCapabilitiesProvider = FutureProvider<DbSecurityCapabilities>((
  ref,
) async {
  final cached = ref.read(configProvider).securityProbeCache;
  if (cached != null) return cached;
  return probeCapabilities();
});

/// Classified reason the hardware tier is unavailable on this host.
///
/// Real probe (not a per-platform guess):
/// - Linux: routes through FRB into
///   `lfs_core::platform::linux::tpm::probe` — distinguishes missing
///   `/dev/tpmrm0`, missing `tpm2` binary, and generic probe-failed.
/// - Windows: asks `NCryptOpenStorageProvider` for the Platform Crypto
///   Provider (TPM 2.0) vs the software KSP.
/// - macOS / iOS: runs `LAContext.canEvaluatePolicy` and inspects
///   the LAError code — distinguishes missing Secure Enclave (pre-T2
///   Intel Mac), passcode unset, and Simulator.
/// - Android: asks `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`
///   — distinguishes pre-API-28 devices, no biometric hardware, and
///   no enrolled biometric.
///
/// Only resolved when the base capability probe says hardware is
/// unavailable — if it is reachable, this provider returns
/// [HardwareProbeDetail.available] and the UI shows no unavailable
/// notice.
enum HardwareProbeDetail {
  available,

  /// Fallback when we can't classify the failure further. Safe
  /// default — user sees the generic "unavailable on this device"
  /// line with no misleading specificity.
  generic,

  // ── Linux ────────────────────────────────────────────────────────
  /// `/dev/tpmrm0` missing on Linux. User fix: enable fTPM / PTT in
  /// BIOS, or accept that the host has no TPM hardware.
  linuxDeviceMissing,

  /// `tpm2` binary missing on Linux. User fix: install `tpm2-tools`.
  linuxBinaryMissing,

  /// `tpm2 getcap` failed on Linux — usually permissions on
  /// `/dev/tpmrm0` or a misbehaving tpm2-tools install. Generic
  /// "check logs" fallback line.
  linuxProbeFailed,

  // ── Windows ──────────────────────────────────────────────────────
  /// Only the Microsoft Software KSP opens; the Platform Crypto
  /// Provider (TPM 2.0) is unreachable. Actionable: enable fTPM in
  /// UEFI firmware or install on hardware that exposes a TPM 2.0.
  windowsSoftwareOnly,

  /// Neither CNG provider opens — both the Platform Crypto Provider
  /// and the software KSP are missing. Indicates a corrupted crypto
  /// subsystem or a locked-down enterprise Group Policy; UI shows a
  /// diagnostic hint.
  windowsProvidersMissing,

  // ── macOS ────────────────────────────────────────────────────────
  /// Secure Enclave unavailable — typically a pre-2017 Intel Mac
  /// without a T1 / T2 security chip. User cannot enable T2 on this
  /// machine; fall back to master password.
  macosNoSecureEnclave,

  /// Device passcode is not set — Secure Enclave key creation with
  /// `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` requires one.
  /// Actionable: set a login passcode in System Settings.
  macosPasscodeNotSet,

  /// Any other LAContext error (biometry lockout, odd fallthrough).
  /// Logged for diagnostics; UI shows the generic copy.
  macosGeneric,

  // ── iOS ──────────────────────────────────────────────────────────
  /// Device passcode is not set — same cause as [macosPasscodeNotSet]
  /// but copy targets iOS Settings → Face ID & Passcode.
  iosPasscodeNotSet,

  /// Running on the iOS Simulator — the Simulator has no Secure
  /// Enclave, so T2 is impossible there. Dev-mode only surface.
  iosSimulator,

  /// Any other LAContext error on iOS. Logged for diagnostics.
  iosGeneric,

  /// macOS Secure Enclave rejected the real key-create probe with
  /// `errSecMissingEntitlement` (-34018). Ad-hoc-signed bundles
  /// (every release we ship without an Apple Developer ID cert)
  /// surface this on the first SE write because Keychain Services
  /// bind every item to the Code Directory hash and the ad-hoc hash
  /// changes per release. Wizard / Settings copy points the user at
  /// the bundled `macos-resign.sh` helper which gives the install a
  /// stable self-signed identity.
  macosSigningIdentityMissing,

  // ── Android ──────────────────────────────────────────────────────
  /// Android < 9 (API level < 28). StrongBox does not exist and the
  /// `setInvalidatedByBiometricEnrollment` flag behaves unreliably on
  /// pre-P devices, so T2 is gated behind SDK 28.
  androidApiTooLow,

  /// No biometric hardware on this device at all
  /// (BIOMETRIC_ERROR_NO_HARDWARE). User must rely on master password.
  androidBiometricNone,

  /// Biometric hardware exists but user hasn't enrolled a fingerprint
  /// or face. Actionable: enrol in Settings → Security & privacy →
  /// Biometrics.
  androidBiometricNotEnrolled,

  /// Biometric temporarily unusable — lockout after too many failures
  /// or pending security update. UI copy asks user to retry later.
  androidBiometricUnavailable,

  /// Biometric half OK but the real Keystore key-create probe
  /// failed. Covers StrongBox-unavailable, UnknownError, custom-ROM-
  /// stripped-TEE and similar — none individually actionable for
  /// the user, but the typed reason explains why T2 is greyed out
  /// instead of leaving them on a generic "unavailable" string.
  androidKeystoreRejected,

  /// Any other BiometricManager status we didn't map. Logged for
  /// diagnostics.
  androidGeneric,
}

final hardwareProbeDetailProvider = FutureProvider<HardwareProbeDetail>((
  ref,
) async {
  // Derive from the cached capability snapshot instead of running a
  // second deep probe. `securityCapabilitiesProvider` already ran
  // `hardwareVault.probeDetail` (Windows / macOS / iOS / Android) and
  // stashed the raw code string on `caps.hardwareProbeCode`; Linux
  // re-probes here directly through FRB into
  // `lfs_core::platform::linux::tpm::probe` (the cap snapshot's
  // `'unknown'` fallback is the placeholder for that, since the
  // capabilities orchestrator does not yet run the Linux TPM probe).
  // One deep probe per session instead of three (capabilities +
  // hardware-detail + keyring-detail each used to trigger their own
  // round-trip, and the Windows createprimary + macOS SE probe each
  // take hundreds of ms — Settings visibly hung on open while they
  // ran in series).
  final caps = await ref.watch(securityCapabilitiesProvider.future);
  if (Platform.isLinux) {
    // `tpmProbe` accepts `null` for binary / device / timeoutMs and
    // applies the canonical lfs_core defaults itself; passing
    // Dart-side literals would duplicate the platform defaults
    // across the FRB boundary.
    final result = await rust_tpm.tpmProbe();
    switch (result) {
      case rust_tpm.DbTpmProbeResult.available:
        return HardwareProbeDetail.available;
      case rust_tpm.DbTpmProbeResult.deviceNodeMissing:
        return HardwareProbeDetail.linuxDeviceMissing;
      case rust_tpm.DbTpmProbeResult.binaryMissing:
        return HardwareProbeDetail.linuxBinaryMissing;
      case rust_tpm.DbTpmProbeResult.probeFailed:
        return HardwareProbeDetail.linuxProbeFailed;
      case rust_tpm.DbTpmProbeResult.notLinux:
        return HardwareProbeDetail.generic;
    }
  }
  return decodeHardwareProbeCode(caps.hardwareProbeCode);
});

/// Map an opaque native probe code to the typed [HardwareProbeDetail].
/// Unknown codes fall through to [HardwareProbeDetail.generic] so a
/// plugin that adds a new reason ahead of the Dart enum degrades to the
/// generic copy instead of crashing the Settings screen.
HardwareProbeDetail decodeHardwareProbeCode(String code) {
  switch (code) {
    case 'available':
      return HardwareProbeDetail.available;
    case 'windowsSoftwareOnly':
      return HardwareProbeDetail.windowsSoftwareOnly;
    case 'windowsProvidersMissing':
      return HardwareProbeDetail.windowsProvidersMissing;
    case 'macosNoSecureEnclave':
      return HardwareProbeDetail.macosNoSecureEnclave;
    case 'macosPasscodeNotSet':
      return HardwareProbeDetail.macosPasscodeNotSet;
    case 'macosSigningIdentityMissing':
      return HardwareProbeDetail.macosSigningIdentityMissing;
    case 'macosGeneric':
      return HardwareProbeDetail.macosGeneric;
    case 'iosPasscodeNotSet':
      return HardwareProbeDetail.iosPasscodeNotSet;
    case 'iosSimulator':
      return HardwareProbeDetail.iosSimulator;
    case 'iosGeneric':
      return HardwareProbeDetail.iosGeneric;
    case 'androidApiTooLow':
      return HardwareProbeDetail.androidApiTooLow;
    case 'androidBiometricNone':
      return HardwareProbeDetail.androidBiometricNone;
    case 'androidBiometricNotEnrolled':
      return HardwareProbeDetail.androidBiometricNotEnrolled;
    case 'androidBiometricUnavailable':
      return HardwareProbeDetail.androidBiometricUnavailable;
    case 'androidKeystoreRejected':
      return HardwareProbeDetail.androidKeystoreRejected;
    case 'androidGeneric':
      return HardwareProbeDetail.androidGeneric;
    default:
      return HardwareProbeDetail.generic;
  }
}

/// Classified keyring (T1) probe outcome. Mirrors the enum on
/// [SecureKeyStorage] so UI code can depend only on the provider
/// layer — no need to import the storage class to render a hint.
final keyringProbeDetailProvider = FutureProvider<DbKeyringProbeResult>((
  ref,
) async {
  // Same "derive from the capability snapshot" dance as
  // `hardwareProbeDetailProvider`: `securityCapabilitiesProvider`
  // already ran `SecureKeyStorage.probe` and stashed the classified
  // result. Re-running it here doubled the keychain write-read-delete
  // round-trip on every Settings open, which visibly hung on macOS
  // ad-hoc bundles where the keychain retries before returning
  // `errSecMissingEntitlement`.
  final caps = await ref.watch(securityCapabilitiesProvider.future);
  return caps.keychainProbe;
});

/// Resolve the localised user-facing copy for a [DbKeyringProbeResult].
/// Shared between Settings and the first-launch wizard so the copy
/// stays in lockstep.
String keyringProbeDetailText(S l10n, DbKeyringProbeResult result) {
  switch (result) {
    case DbKeyringProbeResult.available:
      return '';
    case DbKeyringProbeResult.linuxNoSecretService:
      return l10n.keyringProbeLinuxNoSecretService;
    case DbKeyringProbeResult.probeFailed:
      return l10n.keyringProbeFailed;
  }
}

/// Resolve the localised user-facing copy for a [HardwareProbeDetail].
/// Shared between Settings and any first-launch diagnostic surface
/// so the copy stays in lockstep.
String hardwareProbeDetailText(S l10n, HardwareProbeDetail detail) {
  switch (detail) {
    case HardwareProbeDetail.available:
      return '';
    case HardwareProbeDetail.generic:
      return l10n.firstLaunchSecurityHardwareUnavailableGeneric;
    case HardwareProbeDetail.linuxDeviceMissing:
      return l10n.hwProbeLinuxDeviceMissing;
    case HardwareProbeDetail.linuxBinaryMissing:
      return l10n.hwProbeLinuxBinaryMissing;
    case HardwareProbeDetail.linuxProbeFailed:
      return l10n.hwProbeLinuxProbeFailed;
    case HardwareProbeDetail.windowsSoftwareOnly:
      return l10n.hwProbeWindowsSoftwareOnly;
    case HardwareProbeDetail.windowsProvidersMissing:
      return l10n.hwProbeWindowsProvidersMissing;
    case HardwareProbeDetail.macosNoSecureEnclave:
      return l10n.hwProbeMacosNoSecureEnclave;
    case HardwareProbeDetail.macosPasscodeNotSet:
      return l10n.hwProbeMacosPasscodeNotSet;
    case HardwareProbeDetail.macosSigningIdentityMissing:
      return l10n.hwProbeMacosSigningIdentityMissing;
    case HardwareProbeDetail.macosGeneric:
      return l10n.firstLaunchSecurityHardwareUnavailableGeneric;
    case HardwareProbeDetail.iosPasscodeNotSet:
      return l10n.hwProbeIosPasscodeNotSet;
    case HardwareProbeDetail.iosSimulator:
      return l10n.hwProbeIosSimulator;
    case HardwareProbeDetail.iosGeneric:
      return l10n.firstLaunchSecurityHardwareUnavailableGeneric;
    case HardwareProbeDetail.androidApiTooLow:
      return l10n.hwProbeAndroidApiTooLow;
    case HardwareProbeDetail.androidBiometricNone:
      return l10n.hwProbeAndroidBiometricNone;
    case HardwareProbeDetail.androidBiometricNotEnrolled:
      return l10n.hwProbeAndroidBiometricNotEnrolled;
    case HardwareProbeDetail.androidBiometricUnavailable:
      return l10n.hwProbeAndroidBiometricUnavailable;
    case HardwareProbeDetail.androidKeystoreRejected:
      return l10n.hwProbeAndroidKeystoreRejected;
    case HardwareProbeDetail.androidGeneric:
      return l10n.firstLaunchSecurityHardwareUnavailableGeneric;
  }
}

/// Current data protection level, detected at startup.
///
/// Defaults to [SecurityTier.plaintext]. Updated by the security
/// initialization flow in main.dart via [SecurityStateNotifier].
final securityStateProvider =
    NotifierProvider<SecurityStateNotifier, SecurityState>(
      SecurityStateNotifier.new,
    );

/// Immutable snapshot of security state: tier + a probe whether
/// the running session has a DB key staged in
/// `lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`. The bytes live
/// Rust-side only — every consumer that needs them goes through
/// a SecretRef-aware FRB shim, so this class carries no key
/// material.
class SecurityState {
  final SecurityTier level;

  /// True when the running session has unlocked the encrypted DB —
  /// i.e. `app.dbkey.active` SecretStore slot holds the master
  /// key. UI layers gate "lock" / "unlock required" affordances
  /// off this flag.
  final bool hasActiveDbKey;

  const SecurityState({
    this.level = SecurityTier.plaintext,
    this.hasActiveDbKey = false,
  });

  /// Whether data stores should encrypt their contents.
  bool get isEncrypted => level != SecurityTier.plaintext;
}

/// Notifier for security state — set once at startup, updated on
/// master password enable/disable/change. Carries no plaintext key
/// material; the running DB key lives in
/// `lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`. Lock / unlock
/// transitions both flip the [SecurityState.hasActiveDbKey] flag
/// AND drop the SecretStore slot in the lock case so the bytes
/// don't outlive the active session.
class SecurityStateNotifier extends Notifier<SecurityState> {
  @override
  SecurityState build() => const SecurityState();

  /// Mark the running session as on [level], with [hasKey] reflecting
  /// whether `app.dbkey.active` holds a DB key. Caller is responsible
  /// for staging the key Rust-side before this call (typically
  /// through `dbInitFromSecret` which atomically promotes a
  /// caller-minted secret into the active slot).
  void setActive(SecurityTier level, {required bool hasKey}) {
    state = SecurityState(level: level, hasActiveDbKey: hasKey);
    _logTransition(level, hasKey: hasKey);
  }

  void _logTransition(SecurityTier level, {required bool hasKey}) {
    // Security level transitions are load-bearing for support traces
    // — a "why did my DB open in plaintext" ticket is answered by
    // matching the tier on the last transition against the persisted
    // config tier. No key bytes in the log, just the enum name.
    AppLogger.instance.log(
      'SecurityState: tier=${level.name} hasKey=$hasKey',
      name: 'SecurityState',
    );
  }

  /// Clear encryption (revert to plaintext). Drops the active
  /// SecretStore slot Rust-side so the running key bytes don't
  /// outlive the auto-lock / wipe transition. The state flip runs
  /// regardless of whether the FRB drop succeeded — flutter_test
  /// contexts that haven't bootstrapped the native lib still get
  /// the right Riverpod state, and the Rust side is a no-op on
  /// missing-id anyway.
  void clearEncryption() {
    try {
      rust_secrets.secretsDrop(id: kActiveDbKeySecretId);
    } catch (e) {
      AppLogger.instance.log(
        'SecurityState.clearEncryption: secretsDrop swallowed: $e',
        name: 'SecurityState',
      );
    }
    state = const SecurityState();
    AppLogger.instance.log(
      'SecurityState: cleared encryption (plaintext)',
      name: 'SecurityState',
    );
  }
}
