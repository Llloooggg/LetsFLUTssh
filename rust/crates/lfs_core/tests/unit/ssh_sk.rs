/// Unit tests extracted from ssh/sk.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn is_sk_algorithm_matches_known_variants() {
    assert!(is_sk_algorithm(&Algorithm::SkEd25519));
    assert!(is_sk_algorithm(&Algorithm::SkEcdsaSha2NistP256));
    assert!(!is_sk_algorithm(&Algorithm::Ed25519));
    assert!(!is_sk_algorithm(&Algorithm::Ecdsa {
        curve: EcdsaCurve::NistP256
    }));
}

#[test]
fn algorithm_from_key_type_round_trips_short_tags() {
    assert!(matches!(
        algorithm_from_key_type("sk-ed25519"),
        Some(Algorithm::SkEd25519)
    ));
    assert!(matches!(
        algorithm_from_key_type("sk-ecdsa-p256"),
        Some(Algorithm::SkEcdsaSha2NistP256)
    ));
    assert!(algorithm_from_key_type("ssh-ed25519").is_none());
    assert!(algorithm_from_key_type("").is_none());
}

#[test]
fn algorithm_from_key_type_accepts_full_wire_names() {
    // The DB stores the short tag, but the import path may
    // surface the full wire name from a parsed cert — accept
    // both so the connect dispatch stays single-path.
    assert!(matches!(
        algorithm_from_key_type("sk-ssh-ed25519@openssh.com"),
        Some(Algorithm::SkEd25519)
    ));
    assert!(matches!(
        algorithm_from_key_type("sk-ecdsa-sha2-nistp256@openssh.com"),
        Some(Algorithm::SkEcdsaSha2NistP256)
    ));
}

#[test]
fn encode_sk_signature_ed25519_appends_flags_and_counter() {
    let raw = vec![0xAAu8; 64];
    let out = encode_sk_signature(&Algorithm::SkEd25519, &raw, 0x05, 0x01020304).unwrap();
    // 64 raw bytes || flags byte || u32 BE counter.
    assert_eq!(out.len(), 69);
    assert_eq!(&out[..64], &raw[..]);
    assert_eq!(out[64], 0x05);
    assert_eq!(&out[65..69], &[0x01, 0x02, 0x03, 0x04]);
}

#[test]
fn encode_sk_signature_ed25519_rejects_wrong_size() {
    let bad = vec![0u8; 32];
    let err = encode_sk_signature(&Algorithm::SkEd25519, &bad, 0, 0)
        .expect_err("must reject wrong-size sig");
    assert!(matches!(err, Error::Auth(_)));
}

#[test]
fn encode_sk_signature_ecdsa_p256_uses_wire_mpint() {
    // SEQUENCE { INTEGER 0x01, INTEGER 0x02 } || flags || counter.
    let der: Vec<u8> = vec![0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02];
    let out =
        encode_sk_signature(&Algorithm::SkEcdsaSha2NistP256, &der, 0x03, 0x0A_0B_0C_0D).unwrap();
    // mpint(1) || mpint(2) — 10 bytes — then flags + counter.
    assert_eq!(
        &out[..10],
        &[
            0, 0, 0, 1, 0x01, // mpint r
            0, 0, 0, 1, 0x02, // mpint s
        ]
    );
    assert_eq!(out[10], 0x03);
    assert_eq!(&out[11..15], &[0x0A, 0x0B, 0x0C, 0x0D]);
}

#[test]
fn encode_sk_signature_ecdsa_p256_rejects_truncated_der() {
    let err = encode_sk_signature(
        &Algorithm::SkEcdsaSha2NistP256,
        &[0x30, 0x06, 0x02, 0x01],
        0,
        0,
    )
    .unwrap_err();
    assert!(matches!(err, Error::Auth(_)));
}

#[test]
fn encode_signature_outer_string_carries_algorithm_then_sig() {
    // The outer wire string is `length || string(name) ||
    // string(blob)`. Confirm the byte layout.
    let sig_blob = b"sigbytes".to_vec();
    let out = encode_signature(&Algorithm::SkEd25519, &sig_blob).unwrap();
    // First four bytes are the outer length.
    let outer_len = u32::from_be_bytes(out[0..4].try_into().unwrap()) as usize;
    assert_eq!(out.len(), 4 + outer_len);
    // Next four bytes — length of the algorithm-name string.
    let name_len = u32::from_be_bytes(out[4..8].try_into().unwrap()) as usize;
    let name = std::str::from_utf8(&out[8..8 + name_len]).unwrap();
    assert_eq!(name, "sk-ssh-ed25519@openssh.com");
    // Followed by the length-prefixed signature blob.
    let after_name = 8 + name_len;
    let blob_len = u32::from_be_bytes(out[after_name..after_name + 4].try_into().unwrap()) as usize;
    assert_eq!(blob_len, sig_blob.len());
    assert_eq!(
        &out[after_name + 4..after_name + 4 + blob_len],
        &sig_blob[..]
    );
}

#[test]
fn algorithm_wire_name_rejects_software_key() {
    let err = algorithm_wire_name(&Algorithm::Ed25519).unwrap_err();
    assert!(matches!(err, Error::Auth(_)));
}
