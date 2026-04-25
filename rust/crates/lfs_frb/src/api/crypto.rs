//! FRB adapter for `lfs_core::crypto`.
//!
//! HKDF-SHA-256 + Ed25519 verify exposed to Dart so the app can drop
//! pointycastle's `HKDFKeyDerivator` and pinenacl's `VerifyKey`.
//! Both calls are short and CPU-bound; we still spawn_blocking them
//! so the FRB worker thread doesn't get stuck on a big update-feed
//! payload.

/// HKDF-SHA-256: derive `length` bytes from `ikm` with the given
/// `salt` + `info` context tag. `length` must be in 1..=8160.
pub async fn crypto_hkdf_sha256(
    ikm: Vec<u8>,
    salt: Vec<u8>,
    info: Vec<u8>,
    length: u32,
) -> Result<Vec<u8>, String> {
    let length_usize = length as usize;
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::hkdf_sha256(&ikm, &salt, &info, length_usize).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hkdf task: {e}"))?
}

/// Verify an Ed25519 signature over `message` against `public_key`.
/// Returns `false` on any malformed input — never throws — so the
/// caller's "no signature match → fail closed" branch is the only
/// negative path it has to handle.
pub async fn crypto_ed25519_verify(
    public_key: Vec<u8>,
    message: Vec<u8>,
    signature: Vec<u8>,
) -> bool {
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::ed25519_verify(&public_key, &message, &signature)
    })
    .await
    .unwrap_or(false)
}

/// AES-256-GCM encrypt with a fresh random nonce. Returns the wire
/// shape `nonce || ciphertext || tag` — the same layout the legacy
/// pointycastle-backed `AesGcm.encrypt` produced, so existing on-disk
/// envelopes round-trip without a format bump.
pub async fn crypto_aes_gcm_encrypt(key: Vec<u8>, plaintext: Vec<u8>) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::aes_gcm_encrypt(&key, &plaintext).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("aes-gcm encrypt task: {e}"))?
}

/// AES-256-GCM decrypt for inputs in `nonce || ciphertext || tag`
/// shape. GCM tag is verified — wrong key / corrupted bytes / tampered
/// tag all return a typed error.
pub async fn crypto_aes_gcm_decrypt(key: Vec<u8>, data: Vec<u8>) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::aes_gcm_decrypt(&key, &data).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("aes-gcm decrypt task: {e}"))?
}

/// Caller-managed nonce variant. `nonce` must be 12 bytes; output is
/// `ciphertext || tag` (no nonce prefix). Used by per-frame envelopes
/// that frame the nonce themselves (recorder, .lfs archive).
pub async fn crypto_aes_gcm_encrypt_raw(
    key: Vec<u8>,
    nonce: Vec<u8>,
    plaintext: Vec<u8>,
    aad: Vec<u8>,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::aes_gcm_encrypt_raw(&key, &nonce, &plaintext, &aad)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("aes-gcm encrypt-raw task: {e}"))?
}

/// Caller-managed nonce decrypt. Input is `ciphertext || tag`.
pub async fn crypto_aes_gcm_decrypt_raw(
    key: Vec<u8>,
    nonce: Vec<u8>,
    ciphertext: Vec<u8>,
    aad: Vec<u8>,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::aes_gcm_decrypt_raw(&key, &nonce, &ciphertext, &aad)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("aes-gcm decrypt-raw task: {e}"))?
}

/// Argon2id key derivation. CPU + memory-heavy — runs on the
/// blocking pool so the FRB worker thread isn't pinned for the
/// 1–3 seconds production params take. Caller scrubs the returned
/// bytes after use; Rust drops them on its side already.
pub async fn crypto_argon2id_derive(
    password: Vec<u8>,
    salt: Vec<u8>,
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
    length: u32,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::crypto::argon2id_derive(
            &password,
            &salt,
            memory_kib,
            iterations,
            parallelism,
            length,
        )
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("argon2id task: {e}"))?
}
