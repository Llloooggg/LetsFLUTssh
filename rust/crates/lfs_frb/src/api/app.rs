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
/// plaintext.
pub fn secrets_has(id: String) -> bool {
    lfs_core::app::instance().secrets.has(&id)
}

/// Drop the secret under [id]. Idempotent.
pub fn secrets_drop(id: String) {
    lfs_core::app::instance().secrets.drop_id(&id);
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
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db_init task: {e}"))?
}

/// Drop the running Rust DB handle. Idempotent. Used by the auto-
/// lock path to wipe SQLCipher's C-layer page-cipher state when the
/// user steps away. Unlock re-calls `db_init` to bring the handle
/// back under the freshly re-derived master key.
pub fn db_close() {
    lfs_core::app::instance().db_close();
}

/// Re-encrypt the running Rust DB with `new_key`. Used by the
/// security-tier switcher so the encrypted `lfs_core.db` rekeys
/// atomically on tier transitions. Empty `new_key` is rejected —
/// see `Db::rekey`.
pub async fn db_rekey(new_key: Vec<u8>) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let db = lfs_core::app::instance()
            .db()
            .ok_or_else(|| "db not initialized".to_string())?;
        db.rekey(&new_key).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db_rekey task: {e}"))?
}

/// Smoke-test query — returns the count of rows in `sqlite_master`.
/// Used by Dart at startup to assert the DB is reachable before
/// the rest of the app uses it.
pub async fn db_schema_object_count() -> Result<i64, String> {
    tokio::task::spawn_blocking(move || {
        let db = lfs_core::app::instance()
            .db()
            .ok_or_else(|| "db not initialized".to_string())?;
        db.schema_object_count().map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db_schema_object_count task: {e}"))?
}
