//! S3 session details DAO. One row per `sessions` row whose
//! `kind = 's3'`; carries the S3 transport-config tuple (access key
//! id, region, endpoint, addressing style, default bucket, default
//! prefix).
//!
//! **Why a join table.** S3-specific config has no meaningful
//! defaults on a kind=ssh / kind=webdav session, and the SSH path
//! is the dominant one in practice. Inlining the columns on
//! `sessions` would force every session read to pay the
//! join-shaped width even when the columns are unused. The join
//! table mirrors `webdav_session_details`; the schema docstring
//! for `webdav_sessions` explains the same trade-off in detail.
//!
//! **Secret discipline.** The secret access key persists on the
//! `secret_access_key` column (encrypted at rest by SQLCipher,
//! same posture as `ssh_session_details.password` /
//! `webdav_session_details.password`). The connect path calls
//! [`stage_secret_into_store`] right before `s3_connect`, which
//! copies the bytes from the column into the process-singleton
//! `SecretStore` under `session.s3.<session_id>` — the FRB
//! `s3_connect` reads by id so the plaintext never crosses back to
//! Dart. Plaintext travels FRB only one-way (Dart → Rust on save
//! via [`set_secret_access_key`]); the typed [`S3SessionRow`] read
//! path returns metadata only.
//!
//! **Tombstone discipline.** Same shape as `webdav_session_details`:
//! `delete` flips `deleted_at` to `now_unix_ms()` and bumps
//! `updated_at`, `upsert` clears the tombstone + stamps a fresh
//! `updated_at`, `purge_tombstones` removes rows older than a
//! threshold.

use rusqlite::params;

use crate::db::DbAccess;
use crate::error::Error;
use crate::secrets::SecretStore;

/// Canonical SecretStore id for an S3 session's secret access
/// key. Connect-path callers compose the id through this helper
/// so a staging audit (`SecretStore::list_ids`) can grep for it
/// without having to know every call site.
pub fn s3_secret_id(session_id: &str) -> String {
    format!("session.s3.{session_id}")
}

/// One S3 session row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct S3SessionRow {
    pub session_id: String,
    pub access_key_id: String,
    /// AWS region wire value (`us-east-1`, `eu-west-2`, `auto` for
    /// Cloudflare R2). Stored verbatim so a future region-aware
    /// transport probe can read it without parsing.
    pub region: String,
    /// Endpoint URL — `https://...`. Empty selects the AWS-default
    /// endpoint for the resolved region. Non-empty value is used
    /// verbatim (MinIO, Wasabi, R2, Spaces, Scaleway, B2-S3).
    pub endpoint: String,
    /// Addressing style. `false` (default) selects virtual-host
    /// addressing (`<bucket>.s3.<region>.amazonaws.com`); `true`
    /// selects path addressing (`<endpoint>/<bucket>/...`).
    /// MinIO and some private S3 deployments require path style.
    pub path_style: bool,
    pub default_bucket: String,
    pub default_prefix: String,
    /// Trusted certificate PEM (one or more `-----BEGIN
    /// CERTIFICATE-----` blocks) added as an additional root for
    /// the S3 session's reqwest client. `None` falls back to the
    /// system trust store. Mirrors the WebDAV detail row so both
    /// transports share one self-signed-endpoint surface.
    pub trusted_cert_pem: Option<String>,
    /// Last-resort `danger_accept_invalid_certs(true)` toggle.
    /// `true` skips every certificate check — the dialog renders
    /// an explicit MITM warning before letting the user flip it on.
    pub insecure_skip_verify: bool,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<S3SessionRow> {
    let path_style_int: i64 = row.get("path_style")?;
    let insecure_int: i64 = row.get("insecure_skip_verify")?;
    Ok(S3SessionRow {
        session_id: row.get("session_id")?,
        access_key_id: row.get("access_key_id")?,
        region: row.get("region")?,
        endpoint: row.get("endpoint")?,
        path_style: path_style_int != 0,
        default_bucket: row.get("default_bucket")?,
        default_prefix: row.get("default_prefix")?,
        trusted_cert_pem: row.get("trusted_cert_pem")?,
        insecure_skip_verify: insecure_int != 0,
    })
}

/// Fetch the S3 detail row paired with `session_id`. Returns
/// `None` when the session is not an S3 kind, has not been
/// configured yet, or has been tombstoned by a `delete` call.
pub fn get(conn: &impl DbAccess, session_id: &str) -> Result<Option<S3SessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix, \
                    trusted_cert_pem, insecure_skip_verify \
             FROM s3_session_details \
             WHERE session_id = ?1 AND deleted_at IS NULL",
        )
        .map_err(|e| Error::Db(format!("s3_session_details get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("s3_session_details get query: {e}")))?;
    match rows.next() {
        Some(Ok(r)) => Ok(Some(r)),
        Some(Err(e)) => Err(Error::Db(format!("s3_session_details get row: {e}"))),
        None => Ok(None),
    }
}

/// Insert or replace the S3 detail row for `row.session_id`. The
/// caller is responsible for stamping the matching `sessions` row
/// with `kind = 's3'`. Stamps a fresh `updated_at` so the sync
/// LWW gate moves forward; clears any pre-existing tombstone so a
/// revived row is observable again.
pub fn upsert(conn: &impl DbAccess, row: &S3SessionRow) -> Result<(), Error> {
    upsert_with_stamp(conn, row, now_unix_ms())
}

/// Same as [`upsert`] but with an explicit `updated_at_ms` stamp.
/// Used by the sync apply path so the receiver records the peer's
/// timestamp instead of a fresh local one.
pub fn upsert_with_stamp(
    conn: &impl DbAccess,
    row: &S3SessionRow,
    updated_at_ms: i64,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO s3_session_details ( \
               session_id, access_key_id, region, endpoint, path_style, \
               default_bucket, default_prefix, \
               trusted_cert_pem, insecure_skip_verify, updated_at \
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) \
             ON CONFLICT(session_id) DO UPDATE SET \
               access_key_id        = excluded.access_key_id, \
               region               = excluded.region, \
               endpoint             = excluded.endpoint, \
               path_style           = excluded.path_style, \
               default_bucket       = excluded.default_bucket, \
               default_prefix       = excluded.default_prefix, \
               trusted_cert_pem     = excluded.trusted_cert_pem, \
               insecure_skip_verify = excluded.insecure_skip_verify, \
               updated_at           = excluded.updated_at, \
               deleted_at           = NULL",
            params![
                row.session_id,
                row.access_key_id,
                row.region,
                row.endpoint,
                i64::from(row.path_style),
                row.default_bucket,
                row.default_prefix,
                row.trusted_cert_pem,
                i64::from(row.insecure_skip_verify),
                updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("s3_session_details upsert: {e}")))?;
    Ok(())
}

/// Replace the persisted secret access key for `session_id`. Empty
/// `value` clears the credential. Returns rows affected (`0` when
/// the S3 detail row hasn't been inserted yet — the caller must
/// `upsert` first). Bumps the parent `s3_session_details.updated_at`
/// so the sync LWW gate moves forward; the parent
/// `sessions.updated_at` is bumped too so a listing query that
/// watches the parent row sees the edit.
///
/// `value` reaches us through FRB but never crosses back to Dart —
/// combined with [`stage_secret_into_store`] this lets the edit
/// dialog save a fresh secret access key without ever pre-filling
/// the old one onto the Dart heap.
pub fn set_secret_access_key(
    conn: &impl DbAccess,
    session_id: &str,
    value: &str,
) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE s3_session_details \
                SET secret_access_key = ?1, updated_at = ?2 \
                WHERE session_id = ?3 AND deleted_at IS NULL",
            params![value, now_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details set_secret_access_key: {e}")))?;
    if n > 0 {
        conn.raw()
            .execute(
                "UPDATE sessions SET updated_at = ?1 \
                    WHERE id = ?2 AND deleted_at IS NULL",
                params![now_ms, session_id],
            )
            .map_err(|e| {
                Error::Db(format!(
                    "s3_session_details set_secret_access_key parent stamp: {e}"
                ))
            })?;
    }
    Ok(n)
}

/// Cheap presence probe — the edit dialog needs to render the
/// "[Saved] type to change" hint without ever reading the
/// plaintext back over FRB. Returns `false` for a missing row, a
/// tombstoned row, or an empty-string column.
pub fn has_secret_access_key(conn: &impl DbAccess, session_id: &str) -> Result<bool, Error> {
    let row: Option<String> = conn
        .raw()
        .query_row(
            "SELECT secret_access_key FROM s3_session_details \
                WHERE session_id = ?1 AND deleted_at IS NULL",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    Ok(row.map(|s| !s.is_empty()).unwrap_or(false))
}

/// Read the persisted secret access key and push it into the
/// process-singleton `SecretStore` under [`s3_secret_id`]`(session_id)`.
/// Returns `true` when a non-empty key was staged, `false` otherwise
/// (missing row, tombstoned row, or empty-string column).
///
/// Pairs with [`set_secret_access_key`]: the save path commits to
/// the column, the connect path stages from the column into the
/// SecretStore right before [`crate::s3::client::S3Client`] runs
/// its connect probe.
pub fn stage_secret_into_store(
    conn: &impl DbAccess,
    store: &SecretStore,
    session_id: &str,
) -> Result<bool, Error> {
    let row: Option<String> = conn
        .raw()
        .query_row(
            "SELECT secret_access_key FROM s3_session_details \
                WHERE session_id = ?1 AND deleted_at IS NULL",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    let Some(key) = row else { return Ok(false) };
    if key.is_empty() {
        return Ok(false);
    }
    store.put(&s3_secret_id(session_id), key.as_bytes());
    Ok(true)
}

/// Soft-delete every live row. Tombstones share one stamp so the
/// bulk-clear is a single point on the sync timeline. Used by the
/// archive-import replace mode before re-populating.
pub fn delete_all(conn: &impl DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE s3_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("s3_session_details delete_all: {e}")))
}

/// Soft-delete the S3 detail row for `session_id`. Flips
/// `deleted_at` to `now_unix_ms()` and bumps `updated_at`. Returns
/// `0` when the session was never an S3 kind or the row is already
/// tombstoned.
pub fn delete(conn: &impl DbAccess, session_id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE s3_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE session_id = ?2 AND deleted_at IS NULL",
            params![now_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details delete: {e}")))?;
    Ok(n)
}

/// Every live S3 detail row, ordered by `session_id`. Used by
/// archive export. Most callers want [`get`] instead. Tombstoned
/// rows are filtered.
pub fn list_all(conn: &impl DbAccess) -> Result<Vec<S3SessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix, \
                    trusted_cert_pem, insecure_skip_verify \
             FROM s3_session_details WHERE deleted_at IS NULL \
             ORDER BY session_id ASC",
        )
        .map_err(|e| Error::Db(format!("s3_session_details list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("s3_session_details list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("s3_session_details list row: {e}")))?);
    }
    Ok(out)
}

/// Every row paired with `(updated_at_ms, deleted_at)`. Sync
/// composers emit tombstoned rows so a peer device can replay the
/// removal. Archive composers filter out tombstones to keep the
/// wire payload to live rows.
pub fn list_all_with_tombstones(
    conn: &impl DbAccess,
) -> Result<Vec<(S3SessionRow, i64, Option<i64>)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix, \
                    trusted_cert_pem, insecure_skip_verify, \
                    updated_at, deleted_at \
             FROM s3_session_details ORDER BY session_id ASC",
        )
        .map_err(|e| {
            Error::Db(format!(
                "s3_session_details list_all_with_tombstones prepare: {e}"
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
                "s3_session_details list_all_with_tombstones query: {e}"
            ))
        })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| {
            Error::Db(format!(
                "s3_session_details list_all_with_tombstones row: {e}"
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
            "SELECT updated_at FROM s3_session_details WHERE session_id = ?1",
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
            "UPDATE s3_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE session_id = ?2 AND (updated_at IS NULL OR updated_at < ?1)",
            params![deleted_at_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details apply_tombstone: {e}")))
}

/// Physically remove rows whose `deleted_at` is older than
/// `before_ms`. Reserved for sync-merge teardown.
pub fn purge_tombstones(conn: &impl DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM s3_session_details \
             WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("s3_session_details purge_tombstones: {e}")))
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
#[path = "../../tests/unit/db_s3_sessions.rs"]
mod tests;
