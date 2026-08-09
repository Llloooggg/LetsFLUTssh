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
///
/// `trusted_cert_pem` carries a PEM blob added as an additional
/// root CA for the session's reqwest client (lets self-signed
/// endpoints validate without polluting the OS trust store).
/// `insecure_skip_verify` is the last-resort escape hatch that
/// disables every certificate check — the dialog renders an
/// explicit MITM warning before letting the user flip it on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WebDavSessionRow {
    pub session_id: String,
    pub base_url: String,
    pub username: String,
    pub auth_method: String,
    pub trusted_cert_pem: Option<String>,
    pub insecure_skip_verify: bool,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<WebDavSessionRow> {
    let insecure_int: i64 = row.get("insecure_skip_verify")?;
    Ok(WebDavSessionRow {
        session_id: row.get("session_id")?,
        base_url: row.get("base_url")?,
        username: row.get("username")?,
        auth_method: row.get("auth_method")?,
        trusted_cert_pem: row.get("trusted_cert_pem")?,
        insecure_skip_verify: insecure_int != 0,
    })
}

/// Fetch the WebDAV detail row paired with `session_id`. Returns
/// `None` when the session is not a WebDAV kind, has not been
/// configured yet, or has been tombstoned by a `delete` call.
pub fn get(conn: &impl DbAccess, session_id: &str) -> Result<Option<WebDavSessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, base_url, username, auth_method, \
                    trusted_cert_pem, insecure_skip_verify \
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
               session_id, base_url, username, auth_method, \
               trusted_cert_pem, insecure_skip_verify, updated_at \
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
             ON CONFLICT(session_id) DO UPDATE SET \
               base_url             = excluded.base_url, \
               username             = excluded.username, \
               auth_method          = excluded.auth_method, \
               trusted_cert_pem     = excluded.trusted_cert_pem, \
               insecure_skip_verify = excluded.insecure_skip_verify, \
               updated_at           = excluded.updated_at, \
               deleted_at           = NULL",
            params![
                row.session_id,
                row.base_url,
                row.username,
                row.auth_method,
                row.trusted_cert_pem,
                i64::from(row.insecure_skip_verify),
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
            "SELECT session_id, base_url, username, auth_method, \
                    trusted_cert_pem, insecure_skip_verify \
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
            "SELECT session_id, base_url, username, auth_method, \
                    trusted_cert_pem, insecure_skip_verify, \
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
#[path = "../../tests/unit/db_webdav_sessions.rs"]
mod tests;
