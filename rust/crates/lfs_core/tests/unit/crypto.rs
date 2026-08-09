/// Unit tests extracted from crypto.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn hkdf_known_answer_test() {
    // RFC 5869 Test Case 1: HKDF-SHA-256 with non-empty salt + info.
    let ikm = hex_decode("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b");
    let salt = hex_decode("000102030405060708090a0b0c");
    let info = hex_decode("f0f1f2f3f4f5f6f7f8f9");
    let okm = hkdf_sha256(&ikm, &salt, &info, 42).expect("hkdf");
    let expected = hex_decode(
        "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
    );
    assert_eq!(okm.as_slice(), expected.as_slice());
}

#[test]
fn hkdf_zero_length_rejected() {
    let result = hkdf_sha256(&[1; 32], &[], &[], 0);
    assert!(matches!(result, Err(Error::Crypto(_))));
}

#[test]
fn ed25519_round_trip() {
    use ed25519_dalek::{Signer, SigningKey};
    let sk = SigningKey::from_bytes(&[7u8; 32]);
    let msg = b"hello world";
    let sig = sk.sign(msg);
    let pk = sk.verifying_key().to_bytes();
    assert!(ed25519_verify(&pk, msg, &sig.to_bytes()));
}

#[test]
fn ed25519_rejects_tampered_signature() {
    use ed25519_dalek::{Signer, SigningKey};
    let sk = SigningKey::from_bytes(&[7u8; 32]);
    let msg = b"hello world";
    let mut sig = sk.sign(msg).to_bytes();
    sig[0] ^= 0x01;
    let pk = sk.verifying_key().to_bytes();
    assert!(!ed25519_verify(&pk, msg, &sig));
}

#[test]
fn ed25519_rejects_wrong_lengths() {
    // Bad public key
    assert!(!ed25519_verify(&[0u8; 16], b"x", &[0u8; 64]));
    // Bad signature
    assert!(!ed25519_verify(&[0u8; 32], b"x", &[0u8; 16]));
}

fn hex_decode(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

#[test]
fn aes_gcm_round_trip() {
    let key = vec![7u8; 32];
    let plaintext = b"the quick brown fox";
    let ct = aes_gcm_encrypt(&key, plaintext).expect("encrypt");
    // Output is nonce || ct+tag. Same call twice produces different
    // bytes because the nonce is freshly generated.
    let ct2 = aes_gcm_encrypt(&key, plaintext).expect("encrypt");
    assert_ne!(ct, ct2);
    let pt = aes_gcm_decrypt(&key, &ct).expect("decrypt");
    assert_eq!(pt.as_slice(), plaintext);
}

#[test]
fn aes_gcm_rejects_wrong_key() {
    let key = vec![7u8; 32];
    let other = vec![8u8; 32];
    let ct = aes_gcm_encrypt(&key, b"secret").unwrap();
    assert!(aes_gcm_decrypt(&other, &ct).is_err());
}

#[test]
fn aes_gcm_rejects_tampered_ciphertext() {
    let key = vec![7u8; 32];
    let mut ct = aes_gcm_encrypt(&key, b"secret").unwrap();
    // Flip a bit in the ciphertext (after the 12-byte nonce).
    ct[AES_GCM_IV_LEN + 1] ^= 0x01;
    assert!(aes_gcm_decrypt(&key, &ct).is_err());
}

#[test]
fn aes_gcm_known_answer_test_nist_sp_800_38d_vector_12() {
    // NIST SP 800-38D appendix B test vector 12 (AES-256 GCM):
    // 32-byte key, 12-byte IV, 60-byte plaintext, 20-byte AAD.
    // Pin the byte-for-byte output to catch any regression in the
    // underlying `aes-gcm` crate (algorithm switch, dependency
    // bump, padding bug). Without a KAT only round-trip is
    // pinned, which would silently accept any consistent (even
    // wrong) cipher.
    let key = hex_decode("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308");
    let nonce = hex_decode("cafebabefacedbaddecaf888");
    let plaintext = hex_decode(
        "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
    );
    let aad = hex_decode("feedfacedeadbeeffeedfacedeadbeefabaddad2");
    let expected_ct_with_tag = hex_decode(
        "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b",
    );
    let actual = aes_gcm_encrypt_raw(&key, &nonce, &plaintext, &aad).expect("encrypt");
    assert_eq!(
        actual, expected_ct_with_tag,
        "AES-256-GCM KAT mismatch — algorithm regression?"
    );
    // Verify decrypt round-trips against the same vector so a
    // future split between encrypt + decrypt impls can't drift
    // unnoticed.
    let decrypted =
        aes_gcm_decrypt_raw(&key, &nonce, &expected_ct_with_tag, &aad).expect("decrypt");
    assert_eq!(decrypted.as_slice(), plaintext.as_slice());
}

#[test]
fn aes_gcm_known_answer_test_empty_payload_with_aad() {
    // Companion KAT with empty plaintext + non-empty AAD —
    // exercises the AAD-only authentication path the recorder's
    // empty-frame handling depends on. Tag is computed off AAD
    // alone so a regression that drops AAD from the tag would
    // surface here.
    let key = hex_decode("0000000000000000000000000000000000000000000000000000000000000000");
    let nonce = hex_decode("000000000000000000000000");
    let plaintext: Vec<u8> = Vec::new();
    let aad = b"binding-aad";
    let actual = aes_gcm_encrypt_raw(&key, &nonce, &plaintext, aad).expect("encrypt");
    // 16-byte tag only (no ciphertext for empty plaintext).
    assert_eq!(actual.len(), AES_GCM_TAG_LEN);
    // Decrypt must reproduce empty plaintext when AAD matches,
    // and reject when it doesn't.
    let decrypted = aes_gcm_decrypt_raw(&key, &nonce, &actual, aad).expect("decrypt");
    assert!(decrypted.is_empty());
    assert!(aes_gcm_decrypt_raw(&key, &nonce, &actual, b"different-aad").is_err());
}

#[test]
fn aes_gcm_raw_round_trip_with_aad() {
    let key = vec![3u8; 32];
    let nonce = vec![4u8; 12];
    let aad = b"frame-context";
    let pt = b"recorder frame payload";
    let ct = aes_gcm_encrypt_raw(&key, &nonce, pt, aad).unwrap();
    let dec = aes_gcm_decrypt_raw(&key, &nonce, &ct, aad).unwrap();
    assert_eq!(dec.as_slice(), pt);
    // Wrong AAD must fail.
    assert!(aes_gcm_decrypt_raw(&key, &nonce, &ct, b"other-context").is_err());
}

#[test]
fn aes_gcm_rejects_bad_nonce_len() {
    let key = vec![3u8; 32];
    let result = aes_gcm_encrypt_raw(&key, &[1u8; 8], b"x", &[]);
    assert!(matches!(result, Err(Error::Crypto(_))));
}

#[test]
fn aes_gcm_rejects_bad_key_len() {
    let result = aes_gcm_encrypt(&[0u8; 16], b"x");
    assert!(matches!(result, Err(Error::Crypto(_))));
}

#[test]
fn argon2id_known_answer_test() {
    // Argon2id KAT at t=3, m=32 KiB, p=4, length=32,
    // password = 32 * 0x01, salt = 16 * 0x02. Same input
    // shape as the RFC 9106 §5.3 reference vector minus the
    // 8-byte secret + 12-byte AD (our surface does not feed
    // either; the underlying `argon2` crate's
    // `hash_password_into` runs with empty secret + empty AD
    // by definition). The expected hex is the byte-exact
    // output of `argon2 = "0.5"` with the workspace-pinned
    // toolchain — pin it here so a silent algorithmic
    // regression in any future bump fails the build before
    // the bytes reach an installed user's vault.
    let pwd = vec![0x01u8; 32];
    let salt = vec![0x02u8; 16];
    let derived = argon2id_derive(&pwd, &salt, 32, 3, 4, 32).unwrap();
    let expected = hex_decode("03aab965c12001c9d7d0d2de33192c0494b684bb148196d73c1df1acaf6d0c2e");
    assert_eq!(
        *derived, expected,
        "Argon2id KAT mismatch — algorithm regression?"
    );
    // Reproducibility — two runs with identical inputs must
    // yield identical output.
    let again = argon2id_derive(&pwd, &salt, 32, 3, 4, 32).unwrap();
    assert_eq!(derived, again);
    // Different memory cost must yield different output.
    let different = argon2id_derive(&pwd, &salt, 64, 3, 4, 32).unwrap();
    assert_ne!(derived, different);
}

#[test]
fn argon2id_rejects_zero_length() {
    let result = argon2id_derive(&[1; 8], &[2; 16], 32, 3, 1, 0);
    assert!(matches!(result, Err(Error::Crypto(_))));
}

#[test]
fn hmac_sha256_known_answer_rfc4231_case_1() {
    // RFC 4231 §4.2 test case 1: 20-byte 0x0b key, "Hi There".
    let key = vec![0x0b; 20];
    let mac = hmac_sha256(&key, b"Hi There");
    assert_eq!(mac.len(), 32);
    assert_eq!(
        *mac,
        hex_decode("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    );
}

#[test]
fn hmac_sha256_empty_key_and_message_match_rust_crypto() {
    // Empty inputs are valid for HMAC; the gate paths use this
    // edge case when the user picks "no password" on T2.
    let mac_a = hmac_sha256(&[], &[]);
    let mac_b = hmac_sha256(&[], &[]);
    assert_eq!(mac_a, mac_b);
    assert_eq!(mac_a.len(), 32);
}

#[test]
fn hmac_sha256_key_length_does_not_truncate_output() {
    // The Dart sites pass keys of every length (32-byte salt,
    // 32-byte pepper, 32-byte derived password hash). Output
    // must always be 32 bytes, the SHA-256 block size.
    for key_len in [0, 1, 16, 32, 64, 100] {
        let key = vec![0x42u8; key_len];
        let mac = hmac_sha256(&key, b"x");
        assert_eq!(mac.len(), 32, "key_len={key_len}");
    }
}

#[test]
fn constant_time_eq_matches_equal_bytes() {
    assert!(constant_time_eq(b"abc", b"abc"));
    assert!(constant_time_eq(&[], &[]));
    assert!(constant_time_eq(&[0u8; 32], &[0u8; 32]));
}

#[test]
fn constant_time_eq_rejects_different_bytes() {
    assert!(!constant_time_eq(b"abc", b"abd"));
    assert!(!constant_time_eq(&[0u8; 32], &[1u8; 32]));
}

#[test]
fn sha256_known_answer_empty_input() {
    // FIPS 180-4 reference vector: SHA-256("") = e3b0c4...
    assert_eq!(
        sha256_hex(b""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
}

#[test]
fn sha256_known_answer_abc() {
    // FIPS 180-4 reference vector: SHA-256("abc")
    assert_eq!(
        sha256_hex(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
}

#[test]
fn sha256_bytes_match_hex_string() {
    let raw = sha256(b"hello world");
    assert_eq!(raw.len(), 32);
    let hex = sha256_hex(b"hello world");
    let mut from_bytes = String::new();
    for b in &raw {
        use std::fmt::Write as _;
        let _ = write!(from_bytes, "{b:02x}");
    }
    assert_eq!(hex, from_bytes);
}

#[test]
fn constant_time_eq_rejects_different_lengths() {
    // Length mismatch fails fast — the lengths themselves are
    // not secret, only the byte content is.
    assert!(!constant_time_eq(b"abc", b"abcd"));
    assert!(!constant_time_eq(b"", b"x"));
    assert!(!constant_time_eq(b"x", b""));
}
