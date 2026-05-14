//! FRB adapter for `lfs_core::security::master_password`.
//!
//! Sync where the underlying op is a stat / file-delete (`is_enabled`,
//! `disable`, `reset`); async where Argon2id runs (`enable`,
//! `verify_and_derive`, `change_password`). Each async call hops
//! through `tokio::task::spawn_blocking` so the 400-1500ms wall-clock
//! KDF cost frees the FRB worker.
//!
//! `support_dir` is the platform `getApplicationSupportDirectory()`
//! path. Dart resolves it once at startup (via the `path_provider`
//! plugin) and pins it Rust-side through `config_store_init`; every
//! subsequent FRB op in this module reads the pin via
//! `lfs_core::app::instance().support_dir()` (which delegates to
//! the `master_password::try_pinned_support_dir` singleton). Path
//! resolution stays Dart's responsibility (the plugin contract is
//! platform-bound), but the threading concern shrinks to a single
//! pin call inside `config_store_init`.

use lfs_core::security::master_password::{self, KdfParams};

/// FRB-safe re-export of `master_password::try_pinned_support_dir`.
/// Returns a typed `Result` so a misordered FRB call (the pin set
/// before any master_password op runs) surfaces as a `String`
/// across the boundary instead of panicking the FRB worker.
fn support_dir() -> Result<&'static std::path::Path, String> {
    master_password::try_pinned_support_dir().map_err(|e| crate::api::frb_err::from_core(&e))
}

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

/// True when `credentials.kdf` exists under the pinned support
/// dir — the master-password tier is enabled. `Err` only when the
/// pin has not been set (FRB-callable misorder), not when the file
/// is absent (that is the documented `Ok(false)`).
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_is_enabled() -> Result<bool, String> {
    Ok(master_password::is_enabled(support_dir()?))
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
    password: Vec<u8>,
    params: DbKdfParams,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::enable(support_dir()?, &password, &params.into()).map(|z| z.to_vec())
    })
    .await
    .map_err(|e| format!("master_password_enable task: {e}"))?
}

/// SecretRef variant of [`master_password_enable`]. Stages the
/// derived key directly into [`lfs_core::secrets::SecretStore`]
/// under [`secret_id`] instead of returning the bytes over FRB.
/// Caller routes the same id through `db_rekey_from_secret` /
/// `db_init_from_secret` so the AES bytes never touch the Dart
/// heap.
///
/// Idempotent on `secret_id` collision: replaces any prior value at
/// the same id (the previous `Zeroizing` buffer scrubs on drop).
pub async fn master_password_enable_to_secret(
    password: Vec<u8>,
    params: DbKdfParams,
    secret_id: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let key = master_password::enable(support_dir()?, &password, &params.into())?;
        lfs_core::app::instance().secrets.put(&secret_id, &key);
        Ok::<_, String>(())
    })
    .await
    .map_err(|e| format!("master_password_enable_to_secret task: {e}"))?
}

/// Verify the old password, then re-key under the new one. Returns
/// the new derived key. `Err("Current password is incorrect")` on
/// wrong old password — the Dart `MasterPasswordException` wrapper
/// surfaces it to the change-password dialog.
pub async fn master_password_change(
    old_password: Vec<u8>,
    new_password: Vec<u8>,
    params: DbKdfParams,
) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::change_password(
            support_dir()?,
            &old_password,
            &new_password,
            &params.into(),
        )
        .map(|z| z.to_vec())
    })
    .await
    .map_err(|e| format!("master_password_change task: {e}"))?
}

/// SecretRef variant of [`master_password_change`]. Stages the
/// freshly-derived key directly into
/// [`lfs_core::secrets::SecretStore`] under [`secret_id`] instead
/// of returning the bytes over FRB. Caller routes the same id
/// through `db_rekey_from_secret` so the AES bytes never touch the
/// Dart heap — finishes the master-password SecretRef family
/// alongside `master_password_enable_to_secret` and
/// `master_password_verify_and_derive_to_secret`.
///
/// Idempotent on `secret_id` collision: replaces any prior value
/// at the same id (the previous `Zeroizing` buffer scrubs on drop).
/// `Err("Current password is incorrect")` on wrong old password —
/// the SecretStore stays untouched.
pub async fn master_password_change_to_secret(
    old_password: Vec<u8>,
    new_password: Vec<u8>,
    params: DbKdfParams,
    secret_id: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let key = master_password::change_password(
            support_dir()?,
            &old_password,
            &new_password,
            &params.into(),
        )?;
        lfs_core::app::instance().secrets.put(&secret_id, &key);
        Ok::<_, String>(())
    })
    .await
    .map_err(|e| format!("master_password_change_to_secret task: {e}"))?
}

/// Drop the KDF + verifier files. Caller is responsible for
/// re-encrypting stores with a fresh random key + writing
/// `credentials.key`.
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_disable() -> Result<(), String> {
    master_password::disable(support_dir()?)
}

/// Drop everything: KDF + verifier + key file. Destructive — only
/// the forgotten-password reset flow uses this once the user has
/// confirmed the data loss.
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_reset() -> Result<(), String> {
    master_password::reset(support_dir()?)
}

/// Single-KDF unlock: derive the key, decrypt-and-match the verifier,
/// return `Some(key)` on success or `None` on a wrong password.
/// `Err` is reserved for "the tier is not enabled" / "files corrupt".
pub async fn master_password_verify_and_derive(
    password: Vec<u8>,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        master_password::verify_and_derive(support_dir()?, &password)
            .map(|opt| opt.map(|z| z.to_vec()))
    })
    .await
    .map_err(|e| format!("master_password_verify task: {e}"))?
}

/// SecretRef variant of [`master_password_verify_and_derive`].
/// Stages the derived key directly into
/// [`lfs_core::secrets::SecretStore`] under `secret_id` (no FRB
/// byte-crossing). Returns:
/// * `Ok(true)` when the password was correct and bytes landed
///   under `secret_id`.
/// * `Ok(false)` on wrong password (no SecretStore mutation).
/// * `Err(_)` for "tier not enabled" / "files corrupt".
pub async fn master_password_verify_and_derive_to_secret(
    password: Vec<u8>,
    secret_id: String,
) -> Result<bool, String> {
    tokio::task::spawn_blocking(move || {
        match master_password::verify_and_derive(support_dir()?, &password)? {
            Some(key) => {
                lfs_core::app::instance().secrets.put(&secret_id, &key);
                Ok::<_, String>(true)
            }
            None => Ok(false),
        }
    })
    .await
    .map_err(|e| format!("master_password_verify_and_derive_to_secret task: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    // The enable / disable / verify / change endpoints route through
    // `support_dir()` (pinned process-singleton) + `Argon2id` (slow);
    // the Dart `master_password_test.dart` integration suite exercises
    // them under a tempdir + cheap KdfParams. The standalone tests
    // below pin the wire-shape primitives that cross the FRB boundary
    // on every call regardless of the pinned support_dir state.

    #[test]
    fn kdf_params_encode_decode_round_trips_production_defaults() {
        // 64 MiB / 3 iter / 1 lane is the documented production
        // baseline (`KdfParams::productionDefaults`). Pin the
        // round-trip so a future codec rewrite can't silently
        // corrupt installed `credentials.kdf` files.
        let bytes = kdf_params_encode(64 * 1024, 3, 1);
        let back = kdf_params_decode(bytes).expect("round trip");
        assert_eq!(back.memory_kib, 64 * 1024);
        assert_eq!(back.iterations, 3);
        assert_eq!(back.parallelism, 1);
    }

    #[test]
    fn kdf_params_decode_rejects_truncated_buffer() {
        // The encoded shape is 10 bytes (algo-id + three u32 BE
        // values). A short slice must surface an Err rather than
        // panic — the on-disk file might have been corrupted /
        // truncated mid-write.
        let res = kdf_params_decode(vec![0x01, 0x00, 0x00]);
        assert!(res.is_err(), "truncated buffer must surface as Err");
    }

    #[test]
    fn kdf_params_decode_rejects_empty_input() {
        assert!(kdf_params_decode(Vec::new()).is_err());
    }

    #[test]
    fn kdf_params_encode_produces_stable_byte_count() {
        // Pin the on-disk envelope size — if a future algo bump
        // grows the block, callers staging the file format need to
        // know.
        let bytes = kdf_params_encode(32 * 1024, 2, 1);
        assert_eq!(bytes.len(), 10, "10-byte envelope: 1 algo + 3 u32 BE");
    }

    #[test]
    fn db_kdf_params_clamps_parallelism_to_u8_max() {
        // `parallelism` crosses FRB as u32 but `KdfParams::parallelism`
        // is u8. The From impl clamps to 255 then KdfParams::decode
        // rejects anything outside 1..=8 — verify the clamp doesn't
        // panic on overflow.
        let p: KdfParams = DbKdfParams {
            memory_kib: 32 * 1024,
            iterations: 2,
            parallelism: 999, // way past u8::MAX
        }
        .into();
        assert_eq!(p.parallelism, u8::MAX, "clamp must saturate at u8::MAX");
    }
}
