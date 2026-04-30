import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/api/persisted_rate_limit.dart' as rust_prl;
import '../../src/rust/api/security_capabilities.dart' as rust_caps;
import '../../src/rust/api/security_config.dart' as rust_sec_cfg;
import '../../src/rust/api/tier_transition_marker.dart' as rust_ttm;

/// `PersistedRateLimiter` HMAC-authenticated state on disk.
class PersistedRateLimitState {
  final int failureCount;
  final int? nextRetryAtMillis;
  const PersistedRateLimitState({
    required this.failureCount,
    required this.nextRetryAtMillis,
  });
}

/// Encode the limiter's state as the HMAC-authenticated frame
/// written to `rate_limit_state.bin` via
/// `lfs_core::security::persisted_rate_limit::encode`.
Uint8List persistedRateLimitEncodeCompat(
  PersistedRateLimitState state,
  Uint8List hmacKey,
) => rust_prl.persistedRateLimitEncode(
  failureCount: state.failureCount,
  nextRetryAtMillis: state.nextRetryAtMillis,
  hmacKey: hmacKey,
);

/// Parse + HMAC-verify the on-disk frame via
/// `lfs_core::security::persisted_rate_limit::decode`. Returns null
/// on tamper / corruption / wrong key — the limiter's caller treats
/// null as "no state on disk" without surfacing the parse error.
PersistedRateLimitState? persistedRateLimitDecodeCompat(
  Uint8List bytes,
  Uint8List hmacKey,
) {
  final decoded = rust_prl.persistedRateLimitDecode(
    bytes: bytes,
    hmacKey: hmacKey,
  );
  if (decoded == null) return null;
  return PersistedRateLimitState(
    failureCount: decoded.failureCount,
    nextRetryAtMillis: decoded.nextRetryAtMillis,
  );
}

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
/// wizard persists inside `config.json::security_probe_cache`.
/// Routes through `lfs_core::security::capabilities`.
Map<String, dynamic> securityCapabilitiesToJsonCompat({
  required bool keychainAvailable,
  required bool hardwareVaultAvailable,
  required bool biometricAvailable,
  required bool fprintdAvailable,
  required bool isLinuxHost,
  required String keychainProbeWireName,
  required String hardwareProbeCode,
}) {
  try {
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
  } catch (_) {
    return {
      'keychain_available': keychainAvailable,
      'hardware_vault_available': hardwareVaultAvailable,
      'biometric_available': biometricAvailable,
      'fprintd_available': fprintdAvailable,
      'is_linux_host': isLinuxHost,
      'keychain_probe': keychainProbeWireName,
      'hardware_probe_code': hardwareProbeCode,
    };
  }
}

/// Parse a `security_probe_cache` JSON snapshot. Returns null on
/// any malformed shape (non-object root, unknown enum case, missing
/// required strings) so the wizard caller falls through to "no
/// cache" and reprobes. Same dual-path rationale as
/// [securityCapabilitiesToJsonCompat] — `probeCapabilities` uses
/// injected fakes that the Rust orchestrator bypasses, so the
/// fallback stays.
CapabilitiesSnapshot? securityCapabilitiesFromJsonCompat(
  Map<String, dynamic>? json,
) {
  if (json == null) return null;
  try {
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
  } catch (_) {
    return _securityCapabilitiesFallback(json);
  }
}

CapabilitiesSnapshot? _securityCapabilitiesFallback(Map<String, dynamic> json) {
  final probeName = json['keychain_probe'];
  if (probeName is! String) return null;
  if (probeName != 'available' &&
      probeName != 'linuxNoSecretService' &&
      probeName != 'probeFailed') {
    return null;
  }
  final hardwareCode = json['hardware_probe_code'];
  if (hardwareCode is! String) return null;
  return CapabilitiesSnapshot(
    keychainAvailable: json['keychain_available'] == true,
    hardwareVaultAvailable: json['hardware_vault_available'] == true,
    biometricAvailable: json['biometric_available'] == true,
    fprintdAvailable: json['fprintd_available'] == true,
    isLinuxHost: json['is_linux_host'] == true,
    keychainProbeWireName: probeName,
    hardwareProbeCode: hardwareCode,
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
/// `config.json::security`. Routes through
/// `lfs_core::security::SecurityConfig::to_json_value`.
Map<String, dynamic> securityConfigToJsonCompat({
  required String tierWireName,
  required bool password,
  required bool biometric,
  required bool biometricShortcut,
  required int pinLength,
}) {
  try {
    final str = rust_sec_cfg.securityConfigToJson(
      tierWireName: tierWireName,
      password: password,
      biometric: biometric,
      biometricShortcut: biometricShortcut,
      pinLength: pinLength,
    );
    return jsonDecode(str) as Map<String, dynamic>;
  } catch (_) {
    return {
      'tier': tierWireName,
      'modifiers': {
        'password': password,
        'biometric': biometric,
        'biometric_shortcut': biometricShortcut,
        'pin_length': pinLength,
      },
    };
  }
}

/// Parse the `SecurityConfig` JSON object. Mirrors the Rust
/// permissive fallback: an unknown / missing tier string falls
/// through to plaintext + default modifiers so the wizard caller
/// routes through the setup flow rather than silently picking an
/// unintended tier.
SecurityConfigSnapshot securityConfigFromJsonCompat(Map<String, dynamic> json) {
  try {
    final str = jsonEncode(json);
    final decoded = rust_sec_cfg.securityConfigFromJson(json: str);
    if (decoded != null) {
      return SecurityConfigSnapshot(
        tierWireName: decoded.tierWireName,
        password: decoded.password,
        biometric: decoded.biometric,
        biometricShortcut: decoded.biometricShortcut,
        pinLength: decoded.pinLength,
      );
    }
  } catch (_) {
    // FRB unavailable — fall through to the Dart parse below.
  }
  return _securityConfigFallback(json);
}

SecurityConfigSnapshot _securityConfigFallback(Map<String, dynamic> json) {
  final tierStr = json['tier'];
  final tierWire = (tierStr is String && _knownTierWireName(tierStr))
      ? tierStr
      : 'plaintext';
  final modifiersJson = json['modifiers'];
  final modifiers = modifiersJson is Map<String, dynamic>
      ? _modifiersFallback(modifiersJson)
      : const _ModifiersResolved.defaults();
  return SecurityConfigSnapshot(
    tierWireName: tierWire,
    password: modifiers.password,
    biometric: modifiers.biometric,
    biometricShortcut: modifiers.biometricShortcut,
    pinLength: modifiers.pinLength,
  );
}

_ModifiersResolved _modifiersFallback(Map<String, dynamic> json) {
  final biometricShortcut = json['biometric_shortcut'] as bool? ?? false;
  final rawPin = (json['pin_length'] as num?)?.toInt() ?? 6;
  return _ModifiersResolved(
    password: json['password'] as bool? ?? false,
    // `biometric` falls back to `biometric_shortcut` on legacy v1
    // configs (matches the Dart `SecurityTierModifiers.fromJson`).
    biometric: json['biometric'] as bool? ?? biometricShortcut,
    biometricShortcut: biometricShortcut,
    pinLength: rawPin < 4 || rawPin > 8 ? 6 : rawPin,
  );
}

class _ModifiersResolved {
  final bool password;
  final bool biometric;
  final bool biometricShortcut;
  final int pinLength;
  const _ModifiersResolved({
    required this.password,
    required this.biometric,
    required this.biometricShortcut,
    required this.pinLength,
  });
  const _ModifiersResolved.defaults()
    : password = false,
      biometric = false,
      biometricShortcut = false,
      pinLength = 6;
}

bool _knownTierWireName(String s) =>
    s == 'plaintext' ||
    s == 'keychain' ||
    s == 'keychain_with_password' ||
    s == 'hardware' ||
    s == 'paranoid';
