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
//! **Secret discipline.** The password / bearer token persists on
//! the `password` column (encrypted at rest by SQLCipher, same
//! posture as `ssh_session_details.password`). The connect path
//! calls [`stage_secret_into_store`] right before `webdav_connect`,
//! which copies the bytes from the column into the process-singleton
//! `SecretStore` under `session.webdav.<session_id>` — the Rust
//! connect surface (`lfs_frb::api::webdav::webdav_connect`) reads
//! by id so the plaintext never crosses back to Dart. Plaintext
//! travels FRB only one-way (Dart → Rust on save via [`set_password`]);
//! the typed [`WebDavSessionRow`] read path returns metadata only.
//!
//! **Tombstone discipline.** `delete` flips `deleted_at` to
//! `now_unix_ms()` and bumps `updated_at` so the sync layer (`§8b`)
//! can replay the removal across devices. `upsert` clears the
//! tombstone + stamps a fresh `updated_at` so a sync receiver sees
//! a strictly newer LWW timestamp than the peer's tombstone.
//! `purge_tombstones` is the teardown that physically removes rows
//! whose `deleted_at` is older than the threshold.

use rusqlite::params;

use crate::db::DbAccess;
use crate::error::Error;
use crate::secrets::SecretStore;

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
/// surface, not in the DAO. The `password` column lives on the
/// table but is deliberately absent from this struct — the FRB
/// boundary only carries metadata back to Dart, never the secret
/// (same one-way discipline as SSH where `password` survives
/// inside `stage_secrets_into_store` only).
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
/// `None` when the session is not a WebDAV kind, has not been
/// configured yet, or has been tombstoned by a `delete` call.
pub fn get(conn: &impl DbAccess, session_id: &str) -> Result<Option<WebDavSessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, base_url, username, auth_method, self_signed_fingerprint \
             FROM webdav_session_details \
             WHERE session_id = ?1 AND deleted_at IS NULL",
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
/// rows ahead of the parent within a transaction). Stamps a fresh
/// `updated_at` so the sync LWW gate moves forward on every write;
/// clears any pre-existing tombstone so a revived row is observable
/// again.
pub fn upsert(conn: &impl DbAccess, row: &WebDavSessionRow) -> Result<(), Error> {
    upsert_with_stamp(conn, row, now_unix_ms())
}

/// Same as [`upsert`] but with an explicit `updated_at_ms` stamp.
/// Used by the sync apply path so the receiver records the peer's
/// timestamp instead of a fresh local one.
pub fn upsert_with_stamp(
    conn: &impl DbAccess,
    row: &WebDavSessionRow,
    updated_at_ms: i64,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO webdav_session_details ( \
               session_id, base_url, username, auth_method, self_signed_fingerprint, \
               updated_at \
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(session_id) DO UPDATE SET \
               base_url = excluded.base_url, \
               username = excluded.username, \
               auth_method = excluded.auth_method, \
               self_signed_fingerprint = excluded.self_signed_fingerprint, \
               updated_at = excluded.updated_at, \
               deleted_at = NULL",
            params![
                row.session_id,
                row.base_url,
                row.username,
                row.auth_method,
                row.self_signed_fingerprint,
                updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details upsert: {e}")))?;
    Ok(())
}

/// Replace the persisted password (or bearer token) for `session_id`.
/// Empty `value` clears the credential. Returns rows affected
/// (`0` when the WebDAV detail row hasn't been inserted yet — the
/// caller must `upsert` first). Bumps the parent
/// `webdav_session_details.updated_at` so the sync LWW gate moves
/// forward; the parent `sessions.updated_at` is bumped too so a
/// listing query that watches the parent row sees the edit.
///
/// `value` reaches us through FRB but never crosses back to Dart —
/// combined with [`stage_secret_into_store`] this lets the edit
/// dialog save a fresh password without ever pre-filling the old
/// one onto the Dart heap.
pub fn set_password(conn: &impl DbAccess, session_id: &str, value: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE webdav_session_details \
                SET password = ?1, updated_at = ?2 \
                WHERE session_id = ?3 AND deleted_at IS NULL",
            params![value, now_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details set_password: {e}")))?;
    if n > 0 {
        conn.raw()
            .execute(
                "UPDATE sessions SET updated_at = ?1 \
                    WHERE id = ?2 AND deleted_at IS NULL",
                params![now_ms, session_id],
            )
            .map_err(|e| {
                Error::Db(format!(
                    "webdav_session_details set_password parent stamp: {e}"
                ))
            })?;
    }
    Ok(n)
}

/// Cheap presence probe — the edit dialog needs to render the
/// "[Saved] type to change" hint without ever reading the
/// plaintext back over FRB. Returns `false` for a missing row, a
/// tombstoned row, or an empty-string column.
pub fn has_password(conn: &impl DbAccess, session_id: &str) -> Result<bool, Error> {
    let row: Option<String> = conn
        .raw()
        .query_row(
            "SELECT password FROM webdav_session_details \
                WHERE session_id = ?1 AND deleted_at IS NULL",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    Ok(row.map(|p| !p.is_empty()).unwrap_or(false))
}

/// Read the persisted password and push it into the
/// process-singleton `SecretStore` under
/// [`webdav_secret_id`]`(session_id)`. Returns `true` when a
/// non-empty password was staged, `false` otherwise (missing row,
/// tombstoned row, or empty-string column).
///
/// Pairs with [`set_password`]: the save path commits to the column,
/// the connect path stages from the column into the SecretStore
/// right before [`crate::webdav::WebDavClient`] runs its connect
/// probe. The plaintext lives in two places at runtime — the
/// SecretStore (RAM) and the SQLCipher-encrypted column on disk —
/// and is never sent back over FRB.
pub fn stage_secret_into_store(
    conn: &impl DbAccess,
    store: &SecretStore,
    session_id: &str,
) -> Result<bool, Error> {
    let row: Option<String> = conn
        .raw()
        .query_row(
            "SELECT password FROM webdav_session_details \
                WHERE session_id = ?1 AND deleted_at IS NULL",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    let Some(password) = row else {
        return Ok(false);
    };
    if password.is_empty() {
        return Ok(false);
    }
    store.put(&webdav_secret_id(session_id), password.as_bytes());
    Ok(true)
}

/// Soft-delete every live row in one shot. Tombstones share one
/// stamp so the bulk-clear is a single point on the sync timeline.
/// Used by the archive-import replace mode before re-populating.
pub fn delete_all(conn: &impl DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE webdav_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details delete_all: {e}")))
}

/// Soft-delete the WebDAV detail row for `session_id`. Flips
/// `deleted_at` to `now_unix_ms()` and bumps `updated_at` so the
/// sync LWW gate sees a strictly newer stamp. Returns the number
/// of rows affected; `0` when the session was never a WebDAV kind
/// or the row is already tombstoned.
pub fn delete(conn: &impl DbAccess, session_id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE webdav_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE session_id = ?2 AND deleted_at IS NULL",
            params![now_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details delete: {e}")))?;
    Ok(n)
}

/// Every live WebDAV detail row, ordered by `session_id`. Used by
/// archive export and a future "all WebDAV sessions" diagnostic.
/// Most callers want [`get`] instead. Tombstoned rows are filtered.
pub fn list_all(conn: &impl DbAccess) -> Result<Vec<WebDavSessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, base_url, username, auth_method, self_signed_fingerprint \
             FROM webdav_session_details WHERE deleted_at IS NULL \
             ORDER BY session_id ASC",
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

/// Every row paired with `(updated_at_ms, deleted_at)`. Sync
/// composers emit tombstoned rows so a peer device can replay
/// the removal; live rows carry their `updated_at` stamp for LWW.
/// Archive composers filter out tombstones to keep the wire
/// payload to live rows.
pub fn list_all_with_tombstones(
    conn: &impl DbAccess,
) -> Result<Vec<(WebDavSessionRow, i64, Option<i64>)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, base_url, username, auth_method, self_signed_fingerprint, \
                    updated_at, deleted_at \
             FROM webdav_session_details ORDER BY session_id ASC",
        )
        .map_err(|e| {
            Error::Db(format!(
                "webdav_session_details list_all_with_tombstones prepare: {e}"
            ))
        })?;
    let rows = stmt
        .query_map([], |r| {
            let row = row_from(r)?;
            let updated_at: i64 = r.get("updated_at")?;
            let deleted_at: Option<i64> = r.get("deleted_at")?;
            Ok((row, updated_at, deleted_at))
        })
        .map_err(|e| {
            Error::Db(format!(
                "webdav_session_details list_all_with_tombstones query: {e}"
            ))
        })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| {
            Error::Db(format!(
                "webdav_session_details list_all_with_tombstones row: {e}"
            ))
        })?);
    }
    Ok(out)
}

/// Look up a row's `updated_at_ms` regardless of tombstone state.
/// Used by the sync apply LWW gate.
pub fn get_updated_at(conn: &impl DbAccess, session_id: &str) -> Result<Option<i64>, Error> {
    let row: Option<i64> = conn
        .raw()
        .query_row(
            "SELECT updated_at FROM webdav_session_details WHERE session_id = ?1",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    Ok(row)
}

/// Apply a peer tombstone with an explicit stamp. The LWW gate
/// rejects stale stamps (peer's stamp strictly newer than the
/// local `updated_at` to land).
pub fn apply_tombstone(
    conn: &impl DbAccess,
    session_id: &str,
    deleted_at_ms: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE webdav_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE session_id = ?2 AND (updated_at IS NULL OR updated_at < ?1)",
            params![deleted_at_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details apply_tombstone: {e}")))
}

/// Physically remove rows whose `deleted_at` is older than
/// `before_ms`. Reserved for sync-merge teardown.
pub fn purge_tombstones(conn: &impl DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM webdav_session_details \
             WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("webdav_session_details purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` /
/// `updated_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
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

    fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
        db.with_conn(|c| {
            let row: Option<i64> = c
                .raw()
                .query_row(
                    "SELECT deleted_at FROM webdav_session_details WHERE session_id = ?1",
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
    fn delete_writes_tombstone_instead_of_removing_row() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        let n = db.with_conn(|c| delete(c, "s1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "s1").is_some());
        // The get filter hides tombstoned rows.
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
        // Repeat delete on already-tombstoned row is a no-op.
        let n = db.with_conn(|c| delete(c, "s1")).unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn cascade_drops_detail_when_parent_session_is_purged() {
        // ON DELETE CASCADE: the join row never outlives its
        // parent's physical removal. `sessions::delete` soft-deletes
        // the parent so the detail row survives until the sync
        // purge runs through `sessions::purge_tombstones`.
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
    fn list_all_orders_by_session_id_and_skips_tombstones() {
        let db = db();
        seed_session(&db, "s1");
        seed_session(&db, "s2");
        seed_session(&db, "s3");
        db.with_conn(|c| upsert(c, &webdav("s2"))).unwrap();
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| upsert(c, &webdav("s3"))).unwrap();
        db.with_conn(|c| delete(c, "s2")).unwrap();
        let all = db.with_conn(list_all).unwrap();
        assert_eq!(
            all.iter()
                .map(|r| r.session_id.as_str())
                .collect::<Vec<_>>(),
            vec!["s1", "s3"]
        );
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| delete(c, "s1")).unwrap();
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
        assert!(raw_deleted_at(&db, "s1").is_none());
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| delete(c, "s1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        // Row is physically gone.
        assert_eq!(
            db.with_conn(|c| {
                let n: i64 = c
                    .raw()
                    .query_row(
                        "SELECT COUNT(*) FROM webdav_session_details WHERE session_id = ?1",
                        params!["s1"],
                        |r| r.get(0),
                    )
                    .unwrap();
                Ok(n)
            })
            .unwrap(),
            0
        );
    }

    #[test]
    fn apply_tombstone_lww_blocks_stale_stamp() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert_with_stamp(c, &webdav("s1"), 100))
            .unwrap();
        let n = db.with_conn(|c| apply_tombstone(c, "s1", 50)).unwrap();
        assert_eq!(n, 0);
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
        let n = db.with_conn(|c| apply_tombstone(c, "s1", 200)).unwrap();
        assert_eq!(n, 1);
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
    }

    #[test]
    fn webdav_secret_id_is_stable() {
        // Connect-path callers compose the id; the canonical form
        // belongs to one place so a staging audit can grep for it.
        assert_eq!(webdav_secret_id("abc"), "session.webdav.abc");
    }

    #[test]
    fn set_password_roundtrips_into_has_and_stage() {
        // Save → reopen → connect path. The save-time setter stamps
        // the column; the connect-time stage call reads it into a
        // fresh SecretStore. This is the exact regression that left
        // the user re-typing the WebDAV password every launch when
        // SecretStore was the only landing pad.
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        let n = db
            .with_conn(|c| set_password(c, "s1", "t0p-s3cret"))
            .unwrap();
        assert_eq!(n, 1);
        assert!(db.with_conn(|c| has_password(c, "s1")).unwrap());

        let store = SecretStore::new();
        let staged = db
            .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
            .unwrap();
        assert!(staged);
        let bytes = store.get(&webdav_secret_id("s1")).expect("staged slot");
        assert_eq!(bytes.as_slice(), b"t0p-s3cret");
    }

    #[test]
    fn set_password_empty_string_clears_and_unstages() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| set_password(c, "s1", "first")).unwrap();
        db.with_conn(|c| set_password(c, "s1", "")).unwrap();
        assert!(!db.with_conn(|c| has_password(c, "s1")).unwrap());
        let store = SecretStore::new();
        let staged = db
            .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
            .unwrap();
        assert!(!staged);
        assert!(store.get(&webdav_secret_id("s1")).is_none());
    }

    #[test]
    fn set_password_returns_zero_when_row_missing() {
        // `set_password` requires the detail row to exist first —
        // the save path always upserts before stamping the password,
        // so a setter call without an upsert is a no-op rather than
        // silently minting an orphan row.
        let db = db();
        seed_session(&db, "s1");
        let n = db.with_conn(|c| set_password(c, "s1", "x")).unwrap();
        assert_eq!(n, 0);
        assert!(!db.with_conn(|c| has_password(c, "s1")).unwrap());
    }

    #[test]
    fn set_password_does_not_disturb_other_columns() {
        // Bumping the password must not corrupt base_url / username /
        // auth_method / fingerprint — the setter is a single-column
        // UPDATE, but assert it on the wire to catch any future
        // change that switches to an INSERT OR REPLACE shape.
        let db = db();
        seed_session(&db, "s1");
        let row = WebDavSessionRow {
            base_url: "https://nc.example.com/dav/files/alice/".into(),
            auth_method: "digest".into(),
            self_signed_fingerprint: Some("SHA256:pin".into()),
            ..webdav("s1")
        };
        db.with_conn(|c| upsert(c, &row)).unwrap();
        db.with_conn(|c| set_password(c, "s1", "after")).unwrap();
        let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
        assert_eq!(got.base_url, row.base_url);
        assert_eq!(got.auth_method, "digest");
        assert_eq!(got.self_signed_fingerprint.as_deref(), Some("SHA256:pin"));
    }

    #[test]
    fn stage_secret_into_store_returns_false_on_missing_row() {
        let db = db();
        seed_session(&db, "s1");
        let store = SecretStore::new();
        let staged = db
            .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
            .unwrap();
        assert!(!staged);
    }

    #[test]
    fn upsert_after_set_password_preserves_secret() {
        // Save flow: the dialog upserts metadata then conditionally
        // calls `set_password`. A re-edit that doesn't change the
        // password re-runs `upsert` alone; the existing password
        // column must survive. Without this guarantee, every
        // metadata edit would silently clear the saved credential.
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
        db.with_conn(|c| set_password(c, "s1", "keep-me")).unwrap();
        // Second upsert (e.g. user toggled auth method from basic to
        // digest) must not wipe the password.
        let row = WebDavSessionRow {
            auth_method: "digest".into(),
            ..webdav("s1")
        };
        db.with_conn(|c| upsert(c, &row)).unwrap();
        assert!(db.with_conn(|c| has_password(c, "s1")).unwrap());
    }
}
