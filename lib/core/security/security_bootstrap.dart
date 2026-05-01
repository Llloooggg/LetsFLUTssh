import 'dart:convert';
import 'dart:io';

import '../../src/rust/api/capabilities_orchestrator.dart' as rust_orch;
import '../../src/rust/api/security_capabilities.dart' as rust_caps;
import '../../src/rust/api/wizard_setup.dart' as rust_wizard;
import '../../utils/logger.dart';
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
  ///
  /// Wire-format owner is `lfs_core::security::capabilities` —
  /// this Dart facade decodes the canonical JSON string into a
  /// `Map<String, dynamic>` for the existing `app_config.dart`
  /// consumers.
  Map<String, dynamic> toJson() {
    final str = rust_caps.securityCapabilitiesToJson(
      keychainAvailable: keychainAvailable,
      hardwareVaultAvailable: hardwareVaultAvailable,
      biometricAvailable: biometricAvailable,
      fprintdAvailable: fprintdAvailable,
      isLinuxHost: isLinuxHost,
      keychainProbeWireName: keychainProbe.name,
      hardwareProbeCode: hardwareProbeCode,
    );
    return jsonDecode(str) as Map<String, dynamic>;
  }

  static SecurityCapabilities? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final decoded = rust_caps.securityCapabilitiesFromJson(
      json: jsonEncode(json),
    );
    if (decoded == null) return null;
    final probe = KeyringProbeResult.values
        .where((v) => v.name == decoded.keychainProbeWireName)
        .firstOrNull;
    if (probe == null) return null;
    return SecurityCapabilities(
      keychainAvailable: decoded.keychainAvailable,
      hardwareVaultAvailable: decoded.hardwareVaultAvailable,
      biometricAvailable: decoded.biometricAvailable,
      fprintdAvailable: decoded.fprintdAvailable,
      isLinuxHost: decoded.isLinuxHost,
      keychainProbe: probe,
      hardwareProbeCode: decoded.hardwareProbeCode,
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
  ///
  /// Routes through
  /// `lfs_core::security::capabilities::can_offer_biometric_modifier`
  /// — the platform-disjunction rule (Linux requires fprintd-or-API,
  /// every other platform takes the API flag verbatim) lives in Rust.
  bool get canOfferBiometricModifier =>
      rust_caps.securityCapabilitiesCanOfferBiometricModifier(
        biometricAvailable: biometricAvailable,
        fprintdAvailable: fprintdAvailable,
        isLinuxHost: isLinuxHost,
      );
}

/// Asynchronously probe every OS / hardware capability the wizard
/// needs.
///
/// Routes through `lfs_core::security::capabilities_orchestrator::run`
/// (FRB async): the orchestrator fans out the four probes concurrently
/// via `tokio::join!`, applies a 5 s per-probe timeout, composes the
/// snapshot, pushes it through the `capabilities_cache` actor, and
/// returns it. The biometric availability probe runs in-process
/// via `lfs_os_security::biometric_auth::check_availability` (or
/// the Linux fprintd D-Bus walk for Linux hosts). Keychain probe +
/// hardware-vault detail still reach the orchestrator through Dart
/// subscribers (`KeychainProbePromptListener`,
/// `HardwareVaultProbePromptListener`) until those probes also
/// land Rust-side.
///
/// Errors propagate directly — the previous Dart-mirror pipeline was
/// retired so a Rust-side failure is no longer silently masked by a
/// shadow probe with different semantics.
Future<SecurityCapabilities> probeCapabilities({
  bool? isLinuxHostOverride,
}) async {
  final linux = isLinuxHostOverride ?? Platform.isLinux;
  final snap = await rust_orch.capabilitiesProbeRun(isLinuxHost: linux);
  final probe =
      KeyringProbeResult.values
          .where((v) => v.name == snap.keychainProbeWireName)
          .firstOrNull ??
      KeyringProbeResult.probeFailed;
  final caps = SecurityCapabilities(
    keychainAvailable: snap.keychainAvailable,
    hardwareVaultAvailable: snap.hardwareVaultAvailable,
    biometricAvailable: snap.biometricAvailable,
    fprintdAvailable: snap.fprintdAvailable,
    isLinuxHost: snap.isLinuxHost,
    keychainProbe: probe,
    hardwareProbeCode: snap.hardwareProbeCode,
  );
  AppLogger.instance.log(
    'Capabilities (orchestrator): keychain=${caps.keychainProbe.name} '
    'hardware=${caps.hardwareProbeCode} '
    'biometric=${caps.biometricAvailable} '
    'fprintd=${caps.fprintdAvailable}',
    name: 'SecurityBootstrap',
  );
  return caps;
}

/// Pure mapping (tier selected in wizard + modifier flags) → the
/// existing `SecurityTier` enum value plus the secret field the
/// downstream `_applyTierChange` / `_firstLaunchSetup` code paths
/// look up. Keeps the wizard UI decoupled from the current
/// persistence shape until the eventual enum-collapse refactor.
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
/// eventual enum-collapse refactor will drop this adapter and let
/// the wizard return `SecurityConfig` directly.
///
/// Routes through `lfs_core::security::map_wizard_choice` (FRB sync)
/// — the choice grammar (which secret slot the typed secret routes
/// into per tier, when keychain splits into the with-password
/// variant) lives in Rust.
MappedSetupChoice mapWizardChoice({
  required WizardTier chosen,
  required bool password,
  required bool biometric,
  String? typedSecret,
}) {
  final r = rust_wizard.securityMapWizardChoice(
    tierWireName: chosen.name,
    password: password,
    biometric: biometric,
    typedSecret: typedSecret,
  );
  return MappedSetupChoice(
    tier: SecurityTierWireName.fromWireName(r.tierWireName),
    modifiers: SecurityTierModifiers(
      password: r.password,
      biometric: r.biometric,
      biometricShortcut: r.biometricShortcut,
    ),
    masterPassword: r.masterPassword,
    shortPassword: r.shortPassword,
    pin: r.pin,
  );
}

/// Normalised tier id the wizard radio-set exposes. Lives in bootstrap
/// so tests can exercise [mapWizardChoice] without pulling the widget
/// layer; never leaks to persistence (the mapper turns it back into a
/// `SecurityTier` before the result leaves the dialog).
enum WizardTier { plaintext, keychain, hardware, paranoid }
