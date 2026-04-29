//! FRB adapter for `lfs_core::security::master_password`.
//!
//! Sync where the underlying op is a stat / file-delete (`is_enabled`,
//! `disable`, `reset`); async where Argon2id runs (`enable`,
//! `verify_and_derive`, `change_password`, `derive_key_from_disk`).
//! Each async call hops through `tokio::task::spawn_blocking` so the
//! 400-1500ms wall-clock KDF cost frees the FRB worker.
//!
//! `support_dir` is the platform `getApplicationSupportDirectory()`
//! path, resolved Dart-side and passed in per call. Mirrors the
//! migration FRB shape — keeps the path-resolution concern Dart's
//! responsibility (it owns the `path_provider` plugin contract) and
//! avoids leaking a global path slot into AppState.

use std::path::Path;

use lfs_core::security::master_password::{self, KdfParams};

/// FRB mirror of `lfs_core::security::master_password::KdfParams`.
/// The Dart side passes the production defaults from
/// `KdfParams.productionDefaults`; tests override with a cheaper
/// profile so unit-test cycles don't spend seconds each.
#[derive(Debug, Clone, Copy)]
pub struct DbKdfParams {
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
}

impl From<DbKdfParams> for KdfParams {
    fn from(p: DbKdfParams) -> Self {
        // FRB's u8 ↔ Dart int round-trip is fine, but emitting u32
        // across the boundary keeps the wire shape consistent with
        // `argon2id_derive` further down. Clamp the parallelism back
        // into u8 here — the validator inside KdfParams::decode
        // catches anything outside 1..=8.
        Self {
            memory_kib: p.memory_kib,
            iterations: p.iterations,
            parallelism: p.parallelism.min(u8::MAX as u32) as u8,
        }
    }
}

/// True when `credentials.kdf` exists under `support_dir` — the
/// master-password tier is enabled.
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_is_enabled(support_dir: String) -> bool {
    master_password::is_enabled(Path::new(&support_dir))
}

/// Encode the algo-id + Argon2id params block to the 10-byte
/// big-endian shape `credentials.kdf` stores after the magic +
/// version header. Lets the Dart `KdfParams.encode` route
/// through the canonical Rust serialiser instead of carrying its
/// own `ByteData.setUint32` block.
#[flutter_rust_bridge::frb(sync)]
pub fn kdf_params_encode(memory_kib: u32, iterations: u32, parallelism: u32) -> Vec<u8> {
    let p = KdfParams::from(DbKdfParams {
        memory_kib,
        iterations,
        parallelism,
    });
    p.encode().to_vec()
}

/// Decode the 10-byte algo-id + Argon2id params block. Returns
/// `Err(message)` for unknown algo ids, truncated buffers, and
/// values outside the sanity ceilings (see `KdfParams::decode`).
/// Wire-shape parity with the Dart `KdfParams.decode` was the
/// deliberate goal — both halves now read the same canonical
/// validator.
#[flutter_rust_bridge::frb(sync)]
pub fn kdf_params_decode(bytes: Vec<u8>) -> Result<DbKdfParams, String> {
    let p = KdfParams::decode(&bytes)?;
    Ok(DbKdfParams {
        memory_kib: p.memory_kib,
        iterations: p.iterations,
        parallelism: u32::from(p.parallelism),
    })
}

/// Enable master-password protection: fresh salt + Argon2id derive +
/// atomic write of the KDF record + verifier files. Returns the
/// derived key — the caller re-encrypts the SQLCipher store with it.
pub async fn master_password_enable(
    support_dir: String,
    password: String,
    params: DbKdfParams,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::enable(Path::new(&support_dir), &password, &params.into())
    })
    .await
    .map_err(|e| format!("master_password_enable task: {e}"))?
}

/// Verify the old password, then re-key under the new one. Returns
/// the new derived key. `Err("Current password is incorrect")` on
/// wrong old password — the Dart `MasterPasswordException` wrapper
/// surfaces it to the change-password dialog.
pub async fn master_password_change(
    support_dir: String,
    old_password: String,
    new_password: String,
    params: DbKdfParams,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::change_password(
            Path::new(&support_dir),
            &old_password,
            &new_password,
            &params.into(),
        )
    })
    .await
    .map_err(|e| format!("master_password_change task: {e}"))?
}

/// Drop the KDF + verifier files. Caller is responsible for
/// re-encrypting stores with a fresh random key + writing
/// `credentials.key`.
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_disable(support_dir: String) -> Result<(), String> {
    master_password::disable(Path::new(&support_dir))
}

/// Drop everything: KDF + verifier + key file. Destructive — only
/// the forgotten-password reset flow uses this once the user has
/// confirmed the data loss.
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_reset(support_dir: String) -> Result<(), String> {
    master_password::reset(Path::new(&support_dir))
}

/// Run the KDF against the on-disk salt + params and return the
/// derived key without checking the verifier. Used when the caller
/// already trusts the password and just needs the key.
pub async fn master_password_derive_key(
    support_dir: String,
    password: String,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::derive_key_from_disk(Path::new(&support_dir), &password)
    })
    .await
    .map_err(|e| format!("master_password_derive_key task: {e}"))?
}

/// Single-KDF unlock: derive the key, decrypt-and-match the verifier,
/// return `Some(key)` on success or `None` on a wrong password.
/// `Err` is reserved for "the tier is not enabled" / "files corrupt".
pub async fn master_password_verify_and_derive(
    support_dir: String,
    password: String,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::verify_and_derive(Path::new(&support_dir), &password)
    })
    .await
    .map_err(|e| format!("master_password_verify task: {e}"))?
}
