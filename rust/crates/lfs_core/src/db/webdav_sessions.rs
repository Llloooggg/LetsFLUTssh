//! WebDAV session details DAO. One row per `sessions` row whose
//! `kind = 'webdav'`; carries the transport-config tuple (base URL,
//! username, auth method, optional self-signed cert fingerprint).
//!
//! **Why a join table.** WebDAV-specific config is meaningless on a
//! kind=ssh session, and SSH sessions outnumber WebDAV ones in
//! practice. Inlining the columns on `sessions` would force every
//! session read to pay the join-shaped width even when the columns
//! are NULL. Keeping them in a side table also leaves room for a
//! future S3 / FTP detail table without piling unrelated columns on
//! the parent.
//!
//! **Secret discipline.** The password / bearer-token value never
//! lands on a column here — `lfs_core::secrets::SecretStore` holds
//! it under `session.webdav.<session_id>` and the connect path
//! resolves it from there. Same posture as the SSH auth path; the
//! join table holds only the URL + the auth-method tag the
//! client needs to decide which header to stamp.

use rusqlite::params;

use crate::db::DbAccess;
use crate::error::Error;

/// Canonical SecretStore id for a WebDAV session's password /
/// bearer token. Connect-path callers compose the id; the
/// canonical form lives one place so a staging audit (`SecretStore::list_ids`)
/// can grep for it without having to know every call site.
pub fn webdav_secret_id(session_id: &str) -> String {
    format!("session.webdav.{session_id}")
}

/// One WebDAV session row. `auth_method` is the string wire value
/// (`"basic"` / `"digest"` / `"bearer"`); the typed
/// `lfs_core::webdav::AuthMethod` parsing happens at the connect
/// surface, not in the DAO.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WebDavSessionRow {
    pub session_id: String,
    pub base_url: String,
    pub username: String,
    pub auth_method: String,
    pub self_signed_fingerprint: Option<String>,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<WebDavSessionRow> {
    Ok(WebDavSessionRow {
        session_id: row.get("session_id")?,
        base_url: row.get("base_url")?,
        username: row.get("username")?,
        auth_method: row.get("auth_method")?,
        self_signed_fingerprint: row.get("self_signed_fingerprint")?,
    })
}

/// Fetch the WebDAV detail row paired with `session_id`. Returns
/// `None` when the session is not a WebDAV kind or has not been
/// configured yet — not an error.
pub fn get(conn: &impl DbAccess, session_id: &str) -> Result<Option<WebDavSessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, base_url, username, auth_method, self_signed_fingerprint \
             FROM webdav_session_details WHERE session_id = ?1",
        )
        .map_err(|e| Error::Db(format!("webdav_session_details get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("webdav_session_details get query: {e}")))?;
    match rows.next() {
        Some(Ok(r)) => Ok(Some(r)),
        Some(Err(e)) => Err(Error::Db(format!("webdav_session_details get row: {e}"))),
        None => Ok(None),
    }
}

/// Insert or replace the WebDAV detail row for `row.session_id`.
/// The caller is responsible for stamping the matching `sessions`
/// row with `kind = 'webdav'` (the schema does not enforce the
/// pairing — a future sync apply path may need to insert detail
/// rows ahead of the parent within a transaction).
pub fn upsert(conn: &impl DbAccess, row: &WebDavSessionRow) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO webdav_session_details ( \
               session_id, base_url, username, auth_method, self_signed_fingerprint \
             ) VALUES (?1, ?2, ?3, ?4, ?5) \
             ON CONFLICT(session_id) DO UPDATE SET \
               base_url = excluded.base_url, \
               username = excluded.username, \
               auth_method = excluded.auth_method, \
               self_signed_fingerprint = excluded.self_signed_fingerprint",
            params![
                row.session_id,
                row.base_url,
                row.username,
                row.auth_method,
                row.self_signed_fingerprint,
            ],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details upsert: {e}")))?;
    Ok(())
}

/// Physically remove every row. Used by the archive-import replace
/// mode before re-populating. No tombstone column today.
pub fn delete_all(conn: &impl DbAccess) -> Result<usize, Error> {
    conn.raw()
        .execute("DELETE FROM webdav_session_details", [])
        .map_err(|e| Error::Db(format!("webdav_session_details delete_all: {e}")))
}

/// Remove the WebDAV detail row for `session_id`. Returns the
/// number of rows affected — `0` is the idempotent no-op when the
/// session was never a WebDAV kind. The session row itself is not
/// touched; the caller deletes that through `sessions::delete`.
pub fn delete(conn: &impl DbAccess, session_id: &str) -> Result<usize, Error> {
    let n = conn
        .raw()
        .execute(
            "DELETE FROM webdav_session_details WHERE session_id = ?1",
            params![session_id],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details delete: {e}")))?;
    Ok(n)
}

/// Every WebDAV detail row, ordered by `session_id`. Used by
/// archive export and a future "all WebDAV sessions" diagnostic.
/// Most callers want [`get`] instead.
pub fn list_all(conn: &impl DbAccess) -> Result<Vec<WebDavSessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, base_url, username, auth_method, self_signed_fingerprint \
             FROM webdav_session_details ORDER BY session_id ASC",
        )
        .map_err(|e| Error::Db(format!("webdav_session_details list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("webdav_session_details list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("webdav_session_details list row: {e}")))?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{bootstrap_schema, sessions, Connection, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn seed_session(db: &Db, id: &str) {
        db.with_conn(|c| {
            sessions::upsert(
                c,
                &sessions::SessionRow {
                    id: id.into(),
                    label: id.into(),
                    kind: sessions::SESSION_KIND_WEBDAV.into(),
                    host: "example.com".into(),
                    port: 443,
                    user: "alice".into(),
                    auth_type: "password".into(),
                    ..Default::default()
                },
            )
        })
        .unwrap();
    }

    fn webdav(session_id: &str) -> WebDavSessionRow {
        WebDavSessionRow {
            session_id: session_id.into(),
            base_url: "https://example.com/remote.php/dav/files/alice/".into(),
            username: "alice".into(),
            auth_method: "basic".into(),
            self_signed_fingerprint: None,
        }
    }

    #[test]
    fn upsert_then_get_round_trips_every_field() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
        assert_eq!(got, webdav("s1"));
    }

    #[test]
    fn get_returns_none_when_no_detail_attached() {
        let db = db();
        seed_session(&db, "s1");
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
    }

    #[test]
    fn upsert_replaces_existing_row_for_same_session() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        let updated = WebDavSessionRow {
            base_url: "https://example.com/webdav/".into(),
            auth_method: "digest".into(),
            self_signed_fingerprint: Some("SHA256:abc".into()),
            ..webdav("s1")
        };
        db.with_conn(|c| upsert(c, &updated)).unwrap();
        let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
        assert_eq!(got.base_url, "https://example.com/webdav/");
        assert_eq!(got.auth_method, "digest");
        assert_eq!(got.self_signed_fingerprint.as_deref(), Some("SHA256:abc"));
    }

    #[test]
    fn delete_returns_one_when_row_existed_zero_when_absent() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        let n = db.with_conn(|c| delete(c, "s1")).unwrap();
        assert_eq!(n, 1);
        let n = db.with_conn(|c| delete(c, "s1")).unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn cascade_drops_detail_when_parent_session_is_purged() {
        // The FK declares ON DELETE CASCADE so the join row never
        // outlives its parent's physical removal. `sessions::delete`
        // soft-deletes the parent under the v3 tombstone contract,
        // so the detail row survives until the sync purge runs
        // through `sessions::purge_tombstones`. Once the parent
        // leaves the table for good, the cascade physically drops
        // the detail row.
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| sessions::delete(c, "s1")).unwrap();
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
        db.with_conn(|c| sessions::purge_tombstones(c, i64::MAX))
            .unwrap();
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
    }

    #[test]
    fn list_all_orders_by_session_id_ascending() {
        let db = db();
        seed_session(&db, "s1");
        seed_session(&db, "s2");
        seed_session(&db, "s3");
        db.with_conn(|c| upsert(c, &webdav("s2"))).unwrap();
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| upsert(c, &webdav("s3"))).unwrap();
        let all = db.with_conn(list_all).unwrap();
        assert_eq!(
            all.iter()
                .map(|r| r.session_id.as_str())
                .collect::<Vec<_>>(),
            vec!["s1", "s2", "s3"]
        );
    }

    #[test]
    fn webdav_secret_id_is_stable() {
        // Connect-path callers compose the id; the canonical form
        // belongs to one place so a staging audit can grep for it.
        assert_eq!(webdav_secret_id("abc"), "session.webdav.abc");
    }
}
