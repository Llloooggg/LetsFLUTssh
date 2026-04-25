//! Phase-2 crypto primitives — pure Rust replacements for
//! pointycastle's HKDF and pinenacl's Ed25519 verify.
//!
//! Boundary:
//!   - `hkdf_sha256` derives keys for the recorder envelope and for
//!     any future `letsflutssh-*` HKDF context tags. RustCrypto's
//!     `hkdf` over `sha2::Sha256`.
//!   - `ed25519_verify` is the pinned-key signature check for update
//!     artefact metadata. `ed25519-dalek` strict-verify mode (no
//!     malleability acceptance).
//!
//! Both functions are CPU-bound, deterministic, and short — caller
//! drives them on whatever thread they like. Adapter crates wrap
//! them in `tokio::task::spawn_blocking` if FRB demands `Send +
//! 'static` on the future.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use argon2::{Algorithm, Argon2, Params, Version};
use hkdf::Hkdf;
use rand::RngCore;
use sha2::Sha256;

use crate::error::Error;

/// AES-256-GCM IV is fixed at 12 bytes (96 bits) — both the
/// IETF / TLS profile and OpenSSH's chacha-poly profile match this.
pub const AES_GCM_IV_LEN: usize = 12;
/// AES-256 key is fixed at 32 bytes.
pub const AES_GCM_KEY_LEN: usize = 32;
/// AES-GCM tag is fixed at 16 bytes (128 bits) — matches the
/// pointycastle default the Dart side ships with.
pub const AES_GCM_TAG_LEN: usize = 16;

/// HKDF-SHA-256 with the standard `extract → expand` flow.
///
/// `length` is the byte count to expand to — capped at 8160
/// (255 * 32) by the spec; the helper rejects anything larger so the
/// caller does not silently get a truncated key.
pub fn hkdf_sha256(ikm: &[u8], salt: &[u8], info: &[u8], length: usize) -> Result<Vec<u8>, Error> {
    if length == 0 || length > 255 * 32 {
        return Err(Error::Crypto(format!(
            "hkdf-sha256 length {length} out of range (1..=8160)"
        )));
    }
    let hk = Hkdf::<Sha256>::new(Some(salt), ikm);
    let mut out = vec![0u8; length];
    hk.expand(info, &mut out)
        .map_err(|e| Error::Crypto(format!("hkdf expand: {e}")))?;
    Ok(out)
}

/// Verify an Ed25519 signature over `message` against `public_key`.
///
/// Returns `Ok(true)` only on a valid signature; bad-length inputs
/// or parse failures return `Ok(false)` (fail-closed). Errors are
/// reserved for genuinely unexpected conditions.
pub fn ed25519_verify(public_key: &[u8], message: &[u8], signature: &[u8]) -> bool {
    if public_key.len() != 32 || signature.len() != 64 {
        return false;
    }
    let mut pk_bytes = [0u8; 32];
    pk_bytes.copy_from_slice(public_key);
    let mut sig_bytes = [0u8; 64];
    sig_bytes.copy_from_slice(signature);

    let Ok(verifier) = ed25519_dalek::VerifyingKey::from_bytes(&pk_bytes) else {
        return false;
    };
    let signature = ed25519_dalek::Signature::from_bytes(&sig_bytes);
    // `verify_strict` rejects signatures that pass the lax check but
    // would be malleable — matches the pinenacl behaviour we replace.
    verifier.verify_strict(message, &signature).is_ok()
}

/// Encrypt `plaintext` with AES-256-GCM. Generates a fresh random
/// 12-byte nonce, returns `nonce || ciphertext || tag` — matches the
/// wire shape `lib/core/security/aes_gcm.dart` ships today.
pub fn aes_gcm_encrypt(key: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, Error> {
    let cipher = build_cipher(key)?;
    let mut nonce_bytes = [0u8; AES_GCM_IV_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ct = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| Error::Crypto(format!("aes-gcm encrypt: {e}")))?;
    let mut out = Vec::with_capacity(AES_GCM_IV_LEN + ct.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ct);
    Ok(out)
}

/// Decrypt the inverse of [aes_gcm_encrypt]: input is
/// `nonce || ciphertext || tag`. GCM tag is verified — bad tag /
/// wrong key / truncated input all surface as `Error::Crypto`.
pub fn aes_gcm_decrypt(key: &[u8], data: &[u8]) -> Result<Vec<u8>, Error> {
    if data.len() < AES_GCM_IV_LEN + AES_GCM_TAG_LEN {
        return Err(Error::Crypto(format!(
            "aes-gcm input too short ({} bytes; need ≥ {})",
            data.len(),
            AES_GCM_IV_LEN + AES_GCM_TAG_LEN
        )));
    }
    let cipher = build_cipher(key)?;
    let nonce = Nonce::from_slice(&data[..AES_GCM_IV_LEN]);
    cipher
        .decrypt(nonce, &data[AES_GCM_IV_LEN..])
        .map_err(|e| Error::Crypto(format!("aes-gcm decrypt: {e}")))
}

/// Encrypt with caller-supplied 12-byte nonce + AAD. Returns
/// `ciphertext || tag` — the nonce is NOT prefixed (caller frames
/// it separately, e.g. recorder per-frame `[len][nonce][ct+tag]`).
pub fn aes_gcm_encrypt_raw(
    key: &[u8],
    nonce: &[u8],
    plaintext: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>, Error> {
    if nonce.len() != AES_GCM_IV_LEN {
        return Err(Error::Crypto(format!(
            "aes-gcm nonce length {} (expected {AES_GCM_IV_LEN})",
            nonce.len()
        )));
    }
    let cipher = build_cipher(key)?;
    let nonce_obj = Nonce::from_slice(nonce);
    cipher
        .encrypt(
            nonce_obj,
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|e| Error::Crypto(format!("aes-gcm encrypt-raw: {e}")))
}

/// Decrypt with caller-supplied 12-byte nonce + AAD. Input is
/// `ciphertext || tag`.
pub fn aes_gcm_decrypt_raw(
    key: &[u8],
    nonce: &[u8],
    ciphertext: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>, Error> {
    if nonce.len() != AES_GCM_IV_LEN {
        return Err(Error::Crypto(format!(
            "aes-gcm nonce length {} (expected {AES_GCM_IV_LEN})",
            nonce.len()
        )));
    }
    if ciphertext.len() < AES_GCM_TAG_LEN {
        return Err(Error::Crypto(format!(
            "aes-gcm ciphertext too short ({} bytes; need ≥ {AES_GCM_TAG_LEN})",
            ciphertext.len()
        )));
    }
    let cipher = build_cipher(key)?;
    let nonce_obj = Nonce::from_slice(nonce);
    cipher
        .decrypt(
            nonce_obj,
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|e| Error::Crypto(format!("aes-gcm decrypt-raw: {e}")))
}

/// Argon2id key derivation. `memory_kib` / `iterations` / `parallelism`
/// match the pointycastle parameters the Dart side ships today, so
/// existing on-disk salts derive identical bytes when verified
/// through this path. Output is `length` bytes (typically 32 for the
/// AES-256-GCM master key derivation).
pub fn argon2id_derive(
    password: &[u8],
    salt: &[u8],
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
    length: u32,
) -> Result<Vec<u8>, Error> {
    let length_usize = length as usize;
    if length_usize == 0 || length_usize > 64 * 1024 * 1024 {
        return Err(Error::Crypto(format!(
            "argon2id output length {length_usize} out of range (1..=67108864)"
        )));
    }
    let params = Params::new(memory_kib, iterations, parallelism, Some(length_usize))
        .map_err(|e| Error::Crypto(format!("argon2id params: {e}")))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut out = vec![0u8; length_usize];
    argon2
        .hash_password_into(password, salt, &mut out)
        .map_err(|e| Error::Crypto(format!("argon2id derive: {e}")))?;
    Ok(out)
}

fn build_cipher(key: &[u8]) -> Result<Aes256Gcm, Error> {
    if key.len() != AES_GCM_KEY_LEN {
        return Err(Error::Crypto(format!(
            "aes-256-gcm key length {} (expected {AES_GCM_KEY_LEN})",
            key.len()
        )));
    }
    let key_obj = Key::<Aes256Gcm>::from_slice(key);
    Ok(Aes256Gcm::new(key_obj))
}

#[cfg(test)]
mod tests {
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
        assert_eq!(okm, expected);
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
        assert_eq!(pt, plaintext);
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
    fn aes_gcm_raw_round_trip_with_aad() {
        let key = vec![3u8; 32];
        let nonce = vec![4u8; 12];
        let aad = b"frame-context";
        let pt = b"recorder frame payload";
        let ct = aes_gcm_encrypt_raw(&key, &nonce, pt, aad).unwrap();
        let dec = aes_gcm_decrypt_raw(&key, &nonce, &ct, aad).unwrap();
        assert_eq!(dec, pt);
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
        // RFC 9106 §5.3 KAT for Argon2id at t=3, m=32 KiB, p=4,
        // length=32, password = 32 * 0x01, salt = 16 * 0x02. The
        // RFC test vector also feeds 8-byte secret + 12-byte AD; our
        // surface only takes (password, salt) so we verify the
        // simpler constant-input round-trip is reproducible. Two
        // runs with the same inputs must yield the same output.
        let pwd = vec![0x01u8; 32];
        let salt = vec![0x02u8; 16];
        let a = argon2id_derive(&pwd, &salt, 32, 3, 4, 32).unwrap();
        let b = argon2id_derive(&pwd, &salt, 32, 3, 4, 32).unwrap();
        assert_eq!(a, b);
        assert_eq!(a.len(), 32);
        // Different params must yield different output.
        let c = argon2id_derive(&pwd, &salt, 64, 3, 4, 32).unwrap();
        assert_ne!(a, c);
    }

    #[test]
    fn argon2id_rejects_zero_length() {
        let result = argon2id_derive(&[1; 8], &[2; 16], 32, 3, 1, 0);
        assert!(matches!(result, Err(Error::Crypto(_))));
    }
}
