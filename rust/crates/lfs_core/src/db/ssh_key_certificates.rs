//! SshKeyCertificates DAO — one OpenSSH certificate per stored
//! `ssh_keys` row. Backs the Dart key-manager "Import certificate"
//! flow.
//!
//! **Why a join table.** A certificate is meaningless without its
//! private key — the user presents `(key, cert)` together at userauth
//! time. Inlining the columns on `ssh_keys` would force every key
//! read to pay the BLOB column cost; the join keeps the listing path
//! lean and supports an absence (key without cert) as a clean row
//! gap rather than nullable column drift.
//!
//! `principals` and `critical_options` are stored as serialized JSON
//! so the DAO does not need a junction table for what is a tiny
//! opaque list / map per row. The DAO owns the JSON encode / decode
//! at the SQL boundary — callers receive [`CertRecord`] with typed
//! `Vec<String>` / `BTreeMap<String, String>` shapes and never see
//! the wire grammar. The cert blob itself stays as BLOB because
//! OpenSSH wire format is binary inside its base64 wrapper — the
//! typed view in `keys::CertSummary` is rebuilt from
//! `parse_openssh_cert` on read where the UI surfaces it.

use std::collections::BTreeMap;

use rusqlite::params;

use crate::db::DbAccess;
use crate::error::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CertRecord {
    pub key_id: String,
    pub certificate: Vec<u8>,
    /// Unix seconds (matches the cert's wire-format validity field).
    pub valid_after: i64,
    /// Unix seconds.
    pub valid_before: i64,
    /// Hosts / users the cert is valid for. Empty list means
    /// "valid for any principal" per OpenSSH's wire-format convention.
    pub principals: Vec<String>,
    /// `force-command` / `source-address` / any other openssh option
    /// name → value. `BTreeMap` so iteration order is stable for
    /// round-trip equality.
    pub critical_options: BTreeMap<String, String>,
    /// Display fingerprint of the certificate blob (`SHA256:<base64>`).
    pub fingerprint: String,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<CertRecord> {
    let principals_json: String = row.get("principals")?;
    let critical_json: String = row.get("critical_options")?;
    Ok(CertRecord {
        key_id: row.get("key_id")?,
        certificate: row.get("certificate")?,
        valid_after: row.get("valid_after")?,
        valid_before: row.get("valid_before")?,
        principals: decode_principals(&principals_json),
        critical_options: decode_critical_options(&critical_json),
        fingerprint: row.get("fingerprint")?,
    })
}

/// Decode the `principals` column. A malformed value (tampered DB
/// row, manual edit, future-schema drift) folds to the empty list
/// so a single bad row never sinks the whole listing.
fn decode_principals(raw: &str) -> Vec<String> {
    if raw.is_empty() {
        return Vec::new();
    }
    serde_json::from_str::<Vec<String>>(raw).unwrap_or_default()
}

/// Decode the `critical_options` column. A malformed value folds to
/// the empty map. The OpenSSH cert format orders critical options
/// lexicographically; the `BTreeMap` collect preserves that
/// stability so round-trip equality holds.
fn decode_critical_options(raw: &str) -> BTreeMap<String, String> {
    if raw.is_empty() {
        return BTreeMap::new();
    }
    serde_json::from_str::<BTreeMap<String, String>>(raw).unwrap_or_default()
}

/// Encode the `principals` column. Always emits a valid JSON array.
fn encode_principals(principals: &[String]) -> String {
    serde_json::to_string(principals).unwrap_or_else(|_| "[]".to_string())
}

/// Encode the `critical_options` column. Always emits a valid JSON
/// object; the `BTreeMap` keeps key order stable.
fn encode_critical_options(critical: &BTreeMap<String, String>) -> String {
    serde_json::to_string(critical).unwrap_or_else(|_| "{}".to_string())
}

/// Look up the certificate row paired with `key_id`. Returns `None`
/// when the key has no certificate attached — that's the common
/// case, not an error.
pub fn get(conn: &impl DbAccess, key_id: &str) -> Result<Option<CertRecord>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT key_id, certificate, valid_after, valid_before, \
                    principals, critical_options, fingerprint \
             FROM ssh_key_certificates WHERE key_id = ?1",
        )
        .map_err(|e| Error::Db(format!("ssh_key_certificates get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![key_id], row_from)
        .map_err(|e| Error::Db(format!("ssh_key_certificates get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Db(format!("ssh_key_certificates get row: {e}"))),
        None => Ok(None),
    }
}

/// Insert or replace the cert row for `rec.key_id`. The DAO does not
/// validate that the cert and its paired key match — that's the
/// caller's job (the key-manager UI compares fingerprints before
/// calling here so a mismatch surfaces as a localized error rather
/// than a connect-time auth failure).
pub fn upsert(conn: &impl DbAccess, rec: &CertRecord) -> Result<(), Error> {
    let principals_json = encode_principals(&rec.principals);
    let critical_json = encode_critical_options(&rec.critical_options);
    conn.raw()
        .execute(
            "INSERT INTO ssh_key_certificates (\
                 key_id, certificate, valid_after, valid_before, \
                 principals, critical_options, fingerprint\
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
             ON CONFLICT(key_id) DO UPDATE SET \
               certificate = excluded.certificate, \
               valid_after = excluded.valid_after, \
               valid_before = excluded.valid_before, \
               principals = excluded.principals, \
               critical_options = excluded.critical_options, \
               fingerprint = excluded.fingerprint",
            params![
                rec.key_id,
                rec.certificate,
                rec.valid_after,
                rec.valid_before,
                principals_json,
                critical_json,
                rec.fingerprint,
            ],
        )
        .map_err(|e| Error::Db(format!("ssh_key_certificates upsert: {e}")))?;
    Ok(())
}

/// Remove the certificate paired with `key_id`. Returns the number
/// of rows affected — `0` when no cert was attached (idempotent).
pub fn delete(conn: &impl DbAccess, key_id: &str) -> Result<usize, Error> {
    let n = conn
        .raw()
        .execute(
            "DELETE FROM ssh_key_certificates WHERE key_id = ?1",
            params![key_id],
        )
        .map_err(|e| Error::Db(format!("ssh_key_certificates delete: {e}")))?;
    Ok(n)
}

/// Every certificate row, ordered by `key_id`. Used by archive
/// export / a future "all certs" diagnostic view. Order is stable
/// across calls so dedup paths can binary-search the listing.
pub fn list_all(conn: &impl DbAccess) -> Result<Vec<CertRecord>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT key_id, certificate, valid_after, valid_before, \
                    principals, critical_options, fingerprint \
             FROM ssh_key_certificates ORDER BY key_id ASC",
        )
        .map_err(|e| Error::Db(format!("ssh_key_certificates list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("ssh_key_certificates list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("ssh_key_certificates list row: {e}")))?);
    }
    Ok(out)
}

/// Canonical SecretStore id under which a cert blob is staged for
/// the connect path. Mirrors `private_key_secret_id` / the
/// `sess.<slot>.<id>` namespace pattern so the staging audit
/// (`SecretStore::list_ids`) sees a uniform shape.
pub fn certificate_secret_id(key_id: &str) -> String {
    format!("key.cert.{key_id}")
}

/// Read the cert blob for `key_id` and push it into the process-
/// singleton SecretStore under [`certificate_secret_id`]. Returns
/// `Ok(true)` when bytes landed in the store, `Ok(false)` when the
/// key has no cert attached. The bytes themselves are not sensitive
/// in the same way the private PEM is — a certificate is the public
/// half — but routing through SecretStore keeps the connect cascade
/// symmetric with `ssh_keys::stage_secret_into_store` and removes
/// the temptation to round-trip the cert through the Dart heap on
/// the connect path.
pub fn stage_secret_into_store(conn: &impl DbAccess, key_id: &str) -> Result<bool, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached("SELECT certificate FROM ssh_key_certificates WHERE key_id = ?1")
        .map_err(|e| Error::Db(format!("ssh_key_certificates stage prepare: {e}")))?;
    let blob: Option<Vec<u8>> = stmt.query_row(params![key_id], |row| row.get(0)).ok();
    let Some(bytes) = blob else {
        return Ok(false);
    };
    if bytes.is_empty() {
        return Ok(false);
    }
    let store = &crate::app::instance().secrets;
    store.put(&certificate_secret_id(key_id), &bytes);
    Ok(true)
}
#[cfg(test)]
#[path = "../../tests/unit/db_ssh_key_certificates.rs"]
mod tests;
