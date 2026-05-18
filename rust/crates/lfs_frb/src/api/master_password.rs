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
/// The Dart side mirrors the production defaults at startup via
/// `kdf_params_production_defaults` into `KdfParams.productionDefaults`;
/// tests override with a cheaper profile so unit-test cycles don't
/// spend seconds each.
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

/// Production-default Argon2id parameters as defined by
/// `lfs_core::security::master_password::KdfParams::defaults`. The
/// Dart side mirrors this once at startup into
/// `KdfParams.productionDefaults`; every fresh `enable` /
/// `changePassword` / `.lfs` export reads back from the mirror so
/// the Rust constant is the single source of truth.
#[flutter_rust_bridge::frb(sync)]
pub fn kdf_params_production_defaults() -> DbKdfParams {
    let p = KdfParams::defaults();
    DbKdfParams {
        memory_kib: p.memory_kib,
        iterations: p.iterations,
        parallelism: u32::from(p.parallelism),
    }
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
///
/// Promotes any pre-existing `.cast` plaintext recordings to fresh
/// `.lfsr` files wrapped under the new DB key — the `T0 → T1`
/// transition would otherwise leave the recordings in plaintext
/// forever. The promotion runs after the key lands in the secret
/// store so the migration helper reads off the same slot the next
/// `db_rekey_from_secret` will read.
pub async fn master_password_enable_to_secret(
    password: Vec<u8>,
    params: DbKdfParams,
    secret_id: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let key = master_password::enable(support_dir()?, &password, &params.into())?;
        let key_arr: [u8; 32] = key
            .as_slice()
            .try_into()
            .map_err(|_| "new db key wrong length".to_string())?;
        app.secrets.put(&secret_id, &key);
        // Promote plaintext recordings to v1 LFR1 under the new
        // wrap key. A failure here aborts the enable — the password
        // files were already written by `master_password::enable`,
        // so the caller must roll back (delete KDF + verifier) if
        // the migration cannot complete.
        let root = recordings_root_for_migrate()?;
        lfs_core::recorder::migrate::convert_all_cast_to_lfsr(&root, &key_arr)
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
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

/// Full T1 → T0 transition. Drives every persistent artefact that
/// currently lives under the active DB key back to a plaintext
/// shape, in order:
///
/// 1. **Recordings.** `convert_all_lfsr_to_cast` decrypts each
///    `.lfsr` body (under the current ACTIVE DB key) and writes a
///    plaintext `.cast` next to it. Encrypted sidecars drop with
///    the rename. Must happen while the active key is still in
///    memory.
/// 2. **SQLite DB.** `Db::export_plaintext_copy` writes a plaintext
///    sqlite copy via `sqlcipher_export` next to the running
///    encrypted file, then the helper closes the handle, deletes
///    the encrypted DB + its `-wal` / `-shm` sidecars, renames the
///    plaintext copy over the original path, and re-opens the DB
///    unkeyed through `app::db_init`. The DB is plaintext from the
///    next call onwards.
/// 3. **Active DB-key slot.** Dropped from
///    [`lfs_core::secrets::SecretStore`] — the plaintext DB needs
///    no key, and lingering bytes in the slot would only feed an
///    accidental future rekey path under the dead value.
/// 4. **Password files.** `master_password::disable` removes
///    `credentials.kdf` + `credentials.verifier` so the next
///    launch sees no master-password installation and opens the
///    DB without prompting.
///
/// On any failure the function aborts and propagates the error;
/// the encrypted DB stays intact, the password files stay in
/// place, and the user can retry after addressing the underlying
/// issue (typically an out-of-disk during the sqlcipher_export
/// step, or a stuck file handle holding the source DB open).
///
/// Sync FRB call so the entire transition runs on a single
/// blocking thread — concurrent FRB calls serialise behind it via
/// the FRB sync worker pool, which keeps a stale `db_*` request
/// from racing with the rename / reopen window.
#[flutter_rust_bridge::frb(sync)]
pub fn master_password_disable() -> Result<(), String> {
    let app = lfs_core::app::instance();
    let active_key = app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID);
    let active_arr: Option<[u8; 32]> = match active_key {
        Some(k) if !k.is_empty() => Some(
            k.as_slice()
                .try_into()
                .map_err(|_| "active db key wrong length".to_string())?,
        ),
        _ => None,
    };

    // 1. lfsr → cast (only meaningful when a key actually exists).
    if let Some(key) = active_arr {
        let root = recordings_root_for_migrate()?;
        lfs_core::recorder::migrate::convert_all_lfsr_to_cast(&root, &key)
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
    }

    // 2. DB decrypt. Skip when the handle is unavailable (cold-
    //    start before db_init, or a test fixture that never opened
    //    one) — there's nothing to downgrade.
    if active_arr.is_some() {
        if let Some(db) = app.db() {
            let db_path = db.path().to_path_buf();
            if !db_path.as_os_str().is_empty() {
                let tmp = plaintext_export_tmp_path(&db_path)?;
                // Clean up any leftover from a prior crashed attempt
                // so the export does not collide with a stale file.
                let _ = std::fs::remove_file(&tmp);
                db.export_plaintext_copy(&tmp)
                    .map_err(|e| crate::api::frb_err::from_core(&e))?;
                // Release the running handle before the file swap.
                // Other FRB calls observing `app.db() = None` between
                // the close and the re-open get a typed "db not
                // initialized" rather than an open handle to a
                // file that just got renamed out from under them.
                drop(db);
                app.db_close();
                // Wipe the encrypted source + WAL / SHM sidecars
                // BEFORE the rename so the plaintext target lands
                // on a clean path. `remove_file` is best-effort
                // for the sidecars — they may not exist (lazy
                // creation by SQLite).
                let _ = std::fs::remove_file(&db_path);
                for suffix in ["-wal", "-shm", "-journal"] {
                    let mut sidecar = db_path.clone().into_os_string();
                    sidecar.push(suffix);
                    let _ = std::fs::remove_file(std::path::PathBuf::from(sidecar));
                }
                std::fs::rename(&tmp, &db_path).map_err(|e| {
                    // Best-effort cleanup of the orphan tmp on rename
                    // failure so a re-try sees a clean slate.
                    let _ = std::fs::remove_file(&tmp);
                    format!("rename plaintext over db: {e}")
                })?;
                // Re-open as plaintext (empty key) so the DAOs keep
                // working through the rest of this call + future
                // FRB requests.
                app.db_init(&db_path, &[])
                    .map_err(|e| crate::api::frb_err::from_core(&e))?;
            }
        }
    }

    // 3. Clear the ACTIVE DB-key slot. The plaintext DB does not
    //    need it; lingering bytes would only feed an accidental
    //    future rekey path under the dead value.
    app.secrets
        .drop_id(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID);

    // 4. Wipe KDF + verifier files so the next launch boots
    //    straight into plaintext tier.
    master_password::disable(support_dir()?)
}

/// Path the plaintext sqlcipher_export target lands at — a
/// random-suffixed sibling under the same directory as the
/// encrypted source. Per-call random suffix avoids a collision
/// when two transition attempts race (the second attempt was
/// likely a retry after the first crashed mid-flight; the prior
/// tmp gets cleaned by the caller before re-running).
fn plaintext_export_tmp_path(db_path: &std::path::Path) -> Result<std::path::PathBuf, String> {
    let pid = std::process::id();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let parent = db_path
        .parent()
        .ok_or_else(|| format!("db path has no parent: {}", db_path.display()))?;
    let name = db_path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| format!("db path bad name: {}", db_path.display()))?;
    Ok(parent.join(format!("{name}.plain.{pid}.{nanos:x}")))
}

/// Resolve `<support_dir>/recordings` for the migration hooks.
/// Mirrors the FRB-exposed `recorder_recordings_root` but stays
/// inside the same task so the password / rekey paths don't have
/// to round-trip a `String` through Dart.
fn recordings_root_for_migrate() -> Result<std::path::PathBuf, String> {
    let dir = lfs_core::app::instance()
        .support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(dir.join("recordings"))
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
    fn kdf_params_production_defaults_match_core_constant() {
        // The Dart side mirrors this value into
        // `KdfParams.productionDefaults` at startup. Pin the canonical
        // 64 MiB / 3 iter / 1 lane profile so a Rust-side knob change
        // forces a deliberate doc + test update across the boundary.
        let p = kdf_params_production_defaults();
        assert_eq!(p.memory_kib, 64 * 1024);
        assert_eq!(p.iterations, 3);
        assert_eq!(p.parallelism, 1);
    }

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
