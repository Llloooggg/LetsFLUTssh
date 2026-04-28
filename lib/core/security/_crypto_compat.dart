import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/hardware_tier_vault.dart' as rust_hwv;
import '../../src/rust/api/keychain_password_gate.dart' as rust_gate;

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
