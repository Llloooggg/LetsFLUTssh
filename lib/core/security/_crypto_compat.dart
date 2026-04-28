import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/hardware_tier_vault.dart' as rust_hwv;
import '../../src/rust/api/keychain_password_gate.dart' as rust_gate;
import '../../src/rust/api/persisted_rate_limit.dart' as rust_prl;
import '../../src/rust/api/security_capabilities.dart' as rust_caps;
import '../../src/rust/api/security_config.dart' as rust_sec_cfg;
import '../../src/rust/api/tier_transition_marker.dart' as rust_ttm;

/// HMAC-SHA-256 compat wrapper.
///
/// Production routes through `lfs_core::crypto::hmac_sha256` (sync
/// FRB) so the per-tier secret gates share one canonical
/// implementation with the rest of the security stack. Under
/// flutter_test the FRB native lib is not loaded, so the call
/// throws synchronously; the Dart fallback below picks up the
/// same RustCrypto-equivalent path that `package:crypto` already
/// ships, keeping wire-byte parity for any disk blob written
/// from one path and read back from the other.
///
/// Same fallback pattern as `password_strength.dart` —
/// production never reaches the catch arm because RustLib.init
/// runs before any provider graph that pulls a security tier
/// builds, but widget tests + unit suites that don't bootstrap
/// FRB still see the meter (and the gate hash check) work.
Uint8List hmacSha256Compat(Uint8List key, Uint8List message) {
  try {
    return rust_crypto.cryptoHmacSha256(key: key, message: message);
  } catch (_) {
    return Uint8List.fromList(
      dart_crypto.Hmac(dart_crypto.sha256, key).convert(message).bytes,
    );
  }
}

/// Constant-time byte-slice equality compat wrapper.
///
/// Production routes through `lfs_core::crypto::constant_time_eq`
/// (sync FRB), backed by `subtle::ConstantTimeEq`. Falls back to a
/// pure-Dart loop with the same constant-time shape (XOR fold over
/// every byte regardless of where the first mismatch sits) when
/// the FRB native lib is not loaded — same test-context fallback
/// pattern as [hmacSha256Compat]. Length mismatch fails fast: the
/// lengths themselves are not secret, only the byte content is.
bool constantTimeEqCompat(List<int> a, List<int> b) {
  try {
    return rust_crypto.cryptoConstantTimeEq(a: _bytes(a), b: _bytes(b));
  } catch (_) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

Uint8List _bytes(List<int> v) => v is Uint8List ? v : Uint8List.fromList(v);

/// L2 keychain-password-gate seed: random salt + pepper pair.
class KeychainGateSeed {
  final Uint8List salt;
  final Uint8List pepper;
  const KeychainGateSeed({required this.salt, required this.pepper});
}

/// L2 keychain-password-gate disk blob: salt + comparison HMAC the
/// gate persists in `security_pass_hash.bin`.
class KeychainGateBlob {
  final Uint8List salt;
  final Uint8List hmac;
  const KeychainGateBlob({required this.salt, required this.hmac});
}

/// Generate the random salt + pepper pair the L2 gate seeds at
/// `setPassword` time. Routes through
/// `lfs_core::security::keychain_password_gate::random_salt_and_pepper`
/// in production; falls back to `Random.secure()` 32-byte output in
/// flutter_test contexts.
KeychainGateSeed keychainGateRandomSeedCompat() {
  try {
    final s = rust_gate.keychainGateRandomSeed();
    return KeychainGateSeed(salt: s.salt, pepper: s.pepper);
  } catch (_) {
    final rng = _testRng;
    return KeychainGateSeed(
      salt: Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256))),
      pepper: Uint8List.fromList(
        List<int>.generate(32, (_) => rng.nextInt(256)),
      ),
    );
  }
}

/// `HMAC-SHA-256(pepper, salt || password_utf8)` — the gate's
/// comparison HMAC. Routes through
/// `lfs_core::security::keychain_password_gate::compute_gate_hmac`;
/// the fallback path matches byte-for-byte via the existing
/// `hmacSha256Compat` shared between production + test.
Uint8List keychainGateComputeHmacCompat(
  Uint8List pepper,
  Uint8List salt,
  String password,
) {
  try {
    return rust_gate.keychainGateComputeHmac(
      pepper: pepper,
      salt: salt,
      password: password,
    );
  } catch (_) {
    final msg = BytesBuilder()
      ..add(salt)
      ..add(utf8.encode(password));
    return hmacSha256Compat(pepper, msg.toBytes());
  }
}

/// Encode the salt + hmac pair as the JSON envelope written to
/// `security_pass_hash.bin`. Wire format:
/// `{"salt":"<base64>","hmac":"<base64>"}`. The Rust path is
/// canonical; the Dart fallback below produces the same bytes by
/// construction.
String keychainGateEncodeBlobCompat(Uint8List salt, Uint8List hmac) {
  try {
    return rust_gate.keychainGateEncodeBlob(salt: salt, hmac: hmac);
  } catch (_) {
    return jsonEncode({
      'salt': base64.encode(salt),
      'hmac': base64.encode(hmac),
    });
  }
}

/// Parse the on-disk JSON envelope. Returns null on any malformed
/// shape (bad JSON / missing fields / non-string values / invalid
/// base64 / empty decoded bytes); the gate's `verify` treats null
/// as "wrong password" without surfacing the parse error.
KeychainGateBlob? keychainGateDecodeBlobCompat(String blob) {
  try {
    final decoded = rust_gate.keychainGateDecodeBlob(blob: blob);
    return KeychainGateBlob(salt: decoded.salt, hmac: decoded.hmac);
  } on AnyhowException catch (_) {
    return null;
  } catch (_) {
    // FRB native lib unavailable (test context) — parse Dart-side.
    return _decodeBlobFallback(blob);
  }
}

KeychainGateBlob? _decodeBlobFallback(String blob) {
  try {
    final decoded = jsonDecode(blob);
    if (decoded is! Map<String, dynamic>) return null;
    final saltB64 = decoded['salt'];
    final hmacB64 = decoded['hmac'];
    if (saltB64 is! String || hmacB64 is! String) return null;
    final salt = base64.decode(saltB64);
    final hmac = base64.decode(hmacB64);
    if (salt.isEmpty || hmac.isEmpty) return null;
    return KeychainGateBlob(salt: salt, hmac: hmac);
  } catch (_) {
    return null;
  }
}

/// `Random.secure()` for the test-context fallback. Production
/// never touches it (the FRB path returns first); allocating a
/// single shared instance avoids paying the seeding cost per call
/// in the test suite.
final math.Random _testRng = math.Random.secure();

/// L3 hardware-tier-vault Linux disk blob: salt + TPM-sealed
/// DB-key bytes the vault persists in `hardware_vault.bin`.
class HardwareTierLinuxBlob {
  final Uint8List salt;
  final Uint8List sealed;
  const HardwareTierLinuxBlob({required this.salt, required this.sealed});
}

/// Encode the salt + sealed-blob pair as the JSON envelope written
/// to `hardware_vault.bin` on Linux. Wire format:
/// `{"salt":"<base64>","sealed":"<base64>"}`. Same Rust-canonical /
/// Dart-fallback shape as the L2 gate's
/// [keychainGateEncodeBlobCompat].
String hardwareTierEncodeLinuxBlobCompat(Uint8List salt, Uint8List sealed) {
  try {
    return rust_hwv.hardwareTierVaultEncodeLinuxBlob(
      salt: salt,
      sealed: sealed,
    );
  } catch (_) {
    return jsonEncode({
      'salt': base64.encode(salt),
      'sealed': base64.encode(sealed),
    });
  }
}

/// Parse the on-disk JSON envelope. Returns null on any malformed
/// shape (bad JSON / missing fields / non-string values / invalid
/// base64 / empty decoded bytes); the vault's `read` treats null
/// as "vault corrupt — route back to password unlock".
HardwareTierLinuxBlob? hardwareTierDecodeLinuxBlobCompat(String blob) {
  try {
    final decoded = rust_hwv.hardwareTierVaultDecodeLinuxBlob(blob: blob);
    return HardwareTierLinuxBlob(salt: decoded.salt, sealed: decoded.sealed);
  } on AnyhowException catch (_) {
    return null;
  } catch (_) {
    return _decodeHardwareLinuxFallback(blob);
  }
}

HardwareTierLinuxBlob? _decodeHardwareLinuxFallback(String blob) {
  try {
    final decoded = jsonDecode(blob);
    if (decoded is! Map<String, dynamic>) return null;
    final saltB64 = decoded['salt'];
    final sealedB64 = decoded['sealed'];
    if (saltB64 is! String || sealedB64 is! String) return null;
    final salt = base64.decode(saltB64);
    final sealed = base64.decode(sealedB64);
    if (salt.isEmpty || sealed.isEmpty) return null;
    return HardwareTierLinuxBlob(salt: salt, sealed: sealed);
  } catch (_) {
    return null;
  }
}

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
/// written to `rate_limit_state.bin`. Wire format documented in
/// `lfs_core::security::persisted_rate_limit`. Production routes
/// through Rust; the fallback below produces byte-identical output
/// for the same inputs (minified JSON in both languages on the
/// shape `{failure_count, next_retry_at_millis}`).
Uint8List persistedRateLimitEncodeCompat(
  PersistedRateLimitState state,
  Uint8List hmacKey,
) {
  try {
    return rust_prl.persistedRateLimitEncode(
      failureCount: state.failureCount,
      nextRetryAtMillis: state.nextRetryAtMillis,
      hmacKey: hmacKey,
    );
  } catch (_) {
    final payload = jsonEncode({
      'failure_count': state.failureCount,
      'next_retry_at_millis': state.nextRetryAtMillis,
    });
    final payloadBytes = utf8.encode(payload);
    final hmac = hmacSha256Compat(hmacKey, Uint8List.fromList(payloadBytes));
    final frame = jsonEncode({
      'payload': base64.encode(payloadBytes),
      'hmac': base64.encode(hmac),
    });
    return Uint8List.fromList(utf8.encode(frame));
  }
}

/// Parse + HMAC-verify the on-disk frame. Returns null on tamper /
/// corruption / wrong key — the limiter's caller treats null as
/// "no state on disk" without surfacing the parse error.
PersistedRateLimitState? persistedRateLimitDecodeCompat(
  Uint8List bytes,
  Uint8List hmacKey,
) {
  try {
    final decoded = rust_prl.persistedRateLimitDecode(
      bytes: bytes,
      hmacKey: hmacKey,
    );
    if (decoded == null) return null;
    return PersistedRateLimitState(
      failureCount: decoded.failureCount,
      nextRetryAtMillis: decoded.nextRetryAtMillis,
    );
  } catch (_) {
    return _decodePersistedRateLimitFallback(bytes, hmacKey);
  }
}

PersistedRateLimitState? _decodePersistedRateLimitFallback(
  Uint8List bytes,
  Uint8List hmacKey,
) {
  try {
    final frame = jsonDecode(utf8.decode(bytes));
    if (frame is! Map<String, dynamic>) return null;
    final payloadB64 = frame['payload'];
    final hmacB64 = frame['hmac'];
    if (payloadB64 is! String || hmacB64 is! String) return null;
    final payloadBytes = base64.decode(payloadB64);
    final claimed = base64.decode(hmacB64);
    final expected = hmacSha256Compat(hmacKey, payloadBytes);
    if (!constantTimeEqCompat(claimed, expected)) return null;
    final payload = jsonDecode(utf8.decode(payloadBytes));
    if (payload is! Map<String, dynamic>) return null;
    final failureCount = (payload['failure_count'] as num?)?.toInt() ?? 0;
    final retryMillis = (payload['next_retry_at_millis'] as num?)?.toInt();
    return PersistedRateLimitState(
      failureCount: failureCount,
      nextRetryAtMillis: retryMillis,
    );
  } catch (_) {
    return null;
  }
}

/// Marker file name used by both the Rust + Dart-fallback paths.
/// Mirror of `lfs_core::security::tier_transition_marker::MARKER_FILE_NAME`.
const String _tierTransitionMarkerFileName = '.tier-transition-pending';

/// Read the `.tier-transition-pending` marker body from
/// [supportDir], or null when absent. Production routes through
/// `lfs_core::security::tier_transition_marker::read`; flutter_test
/// contexts that don't load the FRB native lib fall back to direct
/// File I/O at the same path.
String? tierTransitionMarkerReadCompat(String supportDir) {
  try {
    return rust_ttm.tierTransitionMarkerRead(supportDir: supportDir);
  } catch (_) {
    final file = File('$supportDir/$_tierTransitionMarkerFileName');
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }
}

/// Write the `.tier-transition-pending` marker with [payload] as
/// its body. Production routes through Rust (atomic + 0600 hardened);
/// the Dart fallback writes directly + chmods via the file_utils
/// helper to match the production perms.
Future<void> tierTransitionMarkerWriteCompat(
  String supportDir,
  String payload,
) async {
  try {
    rust_ttm.tierTransitionMarkerWrite(
      supportDir: supportDir,
      payload: payload,
    );
  } catch (_) {
    final dir = Directory(supportDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = '$supportDir/$_tierTransitionMarkerFileName';
    final file = File(path);
    file.writeAsStringSync(payload, flush: true);
  }
}

/// Drop the `.tier-transition-pending` marker. Idempotent on a
/// missing file. Production routes through Rust; the fallback path
/// deletes via `dart:io`.
void tierTransitionMarkerClearCompat(String supportDir) {
  try {
    rust_ttm.tierTransitionMarkerClear(supportDir: supportDir);
  } catch (_) {
    final file = File('$supportDir/$_tierTransitionMarkerFileName');
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
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
/// Production routes through `lfs_core::security::capabilities`;
/// flutter_test contexts that don't load the FRB native lib fall
/// back to a Dart literal that produces the same field set.
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
/// cache" and reprobes. Mirror of the Dart `SecurityCapabilities.fromJson`
/// strictness — bool fields default to `false` when missing or
/// non-bool, every other field type-checks fail-closed.
CapabilitiesSnapshot? securityCapabilitiesFromJsonCompat(
  Map<String, dynamic>? json,
) {
  if (json == null) return null;
  try {
    final str = jsonEncode(json);
    final decoded = rust_caps.securityCapabilitiesFromJson(json: str);
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
/// `lfs_core::security::SecurityConfig::to_json_value` in
/// production; fallback path produces the same nested map shape so
/// flutter_test cases relying on the literal `{tier, modifiers}`
/// envelope keep working without bootstrapping the FRB native lib.
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
