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
mod tests {
    use super::*;
    use crate::db::{bootstrap_schema, ssh_keys, Connection, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn seed_key(db: &Db, id: &str) {
        db.with_conn(|c| {
            ssh_keys::upsert(
                c,
                &ssh_keys::SshKeyRow {
                    id: id.into(),
                    label: "lab".into(),
                    private_key: "PRIV".into(),
                    public_key: "ssh-ed25519 AAAA".into(),
                    key_type: "ssh-ed25519".into(),
                    is_generated: false,
                    created_at_ms: 0,
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
                },
            )
        })
        .unwrap();
    }

    fn cert(key_id: &str) -> CertRecord {
        let mut critical = BTreeMap::new();
        critical.insert("force-command".to_string(), "echo hi".to_string());
        CertRecord {
            key_id: key_id.into(),
            certificate: vec![0xDE, 0xAD, 0xBE, 0xEF],
            valid_after: 1_700_000_000,
            valid_before: 1_700_086_400,
            principals: vec!["alice".to_string(), "root".to_string()],
            critical_options: critical,
            fingerprint: "SHA256:abc".into(),
        }
    }

    #[test]
    fn upsert_then_get_round_trips_every_field() {
        let db = db();
        seed_key(&db, "k1");
        db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
        let got = db.with_conn(|c| get(c, "k1")).unwrap().unwrap();
        assert_eq!(got, cert("k1"));
    }

    #[test]
    fn get_returns_none_when_no_cert_attached() {
        let db = db();
        seed_key(&db, "k1");
        assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_none());
    }

    #[test]
    fn upsert_replaces_existing_row_for_same_key() {
        let db = db();
        seed_key(&db, "k1");
        db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
        let updated = CertRecord {
            certificate: vec![0x01, 0x02],
            valid_before: 2_000_000_000,
            fingerprint: "SHA256:def".into(),
            ..cert("k1")
        };
        db.with_conn(|c| upsert(c, &updated)).unwrap();
        let got = db.with_conn(|c| get(c, "k1")).unwrap().unwrap();
        assert_eq!(got.certificate, vec![0x01, 0x02]);
        assert_eq!(got.valid_before, 2_000_000_000);
        assert_eq!(got.fingerprint, "SHA256:def");
    }

    #[test]
    fn delete_returns_one_when_row_existed_zero_when_absent() {
        let db = db();
        seed_key(&db, "k1");
        db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
        let n = db.with_conn(|c| delete(c, "k1")).unwrap();
        assert_eq!(n, 1);
        let n = db.with_conn(|c| delete(c, "k1")).unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn cascade_delete_drops_cert_when_parent_key_is_purged() {
        // The FK declares ON DELETE CASCADE so the join row never
        // outlives its parent's physical removal. `ssh_keys::delete`
        // soft-deletes the parent under the v3 tombstone contract,
        // so the cert survives until the sync-purge runs through
        // `ssh_keys::purge_tombstones`. Once the parent leaves the
        // table for good, the cascade physically drops the cert.
        let db = db();
        seed_key(&db, "k1");
        db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
        db.with_conn(|c| ssh_keys::delete(c, "k1")).unwrap();
        // Cert still present while the parent key is tombstoned.
        assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_some());
        // Physical purge of the parent fires the cascade.
        db.with_conn(|c| ssh_keys::purge_tombstones(c, i64::MAX))
            .unwrap();
        assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_none());
    }

    #[test]
    fn list_all_orders_by_key_id_ascending() {
        let db = db();
        seed_key(&db, "k1");
        seed_key(&db, "k2");
        seed_key(&db, "k3");
        db.with_conn(|c| upsert(c, &cert("k2"))).unwrap();
        db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
        db.with_conn(|c| upsert(c, &cert("k3"))).unwrap();
        let all = db.with_conn(list_all).unwrap();
        assert_eq!(
            all.iter().map(|r| r.key_id.as_str()).collect::<Vec<_>>(),
            vec!["k1", "k2", "k3"]
        );
    }

    #[test]
    fn certificate_secret_id_is_stable() {
        // Connect-path callers compose the id; the canonical form
        // belongs to one place so a staging audit can grep for it.
        assert_eq!(certificate_secret_id("abc"), "key.cert.abc");
    }
}
