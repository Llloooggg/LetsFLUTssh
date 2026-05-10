//! FRB adapter for `lfs_core::app`.
//!
//! Surfaces the process-singleton AppState plus the secret-store CRUD
//! the connection layer uses to keep credentials Rust-side, plus the
//! `db_*` lifecycle (open / rekey / smoke-test) for the rusqlite
//! handle.
//!
//! Init contract: Dart calls `app_init` once during startup
//! (`main.dart` after `RustLib.init()`), then any other secrets/* or
//! db_* commands. Repeat calls are no-ops.

/// Initialise the process-singleton AppState. Idempotent.
pub fn app_init() {
    lfs_core::app::init();
}

/// Store `bytes` under `id` in the SecretStore. Replaces any prior
/// entry at the same id (the previous Zeroizing buffer scrubs on
/// drop). Caller is responsible for picking namespaced ids — see
/// `lfs_core::secrets` for the convention.
pub fn secrets_put(id: String, bytes: Vec<u8>) {
    lfs_core::app::instance().secrets.put(&id, &bytes);
}

/// Whether [id] has a stored secret. Used by Dart UI to render
/// "password set"/"key configured" badges without ever touching the
/// plaintext. Sync — single hashmap probe.
#[flutter_rust_bridge::frb(sync)]
pub fn secrets_has(id: String) -> bool {
    lfs_core::app::instance().secrets.has(&id)
}

/// Drop the secret under [id]. Idempotent. Sync — single hashmap
/// remove.
#[flutter_rust_bridge::frb(sync)]
pub fn secrets_drop(id: String) {
    lfs_core::app::instance().secrets.drop_id(&id);
}

/// Atomic read-and-remove. Returns the bytes that were stored
/// under [id] AND removes the entry from the store inside the
/// same critical section so concurrent callers see either the
/// same bytes (their lock landed first) or empty (ours did).
///
/// The Dart bus-driven unlock listener reads the staged tier
/// key here once on `TierStateChanged.unlocked`, hands the
/// bytes to `dbInit` (which lands them in rusqlite/SQLCipher's
/// page-cipher key on the Rust side), and the SecretStore entry
/// is gone after a single FRB byte crossing.
///
/// Returns `None` when the id is missing, `Some(bytes)` when the
/// secret is staged. **Don't collapse missing-id and empty-bytes
/// into a single `Vec::new()` return** — an empty `Vec` is a
/// legal staged secret (zero-byte keys / passwords from a
/// sentinel tier-reset path), so a caller can't distinguish
/// "no secret here" from "this secret is intentionally empty"
/// off `Vec::isEmpty` alone.
#[flutter_rust_bridge::frb(sync)]
pub fn secrets_take(id: String) -> Option<Vec<u8>> {
    lfs_core::app::instance()
        .secrets
        .take(&id)
        .map(|buf| buf.to_vec())
}

/// Read the bytes stored under [`id`] WITHOUT removing the entry.
/// Used by hardware-vault store flows that still need the raw bytes
/// for a TPM CLI shell-out / Windows MethodChannel call but want
/// the SecretStore entry to survive so the follow-up
/// `secrets_take` for the rusqlite/SQLCipher rekey
/// (`db_rekey_from_secret`) still has something to consume.
/// Returns `None` when the id is missing.
#[flutter_rust_bridge::frb(sync)]
pub fn secrets_get(id: String) -> Option<Vec<u8>> {
    lfs_core::app::instance()
        .secrets
        .get(&id)
        .map(|buf| buf.to_vec())
}

/// Drop every secret in [ids] in a single FRB hop. Used by the
/// connect path's transient-secret cleanup so an N-id evict
/// doesn't pay N FRB round-trips. Idempotent on a missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn secrets_drop_many(ids: Vec<String>) {
    let store = &lfs_core::app::instance().secrets;
    for id in ids {
        store.drop_id(&id);
    }
}

/// Drop every cached secret. The caller — typically the auto-lock
/// path or the explicit "wipe data" flow — uses this to evict the
/// cache wholesale on lock / sign-out.
pub fn secrets_clear() {
    lfs_core::app::instance().secrets.clear();
}

/// Open the app sqlite database at `path` with the given SQLCipher
/// master key. Runs on tokio's blocking pool — rusqlite is blocking
/// and we don't want to pin the FRB worker. Idempotent on the same
/// (path, key) pair; replaces any previously-initialised handle.
///
/// `key` is empty for unencrypted databases (the plaintext-tier
/// path). Hex-encoding into `PRAGMA key = "x'...'"` happens
/// inside `lfs_core::db::Db::open`.
pub async fn db_init(path: String, key: Vec<u8>) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::app::instance()
            .db_init(std::path::Path::new(&path), &key)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("db_init task: {e}"))?
}

/// SecretRef variant of [`db_init`]. Pulls the SQLCipher key from
/// the process-singleton `SecretStore` under [`secret_id`] and hands
/// it to `Db::open` without the bytes ever crossing the FRB
/// boundary. On success the entry is renamed to
/// [`lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`] so every downstream
/// consumer (recorder HKDF, biometric vault store, mid-session
/// reopen) reads from the canonical slot — there is exactly one
/// place the running key lives.
///
/// `secret_id` empty string OR a missing-id case both fall through
/// to the unencrypted (plaintext-tier) path so test fixtures that
/// "open with no key" stay symmetric with [`db_init`]'s
/// `Vec::new()` behaviour. In the plaintext branch the active slot
/// is dropped (auto-lock semantics).
pub async fn db_init_from_secret(path: String, secret_id: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        if secret_id.is_empty() {
            app.secrets
                .drop_id(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID);
            return app
                .db_init(std::path::Path::new(&path), &[])
                .map_err(|e| crate::api::frb_err::from_core(&e));
        }
        let key = app
            .secrets
            .get(&secret_id)
            .ok_or_else(|| format!("secret not found: {secret_id}"))?;
        app.db_init(std::path::Path::new(&path), &key)
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        // Promote source → active. `rename` is atomic; a no-op when
        // source already matches the active slot id.
        app.secrets
            .rename(&secret_id, lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID);
        Ok(())
    })
    .await
    .map_err(|e| format!("db_init_from_secret task: {e}"))?
}

/// Drop the running Rust DB handle. Idempotent. Used by the auto-
/// lock path to wipe SQLCipher's C-layer page-cipher state when the
/// user steps away. Unlock re-calls `db_init` to bring the handle
/// back under the freshly re-derived master key.
pub fn db_close() {
    lfs_core::app::instance().db_close();
}

/// Re-encrypt the running Rust DB with `new_key`. Used by the
/// security-tier switcher so the encrypted `letsflutssh.db` rekeys
/// atomically on tier transitions. Empty `new_key` is rejected —
/// see `Db::rekey`.
pub async fn db_rekey(new_key: Vec<u8>) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let db = lfs_core::app::instance()
            .db()
            .ok_or_else(|| "db not initialized".to_string())?;
        db.rekey(&new_key)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("db_rekey task: {e}"))?
}

/// SecretRef variant of [`db_rekey`]. Reads the new key from
/// [`lfs_core::secrets::SecretStore`] under [`secret_id`]; on a
/// successful `PRAGMA rekey` the entry is renamed to
/// [`lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`] so the running key
/// lives in the canonical slot. Same atomicity semantics as
/// `db_rekey`: SQLCipher either re-encrypts every page under the
/// new key or leaves the DB on the old key. Bytes never cross the
/// FRB boundary.
pub async fn db_rekey_from_secret(secret_id: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let new_key = app
            .secrets
            .get(&secret_id)
            .ok_or_else(|| format!("secret not found: {secret_id}"))?;
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        db.rekey(&new_key)
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        app.secrets
            .rename(&secret_id, lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID);
        Ok(())
    })
    .await
    .map_err(|e| format!("db_rekey_from_secret task: {e}"))?
}

/// Smoke-test query — returns the count of rows in `sqlite_master`.
/// Used by Dart at startup to assert the DB is reachable before
/// the rest of the app uses it.
pub async fn db_schema_object_count() -> Result<i64, String> {
    tokio::task::spawn_blocking(move || {
        let db = lfs_core::app::instance()
            .db()
            .ok_or_else(|| "db not initialized".to_string())?;
        db.schema_object_count()
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("db_schema_object_count task: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    // Tests share the singleton across the binary — use uniquely
    // namespaced ids ("api-app-test-…") so cross-test ordering
    // doesn't leak. `app::init()` is idempotent + cargo-test safe
    // (already exercised by `lfs_core::app::tests::init_is_idempotent`).

    #[test]
    fn app_init_is_idempotent_through_frb_shim() {
        // Two consecutive calls must not panic — pin the contract
        // the Dart `main.dart` bootstrap relies on.
        app_init();
        app_init();
    }

    #[test]
    fn secrets_put_then_get_round_trips_bytes() {
        app_init();
        let id = "api-app-test-put-get".to_string();
        secrets_put(id.clone(), b"hunter2".to_vec());
        let got = secrets_get(id.clone()).expect("get");
        assert_eq!(got, b"hunter2");
        secrets_drop(id);
    }

    #[test]
    fn secrets_has_returns_true_after_put_and_false_after_drop() {
        app_init();
        let id = "api-app-test-has".to_string();
        secrets_put(id.clone(), b"x".to_vec());
        assert!(secrets_has(id.clone()));
        secrets_drop(id.clone());
        assert!(!secrets_has(id));
    }

    #[test]
    fn secrets_take_removes_entry_and_returns_bytes() {
        app_init();
        let id = "api-app-test-take".to_string();
        secrets_put(id.clone(), b"once".to_vec());
        let taken = secrets_take(id.clone()).expect("take");
        assert_eq!(taken, b"once");
        // After take the entry is gone — second take returns None.
        assert!(secrets_take(id).is_none());
    }

    #[test]
    fn secrets_take_returns_none_for_missing_id() {
        app_init();
        // Pin the post-audit contract — None for missing, not an
        // empty Vec.
        assert!(secrets_take("api-app-test-ghost-id".into()).is_none());
    }

    #[test]
    fn secrets_drop_many_clears_each_id_in_one_hop() {
        app_init();
        for n in 0..3 {
            secrets_put(format!("api-app-test-many-{n}"), b"x".to_vec());
        }
        secrets_drop_many(vec![
            "api-app-test-many-0".into(),
            "api-app-test-many-1".into(),
            "api-app-test-many-2".into(),
        ]);
        for n in 0..3 {
            assert!(!secrets_has(format!("api-app-test-many-{n}")));
        }
    }

    #[test]
    fn secrets_drop_idempotent_on_unknown_id() {
        app_init();
        // No-op on missing — connect path's transient cleanup runs
        // unconditionally.
        secrets_drop("api-app-test-already-dropped".into());
    }
}
