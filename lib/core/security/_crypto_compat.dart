import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;

import '../../src/rust/api/crypto.dart' as rust_crypto;

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
