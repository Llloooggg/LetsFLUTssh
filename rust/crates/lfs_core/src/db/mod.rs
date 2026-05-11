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
//! v1 floor is "what drift used to ship", recorded so a future
//! `ALTER TABLE` migration has a real anchor to read off.
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
    #[allow(dead_code)] // false positive: tests resolve through this inherent.
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
pub struct Db {
    conn: Mutex<Connection>,
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
        })
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
/// migration step. Bump this constant + extend
/// [`bootstrap_schema`] with a `match` arm whenever the schema
/// changes. v1 is "what drift used to ship before the rusqlite
/// port", recorded explicitly so a future ALTER TABLE has a
/// real anchor. v2 adds the `ssh_key_certificates` join table.
/// v3 adds the `deleted_at` tombstone column + matching index to
/// the five user-data tables (`sessions`, `ssh_keys`, `tags`,
/// `snippets`, `sftp_bookmarks`) — see
/// [`bootstrap_schema`] for the per-table ALTER step, and
/// `ARCHITECTURE.md §11` for the soft-delete contract. v4 drops
/// the inline `UNIQUE(name)` on `tags` and replaces it with a
/// partial-unique index gated on `deleted_at IS NULL`. v5 adds
/// the `kind` column on `sessions` plus the `webdav_session_details`
/// join table so WebDAV sessions can sit alongside SSH ones with
/// per-kind configuration owned by a side table.
pub const SCHEMA_VERSION: i32 = 5;

/// Tables that carry a `deleted_at INTEGER NULL` tombstone column.
/// Single source of truth for the v2 → v3 migration step + the
/// per-DAO tombstone-filter contract — every SELECT against these
/// tables filters `WHERE deleted_at IS NULL`, every `delete*`
/// flips the column to a unix-millis timestamp instead of issuing
/// a `DELETE FROM`. `known_hosts` is **not** in this list: TOFU
/// state is per-device and the sync layer (WebDAV) must not leak
/// host trust across devices — physical removal stays the model
/// there.
const TOMBSTONE_TABLES: &[&str] = &["sessions", "ssh_keys", "tags", "snippets", "sftp_bookmarks"];

/// Create every table the DAOs expect, idempotently, and stamp
/// `PRAGMA user_version = SCHEMA_VERSION` when the on-disk value
/// is strictly below the current version. The `<` test prevents
/// the audit-flagged downgrade case: a user opening a v3 DB with a
/// v2 build leaves `user_version` at 3 and the future v3 build
/// finds it unchanged.
///
/// Forward-stamping is safe for additive shapes (`CREATE TABLE IF
/// NOT EXISTS` / `CREATE INDEX IF NOT EXISTS`); the v1/v2 → v3 step
/// also issues `ALTER TABLE ... ADD COLUMN deleted_at` against the
/// five [`TOMBSTONE_TABLES`]. SQLite errors with "duplicate column
/// name" when the column already exists, so the ALTER block is
/// gated by `(1..3).contains(&current)` — fires only when the DB
/// was bootstrapped under v1/v2 (`current >= 1`) but predates the
/// column (`current < 3`). A fresh install (`current == 0`) takes
/// the column via the `CREATE TABLE IF NOT EXISTS` block above and
/// skips the ALTER. The tombstone indexes are created
/// unconditionally after the upgrade arm — see
/// [`create_tombstone_indexes`].
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
        // v1/v2 → v3: backfill the `deleted_at` column on every
        // pre-existing tombstoned table. A `current >= 1` floor
        // confirms the database was already bootstrapped under
        // an earlier schema (the tables exist but lack the
        // column); `current == 0` means the SCHEMA_SQL block
        // above just minted a fresh database where every CREATE
        // TABLE already carries `deleted_at`, so the ALTER would
        // surface SQLite's "duplicate column name" error.
        if (1..3).contains(&current) {
            for table in TOMBSTONE_TABLES {
                add_deleted_at_column(conn, table)?;
            }
        }
        // v1/v2/v3 → v4: rebuild `tags` to drop the inline
        // `UNIQUE` on `name`. A tombstoned tag holds the name
        // until purge, which blocked recreating a same-named tag
        // and would have broken the sync-merge replay path.
        // SQLite cannot DROP a column-level UNIQUE without a
        // table rebuild. Fresh installs (`current == 0`) get the
        // new shape from `SCHEMA_SQL` directly and skip this arm.
        if (1..4).contains(&current) {
            rebuild_tags_without_inline_unique(conn)?;
        }
        // v1..v4 → v5: stamp `kind` on every existing session row.
        // `ALTER TABLE` is additive — column lands with the
        // schema default `'ssh'` for every backfilled row, which
        // matches the wire value for the only kind that existed
        // before this hop. `webdav_session_details` lands via
        // `CREATE TABLE IF NOT EXISTS` in `SCHEMA_SQL` and needs
        // no per-step ALTER. Fresh installs (`current == 0`) get
        // the column directly from `SCHEMA_SQL` and skip this arm.
        if (1..5).contains(&current) {
            add_sessions_kind_column(conn)?;
        }
        conn.inner()
            .pragma_update(None, "user_version", SCHEMA_VERSION)
            .map_err(|e| Error::Db(format!("bootstrap schema: stamp user_version: {e}")))?;
    }
    // Tombstone indexes — issued after the column is guaranteed
    // to exist (either via `CREATE TABLE IF NOT EXISTS` on a
    // fresh install or the ALTER block above on an upgrade hop).
    // `CREATE INDEX IF NOT EXISTS` is idempotent so a re-bootstrap
    // is a no-op. Placement after the upgrade arm keeps the
    // schema/index ordering invariant straightforward: column
    // always lands first.
    create_tombstone_indexes(conn)?;
    // Partial unique on `tags(name) WHERE deleted_at IS NULL` so
    // a tombstoned tag does not block a same-named recreate. Also
    // idempotent; runs unconditionally on every bootstrap so a
    // fresh install picks it up alongside the rebuilt-on-upgrade
    // case.
    create_partial_unique_indexes(conn)?;
    Ok(())
}

/// Rebuild the `tags` table to drop the inline `UNIQUE(name)`
/// constraint. The CREATE TABLE statement at module scope already
/// emits the new shape; this helper applies the same change to
/// an existing v1/v2/v3 database. Follows the SQLite-documented
/// "12-step table-rebuild" recipe: disable foreign keys, BEGIN,
/// CREATE new, copy, DROP old, RENAME, foreign-key check, COMMIT,
/// re-enable foreign keys. Run inside `bootstrap_schema` under
/// the version gate, so this is a one-time hop per install.
fn rebuild_tags_without_inline_unique(conn: &Connection) -> Result<(), Error> {
    conn.inner()
        .execute_batch(
            r#"
            PRAGMA foreign_keys = OFF;
            BEGIN TRANSACTION;
            CREATE TABLE tags_new (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color TEXT,
                created_at INTEGER NOT NULL,
                deleted_at INTEGER NULL
            );
            INSERT INTO tags_new (id, name, color, created_at, deleted_at)
                SELECT id, name, color, created_at, deleted_at FROM tags;
            DROP TABLE tags;
            ALTER TABLE tags_new RENAME TO tags;
            COMMIT;
            PRAGMA foreign_keys = ON;
            "#,
        )
        .map_err(|e| Error::Db(format!("bootstrap schema: rebuild tags: {e}")))?;
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

/// Issue `ALTER TABLE <table> ADD COLUMN deleted_at INTEGER NULL`.
/// Called only on the v1/v2 → v3 upgrade hop (`bootstrap_schema`
/// gates it behind `(1..3).contains(&current)`); SQLite errors on
/// duplicate column names, so the structural shape — gate plus
/// one-shot — is the contract that keeps this safe to call without
/// a pre-existence probe.
fn add_deleted_at_column(conn: &Connection, table: &str) -> Result<(), Error> {
    let sql = format!("ALTER TABLE {table} ADD COLUMN deleted_at INTEGER NULL");
    conn.inner()
        .execute_batch(&sql)
        .map_err(|e| Error::Db(format!("bootstrap schema: add {table}.deleted_at: {e}")))
}

/// Issue `ALTER TABLE sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'ssh'`.
/// Called only on the v1..v4 → v5 upgrade hop. Same shape contract
/// as [`add_deleted_at_column`] — duplicate column is an error in
/// SQLite, so the gate plus one-shot keeps the bootstrap idempotent
/// across re-runs.
fn add_sessions_kind_column(conn: &Connection) -> Result<(), Error> {
    conn.inner()
        .execute_batch("ALTER TABLE sessions ADD COLUMN kind TEXT NOT NULL DEFAULT 'ssh'")
        .map_err(|e| Error::Db(format!("bootstrap schema: add sessions.kind: {e}")))
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
    deleted_at INTEGER NULL
);

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

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL DEFAULT '',
    folder_id TEXT,
    kind TEXT NOT NULL DEFAULT 'ssh',
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    user TEXT NOT NULL,
    auth_type TEXT NOT NULL DEFAULT 'password',
    password TEXT NOT NULL DEFAULT '',
    key_path TEXT NOT NULL DEFAULT '',
    key_data TEXT NOT NULL DEFAULT '',
    key_id TEXT,
    passphrase TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 0,
    notes TEXT NOT NULL DEFAULT '',
    last_connected_at INTEGER,
    extras TEXT NOT NULL DEFAULT '{}',
    via_session_id TEXT,
    via_host TEXT,
    via_port INTEGER,
    via_user TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL,
    FOREIGN KEY (key_id) REFERENCES ssh_keys(id) ON DELETE SET NULL,
    FOREIGN KEY (via_session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

-- WebDAV-specific configuration. Keyed by session id with ON DELETE
-- CASCADE so removing a session physically purges its WebDAV row;
-- soft-deletes on `sessions` leave this row in place until the
-- sync-merge purge removes the parent. Password / bearer token is
-- staged into the SecretStore under `session.webdav.<id>` rather
-- than persisted alongside the URL.
CREATE TABLE IF NOT EXISTS webdav_session_details (
    session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
    base_url TEXT NOT NULL,
    username TEXT NOT NULL DEFAULT '',
    auth_method TEXT NOT NULL,
    self_signed_fingerprint TEXT NULL
);
CREATE INDEX IF NOT EXISTS idx_webdav_session_details_session_id
    ON webdav_session_details(session_id);

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
CREATE INDEX IF NOT EXISTS idx_sessions_via_session_id
    ON sessions(via_session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_key_id
    ON sessions(key_id);
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

    /// v2 → v3 upgrade hop. A database stamped at v2 with the
    /// pre-v3 SCHEMA_SQL shape (no `deleted_at` column anywhere)
    /// must pick up the tombstone column on every soft-deletable
    /// table when `bootstrap_schema` runs. The fresh-install path
    /// already carries the column via `CREATE TABLE IF NOT
    /// EXISTS`, so the ALTER arm runs only when `current` lands
    /// in `[1, 3)` — verified here by simulating a v2 install
    /// (run the bootstrap on a fresh DB → rewind `user_version`
    /// to 2 → drop the `deleted_at` column from every tombstoned
    /// table) and re-running the bootstrap. Re-running is
    /// idempotent because the gate re-evaluates to false once
    /// the stamp lands at v3.
    #[test]
    fn bootstrap_v2_to_v3_adds_deleted_at_to_each_tombstone_table() {
        let conn = Connection::open_in_memory().unwrap();
        // Stand up the v3 schema, then strip the new column to
        // mimic a v2 install. `ALTER TABLE … DROP COLUMN` is
        // available on the SQLCipher 4.x build the repo ships
        // (sqlite3 >= 3.35.0). The rewind stamp drops the
        // version back to v2 so the upgrade arm runs again.
        bootstrap_schema(&conn).unwrap();
        // The partial-unique index on `tags(name)` references
        // `deleted_at`; SQLite refuses the column drop while the
        // index references it. Drop it first; the post-bootstrap
        // run recreates it via `create_partial_unique_indexes`.
        conn.inner()
            .execute_batch("DROP INDEX IF EXISTS idx_tags_name_live")
            .unwrap();
        for table in TOMBSTONE_TABLES {
            conn.inner()
                .execute_batch(&format!("DROP INDEX IF EXISTS idx_{table}_deleted_at"))
                .unwrap();
            conn.inner()
                .execute_batch(&format!("ALTER TABLE {table} DROP COLUMN deleted_at"))
                .unwrap();
        }
        // Drop the v5 `sessions.kind` column too — the rewind below
        // stamps user_version=2 and re-bootstrap will replay both
        // the v3 (deleted_at) and v5 (kind) ALTER arms; without
        // dropping `kind` here the v5 ALTER hits a duplicate-column
        // error.
        conn.inner()
            .execute_batch("ALTER TABLE sessions DROP COLUMN kind")
            .unwrap();
        conn.inner().pragma_update(None, "user_version", 2).unwrap();

        bootstrap_schema(&conn).unwrap();
        assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);

        // Every table now carries the column. The column probe
        // goes through `pragma_table_info` so a missing column
        // shows up as "column did not appear in pragma output".
        for table in TOMBSTONE_TABLES {
            let mut has_col = false;
            conn.inner()
                .pragma(None, "table_info", table, |row| {
                    let name: String = row.get("name")?;
                    if name == "deleted_at" {
                        has_col = true;
                    }
                    Ok(())
                })
                .unwrap();
            assert!(
                has_col,
                "{table} must carry deleted_at after v2 → v3 upgrade"
            );
        }

        // Re-running bootstrap is a no-op — the duplicate-column
        // failure would surface as `Error::Db("... duplicate
        // column name ...")` from the second ALTER hop. The
        // `current < SCHEMA_VERSION` gate is what keeps this
        // safe, and the test pins that contract.
        bootstrap_schema(&conn).unwrap();
        assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);
    }

    /// v4 → v5 upgrade hop. A database stamped at v4 with the
    /// pre-v5 sessions shape (no `kind` column) must pick up the
    /// column on bootstrap. Webdav_session_details lands via
    /// `CREATE TABLE IF NOT EXISTS` in `SCHEMA_SQL` and needs no
    /// per-step ALTER, so the test only inspects `sessions.kind`.
    #[test]
    fn bootstrap_v4_to_v5_adds_kind_column_to_sessions() {
        let conn = Connection::open_in_memory().unwrap();
        bootstrap_schema(&conn).unwrap();
        // Strip the kind column to mimic a v4 install. `ALTER TABLE …
        // DROP COLUMN` is available on the SQLCipher 4.x build
        // (sqlite3 >= 3.35.0). Rewind user_version to v4 so the
        // upgrade arm re-runs.
        conn.inner()
            .execute_batch("ALTER TABLE sessions DROP COLUMN kind")
            .unwrap();
        conn.inner().pragma_update(None, "user_version", 4).unwrap();

        bootstrap_schema(&conn).unwrap();
        assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);

        let mut has_kind = false;
        conn.inner()
            .pragma(None, "table_info", "sessions", |row| {
                let name: String = row.get("name")?;
                if name == "kind" {
                    has_kind = true;
                }
                Ok(())
            })
            .unwrap();
        assert!(has_kind, "sessions must carry kind after v4 → v5 upgrade");

        // Re-running bootstrap is a no-op — the duplicate-column
        // failure would surface as `Error::Db("... duplicate column
        // name ...")` from the second ALTER hop. The
        // `current < SCHEMA_VERSION` gate is what keeps this safe.
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
