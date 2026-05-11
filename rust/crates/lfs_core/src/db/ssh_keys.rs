//! SshKeys DAO. Backs the Dart `KeyStore` over FRB.
//!
//! **Secret-store angle**: `private_key` is sensitive PEM text. The
//! [`stage_secret_into_store`] helper reads it inside Rust and pushes
//! it directly into the process-singleton SecretStore so the Dart
//! connect path can resolve a saved key by id without ever
//! materialising the bytes on the Dart heap.

use crate::db::Connection;
use rusqlite::params;
use sha2::{Digest, Sha256};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct SshKeyRow {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    /// Unix-millis at create time. The drift schema stores a
    /// DateTime value as INTEGER milliseconds-since-epoch via
    /// `DateTimeColumn`'s default mapping.
    pub created_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SshKeyRow> {
    Ok(SshKeyRow {
        id: row.get("id")?,
        label: row.get("label")?,
        private_key: row.get("private_key")?,
        public_key: row.get("public_key")?,
        key_type: row.get("key_type")?,
        // drift maps Bool to int 0/1
        is_generated: row.get::<_, i64>("is_generated")? != 0,
        created_at_ms: row.get("created_at")?,
    })
}

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<SshKeyRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys WHERE deleted_at IS NULL ORDER BY created_at DESC",
        )
        .map_err(|e| Error::Db(format!("ssh_keys list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("ssh_keys list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("ssh_keys row: {e}")))?);
    }
    Ok(out)
}

pub fn get(conn: &impl crate::db::DbAccess, id: &str) -> Result<Option<SshKeyRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys WHERE id = ?1 AND deleted_at IS NULL",
        )
        .map_err(|e| Error::Db(format!("ssh_keys get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![id], row_from)
        .map_err(|e| Error::Db(format!("ssh_keys get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Db(format!("ssh_keys get row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &SshKeyRow) -> Result<(), Error> {
    conn.raw().execute(
        "INSERT INTO ssh_keys (id, label, private_key, public_key, key_type, is_generated, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
         ON CONFLICT(id) DO UPDATE SET \
           label = excluded.label, \
           private_key = excluded.private_key, \
           public_key = excluded.public_key, \
           key_type = excluded.key_type, \
           is_generated = excluded.is_generated, \
           created_at = excluded.created_at, \
           deleted_at = NULL",
        params![
            row.id,
            row.label,
            row.private_key,
            row.public_key,
            row.key_type,
            if row.is_generated { 1 } else { 0 },
            row.created_at_ms,
        ],
    )
    .map_err(|e| Error::Db(format!("ssh_keys upsert: {e}")))?;
    Ok(())
}

/// Listing-only view of an `ssh_keys` row. Carries the metadata
/// needed by the key manager / import-dedup / export-selection UIs
/// **without** the `private_key` PEM bytes. `private_fingerprint`
/// and `public_fingerprint` are pre-hashed inside Rust so that
/// dedup paths (`SshDirImportDialog`, etc.) can compare against
/// scanned key material without ever pulling the PEM through the
/// FRB boundary.
#[derive(Debug, Clone)]
pub struct SshKeyMetadata {
    pub id: String,
    pub label: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
    /// SHA-256 hex of the normalized PEM (trimmed, CRLF→LF), or the
    /// empty string if the row has no private key. Mirrors
    /// `KeyStore.privateKeyFingerprint` exactly so existing dedup
    /// sets continue to compare against scanned PEMs.
    pub private_fingerprint: String,
    /// SHA-256 hex of the normalized OpenSSH public key, or the
    /// empty string if the row has no public half. Mirrors
    /// `KeyStore.publicKeyFingerprint`.
    pub public_fingerprint: String,
}

pub fn list_metadata(conn: &impl crate::db::DbAccess) -> Result<Vec<SshKeyMetadata>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys WHERE deleted_at IS NULL ORDER BY created_at DESC",
        )
        .map_err(|e| Error::Db(format!("ssh_keys list_metadata prepare: {e}")))?;
    let rows = stmt
        .query_map([], |row| {
            let private_key: String = row.get("private_key")?;
            let public_key: String = row.get("public_key")?;
            Ok(SshKeyMetadata {
                id: row.get("id")?,
                label: row.get("label")?,
                key_type: row.get("key_type")?,
                is_generated: row.get::<_, i64>("is_generated")? != 0,
                created_at_ms: row.get("created_at")?,
                private_fingerprint: normalized_sha256_hex(&private_key),
                public_fingerprint: normalized_sha256_hex(&public_key),
                public_key,
            })
        })
        .map_err(|e| Error::Db(format!("ssh_keys list_metadata query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("ssh_keys list_metadata row: {e}")))?);
    }
    Ok(out)
}

/// Mirrors `KeyStore.privateKeyFingerprint` /
/// `KeyStore.publicKeyFingerprint`: trim, CRLF→LF, SHA-256 hex.
/// Empty input returns an empty string so set-membership checks
/// don't false-match on missing keys.
fn normalized_sha256_hex(s: &str) -> String {
    let normalized = s.replace("\r\n", "\n");
    let trimmed = normalized.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut hasher = Sha256::new();
    hasher.update(trimmed.as_bytes());
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(digest.len() * 2);
    for b in digest.iter() {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

/// Replace the live `ssh_keys` set with `rows` inside a single
/// transaction. Used by `KeysNotifier.saveAll` in place of N
/// delete + N upsert FRB hops — the per-row hop is the dominant
/// cost when the notifier flushes its in-memory cache.
///
/// Soft-delete shape: the clearing step tombstones every live
/// row, then each row in `rows` is upserted with
/// `deleted_at = NULL` so collisions revive existing keys rather
/// than fail the insert. The net effect on `list_all` is the same
/// as the old physical-delete model — only the supplied set is
/// visible afterwards — but the residual tombstones let a
/// sync-merge replay the removal across devices. Physical
/// teardown of the tombstones runs through
/// [`purge_tombstones`].
///
/// Atomicity: the tombstone + upserts run inside a single
/// `conn.inner_mut().transaction()`; a failure mid-loop rolls
/// back so the table never lands half-cleared.
pub fn replace_all(conn: &mut Connection, rows: &[SshKeyRow]) -> Result<(), Error> {
    let now_ms = now_unix_ms();
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("ssh_keys replace_all: begin tx: {e}")))?;
    tx.execute(
        "UPDATE ssh_keys SET deleted_at = ?1 WHERE deleted_at IS NULL",
        params![now_ms],
    )
    .map_err(|e| Error::Db(format!("ssh_keys replace_all: tombstone: {e}")))?;
    {
        let mut stmt = tx
            .prepare_cached(
                "INSERT INTO ssh_keys (id, label, private_key, public_key, key_type, is_generated, created_at) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
                 ON CONFLICT(id) DO UPDATE SET \
                   label = excluded.label, \
                   private_key = excluded.private_key, \
                   public_key = excluded.public_key, \
                   key_type = excluded.key_type, \
                   is_generated = excluded.is_generated, \
                   created_at = excluded.created_at, \
                   deleted_at = NULL",
            )
            .map_err(|e| Error::Db(format!("ssh_keys replace_all: prepare insert: {e}")))?;
        for row in rows {
            stmt.execute(params![
                row.id,
                row.label,
                row.private_key,
                row.public_key,
                row.key_type,
                if row.is_generated { 1 } else { 0 },
                row.created_at_ms,
            ])
            .map_err(|e| Error::Db(format!("ssh_keys replace_all: insert: {e}")))?;
        }
    }
    tx.commit()
        .map_err(|e| Error::Db(format!("ssh_keys replace_all: commit: {e}")))?;
    Ok(())
}

/// Soft-delete a single stored key by id. Flips `deleted_at` to
/// `now_unix_ms()`; the row survives so the sync-merge layer
/// (`§8b`) can replay the deletion. `ON DELETE CASCADE` on
/// `ssh_key_certificates.key_id` is preserved because the
/// physical row is not removed — the cert table is kept in
/// lock-step manually wherever the connect path resolves the
/// key; see ARCHITECTURE.md §11.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE ssh_keys SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("ssh_keys delete: {e}")))?;
    Ok(n)
}

/// Physically remove `ssh_keys` rows whose `deleted_at` is older
/// than `before_ms`. Reserved for sync-merge teardown (`§8b`);
/// production paths use [`delete`] / [`replace_all`].
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM ssh_keys WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("ssh_keys purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Composite import — looks up an existing key by content
/// fingerprint (public-key first, falling back to private-key);
/// returns the existing id when a match is found. Otherwise mints
/// a new id (when the proposed id collides with a stored key) and
/// inserts a fresh row under a unique-suffixed label. All in one
/// transaction.
///
/// Returns the id the caller should use downstream (existing or
/// freshly inserted). Mirrors the Dart
/// `KeyStore.importForMerge` orchestration; folding the steps
/// Rust-side keeps the dedup-by-fingerprint + label-uniqueness +
/// insert sequence atomic and lets the Dart caller drop to a
/// single FRB call.
pub fn import_key_for_merge(conn: &mut Connection, proposed: &SshKeyRow) -> Result<String, Error> {
    use rand::RngCore;
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("ssh_keys import_for_merge tx: {e}")))?;

    let public_target = crate::keys::normalized_text_fingerprint(&proposed.public_key);
    let private_target = crate::keys::normalized_text_fingerprint(&proposed.private_key);

    // Two-phase fingerprint lookup mirrors the Dart side: public
    // wins (cheap, never touches private material); private is the
    // fallback for stored rows that have no public key.
    let metadata = list_metadata(&tx)?;
    if !public_target.is_empty() {
        if let Some(found) = metadata
            .iter()
            .find(|m| m.public_fingerprint == public_target)
        {
            return Ok(found.id.clone());
        }
    } else if !private_target.is_empty() {
        if let Some(found) = metadata
            .iter()
            .find(|m| m.private_fingerprint == private_target)
        {
            return Ok(found.id.clone());
        }
    }

    // No content match — insert a fresh row. Uniqueify the label
    // against the live set, mint a new id when the proposed id
    // collides with a stored key.
    let labels: std::collections::HashSet<String> =
        metadata.iter().map(|m| m.label.clone()).collect();
    let new_label = crate::sessions::unique_label(&proposed.label, &labels);
    let id_collision = metadata.iter().any(|m| m.id == proposed.id);
    let new_id = if id_collision {
        let mut bytes = [0u8; 16];
        rand::rngs::OsRng.fill_bytes(&mut bytes);
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    } else {
        proposed.id.clone()
    };

    upsert(
        &tx,
        &SshKeyRow {
            id: new_id.clone(),
            label: new_label,
            private_key: proposed.private_key.clone(),
            public_key: proposed.public_key.clone(),
            key_type: proposed.key_type.clone(),
            is_generated: proposed.is_generated,
            created_at_ms: proposed.created_at_ms,
        },
    )?;
    tx.commit()
        .map_err(|e| Error::Db(format!("ssh_keys import_for_merge commit: {e}")))?;
    Ok(new_id)
}

/// Canonical secret-store id for a stored key's private PEM bytes.
/// Mirrors the `sess.<slot>.<id>` pattern used by the sessions DAO.
pub fn private_key_secret_id(key_id: &str) -> String {
    format!("key.priv.{key_id}")
}

/// Read `private_key` for [`key_id`] and push its bytes into the
/// process-singleton SecretStore under [`private_key_secret_id`].
/// Returns `Ok(true)` when something landed in the store, `Ok(false)`
/// when the row is missing or the column is empty. Plaintext never
/// crosses the FRB boundary back to Dart — the Dart connect path
/// only sees the secret id and constructs the matching
/// `SshAuthPubkeyRef` variant.
pub fn stage_secret_into_store(
    conn: &impl crate::db::DbAccess,
    key_id: &str,
) -> Result<bool, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached("SELECT private_key FROM ssh_keys WHERE id = ?1 AND deleted_at IS NULL")
        .map_err(|e| Error::Db(format!("ssh_keys stage prepare: {e}")))?;
    let private_key: Option<String> = stmt.query_row(params![key_id], |row| row.get(0)).ok();
    let Some(pem) = private_key else {
        return Ok(false);
    };
    if pem.is_empty() {
        return Ok(false);
    }
    let store = &crate::app::instance().secrets;
    store.put(&private_key_secret_id(key_id), pem.as_bytes());
    Ok(true)
}

#[cfg(test)]
mod import_for_merge_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn key(id: &str, label: &str, public: &str, private: &str) -> SshKeyRow {
        SshKeyRow {
            id: id.into(),
            label: label.into(),
            private_key: private.into(),
            public_key: public.into(),
            key_type: "ed25519".into(),
            is_generated: false,
            created_at_ms: 0,
        }
    }

    #[test]
    fn import_for_merge_returns_existing_id_on_public_match() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("existing", "lab", "PUB1\n", "PRIV1")))
            .unwrap();
        let proposed = key("imported", "Different label", "PUB1", "PRIV1");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_eq!(id, "existing");
        // Stored row count unchanged.
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn import_for_merge_inserts_when_no_match() {
        let db = db();
        let proposed = key("imported-id", "lab", "PUB-NEW", "PRIV-NEW");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_eq!(id, "imported-id");
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].public_key, "PUB-NEW");
    }

    #[test]
    fn import_for_merge_uniqueifies_label_against_taken_set() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("e1", "Web", "PUB1", "PRIV1")))
            .unwrap();
        let proposed = key("imported", "Web", "PUB-DIFF", "PRIV-DIFF");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        let rows = db.with_conn(list_all).unwrap();
        let inserted = rows.iter().find(|r| r.id == id).unwrap();
        assert_eq!(inserted.label, "Web (copy)");
    }

    #[test]
    fn import_for_merge_mints_new_id_on_id_collision() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("collision", "Web", "PUB1", "PRIV1")))
            .unwrap();
        let proposed = key("collision", "Other", "PUB-NEW", "PRIV-NEW");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_ne!(id, "collision");
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 2);
    }

    #[test]
    fn import_for_merge_falls_back_to_private_when_public_empty() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("e1", "lab", "", "PRIV-MATCH")))
            .unwrap();
        let proposed = key("imported", "lab2", "", "PRIV-MATCH");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_eq!(id, "e1");
    }
}

#[cfg(test)]
mod tombstone_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn seed(db: &Db, id: &str) {
        db.with_conn(|c| {
            upsert(
                c,
                &SshKeyRow {
                    id: id.into(),
                    label: id.into(),
                    private_key: "PRIV".into(),
                    public_key: "PUB".into(),
                    key_type: "ed25519".into(),
                    is_generated: false,
                    created_at_ms: 0,
                },
            )
        })
        .unwrap();
    }

    fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
        db.with_conn(|c| {
            let row: Option<i64> = c
                .raw()
                .query_row(
                    "SELECT deleted_at FROM ssh_keys WHERE id = ?1",
                    params![id],
                    |r| r.get(0),
                )
                .ok()
                .flatten();
            Ok(row)
        })
        .unwrap()
    }

    #[test]
    fn delete_writes_tombstone_instead_of_removing_row() {
        let db = db();
        seed(&db, "k1");
        let n = db.with_conn(|c| delete(c, "k1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "k1").is_some());
    }

    #[test]
    fn list_all_and_get_skip_tombstoned_rows() {
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
        assert!(db.with_conn(|c| get(c, "dead")).unwrap().is_none());
    }

    #[test]
    fn list_metadata_skips_tombstoned_rows() {
        // list_metadata also filters — dedup paths must not match
        // against tombstoned keys.
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_metadata).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        seed(&db, "k1");
        db.with_conn(|c| delete(c, "k1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "k1").is_none());
    }

    #[test]
    fn replace_all_tombstones_old_rows_and_revives_collisions() {
        // replace_all's clearing step tombstones every live row;
        // the upsert loop revives any id in the new set, leaving
        // the rest visibly gone but available for sync replay.
        let db = db();
        seed(&db, "kept");
        seed(&db, "purged");
        let new_set = vec![SshKeyRow {
            id: "kept".into(),
            label: "renamed".into(),
            private_key: "PRIV2".into(),
            public_key: "PUB2".into(),
            key_type: "ed25519".into(),
            is_generated: true,
            created_at_ms: 0,
        }];
        db.with_conn_mut(|c| replace_all(c, &new_set)).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "kept");
        assert_eq!(rows[0].label, "renamed");
        assert!(raw_deleted_at(&db, "kept").is_none());
        assert!(raw_deleted_at(&db, "purged").is_some());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        seed(&db, "k1");
        db.with_conn(|c| delete(c, "k1")).unwrap();
        seed(&db, "k1");
        assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_some());
        assert!(raw_deleted_at(&db, "k1").is_none());
    }
}
