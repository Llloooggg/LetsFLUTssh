//! Disk-blob format owner for the T1+pw keychain-with-password gate.
//!
//! `KeychainPasswordGate` (Dart) splits the gate's secret across
//! disk + keychain: a salt + comparison-HMAC blob lives in
//! `security_pass_hash.bin` under app-support, and the matching
//! HMAC pepper lives in the OS keychain under `letsflutssh_l2_pepper`.
//! This module owns the on-disk JSON envelope shape — fresh-blob
//! generation (salt + pepper random bytes), encode, decode — so the
//! format lives one place and stays in sync with future bumps.
//!
//! What stays Dart-side: the actual file I/O (writes go through the
//! shared `writeBytesAtomic` helper that hardens to 0600), the
//! pepper round-trip into the OS keychain via
//! `lfs_os_security::secure_key_storage`, and the rate-limit-state
//! clear that runs after a successful `setPassword`.
//!
//! Wire format (JSON object, UTF-8 bytes on disk):
//! ```json
//! { "salt": "<base64 of 32 bytes>", "hmac": "<base64 of 32 bytes>" }
//! ```
//! The HMAC payload is exactly `HMAC-SHA-256(pepper, salt || password)`
//! computed via [`crate::crypto::hmac_sha256`]. The 32-byte salt
//! length is the standard for HMAC-SHA-256 input randomisation; the
//! 32-byte pepper matches the SHA-256 block-input size.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use rand::Rng;
use serde_json::Value;

/// Per-blob random-bytes lengths. Mirrors the Dart-side
/// `_saltLength` + `_pepperLength` constants. Bumps are
/// forward-compatible — a reader does not assume a specific
/// length, only that the base64 decode yields ≥ 1 byte.
pub const SALT_LENGTH: usize = 32;
pub const PEPPER_LENGTH: usize = 32;

/// Generate the random salt + pepper pair the gate seeds at
/// `setPassword` time. Two `OsRng` calls — same source the
/// master-password verifier uses for its salt.
#[must_use]
pub fn random_salt_and_pepper() -> (Vec<u8>, Vec<u8>) {
    let mut salt = vec![0u8; SALT_LENGTH];
    let mut pepper = vec![0u8; PEPPER_LENGTH];
    rand::rng().fill_bytes(&mut salt);
    rand::rng().fill_bytes(&mut pepper);
    (salt, pepper)
}

/// Compute the comparison HMAC the gate stores on disk.
///
/// `HMAC-SHA-256(pepper, salt || password_utf8)`. The Dart-side
/// `_computeHmac` calls this through the FRB crypto shim, so any
/// wire change here (key vs. message ordering, salt-prefix vs.
/// trailing) immediately invalidates every install on disk.
#[must_use]
pub fn compute_gate_hmac(
    pepper: &[u8],
    salt: &[u8],
    password: &[u8],
) -> zeroize::Zeroizing<Vec<u8>> {
    let mut msg = zeroize::Zeroizing::new(Vec::with_capacity(salt.len() + password.len()));
    msg.extend_from_slice(salt);
    msg.extend_from_slice(password);
    crate::crypto::hmac_sha256(pepper, &msg)
}

/// Wire-format version stamped into every freshly-emitted
/// `security_pass_hash.bin`. Future format change → bump this
/// + ship a migration that rewrites the disk blob; readers
///   reject `v` values they do not recognise.
pub const DISK_BLOB_VERSION: u32 = 1;

/// Encode the `{salt, hmac}` pair as the JSON envelope written
/// to `security_pass_hash.bin`. Caller writes the returned
/// string's UTF-8 bytes atomically + hardens to 0600.
#[must_use]
pub fn encode_disk_blob(salt: &[u8], hmac: &[u8]) -> String {
    // Hand-build the JSON object so the field order is stable
    // ({"v": 1, "salt": …, "hmac": …}) — `serde_json::to_string`
    // preserves map insertion order under the default features
    // the workspace pins, but the explicit literal removes any
    // doubt for the wire-format documentation.
    format!(
        "{{\"v\":{},\"salt\":\"{}\",\"hmac\":\"{}\"}}",
        DISK_BLOB_VERSION,
        STANDARD.encode(salt),
        STANDARD.encode(hmac)
    )
}

/// Decoded blob payload — the salt + comparison HMAC the gate read
/// from disk.
#[derive(Debug, Clone)]
pub struct DiskBlob {
    pub salt: Vec<u8>,
    pub hmac: Vec<u8>,
}

/// Parse the on-disk JSON envelope. Returns `Err` for malformed
/// JSON, missing fields, non-string values, or invalid base64. The
/// Dart-side `verify` treats any decode failure as a "wrong
/// password" outcome; surfacing typed errors here keeps the future
/// migration path (re-keying on format bump) cheap.
pub fn decode_disk_blob(blob: &str) -> Result<DiskBlob, String> {
    let value: Value = serde_json::from_str(blob).map_err(|e| format!("blob: parse JSON: {e}"))?;
    let obj = value
        .as_object()
        .ok_or_else(|| String::from("blob: not a JSON object"))?;
    // Accept v=1 explicitly + a missing `v` field (legacy
    // pre-version installs) so the next change-password
    // re-emits with the field present. Unknown / future
    // versions reject so a downgrade can't silently parse a
    // newer-format blob.
    if let Some(v) = obj.get("v").and_then(|x| x.as_u64()) {
        if v != DISK_BLOB_VERSION as u64 {
            return Err(format!("blob: unsupported version {v}"));
        }
    }
    let salt_b64 = obj
        .get("salt")
        .and_then(|v| v.as_str())
        .ok_or_else(|| String::from("blob: missing salt field"))?;
    let hmac_b64 = obj
        .get("hmac")
        .and_then(|v| v.as_str())
        .ok_or_else(|| String::from("blob: missing hmac field"))?;
    let salt = STANDARD
        .decode(salt_b64.as_bytes())
        .map_err(|e| format!("blob: salt decode: {e}"))?;
    let hmac = STANDARD
        .decode(hmac_b64.as_bytes())
        .map_err(|e| format!("blob: hmac decode: {e}"))?;
    if salt.is_empty() || hmac.is_empty() {
        return Err(String::from("blob: empty salt or hmac"));
    }
    Ok(DiskBlob { salt, hmac })
}
#[cfg(test)]
#[path = "../../tests/unit/security_keychain_password_gate.rs"]
mod tests;
