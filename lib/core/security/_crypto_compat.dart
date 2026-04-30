import 'dart:convert';

import '../../src/rust/api/security_capabilities.dart' as rust_caps;
import '../../src/rust/api/security_config.dart' as rust_sec_cfg;
import '../../src/rust/api/tier_transition_marker.dart' as rust_ttm;

/// Read the `.tier-transition-pending` marker body from
/// [supportDir], or null when absent. Routes through
/// `lfs_core::security::tier_transition_marker::read`.
String? tierTransitionMarkerReadCompat(String supportDir) {
  return rust_ttm.tierTransitionMarkerRead(supportDir: supportDir);
}

/// Write the `.tier-transition-pending` marker with [payload] as
/// its body. Routes through Rust — atomic + 0600 hardened.
Future<void> tierTransitionMarkerWriteCompat(
  String supportDir,
  String payload,
) async {
  rust_ttm.tierTransitionMarkerWrite(supportDir: supportDir, payload: payload);
}

/// Drop the `.tier-transition-pending` marker. Idempotent on a
/// missing file. Routes through Rust.
void tierTransitionMarkerClearCompat(String supportDir) {
  rust_ttm.tierTransitionMarkerClear(supportDir: supportDir);
}

/// Snapshot of the parsed `security_probe_cache` block. Mirror of
/// `lfs_core::security::capabilities::SecurityCapabilities`, flattened
/// across the FRB boundary so the Dart caller can rebuild its own
/// `SecurityCapabilities` without re-importing the enum.
class CapabilitiesSnapshot {
  final bool keychainAvailable;
  final bool hardwareVaultAvailable;
  final bool biometricAvailable;
  final bool fprintdAvailable;
  final bool isLinuxHost;
  final String keychainProbeWireName;
  final String hardwareProbeCode;
  const CapabilitiesSnapshot({
    required this.keychainAvailable,
    required this.hardwareVaultAvailable,
    required this.biometricAvailable,
    required this.fprintdAvailable,
    required this.isLinuxHost,
    required this.keychainProbeWireName,
    required this.hardwareProbeCode,
  });
}

/// Encode the security-capabilities snapshot as the JSON map the
/// wizard persists inside `config.json::security_probe_cache` via
/// `lfs_core::security::capabilities`.
Map<String, dynamic> securityCapabilitiesToJsonCompat({
  required bool keychainAvailable,
  required bool hardwareVaultAvailable,
  required bool biometricAvailable,
  required bool fprintdAvailable,
  required bool isLinuxHost,
  required String keychainProbeWireName,
  required String hardwareProbeCode,
}) {
  final str = rust_caps.securityCapabilitiesToJson(
    keychainAvailable: keychainAvailable,
    hardwareVaultAvailable: hardwareVaultAvailable,
    biometricAvailable: biometricAvailable,
    fprintdAvailable: fprintdAvailable,
    isLinuxHost: isLinuxHost,
    keychainProbeWireName: keychainProbeWireName,
    hardwareProbeCode: hardwareProbeCode,
  );
  return jsonDecode(str) as Map<String, dynamic>;
}

/// Parse a `security_probe_cache` JSON snapshot via
/// `lfs_core::security::capabilities`. Returns null on any malformed
/// shape (non-object root, unknown enum case, missing required
/// strings) so the wizard caller falls through to "no cache" and
/// reprobes.
CapabilitiesSnapshot? securityCapabilitiesFromJsonCompat(
  Map<String, dynamic>? json,
) {
  if (json == null) return null;
  final decoded = rust_caps.securityCapabilitiesFromJson(
    json: jsonEncode(json),
  );
  if (decoded == null) return null;
  return CapabilitiesSnapshot(
    keychainAvailable: decoded.keychainAvailable,
    hardwareVaultAvailable: decoded.hardwareVaultAvailable,
    biometricAvailable: decoded.biometricAvailable,
    fprintdAvailable: decoded.fprintdAvailable,
    isLinuxHost: decoded.isLinuxHost,
    keychainProbeWireName: decoded.keychainProbeWireName,
    hardwareProbeCode: decoded.hardwareProbeCode,
  );
}

/// Snapshot of a parsed `SecurityConfig` block from `config.json`.
class SecurityConfigSnapshot {
  final String tierWireName;
  final bool password;
  final bool biometric;
  final bool biometricShortcut;
  final int pinLength;
  const SecurityConfigSnapshot({
    required this.tierWireName,
    required this.password,
    required this.biometric,
    required this.biometricShortcut,
    required this.pinLength,
  });
}

/// Encode the `SecurityConfig` blob persisted under
/// `config.json::security` via
/// `lfs_core::security::SecurityConfig::to_json_value`.
Map<String, dynamic> securityConfigToJsonCompat({
  required String tierWireName,
  required bool password,
  required bool biometric,
  required bool biometricShortcut,
  required int pinLength,
}) {
  final str = rust_sec_cfg.securityConfigToJson(
    tierWireName: tierWireName,
    password: password,
    biometric: biometric,
    biometricShortcut: biometricShortcut,
    pinLength: pinLength,
  );
  return jsonDecode(str) as Map<String, dynamic>;
}

/// Parse the `SecurityConfig` JSON object via
/// `lfs_core::security::SecurityConfig::from_json_value`. The Rust
/// parser is permissively accepting: an unknown / missing tier
/// string falls through to plaintext + default modifiers so the
/// wizard caller routes through the setup flow rather than silently
/// picking an unintended tier.
SecurityConfigSnapshot securityConfigFromJsonCompat(Map<String, dynamic> json) {
  final str = jsonEncode(json);
  final decoded = rust_sec_cfg.securityConfigFromJson(json: str);
  if (decoded == null) {
    // Wire-shape rejected outright — synthesise the plaintext
    // default that the wizard re-prompts against.
    return const SecurityConfigSnapshot(
      tierWireName: 'plaintext',
      password: false,
      biometric: false,
      biometricShortcut: false,
      pinLength: 6,
    );
  }
  return SecurityConfigSnapshot(
    tierWireName: decoded.tierWireName,
    password: decoded.password,
    biometric: decoded.biometric,
    biometricShortcut: decoded.biometricShortcut,
    pinLength: decoded.pinLength,
  );
}
