import 'dart:io' show Platform;

import 'security_tier.dart';

/// Per-platform classification of what actually protects the DB key
/// at the active tier. Orthogonal to the tier itself — two different
/// users on the same T1 tier can have very different effective
/// guarantees depending on whether their OS keychain is hardware-
/// backed or software-only.
///
/// Surfaced as a Settings subtitle ("Backing: Hardware Secure
/// Enclave", "Backing: Software libsecret") so users do not see an
/// abstract tier label and assume parity across platforms.
enum TierBackingLevel {
  /// Apple Secure Enclave — iOS, iPadOS, macOS with T2 / Apple Silicon.
  hardwareSecureEnclave,

  /// Android StrongBox — dedicated secure element (Pixel 3+, Samsung S9+ with eSE).
  hardwareStrongbox,

  /// Android TEE (ARM TrustZone) — Trusty / QSEE. Every Android
  /// device with hardware-backed Keystore that is not StrongBox.
  hardwareTee,

  /// Windows TPM 2.0 — via CNG / NCrypt, or transitively via DPAPI
  /// when DPAPI is configured to use TPM. Every Windows 11 device
  /// (TPM 2.0 hard requirement) and most post-2016 Windows 10.
  hardwareTpm,

  /// Apple Keychain with passcode-only protection (no SE). Rare on
  /// modern Apple devices — legacy Intel Macs without T2.
  softwareKeychainApple,

  /// Windows DPAPI without TPM binding. Older Windows 10 machines
  /// without TPM 2.0, or cases where DPAPI falls back to user-key
  /// protection.
  softwareDpapi,

  /// Linux libsecret (GNOME keyring / KWallet). No TPM integration
  /// in the pub.dev `flutter_secure_storage` surface on Linux —
  /// this is the weakest default across the platform matrix.
  softwareLibsecret,

  /// Plaintext tier — no key, no backing. Surfaced so the Settings
  /// subtitle can still say "no encryption" instead of empty.
  none,

  /// Probe failed to classify — fallback label.
  unknown,
}

extension TierBackingLevelDisplay on TierBackingLevel {
  /// Short human label. Kept English in the code; localised copy
  /// lives in the corresponding ARB key `tierBacking<Kind>`.
  String get shortName {
    switch (this) {
      case TierBackingLevel.hardwareSecureEnclave:
        return 'Secure Enclave';
      case TierBackingLevel.hardwareStrongbox:
        return 'StrongBox';
      case TierBackingLevel.hardwareTee:
        return 'TEE (TrustZone)';
      case TierBackingLevel.hardwareTpm:
        return 'TPM 2.0';
      case TierBackingLevel.softwareKeychainApple:
        return 'Keychain (software)';
      case TierBackingLevel.softwareDpapi:
        return 'DPAPI (software)';
      case TierBackingLevel.softwareLibsecret:
        return 'libsecret (software)';
      case TierBackingLevel.none:
        return 'None';
      case TierBackingLevel.unknown:
        return 'Unknown';
    }
  }

  /// True when the backing is a dedicated hardware security module.
  /// Used by UI call sites that want to flag software-only T1 on
  /// Linux with a warning icon.
  bool get isHardware {
    switch (this) {
      case TierBackingLevel.hardwareSecureEnclave:
      case TierBackingLevel.hardwareStrongbox:
      case TierBackingLevel.hardwareTee:
      case TierBackingLevel.hardwareTpm:
        return true;
      case TierBackingLevel.softwareKeychainApple:
      case TierBackingLevel.softwareDpapi:
      case TierBackingLevel.softwareLibsecret:
      case TierBackingLevel.none:
      case TierBackingLevel.unknown:
        return false;
    }
  }
}

/// Classify the effective backing for a given tier on the current
/// host. Pure function of platform + tier — tested against a
/// platform-override matrix so CI catches regressions without needing
/// to spin up real OSes.
///
/// `osOverride` is the DI hook: pass one of "ios", "macos",
/// "android", "windows", "linux" to simulate the host; default `null`
/// reads `Platform.operatingSystem`.
TierBackingLevel classifyTierBacking(SecurityTier tier, {String? osOverride}) {
  if (tier == SecurityTier.plaintext) return TierBackingLevel.none;

  final os = osOverride ?? Platform.operatingSystem;

  // Paranoid derives the key per-unlock from the master password —
  // the "backing" conceptually lives in the user's head, not in any
  // OS facility. Surface as `none` (no persisted key) rather than
  // picking an OS-specific backing label that would mislead.
  if (tier == SecurityTier.paranoid) return TierBackingLevel.none;

  // T2 (hardware tier) — always hardware-backed by definition.
  // Platform determines WHICH hardware module.
  if (tier == SecurityTier.hardware) {
    switch (os) {
      case 'ios':
        return TierBackingLevel.hardwareSecureEnclave;
      case 'macos':
        return TierBackingLevel.hardwareSecureEnclave;
      case 'android':
        // Cannot distinguish StrongBox from TEE without probing the
        // Keystore via the plugin; that probe lives in
        // `HardwareVaultPlugin.backingLevel`. Default to TEE here —
        // the UI consults the plugin for the refined answer when
        // `BiometricBackingLevel` is available on the same surface.
        return TierBackingLevel.hardwareTee;
      case 'windows':
        return TierBackingLevel.hardwareTpm;
      case 'linux':
        return TierBackingLevel.hardwareTpm;
      default:
        return TierBackingLevel.unknown;
    }
  }

  // T1 (keychain) — varies. Apple / Android / Windows are hardware-
  // backed transitively via the OS keychain. Linux libsecret is
  // software-only.
  if (tier == SecurityTier.keychain ||
      tier == SecurityTier.keychainWithPassword) {
    switch (os) {
      case 'ios':
        return TierBackingLevel.hardwareSecureEnclave;
      case 'macos':
        // Could be software-only on older Intel Macs without T2,
        // but distinguishing needs a runtime SE probe. Default
        // optimistically — Settings refines via the biometric
        // backing level probe.
        return TierBackingLevel.hardwareSecureEnclave;
      case 'android':
        return TierBackingLevel.hardwareTee;
      case 'windows':
        return TierBackingLevel.softwareDpapi;
      case 'linux':
        return TierBackingLevel.softwareLibsecret;
      default:
        return TierBackingLevel.unknown;
    }
  }

  return TierBackingLevel.unknown;
}
