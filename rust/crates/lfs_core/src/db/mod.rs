//! SQLite + SQLCipher database handle.
//!
//! Opens an encrypted sqlite file under `bundled-sqlcipher`
//! (SQLCipher 4.x, AES-256-CBC). **Important cipher caveat**: the
//! drift+sqlite3_flutter_libs side runs SQLite3MultipleCiphers with
//! its built-in default scheme (ChaCha20-Poly1305), NOT real
//! SQLCipher. The two cipher families are wire-incompatible —
//! rusqlite cannot read drift's existing `db.sqlite` directly. While
//! both engines coexist:
//!   1. Rust opens a separate file (`lfs_core.db`) alongside drift's,
//!      keyed off the same master key.
//!   2. A one-shot migration helper reads each drift table through
//!      drift, writes the matching rusqlite tables.
//!   3. Once all DAOs flip to the Rust file, drift retires and its
//!      file is deleted.
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
        let conn = Connection::open(path).map_err(|e| Error::Io(format!("db open: {e}")))?;
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
                .map_err(|e| Error::Io(format!("PRAGMA key: {e}")))?;
            conn.execute_batch("PRAGMA cipher_compatibility = 4")
                .map_err(|e| Error::Io(format!("PRAGMA cipher_compatibility: {e}")))?;
        }
        // Smoke test the key by touching the schema table.
        conn.query_row("SELECT count(*) FROM sqlite_master", [], |row| {
            row.get::<_, i64>(0)
        })
        .map_err(|e| Error::Io(format!("schema probe: {e}")))?;
        // Enable foreign-key enforcement (drift sets this too) so
        // ON DELETE CASCADE / SET NULL behave consistently across
        // both engines while the migration is mid-flight.
        conn.execute_batch("PRAGMA foreign_keys = ON")
            .map_err(|e| Error::Io(format!("PRAGMA foreign_keys: {e}")))?;
        bootstrap_schema(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    /// Smoke-test query the FRB adapter calls during init to verify
    /// the connection is alive. Returns the count of rows in
    /// `sqlite_master` (i.e. table count + index count).
    pub fn schema_object_count(&self) -> Result<i64, Error> {
        let g = self.conn.lock().expect("db lock");
        g.query_row("SELECT count(*) FROM sqlite_master", [], |row| row.get(0))
            .map_err(|e| Error::Io(format!("schema count: {e}")))
    }

    /// Re-encrypt every page under `new_key`. Mirrors drift-side
    /// `rekeyDatabase` so the security-tier switcher can rekey
    /// drift's `letsflutssh.db` and lfs_core's `lfs_core.db` in
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
        let g = self.conn.lock().expect("db lock");
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
        let g = self.conn.lock().expect("db lock");
        f(&g)
    }
}

/// Create every table the DAOs expect, idempotently. Mirrors the
/// drift schema column-for-column. The data migration tool reads
/// from drift's `db.sqlite` (via Dart) and writes through these
/// tables; once that lands the drift Daos retire.
fn bootstrap_schema(conn: &Connection) -> Result<(), Error> {
    conn.execute_batch(SCHEMA_SQL)
        .map_err(|e| Error::Io(format!("bootstrap schema: {e}")))
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
