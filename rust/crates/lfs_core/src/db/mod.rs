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

// Re-exported as the public DAO closure parameter type. The
// rusqlite ABI is intentionally part of the `lfs_core::db`
// public surface: every DAO under `db/*.rs` calls `prepare`,
// `query_row`, `transaction`, etc. directly, and the `run_db_*`
// helpers in `lfs_frb::api::db` thread the type through their
// `FnOnce(&Connection) -> Result<_, Error>` bound. Wrapping in a
// newtype was considered (audit B-WS-4) but would require either
// re-exposing every rusqlite method as a pass-through (~40+
// methods across `Connection` + `Transaction`) or routing every
// DAO query through a typed builder, neither of which carry
// daily benefit beyond the documentation we add here. The
// alternative — `pub(crate) use` — would force `lfs_frb`'s
// generic helpers to either inline into `lfs_core` or clone the
// dispatch boilerplate per DAO; both regress the layer split.
pub use rusqlite::Connection;
use zeroize::Zeroizing;

use crate::error::Error;

pub mod app_configs;
pub mod folders;
pub mod known_hosts;
pub mod port_forwards;
pub mod sessions;
pub mod sftp_bookmarks;
pub mod snippets;
pub mod ssh_keys;
pub mod tags;

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
            conn.execute_batch(&pragma)
                .map_err(|e| Error::Db(format!("PRAGMA key: {e}")))?;
            conn.execute_batch("PRAGMA cipher_compatibility = 4")
                .map_err(|e| Error::Db(format!("PRAGMA cipher_compatibility: {e}")))?;
            crate::app_log_info!(
                "DbOpen",
                "db open phase=pragma_key elapsed={}ms",
                t0.elapsed().as_millis()
            );
        }
        // Smoke test the key by touching the schema table.
        conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
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
        conn.execute_batch("PRAGMA foreign_keys = ON")
            .map_err(|e| Error::Db(format!("PRAGMA foreign_keys: {e}")))?;
        // WAL journal — concurrent readers don't block the writer,
        // crash recovery is faster, and the wipe registry already
        // lists `letsflutssh.db-wal` / `-shm` so the cleanup contract
        // exists for it. NORMAL fsync is the WAL-paired default
        // (DELETE-mode FULL is the historic default, the standard
        // SQLite recommendation pairs WAL with NORMAL).
        conn.execute_batch("PRAGMA journal_mode = WAL")
            .map_err(|e| Error::Db(format!("PRAGMA journal_mode = WAL: {e}")))?;
        conn.execute_batch("PRAGMA synchronous = NORMAL")
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
        g.query_row("SELECT count(*) FROM sqlite_master", [], |row| row.get(0))
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
        g.execute_batch(&pragma)
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
/// real anchor.
pub const SCHEMA_VERSION: i32 = 1;

/// Create every table the DAOs expect, idempotently, and stamp
/// `PRAGMA user_version = SCHEMA_VERSION` if and only if the DB
/// is fresh (current value `0`). The unconditional stamp the
/// audit flagged would silently downgrade a future schema bump:
/// if a user opened a v2 DB with a v1 build, the stamp would
/// rewrite `user_version` to 1 and the next v2 build would mistake
/// the file for a v1 install needing a forward migration that
/// already ran. Tables are `CREATE IF NOT EXISTS` so the call is
/// safe to re-run on every open.
pub(crate) fn bootstrap_schema(conn: &Connection) -> Result<(), Error> {
    conn.execute_batch(SCHEMA_SQL)
        .map_err(|e| Error::Db(format!("bootstrap schema: {e}")))?;
    let mut current: i32 = 0;
    conn.pragma_query(None, "user_version", |row| {
        current = row.get::<_, i32>(0)?;
        Ok(())
    })
    .map_err(|e| Error::Db(format!("bootstrap schema: read user_version: {e}")))?;
    if current == 0 {
        conn.pragma_update(None, "user_version", SCHEMA_VERSION)
            .map_err(|e| Error::Db(format!("bootstrap schema: stamp user_version: {e}")))?;
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
    conn.pragma_query(None, "user_version", |row| {
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
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL DEFAULT '',
    folder_id TEXT,
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
    FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL,
    FOREIGN KEY (key_id) REFERENCES ssh_keys(id) ON DELETE SET NULL,
    FOREIGN KEY (via_session_id) REFERENCES sessions(id) ON DELETE SET NULL
);

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
    name TEXT NOT NULL UNIQUE,
    color TEXT,
    created_at INTEGER NOT NULL
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
    updated_at INTEGER NOT NULL
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
        conn.execute_batch("CREATE TABLE t (x INT)").unwrap();
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

    /// Bootstrap schema + ssh_keys round-trip on an in-memory DB.
    /// Confirms the SQL strings parse and the column shapes match.
    #[test]
    fn ssh_keys_round_trip_in_memory() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON").unwrap();
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
        conn.execute_batch("PRAGMA foreign_keys = ON").unwrap();
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
