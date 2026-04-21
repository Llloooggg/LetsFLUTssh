import 'dart:io';

import 'biometric_auth.dart';
import 'hardware_tier_vault.dart';
import 'linux/fprintd_client.dart';
import 'secure_key_storage.dart';
import 'security_tier.dart';

/// Snapshot of every OS / hardware capability the wizard needs to
/// decide which tiers + modifier combinations to offer on this
/// device. Probed once on wizard open and cached in the dialog
/// state; the wizard renders against the snapshot without further
/// async calls.
///
/// Pure data — no platform channels. Produced by [probeCapabilities];
/// consumed by the setup dialog + tests.
class SecurityCapabilities {
  /// OS keychain is reachable (Keychain / Credential Manager /
  /// libsecret / EncryptedSharedPreferences depending on platform).
  final bool keychainAvailable;

  /// Hardware vault slot is reachable — Secure Enclave on iOS /
  /// macOS with T2, StrongBox / TEE on Android, TPM 2.0 on Windows /
  /// Linux. Governs whether T2 is offered.
  final bool hardwareVaultAvailable;

  /// Biometric API returns SUCCESS (sensor present + at least one
  /// enrolment). Governs the biometric modifier toggle.
  final bool biometricAvailable;

  /// On Linux, `fprintd` is installed + has at least one enrolled
  /// finger. The biometric modifier on Linux flows through
  /// [FprintdClient] and fails silently when this is false.
  final bool fprintdAvailable;

  /// True on Linux only. Wizard uses this to surface the "Linux TPM
  /// without password gives isolation, not authentication" honesty
  /// note when the user picks T2 without the password modifier.
  final bool isLinuxHost;

  /// Classified outcome of [SecureKeyStorage.probe] — the enum the
  /// Dart layer uses to map to localised "why the keyring is
  /// unavailable" copy. `available` on healthy hosts. Populated
  /// alongside [keychainAvailable] so the wizard can render a
  /// specific reason instead of a generic "unavailable" string.
  final KeyringProbeResult keychainProbe;

  /// Raw platform-specific hardware-vault detail code (the string
  /// returned by `HardwareTierVault.probeDetail()` on Android /
  /// iOS / macOS / Windows, or the TPM-CLI outcome on Linux mapped
  /// into the same shape). `available` on healthy hosts, `unknown`
  /// when the native probe is unreachable. Wizard / Settings UI map
  /// this to the `HardwareProbeDetail` enum + localised copy via
  /// `hardwareProbeDetailText`.
  final String hardwareProbeCode;

  const SecurityCapabilities({
    this.keychainAvailable = false,
    this.hardwareVaultAvailable = false,
    this.biometricAvailable = false,
    this.fprintdAvailable = false,
    this.isLinuxHost = false,
    this.keychainProbe = KeyringProbeResult.probeFailed,
    this.hardwareProbeCode = 'unknown',
  });

  SecurityCapabilities copyWith({
    bool? keychainAvailable,
    bool? hardwareVaultAvailable,
    bool? biometricAvailable,
    bool? fprintdAvailable,
    bool? isLinuxHost,
    KeyringProbeResult? keychainProbe,
    String? hardwareProbeCode,
  }) {
    return SecurityCapabilities(
      keychainAvailable: keychainAvailable ?? this.keychainAvailable,
      hardwareVaultAvailable:
          hardwareVaultAvailable ?? this.hardwareVaultAvailable,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      fprintdAvailable: fprintdAvailable ?? this.fprintdAvailable,
      isLinuxHost: isLinuxHost ?? this.isLinuxHost,
      keychainProbe: keychainProbe ?? this.keychainProbe,
      hardwareProbeCode: hardwareProbeCode ?? this.hardwareProbeCode,
    );
  }

  /// JSON shape matches the hand-rolled flat layout the rest of
  /// `app_config.dart` uses — one scalar per key, enums as their
  /// stable Dart `name`. Used by the `security_probe_cache` block in
  /// `config.json` so a fresh app start can serve the Settings cards
  /// straight from the snapshot instead of paying the real probe
  /// cost on every launch. The Recheck button + destructive security
  /// paths clear this cache so the next read reprobes.
  Map<String, dynamic> toJson() => {
    'keychain_available': keychainAvailable,
    'hardware_vault_available': hardwareVaultAvailable,
    'biometric_available': biometricAvailable,
    'fprintd_available': fprintdAvailable,
    'is_linux_host': isLinuxHost,
    'keychain_probe': keychainProbe.name,
    'hardware_probe_code': hardwareProbeCode,
  };

  static SecurityCapabilities? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    // Every field is guarded with a type check because the file is
    // user-writable and may carry a partial / corrupted snapshot from
    // a previous build. A malformed cache is treated as "no cache" so
    // the next call reprobes fresh — we never parse past a bad type
    // into a default.
    final probeName = json['keychain_probe'];
    if (probeName is! String) return null;
    final probe = KeyringProbeResult.values
        .where((v) => v.name == probeName)
        .firstOrNull;
    if (probe == null) return null;
    final hardwareCode = json['hardware_probe_code'];
    if (hardwareCode is! String) return null;
    return SecurityCapabilities(
      keychainAvailable: json['keychain_available'] == true,
      hardwareVaultAvailable: json['hardware_vault_available'] == true,
      biometricAvailable: json['biometric_available'] == true,
      fprintdAvailable: json['fprintd_available'] == true,
      isLinuxHost: json['is_linux_host'] == true,
      keychainProbe: probe,
      hardwareProbeCode: hardwareCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityCapabilities &&
          keychainAvailable == other.keychainAvailable &&
          hardwareVaultAvailable == other.hardwareVaultAvailable &&
          biometricAvailable == other.biometricAvailable &&
          fprintdAvailable == other.fprintdAvailable &&
          isLinuxHost == other.isLinuxHost &&
          keychainProbe == other.keychainProbe &&
          hardwareProbeCode == other.hardwareProbeCode;

  @override
  int get hashCode => Object.hash(
    keychainAvailable,
    hardwareVaultAvailable,
    biometricAvailable,
    fprintdAvailable,
    isLinuxHost,
    keychainProbe,
    hardwareProbeCode,
  );

  /// True when biometric modifier is at all offerable on this host —
  /// on Linux this also requires fprintd+enrolment, on every other
  /// platform the platform biometric API suffices. Password-dependency
  /// ("biometric requires password") is enforced separately by the
  /// wizard UI because it is a UX rule, not a capability fact.
  bool get canOfferBiometricModifier => isLinuxHost
      ? (biometricAvailable || fprintdAvailable)
      : biometricAvailable;
}

/// Asynchronously probe every OS / hardware capability the wizard
/// needs. Returns a [SecurityCapabilities] with sensible defaults on
/// any probe failure so a stuck D-Bus call (common on Linux test
/// boxes) never leaves the user staring at a spinner.
Future<SecurityCapabilities> probeCapabilities({
  required SecureKeyStorage keyStorage,
  required HardwareTierVault hardwareVault,
  BiometricAuth? biometricAuth,
  FprintdClient? fprintdClient,
  bool? isLinuxHostOverride,
}) async {
  final linux = isLinuxHostOverride ?? Platform.isLinux;
  final bio = biometricAuth ?? BiometricAuth();
  final fprintd = fprintdClient ?? FprintdClient();

  Future<T> safely<T>(Future<T> Function() fn, T fallback) async {
    try {
      return await fn();
    } catch (_) {
      return fallback;
    }
  }

  // Single probe per capability — deep probes are expensive (real
  // SE / Keystore / TPM round-trip) so every duplicate call shows
  // up as a UI stutter when Settings opens. `hardwareVault.probeDetail`
  // already runs the same round-trip as `hardwareVault.isAvailable`,
  // so we skip the separate `isAvailable` call and derive the bool
  // from the reason code; same trick for keychain, where `probe()`
  // returns a classified enum and the bool is "probe says available".
  final results = await Future.wait<Object>([
    safely(keyStorage.probe, KeyringProbeResult.probeFailed),
    safely(() async {
      final res = await bio.availability();
      return res == null;
    }, false),
    linux
        ? safely(() async {
            final hash = await fprintd.getEnrolmentHash();
            return hash != null && hash.isNotEmpty;
          }, false)
        : Future.value(false),
    // Raw platform-specific hardware-vault reason code. Carried as a
    // string so `core/security` does not need to import the
    // `HardwareProbeDetail` enum from the providers layer (which
    // would invert the dependency direction); the wizard + Settings
    // code at the widgets/providers layer map the code back to an
    // enum + localised reason copy.
    safely(hardwareVault.probeDetail, 'unknown'),
  ]);

  final keyringProbe = results[0] as KeyringProbeResult;
  final hardwareCode = results[3] as String;
  return SecurityCapabilities(
    keychainAvailable: keyringProbe == KeyringProbeResult.available,
    hardwareVaultAvailable: hardwareCode == 'available',
    biometricAvailable: results[1] as bool,
    fprintdAvailable: results[2] as bool,
    isLinuxHost: linux,
    keychainProbe: keyringProbe,
    hardwareProbeCode: hardwareCode,
  );
}

/// Pure mapping (tier selected in wizard + modifier flags) → the
/// existing `SecurityTier` enum value plus the secret field the
/// downstream `_applyTierChange` / `_firstLaunchSetup` code paths
/// look up. Keeps the wizard UI decoupled from the current persistence
/// shape while the Phase F enum-collapse lands.
///
/// T2 + password → `hardware` tier with the password routed into the
/// `pin` field. The HardwareTierVault's HMAC gate does not care about
/// length or digit-only-ness; a full textual password works there
/// identically to a 6-digit PIN.
///
/// T2 without a password is now accepted: `HardwareTierVault.store`
/// / `read` treat null pin as the "empty auth value" path documented
/// in `resolveAuthValue`, and the unlock path reads
/// `modifiers.password` back to decide whether to prompt. Wizard
/// passes the typed secret through unchanged; callers downstream
/// (`_firstLaunchHardware`, `_applyTierChange`) deal with the
/// nullability correctly.
class MappedSetupChoice {
  final SecurityTier tier;
  final SecurityTierModifiers modifiers;

  /// The user-typed secret the downstream caller needs, routed into
  /// whichever of `masterPassword` / `shortPassword` / `pin` the
  /// legacy switch-case expects for the chosen tier.
  final String? masterPassword;
  final String? shortPassword;
  final String? pin;

  const MappedSetupChoice({
    required this.tier,
    required this.modifiers,
    this.masterPassword,
    this.shortPassword,
    this.pin,
  });
}

/// Translate the wizard's (T0/T1/T2/Paranoid + password + biometric +
/// typed secret) shape into the persistence-layer `SecurityTier` +
/// typed secret the current `_applyTierChange` cascade expects. The
/// Phase F refactor will drop this adapter and let the wizard return
/// `SecurityConfig` directly.
MappedSetupChoice mapWizardChoice({
  required WizardTier chosen,
  required bool password,
  required bool biometric,
  String? typedSecret,
}) {
  final modifiers = SecurityTierModifiers(
    password: password,
    biometric: biometric,
    biometricShortcut: biometric,
  );
  switch (chosen) {
    case WizardTier.plaintext:
      return MappedSetupChoice(
        tier: SecurityTier.plaintext,
        modifiers: modifiers,
      );
    case WizardTier.keychain:
      if (password) {
        return MappedSetupChoice(
          tier: SecurityTier.keychainWithPassword,
          modifiers: modifiers,
          shortPassword: typedSecret,
        );
      }
      return MappedSetupChoice(
        tier: SecurityTier.keychain,
        modifiers: modifiers,
      );
    case WizardTier.hardware:
      return MappedSetupChoice(
        tier: SecurityTier.hardware,
        modifiers: modifiers,
        pin: typedSecret,
      );
    case WizardTier.paranoid:
      return MappedSetupChoice(
        tier: SecurityTier.paranoid,
        modifiers: modifiers,
        masterPassword: typedSecret,
      );
  }
}

/// Normalised tier id the wizard radio-set exposes. Lives in bootstrap
/// so tests can exercise [mapWizardChoice] without pulling the widget
/// layer; never leaks to persistence (the mapper turns it back into a
/// `SecurityTier` before the result leaves the dialog).
enum WizardTier { plaintext, keychain, hardware, paranoid }
