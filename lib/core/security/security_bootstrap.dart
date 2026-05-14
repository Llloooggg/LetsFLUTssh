import 'dart:convert';
import 'dart:io';

import '../../src/rust/api/capabilities_orchestrator.dart' as rust_orch;
import '../../src/rust/api/security_capabilities.dart' as rust_caps;
import '../../src/rust/api/security_capabilities.dart'
    show DbKeyringProbeResult, DbSecurityCapabilities;
import '../../src/rust/api/wizard_setup.dart' as rust_wizard;
import '../../utils/logger.dart';
import 'security_tier.dart';

/// Conveniences on top of the FRB-generated [DbSecurityCapabilities]
/// snapshot so the wizard / Settings consumers can call into the
/// same Rust-side rules ([canOfferBiometricModifier]) and JSON
/// codec ([toJsonMap] / [securityCapabilitiesFromJsonMap]) without
/// repeating boilerplate at every call site.
///
/// One struct, one wire format — the snapshot ships across the FRB
/// boundary as the generated [DbSecurityCapabilities] and lives in
/// `config.json`'s `security_probe_cache` slot under the canonical
/// JSON shape `lfs_core::security::capabilities` emits.
extension DbSecurityCapabilitiesExt on DbSecurityCapabilities {
  /// True when the biometric modifier toggle should be offerable
  /// on this host. Routes through
  /// `lfs_core::security::capabilities::can_offer_biometric_modifier`
  /// — the platform-disjunction rule (Linux requires fprintd-or-API,
  /// every other platform takes the API flag verbatim) lives in
  /// Rust.
  bool get canOfferBiometricModifier =>
      rust_caps.securityCapabilitiesCanOfferBiometricModifier(caps: this);

  /// Pure-Dart field-by-field copy with optional overrides. No FRB
  /// hop — the generated struct is immutable, so a single fresh
  /// instance is the only way to "mutate" a field.
  DbSecurityCapabilities copyWith({
    bool? keychainAvailable,
    bool? hardwareVaultAvailable,
    bool? biometricAvailable,
    bool? fprintdAvailable,
    bool? isLinuxHost,
    DbKeyringProbeResult? keychainProbe,
    String? hardwareProbeCode,
  }) {
    return DbSecurityCapabilities(
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

  /// Render to the JSON shape `config.json`'s `security_probe_cache`
  /// block expects. Wire-format owner is
  /// `lfs_core::security::capabilities` — this getter just decodes
  /// the canonical Rust-emitted string into a Dart map for the
  /// existing `app_config.dart` consumers.
  Map<String, dynamic> get toJsonMap {
    final str = rust_caps.securityCapabilitiesToJson(caps: this);
    return jsonDecode(str) as Map<String, dynamic>;
  }
}

/// Parse a `security_probe_cache` JSON snapshot. Returns `null`
/// for malformed input (non-object root, unknown enum case,
/// missing required strings) so the Dart caller falls through to
/// "no cache" and reprobes.
///
/// Routes through `rust_caps.securityCapabilitiesFromJson` — the
/// wire-format-owning crate's canonical decoder.
DbSecurityCapabilities? securityCapabilitiesFromJsonMap(
  Map<String, dynamic>? json,
) {
  if (json == null) return null;
  return rust_caps.securityCapabilitiesFromJson(json: jsonEncode(json));
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
/// Errors propagate directly. **Don't add a Dart-mirror fallback
/// pipeline** — it would silently mask a Rust-side failure with a
/// shadow probe whose semantics drift from the orchestrator's.
Future<DbSecurityCapabilities> probeCapabilities({
  bool? isLinuxHostOverride,
}) async {
  final linux = isLinuxHostOverride ?? Platform.isLinux;
  final caps = await rust_orch.capabilitiesProbeRun(isLinuxHost: linux);
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
  /// whichever of `masterPassword` / `shortPassword` / `pin` matches
  /// the chosen tier's auth shape.
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
