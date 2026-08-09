//! Crypto primitives — pure-Rust HKDF, Ed25519 verify, AES-256-GCM
//! encrypt/decrypt, Argon2id derivation. Built on the RustCrypto
//! stack (`hkdf` + `ed25519-dalek` + `aes-gcm` + `argon2`). Sole
//! crypto surface for the app — no Dart-side crypto library lives
//! in `pubspec.yaml`, so any new primitive lands here, not in Dart.
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

use aes_gcm::aead::generic_array::GenericArray;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::Aes256Gcm;
use argon2::{Algorithm, Argon2, Params, Version};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use rand::Rng;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

type HmacSha256 = Hmac<Sha256>;

use crate::error::Error;

/// AES-256-GCM IV is fixed at 12 bytes (96 bits) — both the
/// IETF / TLS profile and OpenSSH's chacha-poly profile match this.
pub const AES_GCM_IV_LEN: usize = 12;
/// AES-256 key is fixed at 32 bytes.
pub const AES_GCM_KEY_LEN: usize = 32;
/// AES-GCM tag is fixed at 16 bytes (128 bits) — IETF AEAD profile.
/// **Never bump.** Every on-disk AEAD envelope (`.lfs` archives,
/// `credentials.verify`, recorder frames, secret-store wrappers)
/// is parsed against this constant; a change orphans every
/// pre-bump file with no migration path.
pub const AES_GCM_TAG_LEN: usize = 16;

/// HKDF-SHA-256 with the standard `extract → expand` flow.
///
/// `length` is the byte count to expand to — capped at 8160
/// (255 * 32) by the spec; the helper rejects anything larger so the
/// caller does not silently get a truncated key.
pub fn hkdf_sha256(
    ikm: &[u8],
    salt: &[u8],
    info: &[u8],
    length: usize,
) -> Result<Zeroizing<Vec<u8>>, Error> {
    if length == 0 || length > 255 * 32 {
        return Err(Error::Crypto(format!(
            "hkdf-sha256 length {length} out of range (1..=8160)"
        )));
    }
    let hk = Hkdf::<Sha256>::new(Some(salt), ikm);
    let mut out = Zeroizing::new(vec![0u8; length]);
    hk.expand(info, &mut out)
        .map_err(|e| Error::Crypto(format!("hkdf expand: {e}")))?;
    Ok(out)
}

/// HMAC-SHA-256 over `message` keyed by `key`. Returns the 32-byte
/// MAC tag.
///
/// Used by the security-tier secret gates that prove the user typed
/// the right password / PIN without ever decrypting the wrapped key
/// material:
///
/// * `KeychainPasswordGate` (T1+pw) — gate-stored hash:
///   `HMAC(pepper, salt || password)`. Mismatch ≠ keychain unlock.
/// * `HardwareTierVault` (T2) — TPM auth value:
///   `HMAC(salt, password)` (or `HMAC(salt, fprintdHash)` on the
///   biometric branch). Mismatch ≠ TPM unseal — the hardware
///   enforces the per-attempt rate limit.
/// * `PersistedRateLimiter` — disk-blob signature:
///   `HMAC(stored_password_hash, payload)`. Mismatch indicates
///   tampering; resets to the worst-case backoff.
///
/// Pure RustCrypto; the Dart sites flip to this once the FRB sync
/// shim lands. Keying the HMAC the same way Dart does (key as the
/// HMAC key, message as the data) keeps wire-byte parity with
/// existing on-disk blobs across the migration.
#[must_use]
pub fn hmac_sha256(key: &[u8], message: &[u8]) -> Zeroizing<Vec<u8>> {
    // HMAC accepts any key length (it pads/hashes to the block size
    // internally) so `new_from_slice` never errors here. Construction
    // moved to the `KeyInit` trait in crypto-common 0.2; fully-qualify
    // hmac's `KeyInit` to disambiguate from the `aes_gcm::aead::KeyInit`
    // (crypto-common 0.1) also in scope.
    //
    // Returns `Zeroizing<Vec<u8>>` so the 32-byte tag is wiped on
    // drop. The tag is keyed on a pepper / salt that is itself
    // secret (vault encryption key inputs, persisted rate-limit
    // signing key, T1+pw verification HMAC); leaking the bytes
    // through a heap allocation that lives past the call site
    // would let a memory dump fingerprint the keyed input.
    let mut mac = <HmacSha256 as hmac::digest::KeyInit>::new_from_slice(key)
        .expect("HMAC-SHA-256 accepts any key length");
    mac.update(message);
    Zeroizing::new(mac.finalize().into_bytes().to_vec())
}

/// SHA-256 digest over `bytes`. Returns the 32-byte hash. Used by
/// the per-key fingerprint helpers (`KeyStore.privateKeyFingerprint` /
/// `publicKeyFingerprint`), the known-hosts MD5/SHA-256 fingerprint
/// formatter, fprintd enrolment-list digest, and the update-feed
/// asset content hash. Consolidating here keeps `package:crypto`'s
/// `sha256.convert` from being a per-site dep.
#[must_use]
pub fn sha256(bytes: &[u8]) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher.finalize().to_vec()
}

/// Lower-case hex of [`sha256(bytes)`]. Convenience for callers
/// that store the digest as a hex string (Dart side: every
/// `_sha256Hex` helper).
#[must_use]
pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = sha256(bytes);
    let mut out = String::with_capacity(digest.len() * 2);
    for b in digest {
        use std::fmt::Write as _;
        let _ = write!(out, "{b:02x}");
    }
    out
}

/// Constant-time equality over two byte slices. Returns `false`
/// immediately when the lengths differ (lengths are not secret); the
/// per-byte comparison runs to completion regardless of where the
/// first differing byte sits, so a timing-side-channel attacker
/// cannot binary-search the secret one byte at a time.
///
/// Backed by `subtle::ConstantTimeEq` — never replace with `==` on
/// MAC tags, derived keys, or any value where mismatch leaks part of
/// a secret. The Dart-side `_constantTimeEqual` helpers in the T1+pw
/// gate + persisted-rate-limiter route through this via
/// `crypto_constant_time_eq` so the implementation lives one place.
#[must_use]
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    if a.len() != b.len() {
        return false;
    }
    a.ct_eq(b).into()
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

/// Generate a fresh random 32-byte AES-256 key. Uses `OsRng` —
/// the same source [`aes_gcm_encrypt`] uses for its nonces.
/// Sized at [`AES_GCM_KEY_LEN`] = 32 bytes.
pub fn aes_gcm_random_key() -> Zeroizing<Vec<u8>> {
    let mut key = Zeroizing::new(vec![0u8; AES_GCM_KEY_LEN]);
    rand::rng().fill_bytes(&mut key);
    key
}

/// Encrypt `plaintext` with AES-256-GCM. Generates a fresh random
/// 12-byte nonce, returns `nonce || ciphertext || tag`.
pub fn aes_gcm_encrypt(key: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, Error> {
    let cipher = build_cipher(key)?;
    let mut nonce_bytes = [0u8; AES_GCM_IV_LEN];
    rand::rng().fill_bytes(&mut nonce_bytes);
    let nonce = GenericArray::from_slice(&nonce_bytes);
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
pub fn aes_gcm_decrypt(key: &[u8], data: &[u8]) -> Result<Zeroizing<Vec<u8>>, Error> {
    if data.len() < AES_GCM_IV_LEN + AES_GCM_TAG_LEN {
        return Err(Error::Crypto(format!(
            "aes-gcm input too short ({} bytes; need ≥ {})",
            data.len(),
            AES_GCM_IV_LEN + AES_GCM_TAG_LEN
        )));
    }
    let cipher = build_cipher(key)?;
    let nonce = GenericArray::from_slice(&data[..AES_GCM_IV_LEN]);
    cipher
        .decrypt(nonce, &data[AES_GCM_IV_LEN..])
        .map(Zeroizing::new)
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
    let nonce_obj = GenericArray::from_slice(nonce);
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
) -> Result<Zeroizing<Vec<u8>>, Error> {
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
    let nonce_obj = GenericArray::from_slice(nonce);
    cipher
        .decrypt(
            nonce_obj,
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map(Zeroizing::new)
        .map_err(|e| Error::Crypto(format!("aes-gcm decrypt-raw: {e}")))
}

/// Argon2id key derivation. The four inputs `memory_kib`,
/// `iterations`, `parallelism`, `salt` jointly determine the
/// derived bytes — changing any of them against a stored
/// `credentials.kdf` salt produces a different key and locks the
/// user out. Production defaults live in
/// `lfs_core::security::master_password::KdfParams::defaults`
/// (Argon2id m=64 MiB t=3 p=1, one tier above the OWASP 2024 floor).
/// Output is `length` bytes (typically 32 for the AES-256-GCM master
/// key derivation).
pub fn argon2id_derive(
    password: &[u8],
    salt: &[u8],
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
    length: u32,
) -> Result<Zeroizing<Vec<u8>>, Error> {
    let length_usize = length as usize;
    if length_usize == 0 || length_usize > 64 * 1024 * 1024 {
        return Err(Error::Crypto(format!(
            "argon2id output length {length_usize} out of range (1..=67108864)"
        )));
    }
    let params = Params::new(memory_kib, iterations, parallelism, Some(length_usize))
        .map_err(|e| Error::Crypto(format!("argon2id params: {e}")))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut out = Zeroizing::new(vec![0u8; length_usize]);
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
    let key_obj = GenericArray::from_slice(key);
    Ok(Aes256Gcm::new(key_obj))
}
#[cfg(test)]
#[path = "../tests/unit/crypto.rs"]
mod tests;
