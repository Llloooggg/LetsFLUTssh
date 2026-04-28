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

/// HMAC-SHA-256: 32-byte MAC tag over `message` keyed by `key`.
///
/// Sync because the per-call work is a single SHA-256 digest pass —
/// well under a millisecond even on the slowest mobile target. The
/// security-tier secret gates (`KeychainPasswordGate`,
/// `HardwareTierVault`, `PersistedRateLimiter`) call this from
/// hot-ish paths (every unlock attempt, every persisted-state
/// load) so the async hop overhead would dwarf the work.
#[flutter_rust_bridge::frb(sync)]
pub fn crypto_hmac_sha256(key: Vec<u8>, message: Vec<u8>) -> Vec<u8> {
    lfs_core::crypto::hmac_sha256(&key, &message)
}

/// SHA-256 digest over `bytes`. Returns the 32-byte hash. Sync —
/// per-call work is a single SHA-256 pass, well under a millisecond
/// even on the slowest mobile target. Used by the per-key
/// fingerprint helpers, the known-hosts fingerprint formatter,
/// fprintd enrolment-list digest, and the update-feed asset content
/// hash; consolidating here drops `package:crypto` as a per-site dep.
#[flutter_rust_bridge::frb(sync)]
pub fn crypto_sha256(bytes: Vec<u8>) -> Vec<u8> {
    lfs_core::crypto::sha256(&bytes)
}

/// Lower-case hex of [`crypto_sha256`]. Convenience for callers
/// that store the digest as a hex string. Same hot-path argument
/// as `crypto_sha256` — sync, no async hop.
#[flutter_rust_bridge::frb(sync)]
pub fn crypto_sha256_hex(bytes: Vec<u8>) -> String {
    lfs_core::crypto::sha256_hex(&bytes)
}

/// Constant-time equality over two byte slices. `false` immediately
/// when lengths differ (lengths are not secret); the per-byte
/// comparison runs to completion regardless of where the first
/// differing byte sits, so a timing-side-channel attacker cannot
/// binary-search the secret one byte at a time.
///
/// Sync — same hot-path argument as `crypto_hmac_sha256`. Backed by
/// `subtle::ConstantTimeEq` Rust-side so the implementation lives
/// one place across the per-tier secret gates.
#[flutter_rust_bridge::frb(sync)]
pub fn crypto_constant_time_eq(a: Vec<u8>, b: Vec<u8>) -> bool {
    lfs_core::crypto::constant_time_eq(&a, &b)
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

/// Generate a fresh random AES-256 key (32 bytes from `OsRng`).
/// Synchronous — the call is a single OS getrandom round-trip.
#[flutter_rust_bridge::frb(sync)]
pub fn crypto_aes_gcm_random_key() -> Vec<u8> {
    lfs_core::crypto::aes_gcm_random_key()
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
