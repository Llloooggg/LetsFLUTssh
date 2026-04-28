//! Disk-blob format owner for the L2 keychain-with-password gate.
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
//! `flutter_secure_storage` keychain read/write, and the
//! rate-limit-state clear that runs after a successful
//! `setPassword`.
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
use rand::rngs::OsRng;
use rand::RngCore;
use serde_json::Value;

/// Per-blob random-bytes lengths. Mirrors the Dart-side `_saltLength`
/// + `_pepperLength` constants. Bumps are forward-compatible — a
/// reader does not assume a specific length, only that the base64
/// decode yields ≥ 1 byte.
pub const SALT_LENGTH: usize = 32;
pub const PEPPER_LENGTH: usize = 32;

/// Generate the random salt + pepper pair the gate seeds at
/// `setPassword` time. Two `OsRng` calls — same source the
/// master-password verifier uses for its salt.
#[must_use]
pub fn random_salt_and_pepper() -> (Vec<u8>, Vec<u8>) {
    let mut salt = vec![0u8; SALT_LENGTH];
    let mut pepper = vec![0u8; PEPPER_LENGTH];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut pepper);
    (salt, pepper)
}

/// Compute the comparison HMAC the gate stores on disk.
///
/// `HMAC-SHA-256(pepper, salt || password_utf8)`. The Dart-side
/// `_computeHmac` calls this through the FRB crypto shim, so any
/// wire change here (key vs. message ordering, salt-prefix vs.
/// trailing) immediately invalidates every install on disk.
#[must_use]
pub fn compute_gate_hmac(pepper: &[u8], salt: &[u8], password: &str) -> Vec<u8> {
    let mut msg = Vec::with_capacity(salt.len() + password.len());
    msg.extend_from_slice(salt);
    msg.extend_from_slice(password.as_bytes());
    crate::crypto::hmac_sha256(pepper, &msg)
}

/// Encode the salt + hmac pair as the JSON envelope written to
/// `security_pass_hash.bin`. Caller writes the returned string's
/// UTF-8 bytes atomically + hardens to 0600.
#[must_use]
pub fn encode_disk_blob(salt: &[u8], hmac: &[u8]) -> String {
    // Hand-build the JSON object so the field order is stable
    // ({"salt": …, "hmac": …}) — `serde_json::to_string` preserves
    // map insertion order under the default features the workspace
    // pins, but the explicit literal removes any doubt for the
    // wire-format documentation.
    format!(
        "{{\"salt\":\"{}\",\"hmac\":\"{}\"}}",
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
mod tests {
    use super::*;

    #[test]
    fn random_salt_and_pepper_have_expected_lengths() {
        let (salt, pepper) = random_salt_and_pepper();
        assert_eq!(salt.len(), SALT_LENGTH);
        assert_eq!(pepper.len(), PEPPER_LENGTH);
    }

    #[test]
    fn random_salt_and_pepper_differ_across_calls() {
        // OsRng entropy — two back-to-back calls must produce
        // distinct outputs (collision probability is 2^-256).
        let (s1, p1) = random_salt_and_pepper();
        let (s2, p2) = random_salt_and_pepper();
        assert_ne!(s1, s2);
        assert_ne!(p1, p2);
    }

    #[test]
    fn encode_decode_disk_blob_round_trips() {
        let salt = vec![0x11u8; SALT_LENGTH];
        let hmac = vec![0x22u8; 32];
        let blob = encode_disk_blob(&salt, &hmac);
        let decoded = decode_disk_blob(&blob).unwrap();
        assert_eq!(decoded.salt, salt);
        assert_eq!(decoded.hmac, hmac);
    }

    #[test]
    fn decode_rejects_malformed_json() {
        assert!(decode_disk_blob("not-json-at-all").is_err());
        assert!(decode_disk_blob("[]").is_err()); // top-level array
    }

    #[test]
    fn decode_rejects_missing_fields() {
        assert!(decode_disk_blob("{}").is_err());
        assert!(decode_disk_blob(r#"{"salt":"YQ=="}"#).is_err());
        assert!(decode_disk_blob(r#"{"hmac":"YQ=="}"#).is_err());
    }

    #[test]
    fn decode_rejects_non_string_fields() {
        assert!(decode_disk_blob(r#"{"salt":1,"hmac":"YQ=="}"#).is_err());
        assert!(decode_disk_blob(r#"{"salt":"YQ==","hmac":[]}"#).is_err());
    }

    #[test]
    fn decode_rejects_invalid_base64() {
        let blob = r#"{"salt":"!!!","hmac":"YQ=="}"#;
        assert!(decode_disk_blob(blob).is_err());
    }

    #[test]
    fn decode_rejects_empty_decoded_bytes() {
        // Empty base64 → empty bytes; a legitimate blob never has
        // a zero-length salt or hmac, and a tampered file with
        // those fields must not parse as valid.
        let blob = r#"{"salt":"","hmac":""}"#;
        assert!(decode_disk_blob(blob).is_err());
    }

    #[test]
    fn compute_gate_hmac_is_deterministic() {
        let pepper = vec![0xaau8; PEPPER_LENGTH];
        let salt = vec![0xbbu8; SALT_LENGTH];
        let a = compute_gate_hmac(&pepper, &salt, "secret");
        let b = compute_gate_hmac(&pepper, &salt, "secret");
        assert_eq!(a, b);
        assert_eq!(a.len(), 32, "HMAC-SHA-256 always emits 32 bytes");
    }

    #[test]
    fn compute_gate_hmac_changes_when_password_changes() {
        let pepper = vec![0xaau8; PEPPER_LENGTH];
        let salt = vec![0xbbu8; SALT_LENGTH];
        let a = compute_gate_hmac(&pepper, &salt, "alpha");
        let b = compute_gate_hmac(&pepper, &salt, "beta");
        assert_ne!(a, b);
    }

    #[test]
    fn compute_gate_hmac_changes_when_salt_changes() {
        let pepper = vec![0xaau8; PEPPER_LENGTH];
        let a = compute_gate_hmac(&pepper, &vec![0xbbu8; SALT_LENGTH], "x");
        let b = compute_gate_hmac(&pepper, &vec![0xccu8; SALT_LENGTH], "x");
        assert_ne!(a, b);
    }

    #[test]
    fn compute_gate_hmac_changes_when_pepper_changes() {
        let salt = vec![0xbbu8; SALT_LENGTH];
        let a = compute_gate_hmac(&vec![0xaau8; PEPPER_LENGTH], &salt, "x");
        let b = compute_gate_hmac(&vec![0xddu8; PEPPER_LENGTH], &salt, "x");
        assert_ne!(a, b);
    }
}
