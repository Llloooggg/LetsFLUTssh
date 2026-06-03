//! SQLite + SQLCipher database handle.
//!
//! Opens an encrypted sqlite file under `bundled-sqlcipher`
//! (SQLCipher 4.x, AES-256-CBC + HMAC-SHA512). The page-cipher key
//! the caller hands in is the 32-byte master DB key produced by
//! Argon2id (Paranoid) / pulled out of the OS keychain (T1) /
//! unsealed from the hardware vault (T2); SQLCipher itself does
//! not see Argon2id, only the final 32 bytes.
//!
//! **PBKDF2 is skipped on the page-key derivation** because we
//! pass the key through `PRAGMA key = "x'<64 hex chars>'"` — the
//! raw-key literal shape SQLCipher recognises. The 256 000 default
//! `cipher_kdf_iter` only applies to passphrase-format keys; with
//! a raw 32-byte key the page key is used verbatim and the open
//! cost collapses to single-digit milliseconds. HMAC-key derivation
//! still runs `cipher_hmac_kdf_iter` (default 2 iterations) which
//! is microseconds. If a future caller switches to a passphrase
//! shape — DON'T — re-document this block.
//!
//! **Schema versioning.** [`bootstrap_schema`] writes
//! `PRAGMA user_version = SCHEMA_VERSION` on every fresh open,
//! and the next schema bump bumps that constant + adds a
//! `match user_version { ... }` arm with the migration step. The
//! v1 floor is the drift-bootstrapped baseline, recorded so a
//! future `ALTER TABLE` migration has a real anchor to read off.
//!
//! Threading: every DB call hops to `tokio::task::spawn_blocking`
//! inside the FRB adapter. This struct is Send + Sync (the inner
//! Mutex serialises the rusqlite Connection).
//!
//! Initialisation: `Db::open(path, key)` — typical usage from the
//! adapter is `app::instance().db().init(path, key)` once on
//! startup. Repeat calls are no-ops.

use std::path::Path;
use std::sync::Mutex;

use zeroize::Zeroizing;

use crate::error::Error;

/// Newtype wrap around `rusqlite::Connection` so the rusqlite ABI
/// stays an implementation detail of the `lfs_core::db` module
/// and never crosses the crate boundary. `lfs_frb`'s `run_db_*`
/// helpers thread `&Connection` through their `FnOnce` bounds
/// without seeing rusqlite types — a future swap of the storage
/// backend (rusqlite-2, libsql, sqlx) needs to change only the
/// inner field type and the DAO call sites inside `lfs_core::db`,
/// not every consumer signature in `lfs_frb`.
///
/// DAO modules under `lfs_core::db::*` reach the underlying
/// handle through [`Connection::inner`] / [`Connection::inner_mut`].
/// Those accessors are `pub(crate)` — reachable from sibling DAO
/// files but not from `lfs_frb` — so the only path that sees
/// rusqlite directly is the layer that's tightly coupled to it
/// by intent.
pub struct Connection {
    inner: rusqlite::Connection,
}

impl Connection {
    /// Open a fresh handle to `path`. Internal — `Db::open` is the
    /// production entry point + handles the SQLCipher PRAGMAs.
    ///
    /// Creates the parent directory if missing. `rusqlite::Connection::open`
    /// surfaces a parent-missing failure as a generic `unable to open
    /// database file` error; the mkdir step keeps the contract single-call
    /// for every caller (production `db_init` / `db_init_from_secret` and
    /// test fixtures alike).
    pub(crate) fn open(path: &Path) -> Result<Self, rusqlite::Error> {
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| {
                    rusqlite::Error::InvalidPath(parent.join(format!("create_dir_all: {e}")))
                })?;
            }
        }
        Ok(Self {
            inner: rusqlite::Connection::open(path)?,
        })
    }

    /// In-memory handle. Used by `Db::from_raw_for_tests` and a
    /// handful of unit-test fixtures that need a throw-away
    /// connection without touching disk or SQLCipher.
    #[cfg(test)]
    pub fn open_in_memory() -> Result<Self, rusqlite::Error> {
        Ok(Self {
            inner: rusqlite::Connection::open_in_memory()?,
        })
    }

    /// In-crate accessor for DAO modules. Returns the underlying
    /// rusqlite handle so DAOs can call `prepare` / `execute` /
    /// `query_row` / etc. directly — the methods we'd otherwise
    /// have to forward one-by-one. Visibility is `pub(crate)` so
    /// the rusqlite surface stays inside `lfs_core::db`.
    pub(crate) fn inner(&self) -> &rusqlite::Connection {
        &self.inner
    }

    /// Mutable variant of [`inner`] — needed by DAOs that scope a
    /// `transaction()` (rusqlite returns a `Transaction` that
    /// borrows the connection mutably).
    pub(crate) fn inner_mut(&mut self) -> &mut rusqlite::Connection {
        &mut self.inner
    }

    /// Inherent alias for [`DbAccess::raw`]. In-crate test fixtures
    /// hold a concrete `&Connection` and call `conn.raw()` without
    /// importing the trait; the inherent method shadows the trait
    /// (Rust prefers inherent over trait) and resolves the same
    /// way. DAO bodies that take `&impl DbAccess` keep going
    /// through the trait method — this is a duplication for
    /// ergonomic reasons, not a behaviour difference.
    #[cfg(test)]
    pub(crate) fn raw(&self) -> &rusqlite::Connection {
        &self.inner
    }
}

/// Sealed trait abstracting "anything DAO can run a query against"
/// — production code passes a `&Connection` (newtype) from
/// [`Db::with_conn`]; internal in-crate code that scopes a
/// `rusqlite::Transaction` passes the transaction directly. Both
/// surface a `&rusqlite::Connection` the DAO can call methods on
/// through the `pub(crate)` `raw()` accessor.
///
/// The trait is `pub` so DAO function signatures can name it
/// (`fn list_all(c: &impl DbAccess)`); the `raw()` accessor is
/// `pub(crate)` so the rusqlite type stays inside `lfs_core`.
/// Downstream crates (`lfs_frb`) consume the trait by name only —
/// they never call `raw()` themselves.
pub trait DbAccess {
    /// In-crate accessor to the underlying rusqlite handle.
    /// `pub(crate)`-gated so the rusqlite ABI stays inside
    /// `lfs_core::db`; FRB callers reach DAOs through `with_conn`
    /// closures and never name this method.
    #[doc(hidden)]
    fn raw(&self) -> &rusqlite::Connection;
}

impl DbAccess for Connection {
    fn raw(&self) -> &rusqlite::Connection {
        &self.inner
    }
}

impl<'conn> DbAccess for rusqlite::Transaction<'conn> {
    fn raw(&self) -> &rusqlite::Connection {
        // `Transaction` derefs to `&Connection`; the explicit
        // deref pin keeps the resolution unambiguous if the trait
        // gains another method that shadows a Transaction inherent.
        std::ops::Deref::deref(self)
    }
}

pub mod app_configs;
pub mod folders;
pub mod known_hosts;
pub mod port_forwards;
pub mod s3_sessions;
pub mod sessions;
pub mod sftp_bookmarks;
pub mod snippets;
pub mod ssh_key_certificates;
pub mod ssh_keys;
pub mod tags;
pub mod webdav_sessions;

/// Owned handle to the app sqlite database. Wraps a single
/// rusqlite Connection inside a Mutex so concurrent callers
/// serialise; sqlite itself is single-writer at the file level
/// regardless.
///
/// `path` remembers the on-disk location the handle was opened at
/// so the tier-downgrade flow (`export_plaintext_copy` →
/// rename-over-original → `db_init` unkeyed) can swap the file
/// without the caller threading the path through every FRB hop.
pub struct Db {
    conn: Mutex<Connection>,
    path: std::path::PathBuf,
}

#[cfg(test)]
impl Db {
    /// Test-only constructor — wrap an existing rusqlite
    /// connection (typically `Connection::open_in_memory`) so
    /// downstream module tests (`sessions::Registry`, the future
    /// import / export drivers) can drive the DAOs against an
    /// ephemeral database without going through SQLCipher.
    pub fn from_raw_for_tests(conn: Connection) -> Self {
        Self {
            conn: Mutex::new(conn),
            path: std::path::PathBuf::new(),
        }
    }
}

impl Db {
    /// Open `path` with the given 32-byte SQLCipher master key.
    ///
    /// Sets `PRAGMA key = "x'<hex>'"` to match the literal shape
    /// `database_opener.dart::encryptionKeyToSqlLiteral` produces.
    /// `PRAGMA cipher_compatibility = 4` selects SQLCipher 4.x
    /// defaults (AES-256-CBC). After PRAGMAs we run
    /// `SELECT count(*) FROM sqlite_master` as a smoke test — that
    /// fails immediately on a wrong key (unreadable header) instead
    /// of letting the first real query throw a confusing
    /// "malformed database schema" later. **Note:** an existing
    /// drift-MC ChaCha20 file at this path will NOT open with this
    /// PRAGMA — see the module docstring for the migration plan.
    pub fn open(path: &Path, key: &[u8]) -> Result<Self, Error> {
        // Per-step timing — the Dart-side `RustDbInit` Stopwatch
        // logs the whole `dbInit` FRB hop but cannot split SQLCipher
        // PRAGMA / smoke probe / schema bootstrap. These spans
        // surface the actual culprit when a slow open shows up in
        // a support trace.
        let t0 = std::time::Instant::now();
        let conn = Connection::open(path).map_err(|e| Error::Db(format!("db open: {e}")))?;
        crate::app_log_info!(
            "DbOpen",
            "db open phase=connection elapsed={}ms",
            t0.elapsed().as_millis()
        );
        if !key.is_empty() {
            // Hex-encode for the PRAGMA key literal. Match the Dart
            // `encryptionKeyToSqlLiteral` exactly: lowercase hex, no
            // separators, wrapped in `x'...'`.
            let hex_key: Zeroizing<String> = Zeroizing::new(key.iter().fold(
                String::with_capacity(key.len() * 2),
                |mut acc, b| {
                    use std::fmt::Write as _;
                    let _ = write!(acc, "{b:02x}");
                    acc
                },
            ));
            let pragma = format!("PRAGMA key = \"x'{}'\"", &*hex_key);
            conn.inner()
                .execute_batch(&pragma)
                .map_err(|e| Error::Db(format!("PRAGMA key: {e}")))?;
            conn.inner()
                .execute_batch("PRAGMA cipher_compatibility = 4")
                .map_err(|e| Error::Db(format!("PRAGMA cipher_compatibility: {e}")))?;
            crate::app_log_info!(
                "DbOpen",
                "db open phase=pragma_key elapsed={}ms",
                t0.elapsed().as_millis()
            );
        }
        // Smoke test the key by touching the schema table.
        conn.inner()
            .query_row("SELECT count(*) FROM sqlite_master", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|e| Error::Db(format!("schema probe: {e}")))?;
        crate::app_log_info!(
            "DbOpen",
            "db open phase=schema_probe elapsed={}ms",
            t0.elapsed().as_millis()
        );
        // Enable foreign-key enforcement (drift sets this too) so
        // ON DELETE CASCADE / SET NULL behave consistently across
        // both engines while the migration is mid-flight.
        conn.inner()
            .execute_batch("PRAGMA foreign_keys = ON")
            .map_err(|e| Error::Db(format!("PRAGMA foreign_keys: {e}")))?;
        // WAL journal — concurrent readers don't block the writer,
        // crash recovery is faster, and the wipe registry already
        // lists `letsflutssh.db-wal` / `-shm` so the cleanup contract
        // exists for it. NORMAL fsync is the WAL-paired default
        // (DELETE-mode FULL is the historic default, the standard
        // SQLite recommendation pairs WAL with NORMAL).
        conn.inner()
            .execute_batch("PRAGMA journal_mode = WAL")
            .map_err(|e| Error::Db(format!("PRAGMA journal_mode = WAL: {e}")))?;
        conn.inner()
            .execute_batch("PRAGMA synchronous = NORMAL")
            .map_err(|e| Error::Db(format!("PRAGMA synchronous = NORMAL: {e}")))?;
        // WAL emit creates `-wal` + `-shm` sidecars; harden each to
        // 0600 so a sidecar doesn't drift to inherited 0644 just
        // because SQLite's first write happened under whichever
        // umask the process inherited. Best-effort — sidecars may
        // not exist yet at this point (created lazily on first
        // write); the harden call swallows ENOENT.
        Self::harden_db_files_best_effort(path);
        bootstrap_schema(&conn)?;
        crate::app_log_info!(
            "DbOpen",
            "db open phase=schema_bootstrap elapsed={}ms",
            t0.elapsed().as_millis()
        );
        Ok(Self {
            conn: Mutex::new(conn),
            path: path.to_path_buf(),
        })
    }

    /// Path the handle was opened at. Used by the T1 → T0
    /// (master-password disable) flow to rename the freshly-
    /// exported plaintext copy over the encrypted source.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Decrypt the current encrypted DB into a plaintext sqlite
    /// file at `plaintext_path` via SQLCipher's `sqlcipher_export`.
    /// Empty-string KEY on the ATTACH means the target is written
    /// with no page cipher at all — this is the only correct way
    /// to "downgrade" a SQLCipher database to plaintext, since
    /// `PRAGMA rekey = ''` would just generate a fresh random key
    /// rather than disable encryption (SQLCipher rejects the empty
    /// literal as a tier-downgrade signal).
    ///
    /// Steps:
    ///
    /// 1. `PRAGMA wal_checkpoint(TRUNCATE)` so any pending WAL
    ///    pages are flushed into the main file before the export
    ///    reads it.
    /// 2. `ATTACH DATABASE '<plaintext_path>' AS plaintext KEY ''`
    ///    opens the target as a brand-new plaintext sqlite file.
    /// 3. `SELECT sqlcipher_export('plaintext')` walks every table,
    ///    view, and trigger from the running encrypted DB and copies
    ///    them into the target. `user_version` / `application_id` /
    ///    other meta-pragmas carry over.
    /// 4. `DETACH DATABASE plaintext` flushes the target and
    ///    releases the handle.
    ///
    /// Caller MUST:
    /// - Close this `Db` (drop the `Arc<Db>` + call
    ///   `app::db_close`) before renaming `plaintext_path` over
    ///   `self.path()`.
    /// - Clean up the encrypted DB's `-wal` / `-shm` sidecars
    ///   alongside the rename — they hold encrypted page state
    ///   that the new plaintext file does not need.
    /// - Re-open the DB at `self.path()` with an empty key via
    ///   `app::db_init` so the plaintext file becomes the running
    ///   handle.
    pub fn export_plaintext_copy(&self, plaintext_path: &Path) -> Result<(), Error> {
        let g = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        // Best-effort flush; on the rare case `wal_checkpoint`
        // fails (an open read-tx holding the WAL pinned), the
        // export still sees the latest committed pages via the
        // mvcc snapshot rusqlite holds.
        let _ = g.inner().execute_batch("PRAGMA wal_checkpoint(TRUNCATE)");
        // SQLite string literal escaping: any single quote in the
        // path doubles. Backslashes need no escape (no shell
        // interpretation inside a SQL literal). Production paths
        // under app-support do not carry single quotes; the escape
        // is a defence-in-depth net for hand-edited installs.
        let escaped = plaintext_path.to_string_lossy().replace('\'', "''");
        let attach = format!("ATTACH DATABASE '{escaped}' AS plaintext KEY ''");
        g.inner()
            .execute_batch(&attach)
            .map_err(|e| Error::Db(format!("attach plaintext target: {e}")))?;
        // sqlcipher_export returns NULL on success; we drive it
        // via query_row so the rusqlite error path surfaces a
        // mid-export failure (rare — usually an out-of-disk).
        let export = g
            .inner()
            .query_row("SELECT sqlcipher_export('plaintext')", [], |_row| Ok(()));
        if let Err(e) = export {
            // Detach what we attached so a partial failure does
            // not leave the connection holding a stray schema
            // attached.
            let _ = g.inner().execute_batch("DETACH DATABASE plaintext");
            return Err(Error::Db(format!("sqlcipher_export: {e}")));
        }
        g.inner()
            .execute_batch("DETACH DATABASE plaintext")
            .map_err(|e| Error::Db(format!("detach plaintext target: {e}")))?;
        Ok(())
    }

    /// Harden the SQLCipher DB file + WAL / SHM sidecars to
    /// owner-only on Unix (0600). Mirrors the perm contract every
    /// other secret-bearing artefact under app-support enforces.
    /// Sidecars may not exist at the time this runs (SQLite
    /// creates them lazily on first write); the harden call
    /// silently no-ops on the missing files.
    fn harden_db_files_best_effort(db_path: &Path) {
        let _ = crate::path::harden_file_perms(db_path);
        for suffix in ["-wal", "-shm", "-journal"] {
            if let Some(parent) = db_path.parent() {
                if let Some(name) = db_path.file_name() {
                    let mut sidecar = parent.to_path_buf();
                    let mut sidecar_name = name.to_os_string();
                    sidecar_name.push(suffix);
                    sidecar.push(sidecar_name);
                    if sidecar.exists() {
                        let _ = crate::path::harden_file_perms(&sidecar);
                    }
                }
            }
        }
    }

    /// Smoke-test query the FRB adapter calls during init to verify
    /// the connection is alive. Returns the count of rows in
    /// `sqlite_master` (i.e. table count + index count).
    pub fn schema_object_count(&self) -> Result<i64, Error> {
        let g = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        g.inner()
            .query_row("SELECT count(*) FROM sqlite_master", [], |row| row.get(0))
            .map_err(|e| Error::Db(format!("schema count: {e}")))
    }

    /// Re-encrypt every page under `new_key`. Mirrors drift-side
    /// `rekeyDatabase` so the security-tier switcher can rekey
    /// drift's `letsflutssh.db` and lfs_core's `letsflutssh.db` in
    /// lock-step. Empty `new_key` is rejected — converting back to
    /// plaintext is not a valid lfs_core flow (the schema docstring
    /// describes a key-required handle; a plaintext degrade would
    /// silently disable encryption next boot).
    ///
    /// On any underlying failure the SQL fragment is stripped from
    /// the error message so the hex-encoded key cannot leak into
    /// logs / crash reporters via the rusqlite default formatter.
    pub fn rekey(&self, new_key: &[u8]) -> Result<(), Error> {
        if new_key.is_empty() {
            return Err(Error::Io("db rekey: empty key rejected".into()));
        }
        let hex_key: Zeroizing<String> = Zeroizing::new(new_key.iter().fold(
            String::with_capacity(new_key.len() * 2),
            |mut acc, b| {
                use std::fmt::Write as _;
                let _ = write!(acc, "{b:02x}");
                acc
            },
        ));
        let pragma = format!("PRAGMA rekey = \"x'{}'\"", &*hex_key);
        let g = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        g.inner()
            .execute_batch(&pragma)
            .map_err(|_| Error::Io("db rekey: PRAGMA rekey failed".into()))?;
        Ok(())
    }

    /// Lock the inner connection for a closure. Used by DAO
    /// modules (`db::sessions`, `db::ssh_keys`, ...). The closure
    /// runs on the caller's thread — adapters wrap this whole
    /// function in `spawn_blocking` so the FRB tokio worker isn't
    /// stuck behind disk I/O.
    pub fn with_conn<R>(
        &self,
        f: impl FnOnce(&Connection) -> Result<R, Error>,
    ) -> Result<R, Error> {
        let g = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        f(&g)
    }

    /// Same as [`with_conn`] but hands the closure a `&mut
    /// Connection` so callers that need a `transaction()` (the
    /// import apply driver in particular) can scope rollback /
    /// commit cleanly. The connection still lives behind the
    /// crate-level mutex; only one caller holds the mut ref at
    /// a time.
    pub fn with_conn_mut<R>(
        &self,
        f: impl FnOnce(&mut Connection) -> Result<R, Error>,
    ) -> Result<R, Error> {
        let mut g = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        f(&mut g)
    }
}

/// Current on-disk schema revision. Stamped into the DB via
/// `PRAGMA user_version` on bootstrap so a future schema bump can
/// branch on the read-back value to decide whether to run a
/// migration step. v1 is the baseline shape every table in
/// [`SCHEMA_SQL`] declares. Bump this constant + extend
/// [`bootstrap_schema`] with a `match` arm whenever the schema
/// changes (additive ADD COLUMN / new CREATE TABLE IF NOT EXISTS
/// covered by the existing idempotent path; structural rewrites
/// follow the SQLite 12-step rebuild recipe).
pub const SCHEMA_VERSION: i32 = 1;

/// On-disk file name of the encrypted sqlite database under the
/// app support directory. Single source of truth — every Rust-side
/// caller (orchestrator cascade, wipe path, recovery sweep) derives
/// the full path from `app::support_dir().join(DB_FILE_NAME)`.
/// Mirrors the Dart `_rustDbFileName` constant.
pub const DB_FILE_NAME: &str = "letsflutssh.db";

/// Every table that carries a `deleted_at INTEGER NULL` tombstone
/// column once the schema is at HEAD. The per-DAO tombstone-filter
/// contract — every SELECT filters `WHERE deleted_at IS NULL`,
/// every `delete*` flips the column to a unix-millis stamp instead
/// of issuing a `DELETE FROM` — applies to every entry. `known_hosts`
/// is **not** in this list: TOFU state is per-device and the sync
/// layer (WebDAV) must not leak host trust across devices — physical
/// removal stays the model there.
const TOMBSTONE_TABLES: &[&str] = &[
    "sessions",
    "ssh_keys",
    "tags",
    "snippets",
    "sftp_bookmarks",
    "port_forward_rules",
    "webdav_session_details",
    "s3_session_details",
];

/// Create every table the DAOs expect, idempotently, and stamp
/// `PRAGMA user_version = SCHEMA_VERSION` when the on-disk value
/// is strictly below the current version. The `<` test prevents
/// the downgrade case: a user opening a future-version DB with an
/// older build leaves the stamp untouched so the next forward
/// upgrade picks up cleanly.
///
/// Every table currently lives at the v1 baseline declared in
/// [`SCHEMA_SQL`] (`CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF
/// NOT EXISTS`); no per-step ALTER hops are registered yet. Future
/// schema bumps extend this function with a match arm on `current`,
/// bump [`SCHEMA_VERSION`], and add the rewind+replay test that
/// pins the new hop. Tombstone indexes + partial-unique indexes
/// land unconditionally after the `SCHEMA_SQL` block so a fresh
/// install picks them up alongside the rebuilt-on-upgrade case.
pub(crate) fn bootstrap_schema(conn: &Connection) -> Result<(), Error> {
    conn.inner()
        .execute_batch(SCHEMA_SQL)
        .map_err(|e| Error::Db(format!("bootstrap schema: {e}")))?;
    let mut current: i32 = 0;
    conn.inner()
        .pragma_query(None, "user_version", |row| {
            current = row.get::<_, i32>(0)?;
            Ok(())
        })
        .map_err(|e| Error::Db(format!("bootstrap schema: read user_version: {e}")))?;
    if current < SCHEMA_VERSION {
        conn.inner()
            .pragma_update(None, "user_version", SCHEMA_VERSION)
            .map_err(|e| Error::Db(format!("bootstrap schema: stamp user_version: {e}")))?;
    }
    create_tombstone_indexes(conn)?;
    create_partial_unique_indexes(conn)?;
    Ok(())
}

/// Partial-unique indexes that need to land after `bootstrap_schema`
/// stabilises the column shape. Currently one entry: `tags.name`
/// constrained to live (non-tombstoned) rows so deleting and
/// recreating a same-named tag works without touching the purge
/// queue.
fn create_partial_unique_indexes(conn: &Connection) -> Result<(), Error> {
    conn.inner()
        .execute_batch(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_live \
             ON tags(name) WHERE deleted_at IS NULL",
        )
        .map_err(|e| Error::Db(format!("bootstrap schema: index tags.name (live): {e}")))?;
    Ok(())
}

/// Create the partial-style `deleted_at` index on each
/// soft-deletable table. Idempotent — runs on every bootstrap.
fn create_tombstone_indexes(conn: &Connection) -> Result<(), Error> {
    for table in TOMBSTONE_TABLES {
        let sql =
            format!("CREATE INDEX IF NOT EXISTS idx_{table}_deleted_at ON {table}(deleted_at)");
        conn.inner()
            .execute_batch(&sql)
            .map_err(|e| Error::Db(format!("bootstrap schema: index {table}.deleted_at: {e}")))?;
    }
    Ok(())
}

/// Read the on-disk schema revision. Returns `0` for a freshly
/// initialised DB that hasn't been bootstrapped yet (SQLite
/// default for `user_version`); after [`bootstrap_schema`] it
/// returns [`SCHEMA_VERSION`]. Currently used only by the
/// bootstrap idempotency test; production runs no longer branch
/// on `user_version` because the v1 floor is universal — the
/// next schema bump will surface the first real consumer.
#[cfg(test)]
fn read_schema_version(conn: &Connection) -> Result<i32, Error> {
    let mut value: i32 = 0;
    conn.inner()
        .pragma_query(None, "user_version", |row| {
            value = row.get::<_, i32>(0)?;
            Ok(())
        })
        .map_err(|e| Error::Db(format!("read user_version: {e}")))?;
    Ok(value)
}

const SCHEMA_SQL: &str = r#"
CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    collapsed INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS ssh_keys (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    private_key TEXT NOT NULL,
    public_key TEXT NOT NULL,
    key_type TEXT NOT NULL,
    is_generated INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    -- FIDO2 hardware-key columns. NULL for software keys (the
    -- common case); populated for `sk-ssh-ed25519@openssh.com` /
    -- `sk-ecdsa-sha2-nistp256@openssh.com` rows captured at import.
    -- `credential_id` is the opaque CTAP2 blob the device matches
    -- against on every assertion. `application_string` is the SSH
    -- `application` field (typically `ssh:`). `has_user_verification`
    -- gates the PIN prompt on connect.
    credential_id BLOB NULL,
    application_string TEXT NULL,
    has_user_verification INTEGER NOT NULL DEFAULT 0,
    agent_policy TEXT NOT NULL DEFAULT 'ask',
    backend TEXT NOT NULL DEFAULT 'software',
    pkcs11_uri TEXT NULL,
    pkcs11_module_path TEXT NULL,
    pkcs11_token_serial TEXT NULL,
    pkcs11_object_id BLOB NULL,
    pkcs11_object_label TEXT NULL,
    -- Apple Secure Enclave application-tag (v10). Opaque bytes the
    -- `kSecAttrApplicationTag` lookup matches on. NULL for every
    -- non-enclave row; populated only when `backend = 'enclave'`.
    enclave_tag BLOB NULL,
    -- Windows Hello / NCrypt persistent-key name (v11). UTF-8 string
    -- the `NCryptOpenKey(provider, &hKey, name, …)` lookup re-binds
    -- to on every sign. NULL for every non-`hello` row; populated
    -- only when `backend = 'hello'`.
    hello_credential_name TEXT NULL,
    -- TPM 2.0 SSH ingredient columns (v12). Populated only when
    -- `backend = 'tpm'`. `tpm_blob` carries the TSS2 PRIVATE KEY
    -- ASN.1 bytes per TCG draft `draft-bottomley-tpm2-keys-asn1`
    -- (Linux blob-storage mode); `tpm_handle` is the persistent NV
    -- handle in `0x81010001..0x8101FFFF` when the key was loaded
    -- into TPM RAM; `tpm_provider` is one of `'tss-esapi'`
    -- (Linux ESAPI) / `'cng-pcp'` (Windows PCP silent variant);
    -- `tpm_pin_required` flips the per-sign PIN prompt on;
    -- `cng_key_name` is the Windows PCP-silent variant's CNG
    -- persistent-key name (uses the `letsflutssh-tpm-` prefix to
    -- distinguish from Hello-gated `letsflutssh-ssh-` keys when
    -- `NCryptEnumKeys` walks the provider).
    tpm_blob BLOB NULL,
    tpm_handle INTEGER NULL,
    tpm_provider TEXT NULL,
    tpm_pin_required INTEGER NOT NULL DEFAULT 0,
    cng_key_name TEXT NULL,
    keystore_alias TEXT NULL,
    keystore_strongbox INTEGER NOT NULL DEFAULT 0,
    keystore_user_auth_required INTEGER NOT NULL DEFAULT 0,
    keystore_platform TEXT NULL,
    -- Stub flag (v14). `1` when the row landed as a public-half-only
    -- import (`.lfs` archive or WebDAV sync pull) for a device-bound
    -- backend (`enclave` / `hello` / `tpm` / `keystore`). The key
    -- manager renders such rows desaturated with a "Re-generate
    -- here" / "Remove" action; the session-edit "Key from manager"
    -- picker disables them with a tooltip. The first local
    -- regenerate or remove clears the column. Stays `0` for every
    -- software / FIDO2 / PKCS#11 row (those carry their portable
    -- subset across the wire).
    imported_as_stub INTEGER NOT NULL DEFAULT 0
);
-- Android Hardware Keystore / StrongBox ingredients (v13).
-- Populated only when `backend = 'keystore'`. `keystore_alias` is
-- the AndroidKeyStore alias the `KeyStore.getEntry(alias, null)`
-- lookup re-binds to on every sign (`lfs-keystore-` prefix to stay
-- separate from `FlutterSecureStorageKeyAlias_`).
-- `keystore_strongbox` flips to 1 when `setIsStrongBoxBacked(true)`
-- was accepted; 0 for TEE-only rows so the badge label split
-- (StrongBox HSM vs TEE) is honest. `keystore_user_auth_required`
-- is 1 for every Keystore row today (the wizard always sets
-- `setUserAuthenticationRequired(true)`); reserved as a column so
-- a future no-auth variant lands without a schema bump.
-- `keystore_platform` carries Build.MODEL + Android version,
-- surfaced read-only in the badge popover.
-- backend: software | fido2 | pkcs11 | tpm | enclave | hello | keystore
-- pkcs11 columns populated for backend = pkcs11 rows only.
-- enclave_tag populated for backend = enclave rows only.
-- hello_credential_name populated for backend = hello rows only.
-- tpm_* / cng_key_name populated for backend = tpm rows only.
-- keystore_* populated for backend = keystore rows only.
-- See ARCHITECTURE.md schema docs for full notes.

-- One certificate per stored SSH key. `key_id` is a TEXT foreign
-- key (ssh_keys.id is TEXT, not INTEGER) and doubles as the PK so
-- the upsert can be a plain INSERT OR REPLACE. Validity windows
-- are unix-seconds (matching OpenSSH's wire format); principals
-- and critical_options are stored as serialized JSON so the BTree
-- preserves order and the DAO does not need a junction table for
-- what's a tiny opaque list / map per row.
CREATE TABLE IF NOT EXISTS ssh_key_certificates (
    key_id           TEXT    PRIMARY KEY,
    certificate      BLOB    NOT NULL,
    valid_after      INTEGER NOT NULL,
    valid_before     INTEGER NOT NULL,
    principals       TEXT    NOT NULL DEFAULT '[]',
    critical_options TEXT    NOT NULL DEFAULT '{}',
    fingerprint      TEXT    NOT NULL DEFAULT '',
    FOREIGN KEY (key_id) REFERENCES ssh_keys(id) ON DELETE CASCADE
);

-- Common session row — protocol-neutral. SSH-specific config
-- (host / port / user / auth_type / password / key_path /
-- key_data / key_id / passphrase / via_*) lives in
-- `ssh_session_details`, WebDAV-specific in `webdav_session_details`,
-- S3-specific in `s3_session_details`. Every install lands on this
-- slim shape directly from `SCHEMA_SQL` — `SCHEMA_VERSION` is 1 and
-- `bootstrap_schema` registers no `ALTER` arms.
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL DEFAULT '',
    folder_id TEXT,
    kind TEXT NOT NULL DEFAULT 'ssh',
    sort_order INTEGER NOT NULL DEFAULT 0,
    notes TEXT NOT NULL DEFAULT '',
    last_connected_at INTEGER,
    extras TEXT NOT NULL DEFAULT '{}',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
);

-- SSH-specific session configuration. Keyed by session id with
-- `ON DELETE CASCADE` so removing a session physically purges its
-- SSH row. The credential columns (`password` / `key_data` /
-- `passphrase`) are persisted on the column for archive / wire
-- continuity; the runtime `stage_secrets` path migrates the
-- plaintext into the SecretStore on session open so the in-memory
-- session row never carries the secret material. `via_session_id`
-- references the bastion session (saved-session ProxyJump); the
-- `via_host` / `via_port` / `via_user` columns carry a one-off
-- override when no saved session is referenced.
CREATE TABLE IF NOT EXISTS ssh_session_details (
    session_id     TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
    host           TEXT NOT NULL DEFAULT '',
    port           INTEGER NOT NULL DEFAULT 22,
    user           TEXT NOT NULL DEFAULT '',
    auth_type      TEXT NOT NULL DEFAULT 'password',
    password       TEXT NOT NULL DEFAULT '',
    key_path       TEXT NOT NULL DEFAULT '',
    key_data       TEXT NOT NULL DEFAULT '',
    key_id         TEXT,
    passphrase     TEXT NOT NULL DEFAULT '',
    via_session_id TEXT,
    via_host       TEXT,
    via_port       INTEGER,
    via_user       TEXT,
    updated_at     INTEGER NOT NULL DEFAULT 0,
    deleted_at     INTEGER NULL,
    FOREIGN KEY (key_id) REFERENCES ssh_keys(id) ON DELETE SET NULL,
    FOREIGN KEY (via_session_id) REFERENCES sessions(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_ssh_session_details_session_id
    ON ssh_session_details(session_id);

-- WebDAV-specific configuration. Keyed by session id with ON DELETE
-- CASCADE so removing a session physically purges its WebDAV row;
-- soft-deletes on `sessions` leave this row in place until the
-- sync-merge purge removes the parent. The password / bearer token
-- lives on the `password` column (encrypted at rest by SQLCipher,
-- same posture as `ssh_session_details.password`); the connect path
-- stages it into the in-memory `SecretStore` via
-- [`webdav_sessions::stage_secret_into_store`] just before calling
-- `webdav_connect`. The plaintext never crosses the FRB boundary
-- back to Dart — the edit dialog reads only the `has_password` bool.
CREATE TABLE IF NOT EXISTS webdav_session_details (
    session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
    base_url TEXT NOT NULL,
    username TEXT NOT NULL DEFAULT '',
    auth_method TEXT NOT NULL,
    -- Trusted certificate PEM (one or more `-----BEGIN
    -- CERTIFICATE-----` blocks) added as an additional root for
    -- this session's TLS handshakes. `NULL` falls back to the
    -- system trust store. The dialog hosts the textarea inside the
    -- More options expander since most servers chain to a public CA
    -- and never need it.
    trusted_cert_pem TEXT NULL,
    -- INTEGER boolean. `1` switches the reqwest client to
    -- `danger_accept_invalid_certs(true)` + `danger_accept_invalid_hostnames(true)`,
    -- skipping every certificate check. Last-resort escape hatch
    -- for environments where neither the system trust store nor a
    -- pinned cert is workable; the dialog renders an explicit
    -- MITM warning when the user flips it on.
    insecure_skip_verify INTEGER NOT NULL DEFAULT 0,
    password TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0,
    deleted_at INTEGER NULL
);
CREATE INDEX IF NOT EXISTS idx_webdav_session_details_session_id
    ON webdav_session_details(session_id);

-- S3-compatible session configuration. Same join-table shape as
-- `webdav_session_details`: keyed by session id, ON DELETE CASCADE
-- so the row physically drops when the parent session is purged.
-- The secret access key lives on the `secret_access_key` column
-- (encrypted at rest by SQLCipher); the connect path stages it
-- into the in-memory `SecretStore` via
-- [`s3_sessions::stage_secret_into_store`] just before calling
-- `s3_connect`. The plaintext never crosses the FRB boundary back
-- to Dart — the edit dialog reads only the `has_secret` bool.
-- `path_style` is an INTEGER boolean (0 = virtual-host, 1 = path
-- addressing) so the column stays compatible with SQLite's type
-- system.
CREATE TABLE IF NOT EXISTS s3_session_details (
    session_id              TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
    access_key_id           TEXT NOT NULL DEFAULT '',
    region                  TEXT NOT NULL DEFAULT '',
    endpoint                TEXT NOT NULL DEFAULT '',
    path_style              INTEGER NOT NULL DEFAULT 0,
    default_bucket          TEXT NOT NULL DEFAULT '',
    default_prefix          TEXT NOT NULL DEFAULT '',
    secret_access_key       TEXT NOT NULL DEFAULT '',
    -- Trusted certificate PEM (one or more `-----BEGIN
    -- CERTIFICATE-----` blocks) added as an additional root for
    -- this session's TLS handshakes. `NULL` falls back to the
    -- system trust store. Mirrors the WebDAV detail row so both
    -- transports share one self-signed-endpoint surface.
    trusted_cert_pem        TEXT NULL,
    -- INTEGER boolean. `1` switches the reqwest client to
    -- `danger_accept_invalid_certs(true)` + `danger_accept_invalid_hostnames(true)`,
    -- skipping every certificate check. Last-resort escape hatch
    -- for environments where neither the system trust store nor a
    -- pinned cert is workable — the dialog renders an explicit
    -- MITM warning when the user flips it on.
    insecure_skip_verify    INTEGER NOT NULL DEFAULT 0,
    updated_at              INTEGER NOT NULL DEFAULT 0,
    deleted_at              INTEGER NULL
);
CREATE INDEX IF NOT EXISTS idx_s3_session_details_session_id
    ON s3_session_details(session_id);

CREATE TABLE IF NOT EXISTS known_hosts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    key_type TEXT NOT NULL,
    key_base64 TEXT NOT NULL,
    added_at INTEGER NOT NULL,
    UNIQUE(host, port)
);

CREATE TABLE IF NOT EXISTS app_configs (
    id INTEGER PRIMARY KEY DEFAULT 1,
    data TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    auto_lock_minutes INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    color TEXT,
    created_at INTEGER NOT NULL,
    deleted_at INTEGER NULL
);

CREATE TABLE IF NOT EXISTS session_tags (
    session_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (session_id, tag_id),
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS folder_tags (
    folder_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (folder_id, tag_id),
    FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS snippets (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    command TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL
);

CREATE TABLE IF NOT EXISTS session_snippets (
    session_id TEXT NOT NULL,
    snippet_id TEXT NOT NULL,
    PRIMARY KEY (session_id, snippet_id),
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (snippet_id) REFERENCES snippets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS port_forward_rules (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'local',
    bind_host TEXT NOT NULL DEFAULT '127.0.0.1',
    bind_port INTEGER NOT NULL,
    remote_host TEXT NOT NULL DEFAULT '',
    remote_port INTEGER NOT NULL DEFAULT 0,
    description TEXT NOT NULL DEFAULT '',
    enabled INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT 0,
    deleted_at INTEGER NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sftp_bookmarks (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    remote_path TEXT NOT NULL,
    label TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- Reverse-edge indexes. Every foreign-key column queried as a
-- "join from the *child* side" (rows in this table referencing
-- the parent) needs an explicit index. SQLite indexes the
-- declared PRIMARY KEY automatically but does NOT index foreign-
-- key columns by default; without these every reverse lookup
-- (`SELECT * FROM sessions WHERE folder_id = ?`,
-- `DELETE FROM sftp_bookmarks WHERE session_id = ?`, etc.) was a
-- full table scan. Added at the end of the schema block so an
-- existing database picks them up on the next open without a
-- migration bump (`IF NOT EXISTS` is idempotent).
CREATE INDEX IF NOT EXISTS idx_sessions_folder_id
    ON sessions(folder_id);
-- `via_session_id` and `key_id` moved to `ssh_session_details` on
-- the v15 → v16 schema split. The indexes follow the columns so
-- the ProxyJump bastion lookup and the saved-key lookup keep their
-- O(log n) shape under the new layout.
CREATE INDEX IF NOT EXISTS idx_ssh_session_details_via_session_id
    ON ssh_session_details(via_session_id);
CREATE INDEX IF NOT EXISTS idx_ssh_session_details_key_id
    ON ssh_session_details(key_id);
CREATE INDEX IF NOT EXISTS idx_folders_parent_id
    ON folders(parent_id);
CREATE INDEX IF NOT EXISTS idx_port_forward_rules_session_id
    ON port_forward_rules(session_id);
CREATE INDEX IF NOT EXISTS idx_sftp_bookmarks_session_id
    ON sftp_bookmarks(session_id);
-- Composite-PK tables: the leading column is covered by the PK,
-- but the trailing column needs its own index for the reverse
-- join (`tag → sessions`, `tag → folders`, `snippet → sessions`).
CREATE INDEX IF NOT EXISTS idx_session_tags_tag_id
    ON session_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_folder_tags_tag_id
    ON folder_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_session_snippets_snippet_id
    ON session_snippets(snippet_id);
"#;

#[cfg(test)]
mod tests {
    use super::*;

    /// In-memory database doesn't need a key; verifies the open
    /// path + smoke probe with a no-encryption shortcut.
    #[test]
    fn open_in_memory_with_no_key() {
        let conn = Connection::open_in_memory().unwrap();
        conn.inner()
            .execute_batch("CREATE TABLE t (x INT)")
            .unwrap();
        let db = Db {
            conn: Mutex::new(conn),
            path: std::path::PathBuf::new(),
        };
        let n = db.schema_object_count().unwrap();
        assert!(n >= 1, "schema_object_count was {n}");
    }

    /// `Db::open` against a freshly-created empty file with a
    /// SQLCipher key must succeed — that's the path
    /// `ensureRustDbOpen` hits on first launch (Dart pre-creates a
    /// 0-byte file via `File.create()` before handing the path to
    /// the FRB call). Without this test the schema-probe vs
    /// bootstrap ordering is silently regression-prone: a probe
    /// that runs before the first DDL trips on the empty file
    /// because SQLCipher has no encrypted header to verify yet.
    #[test]
    fn open_creates_fresh_encrypted_db_when_file_is_empty() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("fresh.db");
        // Mirror Dart's `File(path).create()` — empty file on disk.
        std::fs::File::create(&path).unwrap();
        let key = [0x42u8; 32];
        let db = Db::open(&path, &key).expect("open empty file with key must succeed");
        let count = db
            .schema_object_count()
            .expect("schema count after fresh open");
        assert!(count > 0, "bootstrap_schema should have created tables");
    }

    /// `Db::export_plaintext_copy` writes a brand-new plaintext
    /// sqlite file that mirrors every table + row of the running
    /// encrypted DB. Drives the T1 → T0 downgrade path: the
    /// caller renames the export over the encrypted source +
    /// re-opens unkeyed.
    #[test]
    fn export_plaintext_copy_round_trips_under_no_key() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src.db");
        let dst = dir.path().join("plain.db");
        let key = [0x42u8; 32];
        let db = Db::open(&src, &key).expect("open encrypted source");
        // Drop a row through a user-defined table so the export
        // carries schema + data, not just empty bootstrap output.
        db.with_conn(|c| {
            c.inner()
                .execute_batch(
                    "CREATE TABLE migration_probe (id TEXT PRIMARY KEY, payload TEXT);
                     INSERT INTO migration_probe (id, payload) VALUES ('p1', 'hello');",
                )
                .map_err(|e| Error::Db(format!("probe seed: {e}")))
        })
        .unwrap();

        db.export_plaintext_copy(&dst)
            .expect("export plaintext copy");
        assert!(dst.exists(), "exported plaintext file must exist");
        assert_eq!(db.path(), src.as_path(), "source path tracked");

        // Open the export directly through rusqlite — no PRAGMA
        // key, no PRAGMA cipher_compatibility — and read the row
        // back. This is the same shape `db_init(&dst, &[])` will
        // exercise post-rename.
        let plain = rusqlite::Connection::open(&dst).unwrap();
        let payload: String = plain
            .query_row(
                "SELECT payload FROM migration_probe WHERE id = 'p1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(
            payload, "hello",
            "plaintext export must carry the row written under the encrypted source",
        );
        // Probing the source with no key now fails — confirms the
        // source DB is still encrypted (the export did not touch
        // the original file).
        let unkeyed = rusqlite::Connection::open(&src).unwrap();
        let probe = unkeyed.query_row("SELECT count(*) FROM sqlite_master", [], |r| {
            r.get::<_, i64>(0)
        });
        assert!(
            probe.is_err(),
            "encrypted source must reject a no-key open after export",
        );
    }

    /// Bootstrap stamps `user_version = SCHEMA_VERSION` on a fresh
    /// DB and is idempotent on re-bootstrap.
    #[test]
    fn bootstrap_stamps_user_version() {
        let conn = Connection::open_in_memory().unwrap();
        assert_eq!(
            read_schema_version(&conn).unwrap(),
            0,
            "fresh DB starts at user_version 0",
        );
        bootstrap_schema(&conn).unwrap();
        assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);
        // Re-running bootstrap leaves the stamp at the same value.
        bootstrap_schema(&conn).unwrap();
        assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);
    }
    /// Bootstrap schema + ssh_keys round-trip on an in-memory DB.
    /// Confirms the SQL strings parse and the column shapes match.
    #[test]
    fn ssh_keys_round_trip_in_memory() {
        let conn = Connection::open_in_memory().unwrap();
        conn.inner()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        let row = ssh_keys::SshKeyRow {
            id: "k1".into(),
            label: "lap".into(),
            private_key: "PRIVATE".into(),
            public_key: "ssh-ed25519 AAAA".into(),
            key_type: "ssh-ed25519".into(),
            is_generated: true,
            created_at_ms: 1700000000000,
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: ssh_keys::AgentPolicy::Ask,
            backend: ssh_keys::KeyBackend::Software,
            pkcs11_uri: None,
            pkcs11_module_path: None,
            pkcs11_token_serial: None,
            pkcs11_object_id: None,
            pkcs11_object_label: None,
            enclave_tag: None,
            hello_credential_name: None,
            tpm_blob: None,
            tpm_handle: None,
            tpm_provider: None,
            tpm_pin_required: false,
            cng_key_name: None,
            keystore_alias: None,
            keystore_strongbox: false,
            keystore_user_auth_required: false,
            keystore_platform: None,
            imported_as_stub: false,
        };
        ssh_keys::upsert(&conn, &row).unwrap();
        let got = ssh_keys::get(&conn, "k1").unwrap().unwrap();
        assert_eq!(got.label, "lap");
        assert!(got.is_generated);
        let all = ssh_keys::list_all(&conn).unwrap();
        assert_eq!(all.len(), 1);
        let n = ssh_keys::delete(&conn, "k1").unwrap();
        assert_eq!(n, 1);
        assert!(ssh_keys::get(&conn, "k1").unwrap().is_none());
    }

    /// Sessions ↔ folders FK behaves: deleting a folder NULLs the
    /// folder_id on referencing sessions (ON DELETE SET NULL).
    #[test]
    fn sessions_folder_fk_set_null_on_delete() {
        let conn = Connection::open_in_memory().unwrap();
        conn.inner()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        folders::upsert(
            &conn,
            &folders::FolderRow {
                id: "f1".into(),
                name: "Production".into(),
                parent_id: None,
                sort_order: 0,
                collapsed: false,
                created_at_ms: 1700000000000,
            },
        )
        .unwrap();
        sessions::upsert(
            &conn,
            &sessions::SessionRow {
                id: "s1".into(),
                label: "edge".into(),
                folder_id: Some("f1".into()),
                kind: sessions::SESSION_KIND_SSH.into(),
                host: "edge.example".into(),
                port: 22,
                user: "deploy".into(),
                auth_type: "password".into(),
                password: "".into(),
                key_path: "".into(),
                key_data: "".into(),
                key_id: None,
                passphrase: "".into(),
                sort_order: 0,
                notes: "".into(),
                last_connected_at_ms: None,
                extras: "{}".into(),
                via_session_id: None,
                via_host: None,
                via_port: None,
                via_user: None,
                created_at_ms: 1700000000000,
                updated_at_ms: 1700000000000,
            },
        )
        .unwrap();
        folders::delete(&conn, "f1").unwrap();
        let s = sessions::get(&conn, "s1").unwrap().unwrap();
        assert_eq!(s.folder_id, None);
    }
}
