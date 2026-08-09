/// Unit tests extracted from security/keychain_password_gate.rs
/// Declared via `#[path] mod tests;` in the source file.
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
    let a = compute_gate_hmac(&pepper, &salt, b"secret");
    let b = compute_gate_hmac(&pepper, &salt, b"secret");
    assert_eq!(a, b);
    assert_eq!(a.len(), 32, "HMAC-SHA-256 always emits 32 bytes");
}

#[test]
fn compute_gate_hmac_changes_when_password_changes() {
    let pepper = vec![0xaau8; PEPPER_LENGTH];
    let salt = vec![0xbbu8; SALT_LENGTH];
    let a = compute_gate_hmac(&pepper, &salt, b"alpha");
    let b = compute_gate_hmac(&pepper, &salt, b"beta");
    assert_ne!(a, b);
}

#[test]
fn compute_gate_hmac_changes_when_salt_changes() {
    let pepper = [0xaau8; PEPPER_LENGTH];
    let a = compute_gate_hmac(&pepper, &[0xbbu8; SALT_LENGTH], b"x");
    let b = compute_gate_hmac(&pepper, &[0xccu8; SALT_LENGTH], b"x");
    assert_ne!(a, b);
}

#[test]
fn compute_gate_hmac_changes_when_pepper_changes() {
    let salt = [0xbbu8; SALT_LENGTH];
    let a = compute_gate_hmac(&[0xaau8; PEPPER_LENGTH], &salt, b"x");
    let b = compute_gate_hmac(&[0xddu8; PEPPER_LENGTH], &salt, b"x");
    assert_ne!(a, b);
}
