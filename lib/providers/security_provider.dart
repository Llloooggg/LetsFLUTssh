import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/biometric_auth.dart';
import '../core/security/biometric_key_vault.dart';
import '../core/security/hardware_tier_vault.dart';
import '../core/security/keychain_password_gate.dart';
import '../core/security/linux/tpm_client.dart';
import '../core/security/secret_buffer.dart';
import '../core/security/secure_key_storage.dart';
import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';
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

/// L2 keychain-password gate. Split-storage salted HMAC; fronts the
/// keychain-stored DB key with a short-password check dialog.
final keychainPasswordGateProvider = Provider<KeychainPasswordGate>(
  (_) => KeychainPasswordGate(),
);

/// L3 hardware-bound DB key vault (TPM2 on Linux, stubbed elsewhere
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
final securityCapabilitiesProvider = FutureProvider<SecurityCapabilities>((
  ref,
) async {
  final cached = ref.read(configProvider).securityProbeCache;
  if (cached != null) return cached;
  final fresh = await probeCapabilities(
    keyStorage: ref.read(secureKeyStorageProvider),
    hardwareVault: ref.read(hardwareTierVaultProvider),
  );
  // Persist the snapshot so the next cold start returns from the
  // `cached != null` branch above. `update` is awaited so the save
  // is durable before the provider settles — a crash between probe
  // and write would drop the cache for the next launch, which is the
  // safe direction.
  await ref
      .read(configProvider.notifier)
      .update((c) => c.copyWithSecurity(securityProbeCache: fresh));
  return fresh;
});

/// Classified reason the hardware tier is unavailable on this host.
///
/// Real probe (not a per-platform guess):
/// - Linux: delegates to [TpmClient.probe] — distinguishes missing
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
  // drops through that path with `'unknown'` because the TPM probe
  // lives in `TpmClient` at this layer. One deep probe per session
  // instead of three (capabilities + hardware-detail + keyring-detail
  // each used to trigger their own round-trip, and the Windows
  // createprimary + macOS SE probe each take hundreds of ms — Settings
  // visibly hung on open while they ran in series).
  final caps = await ref.watch(securityCapabilitiesProvider.future);
  if (Platform.isLinux) {
    final result = await TpmClient().probe();
    switch (result) {
      case TpmProbeResult.available:
        return HardwareProbeDetail.available;
      case TpmProbeResult.deviceNodeMissing:
        return HardwareProbeDetail.linuxDeviceMissing;
      case TpmProbeResult.binaryMissing:
        return HardwareProbeDetail.linuxBinaryMissing;
      case TpmProbeResult.probeFailed:
        return HardwareProbeDetail.linuxProbeFailed;
      case TpmProbeResult.wrongPlatform:
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
final keyringProbeDetailProvider = FutureProvider<KeyringProbeResult>((
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

/// Resolve the localised user-facing copy for a [KeyringProbeResult].
/// Shared between Settings and the first-launch wizard so the copy
/// stays in lockstep.
String keyringProbeDetailText(S l10n, KeyringProbeResult result) {
  switch (result) {
    case KeyringProbeResult.available:
      return '';
    case KeyringProbeResult.linuxNoSecretService:
      return l10n.keyringProbeLinuxNoSecretService;
    case KeyringProbeResult.probeFailed:
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

/// Immutable snapshot of security state: level + optional encryption key
/// held in a page-locked native buffer.
///
/// [_buffer] owns a [SecretBuffer] with the 32-byte DB key; [encryptionKey]
/// exposes it as a `Uint8List` alias for compatibility with the existing
/// drift/SQLite3MC call sites. The alias stays valid as long as the buffer
/// lives — i.e. until the next `set(...)`/`clearEncryption()` replaces the
/// state, at which point the old buffer is disposed (zeroed + munlock +
/// freed) by [SecurityStateNotifier].
class SecurityState {
  final SecurityTier level;
  final SecretBuffer? _buffer;

  SecurityState({this.level = SecurityTier.plaintext, SecretBuffer? buffer})
    : _buffer = buffer;

  /// Live `Uint8List` view into the locked buffer, or null in plaintext mode.
  Uint8List? get encryptionKey => _buffer?.bytes;

  /// Internal handle — needed by [SecurityStateNotifier] to dispose on
  /// transitions. Not part of the public surface.
  SecretBuffer? get buffer => _buffer;

  /// Whether data stores should encrypt their contents.
  bool get isEncrypted => level != SecurityTier.plaintext;
}

/// Notifier for security state — set once at startup, updated on
/// master password enable/disable/change. Owns the [SecretBuffer] lifecycle:
/// any transition disposes the previous buffer so the plaintext key is
/// zeroed + unlocked + freed before a new one takes its place.
class SecurityStateNotifier extends Notifier<SecurityState> {
  SecretBuffer? _owned;

  @override
  SecurityState build() {
    // Dispose the currently-owned buffer when the provider itself is torn
    // down. Reading `state` inside onDispose isn't allowed (Riverpod
    // forbids ref access from lifecycle callbacks), so we keep a plain
    // field that mirrors the buffer the state holds.
    ref.onDispose(() {
      _owned?.dispose();
      _owned = null;
    });
    return SecurityState();
  }

  /// Set the security level and encryption key. Copies [key] into a fresh
  /// page-locked buffer and disposes the previous one. The caller is
  /// responsible for zeroing its own `Uint8List` copy afterwards.
  void set(SecurityTier level, [Uint8List? key]) {
    final previous = _owned;
    final buffer = key == null ? null : SecretBuffer.fromBytes(key);
    _owned = buffer;
    state = SecurityState(level: level, buffer: buffer);
    previous?.dispose();
  }

  /// Clear encryption (revert to plaintext). Zeroes and releases the
  /// in-memory key.
  void clearEncryption() {
    final previous = _owned;
    _owned = null;
    state = SecurityState();
    previous?.dispose();
  }
}
