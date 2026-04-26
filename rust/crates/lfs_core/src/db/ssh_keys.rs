//! SshKeys DAO. Backs the Dart `KeyStore` over FRB.
//!
//! **Secret-store angle**: `private_key` is sensitive PEM text. The
//! [`stage_secret_into_store`] helper reads it inside Rust and pushes
//! it directly into the process-singleton SecretStore so the Dart
//! connect path can resolve a saved key by id without ever
//! materialising the bytes on the Dart heap.

use rusqlite::{params, Connection};
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

pub fn list_all(conn: &Connection) -> Result<Vec<SshKeyRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys ORDER BY created_at DESC",
        )
        .map_err(|e| Error::Io(format!("ssh_keys list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("ssh_keys list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("ssh_keys row: {e}")))?);
    }
    Ok(out)
}

pub fn get(conn: &Connection, id: &str) -> Result<Option<SshKeyRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys WHERE id = ?1",
        )
        .map_err(|e| Error::Io(format!("ssh_keys get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![id], row_from)
        .map_err(|e| Error::Io(format!("ssh_keys get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Io(format!("ssh_keys get row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &Connection, row: &SshKeyRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO ssh_keys (id, label, private_key, public_key, key_type, is_generated, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
         ON CONFLICT(id) DO UPDATE SET \
           label = excluded.label, \
           private_key = excluded.private_key, \
           public_key = excluded.public_key, \
           key_type = excluded.key_type, \
           is_generated = excluded.is_generated, \
           created_at = excluded.created_at",
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
    .map_err(|e| Error::Io(format!("ssh_keys upsert: {e}")))?;
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

pub fn list_metadata(conn: &Connection) -> Result<Vec<SshKeyMetadata>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys ORDER BY created_at DESC",
        )
        .map_err(|e| Error::Io(format!("ssh_keys list_metadata prepare: {e}")))?;
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
        .map_err(|e| Error::Io(format!("ssh_keys list_metadata query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("ssh_keys list_metadata row: {e}")))?);
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

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    let n = conn
        .execute("DELETE FROM ssh_keys WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("ssh_keys delete: {e}")))?;
    Ok(n)
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
pub fn stage_secret_into_store(conn: &Connection, key_id: &str) -> Result<bool, Error> {
    let mut stmt = conn
        .prepare("SELECT private_key FROM ssh_keys WHERE id = ?1")
        .map_err(|e| Error::Io(format!("ssh_keys stage prepare: {e}")))?;
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
