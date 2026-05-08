//! FRB adapter for `lfs_core::security::keychain_password_gate`.
//!
//! Sync everywhere — every op is a base64 encode/decode + a JSON
//! parse + (for the hmac) a single SHA-256 digest pass. The async
//! hop overhead would dwarf the per-call work, and the T1+pw unlock
//! dialog wants the verify decision before the keychain prompt
//! finishes animating.
//!
//! Disk I/O and the keychain pepper round-trip live Rust-side in
//! [`lfs_core::security::keychain_password_gate_actor`]; this
//! shim only surfaces the pure encode/decode/hmac helpers Dart
//! needs to wire the rate-limiter HMAC key without re-parsing the
//! disk blob format.

use lfs_core::security::keychain_password_gate as gate;

/// Generated salt + pepper bundle the gate seeds at `setPassword`
/// time. Two `OsRng` calls pinned to the master-password verifier's
/// salt source so an audit can confirm the entropy provenance from
/// one place.
#[derive(Debug, Clone)]
pub struct DbKeychainGateSeed {
    pub salt: Vec<u8>,
    pub pepper: Vec<u8>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn keychain_gate_random_seed() -> DbKeychainGateSeed {
    let (salt, pepper) = gate::random_salt_and_pepper();
    DbKeychainGateSeed { salt, pepper }
}

/// `HMAC-SHA-256(pepper, salt || password_utf8)` — the comparison
/// HMAC the gate stores on disk. Wire-byte parity with the Dart
/// `_computeHmac` is enforced by the Rust unit tests; any change
/// in the salt-prefix vs. trailing ordering invalidates every
/// install on disk.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_gate_compute_hmac(pepper: Vec<u8>, salt: Vec<u8>, password: Vec<u8>) -> Vec<u8> {
    gate::compute_gate_hmac(&pepper, &salt, &password)
}

/// Encode the salt + hmac pair as the JSON envelope written to
/// `security_pass_hash.bin`. Caller writes the returned string's
/// UTF-8 bytes atomically + hardens to 0600.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_gate_encode_blob(salt: Vec<u8>, hmac: Vec<u8>) -> String {
    gate::encode_disk_blob(&salt, &hmac)
}

/// FRB mirror of `lfs_core::security::keychain_password_gate::DiskBlob`.
#[derive(Debug, Clone)]
pub struct DbKeychainGateBlob {
    pub salt: Vec<u8>,
    pub hmac: Vec<u8>,
}

/// Parse the on-disk JSON envelope. Returns `Err` on any malformed
/// shape (bad JSON / missing fields / non-string values / invalid
/// base64 / empty decoded bytes). The Dart-side `verify` treats any
/// decode failure as a "wrong password" outcome.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_gate_decode_blob(blob: String) -> Result<DbKeychainGateBlob, String> {
    gate::decode_disk_blob(&blob).map(|b| DbKeychainGateBlob {
        salt: b.salt,
        hmac: b.hmac,
    })
}
