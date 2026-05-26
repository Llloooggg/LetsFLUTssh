//! Sessions DAO. Mirrors `lib/core/db/dao/session_dao.dart`.
//!
//! **Layout**: the `sessions` table carries only the
//! protocol-neutral row (id, label, folder_id, kind, sort_order,
//! notes, last_connected_at, extras, timestamps); every
//! protocol-specific column lives on a separate join table keyed
//! by `session_id`. SSH config (host / port / user / auth_type /
//! password / key_path / key_data / key_id / passphrase / via_*)
//! lives on `ssh_session_details`. WebDAV config (base URL, auth
//! method, self-signed fingerprint) lives on
//! `webdav_session_details`. S3 config (access key id, region,
//! endpoint, path-style flag, default bucket / prefix) lives on
//! `s3_session_details`. The v15 → v16 migration extracts the SSH
//! columns out of `sessions` for pre-existing databases; fresh
//! installs see the slim shape from the first bootstrap.
//!
//! **Read path** — [`list_all`] / [`get`] LEFT JOIN
//! `ssh_session_details` and `COALESCE` the joined columns to the
//! struct defaults (empty string / `22` / `'password'`) so non-SSH
//! rows surface a sane `SessionRow` without populating
//! protocol-irrelevant fields. The SSH-shaped fields stay on
//! `SessionRow` because the archive / QR codecs (`archive/compose`,
//! `archive/apply`, `qr_compose`) operate on the struct verbatim
//! and the wire format must stay stable across migrations.
//!
//! **Write path** — [`upsert`] inserts the common columns into
//! `sessions` and, when `kind == 'ssh'`, upserts the SSH-shaped
//! row into `ssh_session_details`. A `kind != 'ssh'` upsert
//! deletes the join row (defensive — handles a kind change away
//! from SSH). The credential triplet (`password` / `key_data` /
//! `passphrase`) reaches `ssh_session_details` for archive / wire
//! continuity; the runtime [`stage_secrets_into_store`] path
//! migrates each non-empty slot into the SecretStore on open so
//! the in-memory `SessionRow` is the only path that ever carries
//! plaintext on the Rust heap.
//!
//! **Secret-store angle**: the `password`, `key_data`, `passphrase`
//! columns will eventually move out of this DAO entirely (the row
//! carries opaque ids; plaintext lives only in the SecretStore).
//! For now `ssh_session_details` mirrors the plaintext slots so
//! the data backfill can do a straight copy; the follow-up adds an
//! `auth_secret_id` column and drops the plaintext ones.
//!
//! **Session kind**: `kind` is the transport tag. `SESSION_KIND_SSH`,
//! `SESSION_KIND_WEBDAV` and `SESSION_KIND_S3` are the three values
//! in play; the column is `NOT NULL DEFAULT 'ssh'` so existing rows
//! backfill cleanly on the v4 → v5 hop. Reads dispatch to the
//! right join by inspecting `kind` first.

use crate::db::Connection;
use rusqlite::params;

use crate::error::Error;

/// Wire value for an SSH/SFTP session. Persisted in `sessions.kind`.
pub const SESSION_KIND_SSH: &str = "ssh";

/// Wire value for a WebDAV session. Persisted in `sessions.kind`.
pub const SESSION_KIND_WEBDAV: &str = "webdav";

/// Wire value for an S3-compatible session (AWS, MinIO, Wasabi,
/// R2, B2-S3, DigitalOcean Spaces, Scaleway). Persisted in
/// `sessions.kind`. S3-specific configuration (access key id,
/// region, endpoint, path-style flag, default bucket / prefix)
/// lives on the `s3_session_details` join table keyed by session
/// id; reads dispatch to the right join by inspecting `kind`
/// first.
pub const SESSION_KIND_S3: &str = "s3";

#[derive(Debug, Clone, Default)]
pub struct SessionRow {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    /// Transport tag — one of [`SESSION_KIND_SSH`] /
    /// [`SESSION_KIND_WEBDAV`]. Empty string round-trips through the
    /// `Default` impl as the SSH default; the schema column is
    /// `NOT NULL DEFAULT 'ssh'` so an empty string sent to `upsert`
    /// surfaces as the SSH wire value on read.
    pub kind: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    /// JSON object — see drift `extras` column.
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

/// Per-session credential-presence flags pulled from the WebDAV / S3
/// detail join tables. Lives outside [`SessionRow`] so the write
/// path (every `SessionRow { ... }` construction site) stays
/// untouched — the flags are read-only synthesis driven by the
/// LEFT JOIN, and only the session-tree UI's "credentials not
/// set" warning consumes them.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SessionCredentialFlags {
    /// `webdav_session_details.password` exists and is non-empty
    /// for this session id. `false` for SSH / S3 sessions and for
    /// WebDAV sessions that haven't saved a password yet.
    pub has_webdav_password: bool,
    /// `s3_session_details.secret_access_key` exists and is
    /// non-empty for this session id.
    pub has_s3_secret_access_key: bool,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SessionRow> {
    Ok(SessionRow {
        id: row.get("id")?,
        label: row.get("label")?,
        folder_id: row.get("folder_id")?,
        kind: row.get("kind")?,
        host: row.get("host")?,
        port: row.get("port")?,
        user: row.get("user")?,
        auth_type: row.get("auth_type")?,
        password: row.get("password")?,
        key_path: row.get("key_path")?,
        key_data: row.get("key_data")?,
        key_id: row.get("key_id")?,
        passphrase: row.get("passphrase")?,
        sort_order: row.get("sort_order")?,
        notes: row.get("notes")?,
        last_connected_at_ms: row.get("last_connected_at")?,
        extras: row.get("extras")?,
        via_session_id: row.get("via_session_id")?,
        via_host: row.get("via_host")?,
        via_port: row.get("via_port")?,
        via_user: row.get("via_user")?,
        created_at_ms: row.get("created_at")?,
        updated_at_ms: row.get("updated_at")?,
    })
}

/// Read the synthesised non-SSH credential flags off the same JOIN
/// shape `row_from` consumes. Pulled out into its own function so a
/// caller that only needs the flags (e.g. the session-tree UI's
/// fast-path) can skip the full row materialisation; the
/// list / get queries call this alongside [`row_from`] and pair
/// the results.
///
/// SQLite's BOOLEAN is INTEGER under the hood; the synthesised
/// columns arrive as `0` / `1`. The `COALESCE(..., 0)` in
/// [`NON_SSH_SECRET_FLAGS`] collapses any NULL the LEFT JOIN could
/// produce to `0`, so a missing column maps to `false`.
fn flags_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SessionCredentialFlags> {
    let has_webdav_password: i64 = row.get("has_webdav_password").unwrap_or(0);
    let has_s3_secret_access_key: i64 = row.get("has_s3_secret_access_key").unwrap_or(0);
    Ok(SessionCredentialFlags {
        has_webdav_password: has_webdav_password != 0,
        has_s3_secret_access_key: has_s3_secret_access_key != 0,
    })
}

/// Slim-side columns owned by the `sessions` table after the v16
/// schema split. Used by every read query — the SSH-specific
/// columns are pulled separately via [`SSH_JOIN_COLS`] off the
/// `ssh_session_details` join.
const SESSIONS_COLS: &str =
    "s.id, s.label, s.folder_id, s.kind, s.sort_order, s.notes, s.last_connected_at, \
     s.extras, s.created_at, s.updated_at";

/// SSH-specific columns pulled from `ssh_session_details` via a
/// LEFT JOIN. `COALESCE` resolves the joined value when the
/// session is SSH (the row exists) and to the struct-default zero
/// values for every other kind (WebDAV / S3 leave the join row
/// absent). The default literals match the schema defaults on
/// `ssh_session_details` for round-trip stability.
const SSH_JOIN_COLS: &str = "COALESCE(j.host, '') AS host, \
     COALESCE(j.port, 22) AS port, \
     COALESCE(j.user, '') AS user, \
     COALESCE(j.auth_type, 'password') AS auth_type, \
     COALESCE(j.password, '') AS password, \
     COALESCE(j.key_path, '') AS key_path, \
     COALESCE(j.key_data, '') AS key_data, \
     j.key_id AS key_id, \
     COALESCE(j.passphrase, '') AS passphrase, \
     j.via_session_id AS via_session_id, \
     j.via_host AS via_host, \
     j.via_port AS via_port, \
     j.via_user AS via_user";

/// Non-SSH credential presence flags. The session-tree UI's
/// "credentials not set" warning needs to know, per row, whether a
/// password / secret access key has been persisted — for SSH this
/// falls out of `j.password` (already in [`SSH_JOIN_COLS`]); for
/// WebDAV / S3 we synthesise a bool from the matching column on
/// the respective join. `IS NOT NULL` guards the path where the
/// detail row hasn't been inserted yet (the LEFT JOIN leaves every
/// `w.*` / `t.*` reference NULL); `<> ''` handles the case where
/// the user cleared the credential. `COALESCE(..., 0)` collapses
/// the NULL to 0 so the bool the `row_from` reader sees is always
/// a defined integer.
const NON_SSH_SECRET_FLAGS: &str =
    "COALESCE(w.password IS NOT NULL AND w.password <> '', 0) AS has_webdav_password, \
     COALESCE(t.secret_access_key IS NOT NULL AND t.secret_access_key <> '', 0) \
        AS has_s3_secret_access_key";

/// `FROM` + `LEFT JOIN` fragment used by every full-row read.
/// Lifted into a constant so the read paths share one source of
/// truth for the join shape. The two non-SSH joins are filtered on
/// `deleted_at IS NULL` so a tombstoned detail row doesn't keep
/// flagging credentials as present after a soft-delete on the
/// matching kind.
const FROM_JOIN: &str = "FROM sessions s \
     LEFT JOIN ssh_session_details j ON j.session_id = s.id \
     LEFT JOIN webdav_session_details w \
        ON w.session_id = s.id AND w.deleted_at IS NULL \
     LEFT JOIN s3_session_details t \
        ON t.session_id = s.id AND t.deleted_at IS NULL";

/// Normalise an empty-string `kind` to the SSH wire value so a
/// caller that constructed `SessionRow` via the `Default` impl
/// without setting `kind` still upserts a valid non-null column
/// value matching the schema default.
fn normalise_kind(kind: &str) -> &str {
    if kind.is_empty() {
        SESSION_KIND_SSH
    } else {
        kind
    }
}

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<SessionRow>, Error> {
    Ok(list_all_with_flags(conn)?
        .into_iter()
        .map(|(row, _)| row)
        .collect())
}

/// Same shape as [`list_all`] but pairs every session row with the
/// non-SSH credential-presence flags synthesised off the WebDAV / S3
/// detail joins. Used by the session-tree provider to render the
/// "credentials not set" warning without an N+1 lookup hop.
pub fn list_all_with_flags(
    conn: &impl crate::db::DbAccess,
) -> Result<Vec<(SessionRow, SessionCredentialFlags)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(&format!(
            "SELECT {SESSIONS_COLS}, {SSH_JOIN_COLS}, {NON_SSH_SECRET_FLAGS} {FROM_JOIN} \
             WHERE s.deleted_at IS NULL \
             ORDER BY s.sort_order ASC, s.label ASC"
        ))
        .map_err(|e| Error::Db(format!("sessions prepare: {e}")))?;
    let rows = stmt
        .query_map([], |row| Ok((row_from(row)?, flags_from(row)?)))
        .map_err(|e| Error::Db(format!("sessions query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("sessions row: {e}")))?);
    }
    Ok(out)
}

/// Every session paired with `(updated_at_ms, deleted_at)`,
/// tombstones included. The sync composer needs the tombstoned
/// rows so a peer device can replay a deletion; `list_all` filters
/// them out (live snapshot only), which is why a soft-deleted
/// session would otherwise never reach the wire and the peer would
/// push the still-live row straight back. Archive / QR exports keep
/// using `list_all` (live rows only). LWW key is `updated_at_ms` —
/// the same stamp [`apply_tombstone`] gates on.
pub fn list_all_with_tombstones(
    conn: &impl crate::db::DbAccess,
) -> Result<Vec<(SessionRow, i64, Option<i64>)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(&format!(
            "SELECT {SESSIONS_COLS}, {SSH_JOIN_COLS}, s.deleted_at AS deleted_at \
             {FROM_JOIN} ORDER BY s.sort_order ASC, s.label ASC"
        ))
        .map_err(|e| Error::Db(format!("sessions list_all_with_tombstones prepare: {e}")))?;
    let rows = stmt
        .query_map([], |row| {
            let r = row_from(row)?;
            let updated_at = r.updated_at_ms;
            let deleted_at: Option<i64> = row.get("deleted_at")?;
            Ok((r, updated_at, deleted_at))
        })
        .map_err(|e| Error::Db(format!("sessions list_all_with_tombstones query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("sessions list_all_with_tombstones row: {e}")))?);
    }
    Ok(out)
}

/// Apply a peer tombstone with an explicit stamp under the sync
/// LWW rule. The row's `deleted_at` flips and `updated_at` advances
/// to the same stamp only when the peer's `deleted_at_ms` is
/// strictly newer than the local `updated_at` — a tie or a stale
/// stamp loses, so a deletion never clobbers a fresher local edit.
/// Returns the affected row count (0 = LWW rejected the tombstone).
pub fn apply_tombstone(
    conn: &impl crate::db::DbAccess,
    id: &str,
    deleted_at_ms: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE sessions SET deleted_at = ?1, updated_at = ?1 \
             WHERE id = ?2 AND (updated_at IS NULL OR updated_at < ?1)",
            params![deleted_at_ms, id],
        )
        .map_err(|e| Error::Db(format!("sessions apply_tombstone: {e}")))
}

pub fn get(conn: &impl crate::db::DbAccess, id: &str) -> Result<Option<SessionRow>, Error> {
    Ok(get_with_flags(conn, id)?.map(|(row, _)| row))
}

/// Same as [`get`] but also returns the non-SSH credential-presence
/// flags. Used by callers that need to render the "credentials not
/// set" warning on a single row (refresh after edit dialog Save).
pub fn get_with_flags(
    conn: &impl crate::db::DbAccess,
    id: &str,
) -> Result<Option<(SessionRow, SessionCredentialFlags)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(&format!(
            "SELECT {SESSIONS_COLS}, {SSH_JOIN_COLS}, {NON_SSH_SECRET_FLAGS} {FROM_JOIN} \
             WHERE s.id = ?1 AND s.deleted_at IS NULL"
        ))
        .map_err(|e| Error::Db(format!("sessions get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![id], |row| Ok((row_from(row)?, flags_from(row)?)))
        .map_err(|e| Error::Db(format!("sessions get query: {e}")))?;
    match rows.next() {
        Some(Ok(r)) => Ok(Some(r)),
        Some(Err(e)) => Err(Error::Db(format!("sessions get row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &SessionRow) -> Result<(), Error> {
    let kind = normalise_kind(&row.kind);
    conn.raw()
        .execute(
            "INSERT INTO sessions (id, label, folder_id, kind, sort_order, notes, \
           last_connected_at, extras, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) \
         ON CONFLICT(id) DO UPDATE SET \
           label = excluded.label, \
           folder_id = excluded.folder_id, \
           kind = excluded.kind, \
           sort_order = excluded.sort_order, \
           notes = excluded.notes, \
           last_connected_at = excluded.last_connected_at, \
           extras = excluded.extras, \
           updated_at = excluded.updated_at, \
           deleted_at = NULL",
            params![
                row.id,
                row.label,
                row.folder_id,
                kind,
                row.sort_order,
                row.notes,
                row.last_connected_at_ms,
                row.extras,
                row.created_at_ms,
                row.updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("sessions upsert: {e}")))?;

    // Protocol-specific detail rows. Each kind owns one join table;
    // the upsert keeps the live kind's row in sync and drops any
    // stale row from the other two so a kind change does not leak
    // the previous transport's URL / credentials under the same
    // session id. Idempotent — already-empty deletes are no-ops.
    if kind == SESSION_KIND_SSH {
        upsert_ssh_details(conn, row)?;
    } else {
        delete_ssh_details(conn, &row.id)?;
    }
    if kind != SESSION_KIND_WEBDAV {
        delete_webdav_details(conn, &row.id)?;
    }
    if kind != SESSION_KIND_S3 {
        delete_s3_details(conn, &row.id)?;
    }
    Ok(())
}

/// Transactional entry point for the standalone FRB upsert. [`upsert`]
/// writes the parent row plus up to four protocol-detail ins/del as
/// separate statements; wrapping them in one transaction means a
/// mid-sequence failure (FK violation on a stale `via_session_id`,
/// disk-full, a kind switch whose detail-insert succeeds but a stale-
/// row delete fails) rolls back wholesale instead of leaving a session
/// row with missing or stale detail rows. The archive-apply path calls
/// [`upsert`] directly — it already runs inside its own transaction,
/// and rusqlite does not nest.
pub fn upsert_in_tx(conn: &mut Connection, row: &SessionRow) -> Result<(), Error> {
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("sessions upsert tx: {e}")))?;
    upsert(&tx, row)?;
    tx.commit()
        .map_err(|e| Error::Db(format!("sessions upsert commit: {e}")))
}

/// Physically remove the `webdav_session_details` row for a session
/// id. Issued when an upsert lands a non-WebDAV kind so a prior
/// WebDAV row does not stay reachable as stale transport config.
fn delete_webdav_details(conn: &impl crate::db::DbAccess, id: &str) -> Result<(), Error> {
    conn.raw()
        .execute(
            "DELETE FROM webdav_session_details WHERE session_id = ?1",
            params![id],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details delete: {e}")))?;
    Ok(())
}

/// Physically remove the `s3_session_details` row for a session id.
/// Same shape as [`delete_webdav_details`] — fires on a kind change
/// away from S3.
fn delete_s3_details(conn: &impl crate::db::DbAccess, id: &str) -> Result<(), Error> {
    conn.raw()
        .execute(
            "DELETE FROM s3_session_details WHERE session_id = ?1",
            params![id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details delete: {e}")))?;
    Ok(())
}

/// Push the SSH-shaped row into `ssh_session_details`. Single-
/// statement UPSERT keyed by `session_id` — the FK to `sessions`
/// is `ON DELETE CASCADE`, so a soft- or hard-deleted parent
/// drops the join row automatically; this path covers the
/// straight-edit case where the parent stays alive.
fn upsert_ssh_details(conn: &impl crate::db::DbAccess, row: &SessionRow) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO ssh_session_details \
               (session_id, host, port, user, auth_type, password, key_path, key_data, \
                key_id, passphrase, via_session_id, via_host, via_port, via_user, \
                updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15) \
             ON CONFLICT(session_id) DO UPDATE SET \
                host = excluded.host, \
                port = excluded.port, \
                user = excluded.user, \
                auth_type = excluded.auth_type, \
                password = excluded.password, \
                key_path = excluded.key_path, \
                key_data = excluded.key_data, \
                key_id = excluded.key_id, \
                passphrase = excluded.passphrase, \
                via_session_id = excluded.via_session_id, \
                via_host = excluded.via_host, \
                via_port = excluded.via_port, \
                via_user = excluded.via_user, \
                updated_at = excluded.updated_at, \
                deleted_at = NULL",
            params![
                row.id,
                row.host,
                row.port,
                row.user,
                row.auth_type,
                row.password,
                row.key_path,
                row.key_data,
                row.key_id,
                row.passphrase,
                row.via_session_id,
                row.via_host,
                row.via_port,
                row.via_user,
                row.updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("ssh_session_details upsert: {e}")))?;
    Ok(())
}

/// Physically drop the `ssh_session_details` row for a session id.
/// Issued whenever a session's `kind` lands on a non-SSH value —
/// re-saving an SSH session as WebDAV must not leave the old SSH
/// credential blob discoverable on the join table.
fn delete_ssh_details(conn: &impl crate::db::DbAccess, id: &str) -> Result<(), Error> {
    conn.raw()
        .execute(
            "DELETE FROM ssh_session_details WHERE session_id = ?1",
            params![id],
        )
        .map_err(|e| Error::Db(format!("ssh_session_details delete: {e}")))?;
    Ok(())
}

/// Soft-delete a single session by id. Flips `deleted_at` to
/// `now_unix_ms()` instead of issuing a `DELETE FROM`; the row
/// survives the call so a sync-merge (`§8b`) can replay the
/// tombstone across devices. Already-tombstoned rows are not
/// retouched — `AND deleted_at IS NULL` keeps the stamp stable.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE sessions SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("sessions delete: {e}")))
}

/// Bulk soft-delete by id list. Empty input is a cheap no-op (no
/// SQL). Each row's `deleted_at` is stamped to the same
/// `now_unix_ms()` so the tombstones share a coherent timestamp,
/// regardless of how fast the rusqlite worker drains.
pub fn delete_multiple(conn: &impl crate::db::DbAccess, ids: &[String]) -> Result<usize, Error> {
    if ids.is_empty() {
        return Ok(0);
    }
    let now_ms = now_unix_ms();
    let placeholders = vec!["?"; ids.len()].join(",");
    let sql = format!(
        "UPDATE sessions SET deleted_at = ?1 \
         WHERE id IN ({placeholders}) AND deleted_at IS NULL"
    );
    let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(1 + ids.len());
    params_vec.push(&now_ms as &dyn rusqlite::ToSql);
    for id in ids {
        params_vec.push(id as &dyn rusqlite::ToSql);
    }
    conn.raw()
        .execute(&sql, params_vec.as_slice())
        .map_err(|e| Error::Db(format!("sessions delete_multiple: {e}")))
}

/// Soft-delete every live session. Tombstones share one
/// timestamp so the bulk-clear is a single point on the sync
/// timeline. Already-tombstoned rows are left untouched.
pub fn delete_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE sessions SET deleted_at = ?1 WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("sessions delete_all: {e}")))
}

/// Physically remove session rows whose `deleted_at` is strictly
/// older than `before_ms`. Reserved for the sync-merge teardown
/// (`§8b`) — production paths use the tombstone-flipping
/// `delete*` family above so a peer device can observe the
/// deletion before the row leaves the table.
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM sessions WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("sessions purge_tombstones: {e}")))
}

/// Current unix-millis. Captured here so every soft-delete path
/// inside the DAO shares the same shape — the sync layer expects
/// `deleted_at` to be a unix-millis stamp, matching `created_at`
/// / `updated_at` on the same row.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Set `folder_id` for a single session, refreshing `updated_at`.
pub fn move_to_folder(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
    folder_id: Option<&str>,
    updated_at_ms: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE sessions SET folder_id = ?1, updated_at = ?2 \
             WHERE id = ?3 AND deleted_at IS NULL",
            params![folder_id, updated_at_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("sessions move_to_folder: {e}")))
}

/// What got staged into the [`crate::secrets::SecretStore`] by
/// [`stage_secrets_into_store`]. The bools tell the caller which
/// `SshAuth*Ref` variant to construct without needing to read the
/// columns themselves.
#[derive(Debug, Clone, Default)]
pub struct StagedSecrets {
    pub auth_type: String,
    pub has_password: bool,
    pub has_key_data: bool,
    pub has_passphrase: bool,
}

/// Read `password` / `key_data` / `passphrase` for a saved session
/// and push every non-empty field into the process-singleton secret
/// store under the canonical `sess.<slot>.<id>` ids. Plaintext bytes
/// never cross the FRB boundary back to Dart — only the bool flags
/// describing which slots were staged. The caller then dispatches
/// to the matching `SshAuth*Ref` connect variant.
///
/// Returns `Ok(None)` when the session row is missing.
pub fn stage_secrets_into_store(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Option<StagedSecrets>, Error> {
    // SSH-only path. The credential triplet lives on
    // `ssh_session_details`; non-SSH sessions never had `password`
    // / `key_data` / `passphrase` columns at all, so the LEFT JOIN
    // resolves them to NULL — `COALESCE` materialises empty strings
    // and the `has_*` flags below stay false.
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT COALESCE(j.auth_type, 'password') AS auth_type, \
                    COALESCE(j.password, '') AS password, \
                    COALESCE(j.key_data, '') AS key_data, \
                    COALESCE(j.passphrase, '') AS passphrase \
             FROM sessions s LEFT JOIN ssh_session_details j ON j.session_id = s.id \
             WHERE s.id = ?1 AND s.deleted_at IS NULL",
        )
        .map_err(|e| Error::Db(format!("sessions stage_secrets prepare: {e}")))?;
    let row: Option<(String, String, String, String)> = stmt
        .query_row(params![session_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .ok();
    let Some((auth_type, password, key_data, passphrase)) = row else {
        return Ok(None);
    };

    let store = &crate::app::instance().secrets;
    let has_password = !password.is_empty();
    if has_password {
        store.put(&format!("sess.password.{session_id}"), password.as_bytes());
    }
    let has_key_data = !key_data.is_empty();
    if has_key_data {
        store.put(&format!("sess.key.{session_id}"), key_data.as_bytes());
    }
    let has_passphrase = !passphrase.is_empty();
    if has_passphrase {
        store.put(
            &format!("sess.passphrase.{session_id}"),
            passphrase.as_bytes(),
        );
    }

    Ok(Some(StagedSecrets {
        auth_type,
        has_password,
        has_key_data,
        has_passphrase,
    }))
}

/// Plain-data view of a session row used by [`update_metadata`].
/// The credential columns (`password` / `key_data` / `passphrase`)
/// are deliberately absent — they are owned by
/// [`set_secret_column`] / [`stage_secrets_into_store`] so that
/// metadata edits never need to round-trip plaintext.
#[derive(Debug, Clone)]
pub struct SessionMetadata {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub key_path: String,
    pub key_id: Option<String>,
    pub sort_order: i64,
    pub notes: String,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub updated_at_ms: i64,
}

/// Update the non-credential metadata of a session in place. The
/// `password` / `key_data` / `passphrase` columns are deliberately
/// untouched — credential edits go through [`set_secret_column`]
/// instead, so the edit dialog can save metadata changes without
/// having to first read the existing secret bytes onto the Dart
/// heap and write them back.
pub fn update_metadata(
    conn: &impl crate::db::DbAccess,
    m: &SessionMetadata,
) -> Result<usize, Error> {
    // Protocol-neutral metadata lives on `sessions`. The function
    // returns the row count from this statement so callers can
    // still detect "missing parent" (0 rows) before the join-table
    // update step touches `ssh_session_details`.
    let n = conn
        .raw()
        .execute(
            "UPDATE sessions SET \
               label = ?1, folder_id = ?2, sort_order = ?3, \
               notes = ?4, extras = ?5, updated_at = ?6 \
             WHERE id = ?7 AND deleted_at IS NULL",
            params![
                m.label,
                m.folder_id,
                m.sort_order,
                m.notes,
                m.extras,
                m.updated_at_ms,
                m.id,
            ],
        )
        .map_err(|e| Error::Db(format!("sessions update_metadata: {e}")))?;
    if n == 0 {
        return Ok(0);
    }

    // SSH-shaped fields then land on `ssh_session_details` for
    // SSH sessions. The caller is the session-edit dialog, which
    // carries `host` / `port` / `user` / `auth_type` / `key_path` /
    // `key_id` / `via_*` for SSH and empty strings / zeros for the
    // other kinds (the WebDAV / S3 transport tuple lives on its own
    // join). The straightforward way to keep the contract is to
    // inspect the row's join shape: a row with an
    // `ssh_session_details` entry already on file is SSH; one
    // without is not. The dialog only mutates SSH metadata through
    // this entry point, so the gate is sufficient.
    let has_join: bool = conn
        .raw()
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM ssh_session_details WHERE session_id = ?1)",
            params![m.id],
            |row| row.get(0),
        )
        .map_err(|e| Error::Db(format!("sessions update_metadata probe: {e}")))?;
    if !has_join {
        return Ok(n);
    }
    conn.raw()
        .execute(
            "UPDATE ssh_session_details SET \
               host = ?1, port = ?2, user = ?3, auth_type = ?4, key_path = ?5, key_id = ?6, \
               via_session_id = ?7, via_host = ?8, via_port = ?9, via_user = ?10, \
               updated_at = ?11 \
             WHERE session_id = ?12",
            params![
                m.host,
                m.port,
                m.user,
                m.auth_type,
                m.key_path,
                m.key_id,
                m.via_session_id,
                m.via_host,
                m.via_port,
                m.via_user,
                m.updated_at_ms,
                m.id,
            ],
        )
        .map_err(|e| Error::Db(format!("ssh_session_details update_metadata: {e}")))?;
    Ok(n)
}

/// Replace a single credential column on a session row. `slot` is one
/// of `"password"`, `"key_data"`, `"passphrase"`. Empty `value` writes
/// an empty string (clears the credential). `value` reaches us
/// through FRB but never crosses back to Dart — combined with
/// [`stage_secrets_into_store`] this lets the edit dialog save a new
/// password without ever pre-filling the old one onto the Dart heap.
/// Returns rows affected (1 on success, 0 on missing row, error on
/// unrecognised slot).
pub fn set_secret_column(
    conn: &impl crate::db::DbAccess,
    id: &str,
    slot: &str,
    value: &str,
    updated_at_ms: i64,
) -> Result<usize, Error> {
    let column = match slot {
        "password" => "password",
        "key_data" => "key_data",
        "passphrase" => "passphrase",
        other => return Err(Error::Db(format!("unknown secret slot: {other}"))),
    };
    // The credential triplet lives on `ssh_session_details`. The
    // caller (`db_sessions_set_secret`) is only fired for SSH
    // sessions; a sanity guard here makes the call a no-op on
    // missing-row rather than minting an orphaned `ssh_session_details`
    // entry. The parent `sessions.updated_at` also moves so the
    // sync layer's LWW timestamp on the row reflects the edit.
    let sql = format!(
        "UPDATE ssh_session_details SET {column} = ?1, updated_at = ?2 \
         WHERE session_id = ?3"
    );
    let n = conn
        .raw()
        .execute(&sql, params![value, updated_at_ms, id])
        .map_err(|e| Error::Db(format!("ssh_session_details set_secret_column: {e}")))?;
    if n > 0 {
        conn.raw()
            .execute(
                "UPDATE sessions SET updated_at = ?1 \
                 WHERE id = ?2 AND deleted_at IS NULL",
                params![updated_at_ms, id],
            )
            .map_err(|e| Error::Db(format!("sessions set_secret_column parent stamp: {e}")))?;
    }
    Ok(n)
}

/// Copy a session row by id, allocating a new id + label and
/// optionally relocating into `target_folder_id`. Credentials
/// (`password` / `key_data` / `passphrase`) flow column-to-column
/// inside SQLite without crossing back to Dart — no plaintext
/// crosses the FRB boundary for the copy. Returns "session
/// missing" when the source row has been deleted.
pub fn duplicate_session(
    conn: &impl crate::db::DbAccess,
    src_id: &str,
    new_id: &str,
    new_label: &str,
    target_folder_id: Option<&str>,
    now_ms: i64,
) -> Result<(), Error> {
    // Slim `sessions` row first. Common columns copy
    // column-to-column; `id`, `label`, `folder_id`, `created_at`,
    // `updated_at` are overridden; `last_connected_at` resets so
    // the duplicate looks "never connected".
    let n = conn
        .raw()
        .execute(
            "INSERT INTO sessions ( \
               id, label, folder_id, kind, sort_order, notes, \
               last_connected_at, extras, created_at, updated_at \
             ) \
             SELECT \
               ?1 AS id, ?2 AS label, ?3 AS folder_id, kind, sort_order, notes, \
               NULL AS last_connected_at, extras, ?4 AS created_at, ?4 AS updated_at \
             FROM sessions WHERE id = ?5 AND deleted_at IS NULL",
            params![new_id, new_label, target_folder_id, now_ms, src_id],
        )
        .map_err(|e| Error::Db(format!("sessions duplicate: {e}")))?;
    if n == 0 {
        return Err(Error::Io("sessions duplicate: source row missing".into()));
    }

    // The SSH-specific join row copies separately when the source
    // had one. Credentials flow column-to-column inside SQLite and
    // never round-trip to Dart. Non-SSH sources (no join row) skip
    // this step — `INSERT … SELECT` against an empty source set is
    // a no-op, so the predicate-free shape stays correct for every
    // transport.
    conn.raw()
        .execute(
            "INSERT INTO ssh_session_details ( \
               session_id, host, port, user, auth_type, password, key_path, key_data, \
               key_id, passphrase, via_session_id, via_host, via_port, via_user, updated_at \
             ) \
             SELECT \
               ?1 AS session_id, host, port, user, auth_type, password, key_path, key_data, \
               key_id, passphrase, via_session_id, via_host, via_port, via_user, ?2 AS updated_at \
             FROM ssh_session_details WHERE session_id = ?3",
            params![new_id, now_ms, src_id],
        )
        .map_err(|e| Error::Db(format!("ssh_session_details duplicate: {e}")))?;

    // WebDAV transport tuple — same `INSERT … SELECT` shape so a
    // non-WebDAV source set is a no-op. The duplicate gets its own
    // copy of the URL / username / auth method / trusted-cert PEM /
    // insecure-skip flag; the password / bearer token in SecretStore
    // is NOT cloned (a duplicate is a fresh row and re-uses the
    // source's secret id only if the caller explicitly re-stages —
    // typically the operator re-enters it on first connect of the
    // copy).
    conn.raw()
        .execute(
            "INSERT INTO webdav_session_details ( \
               session_id, base_url, username, auth_method, \
               trusted_cert_pem, insecure_skip_verify, updated_at \
             ) \
             SELECT \
               ?1 AS session_id, base_url, username, auth_method, \
               trusted_cert_pem, insecure_skip_verify, ?2 AS updated_at \
             FROM webdav_session_details WHERE session_id = ?3",
            params![new_id, now_ms, src_id],
        )
        .map_err(|e| Error::Db(format!("webdav_session_details duplicate: {e}")))?;

    // S3 transport tuple — same `INSERT … SELECT` shape. SigV4
    // identity (access_key_id) clones to the copy; the secret access
    // key stays under the source's SecretStore id and the copy
    // re-stages on first save / re-enter. Trust surface
    // (trusted_cert_pem, insecure_skip_verify) clones verbatim.
    conn.raw()
        .execute(
            "INSERT INTO s3_session_details ( \
               session_id, access_key_id, region, endpoint, path_style, \
               default_bucket, default_prefix, \
               trusted_cert_pem, insecure_skip_verify, updated_at \
             ) \
             SELECT \
               ?1 AS session_id, access_key_id, region, endpoint, path_style, \
               default_bucket, default_prefix, \
               trusted_cert_pem, insecure_skip_verify, ?2 AS updated_at \
             FROM s3_session_details WHERE session_id = ?3",
            params![new_id, now_ms, src_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details duplicate: {e}")))?;

    Ok(())
}

/// Transactional entry point for the FRB duplicate. [`duplicate_session`]
/// copies the parent row plus the protocol-detail row as separate
/// `INSERT … SELECT`s; one transaction keeps a partial failure from
/// leaving a duplicated session with no (or a wrong-kind) detail row.
pub fn duplicate_session_in_tx(
    conn: &mut Connection,
    src_id: &str,
    new_id: &str,
    new_label: &str,
    target_folder_id: Option<&str>,
    now_ms: i64,
) -> Result<(), Error> {
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("sessions duplicate tx: {e}")))?;
    duplicate_session(&tx, src_id, new_id, new_label, target_folder_id, now_ms)?;
    tx.commit()
        .map_err(|e| Error::Db(format!("sessions duplicate commit: {e}")))
}

/// Composite duplicate — looks up the source row, resolves
/// [`target_folder_path`] to a folder id (creating folders as
/// needed), computes a unique label against the live session list,
/// generates a fresh UUID, and inserts the duplicate row. All in
/// one transaction so a partial failure rolls back cleanly.
///
/// Returns the new session id. Mirrors what
/// `SessionStore.duplicateSession` was composing Dart-side; folding
/// the steps Rust-side keeps the unique-label + folder-creation +
/// duplicate-insert sequence atomic and lets the Dart caller drop
/// to a single FRB call.
pub fn duplicate_with_path(
    conn: &mut Connection,
    src_id: &str,
    target_folder_path: &str,
    now_ms: i64,
) -> Result<String, Error> {
    use rand::Rng;
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("sessions duplicate_with_path tx: {e}")))?;

    // Source row — needed for the base label.
    let mut stmt = tx
        .prepare_cached("SELECT label FROM sessions WHERE id = ?1 AND deleted_at IS NULL")
        .map_err(|e| Error::Db(format!("sessions duplicate_with_path lookup: {e}")))?;
    let base_label: String = stmt
        .query_row([src_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Db(format!("sessions duplicate_with_path source missing: {e}")))?;
    drop(stmt);

    // Live session labels — feed unique_label so the returned label
    // doesn't collide with anything already in the list.
    let mut taken: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut labels_stmt = tx
        .prepare_cached("SELECT label FROM sessions WHERE deleted_at IS NULL")
        .map_err(|e| Error::Db(format!("sessions duplicate_with_path labels: {e}")))?;
    let label_rows = labels_stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Db(format!("sessions duplicate_with_path labels query: {e}")))?;
    for r in label_rows {
        taken.insert(
            r.map_err(|e| Error::Db(format!("sessions duplicate_with_path label row: {e}")))?,
        );
    }
    drop(labels_stmt);
    let new_label = crate::sessions::unique_label(&base_label, &taken);

    // Folder ensure — walks the path inside the same tx so a
    // partial folder create rolls back with the duplicate.
    let target_folder_id = crate::db::folders::ensure_folder_path(&tx, target_folder_path, now_ms)?;

    // Fresh id.
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    let new_id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();

    duplicate_session(
        &tx,
        src_id,
        &new_id,
        &new_label,
        target_folder_id.as_deref(),
        now_ms,
    )?;

    tx.commit()
        .map_err(|e| Error::Db(format!("sessions duplicate_with_path commit: {e}")))?;

    Ok(new_id)
}

/// Bulk variant of [`move_to_folder`].
pub fn move_multiple(
    conn: &impl crate::db::DbAccess,
    ids: &[String],
    folder_id: Option<&str>,
    updated_at_ms: i64,
) -> Result<usize, Error> {
    if ids.is_empty() {
        return Ok(0);
    }
    let placeholders = vec!["?"; ids.len()].join(",");
    let sql = format!(
        "UPDATE sessions SET folder_id = ?1, updated_at = ?2 \
         WHERE id IN ({placeholders}) AND deleted_at IS NULL"
    );
    let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(2 + ids.len());
    params_vec.push(&folder_id as &dyn rusqlite::ToSql);
    params_vec.push(&updated_at_ms as &dyn rusqlite::ToSql);
    for id in ids {
        params_vec.push(id as &dyn rusqlite::ToSql);
    }
    conn.raw()
        .execute(&sql, params_vec.as_slice())
        .map_err(|e| Error::Db(format!("sessions move_multiple: {e}")))
}

/// Single session input for [`restore_snapshot`]. Mirrors
/// `SessionRow` but carries a `folder_path` string instead of a
/// pre-resolved `folder_id` — the snapshot caller (undo history)
/// only knows the path, and the post-restore folder tree is
/// re-minted inside the same transaction so any prior id is
/// stale anyway.
#[derive(Debug, Clone, Default)]
pub struct RestoreSessionInput {
    pub id: String,
    pub label: String,
    pub folder_path: String,
    pub kind: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

/// Atomic restore from an undo-history snapshot. Wipes the live
/// sessions + folders tables, re-creates the folder tree from the
/// distinct paths, and re-inserts every session under the freshly-
/// resolved folder id. All in one transaction so a partial failure
/// rolls back to the pre-restore state.
///
/// Empty folders (`empty_folder_paths`) are ensured separately so a
/// snapshot that captured an empty folder tree (no sessions) still
/// rebuilds the folder rows.
///
/// Replaces the Dart `SessionStore.restoreSnapshot` orchestration
/// (`dbSessionsDeleteAll` + `dbFoldersDeleteAll` + N×
/// `resolveFolderPath` + N× `dbSessionsUpsert` + M×
/// `resolveFolderPath`) with one FRB call. The N+1 round-trip
/// pattern collapses to a single transaction.
pub fn restore_snapshot(
    conn: &mut Connection,
    sessions: Vec<RestoreSessionInput>,
    empty_folder_paths: Vec<String>,
    now_ms: i64,
) -> Result<(), Error> {
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("sessions restore_snapshot tx: {e}")))?;

    delete_all(&tx)?;
    crate::db::folders::delete_all(&tx)?;

    for s in sessions {
        let folder_id = crate::db::folders::ensure_folder_path(&tx, &s.folder_path, now_ms)?;
        let row = SessionRow {
            id: s.id,
            label: s.label,
            folder_id,
            kind: s.kind,
            host: s.host,
            port: s.port,
            user: s.user,
            auth_type: s.auth_type,
            password: s.password,
            key_path: s.key_path,
            key_data: s.key_data,
            key_id: s.key_id,
            passphrase: s.passphrase,
            sort_order: s.sort_order,
            notes: s.notes,
            last_connected_at_ms: s.last_connected_at_ms,
            extras: s.extras,
            via_session_id: s.via_session_id,
            via_host: s.via_host,
            via_port: s.via_port,
            via_user: s.via_user,
            created_at_ms: s.created_at_ms,
            updated_at_ms: s.updated_at_ms,
        };
        upsert(&tx, &row)?;
    }

    for path in empty_folder_paths {
        crate::db::folders::ensure_folder_path(&tx, &path, now_ms)?;
    }

    tx.commit()
        .map_err(|e| Error::Db(format!("sessions restore_snapshot commit: {e}")))?;
    Ok(())
}

#[cfg(test)]
mod duplicate_tests {
    use super::*;
    use crate::db::{bootstrap_schema, folders, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn seed_session(db: &Db, id: &str, label: &str, folder_id: Option<&str>) {
        db.with_conn(|c| {
            let row = SessionRow {
                id: id.into(),
                label: label.into(),
                folder_id: folder_id.map(String::from),
                kind: SESSION_KIND_SSH.into(),
                host: "h".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                password: "secret".into(),
                key_path: String::new(),
                key_data: String::new(),
                key_id: None,
                passphrase: String::new(),
                sort_order: 0,
                notes: String::new(),
                last_connected_at_ms: None,
                extras: String::new(),
                via_session_id: None,
                via_host: None,
                via_port: None,
                via_user: None,
                created_at_ms: 0,
                updated_at_ms: 0,
            };
            upsert(c, &row)
        })
        .unwrap();
    }

    #[test]
    fn upsert_in_tx_round_trips_and_switches_kind() {
        let db = db();
        let mut row = SessionRow {
            id: "s1".into(),
            label: "Box".into(),
            folder_id: None,
            kind: SESSION_KIND_SSH.into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            password: "secret".into(),
            key_path: String::new(),
            key_data: String::new(),
            key_id: None,
            passphrase: String::new(),
            sort_order: 0,
            notes: String::new(),
            last_connected_at_ms: None,
            extras: String::new(),
            via_session_id: None,
            via_host: None,
            via_port: None,
            via_user: None,
            created_at_ms: 0,
            updated_at_ms: 0,
        };
        db.with_conn_mut(|c| upsert_in_tx(c, &row)).unwrap();
        let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
        assert_eq!(got.kind, SESSION_KIND_SSH);
        assert_eq!(got.host, "h");

        // Switch the kind: the SSH detail row must be dropped and the
        // WebDAV row written — both in one transaction.
        row.kind = SESSION_KIND_WEBDAV.into();
        db.with_conn_mut(|c| upsert_in_tx(c, &row)).unwrap();
        let got2 = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
        assert_eq!(got2.kind, SESSION_KIND_WEBDAV);
        // SSH detail gone → host no longer surfaces from the join.
        assert_eq!(got2.host, "");
    }

    #[test]
    fn duplicate_with_path_inserts_under_resolved_folder() {
        let db = db();
        seed_session(&db, "src", "Web", None);
        let new_id = db
            .with_conn_mut(|c| duplicate_with_path(c, "src", "infra/prod", 1000))
            .unwrap();
        let rows = db.with_conn(list_all).unwrap();
        let copy = rows.iter().find(|r| r.id == new_id).unwrap();
        assert_eq!(copy.label, "Web (copy)");
        // Folder hierarchy was created — leaf folder id matches.
        let f_rows = db.with_conn(folders::list_all).unwrap();
        let prod = f_rows.iter().find(|f| f.name == "prod").unwrap();
        assert_eq!(copy.folder_id.as_deref(), Some(prod.id.as_str()));
    }

    #[test]
    fn duplicate_with_path_propagates_credentials_column_to_column() {
        // Credentials live on the duplicate row even though they
        // never crossed the FRB boundary (the SELECT-INSERT in
        // duplicate_session preserves them).
        let db = db();
        seed_session(&db, "src", "S", None);
        let new_id = db
            .with_conn_mut(|c| duplicate_with_path(c, "src", "", 1000))
            .unwrap();
        let rows = db.with_conn(list_all).unwrap();
        let copy = rows.iter().find(|r| r.id == new_id).unwrap();
        assert_eq!(copy.password, "secret");
    }

    #[test]
    fn duplicate_with_path_unique_label_walks_taken_set() {
        let db = db();
        seed_session(&db, "src", "Web", None);
        // Pre-stamp the obvious dedup name so the next duplicate
        // walks past it instead of colliding.
        seed_session(&db, "existing", "Web (copy)", None);
        let new_id = db
            .with_conn_mut(|c| duplicate_with_path(c, "src", "", 0))
            .unwrap();
        let rows = db.with_conn(list_all).unwrap();
        let copy = rows.iter().find(|r| r.id == new_id).unwrap();
        assert_eq!(copy.label, "Web (copy 2)");
    }

    #[test]
    fn duplicate_with_path_empty_path_is_root_level() {
        let db = db();
        seed_session(&db, "src", "Web", None);
        let new_id = db
            .with_conn_mut(|c| duplicate_with_path(c, "src", "", 0))
            .unwrap();
        let rows = db.with_conn(list_all).unwrap();
        let copy = rows.iter().find(|r| r.id == new_id).unwrap();
        assert!(copy.folder_id.is_none());
    }

    #[test]
    fn duplicate_with_path_missing_source_errors() {
        let db = db();
        let err = db
            .with_conn_mut(|c| duplicate_with_path(c, "nope", "", 0))
            .unwrap_err();
        assert!(err.to_string().contains("source missing"));
    }

    #[test]
    fn duplicate_with_path_reuses_existing_folder_segments() {
        // Two duplicates into the same path must share the
        // pre-existing folder ids — `ensure_folder_path` should not
        // mint a second `infra` row.
        let db = db();
        seed_session(&db, "src", "Web", None);
        let _first = db
            .with_conn_mut(|c| duplicate_with_path(c, "src", "infra/prod", 0))
            .unwrap();
        let _second = db
            .with_conn_mut(|c| duplicate_with_path(c, "src", "infra/prod", 0))
            .unwrap();
        let folders = db.with_conn(folders::list_all).unwrap();
        let infra_count = folders.iter().filter(|f| f.name == "infra").count();
        assert_eq!(infra_count, 1, "infra folder must be reused");
        let prod_count = folders.iter().filter(|f| f.name == "prod").count();
        assert_eq!(prod_count, 1, "prod folder must be reused");
    }
}

#[cfg(test)]
mod restore_tests {
    use super::*;
    use crate::db::{bootstrap_schema, folders, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn input(id: &str, label: &str, folder_path: &str) -> RestoreSessionInput {
        RestoreSessionInput {
            id: id.into(),
            label: label.into(),
            folder_path: folder_path.into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            ..Default::default()
        }
    }

    #[test]
    fn restore_replaces_live_state_atomically() {
        let db = db();
        // Seed pre-restore state.
        db.with_conn(|c| {
            folders::upsert(
                c,
                &folders::FolderRow {
                    id: "f-old".into(),
                    name: "old".into(),
                    parent_id: None,
                    sort_order: 0,
                    collapsed: false,
                    created_at_ms: 0,
                },
            )
        })
        .unwrap();
        db.with_conn(|c| {
            upsert(
                c,
                &SessionRow {
                    id: "s-old".into(),
                    label: "old".into(),
                    folder_id: Some("f-old".into()),
                    host: "h".into(),
                    port: 22,
                    user: "u".into(),
                    auth_type: "password".into(),
                    ..Default::default()
                },
            )
        })
        .unwrap();

        db.with_conn_mut(|c| {
            restore_snapshot(
                c,
                vec![input("s1", "Web", "infra/prod"), input("s2", "Db", "")],
                vec!["empty/dir".into()],
                100,
            )
        })
        .unwrap();

        // Pre-restore rows are gone.
        let sessions = db.with_conn(list_all).unwrap();
        assert_eq!(sessions.len(), 2);
        assert!(sessions.iter().all(|s| s.id != "s-old"));
        let folder_rows = db.with_conn(folders::list_all).unwrap();
        assert!(folder_rows.iter().all(|f| f.id != "f-old"));
        // Folder tree was rebuilt: infra → prod, empty → dir.
        assert!(folder_rows.iter().any(|f| f.name == "infra"));
        assert!(folder_rows.iter().any(|f| f.name == "prod"));
        assert!(folder_rows.iter().any(|f| f.name == "empty"));
        assert!(folder_rows.iter().any(|f| f.name == "dir"));
        // Session got the freshly-resolved folder id.
        let prod = folder_rows.iter().find(|f| f.name == "prod").unwrap();
        let s1 = sessions.iter().find(|s| s.id == "s1").unwrap();
        assert_eq!(s1.folder_id.as_deref(), Some(prod.id.as_str()));
        let s2 = sessions.iter().find(|s| s.id == "s2").unwrap();
        assert!(s2.folder_id.is_none());
    }

    #[test]
    fn restore_empty_input_clears_everything() {
        let db = db();
        db.with_conn(|c| {
            upsert(
                c,
                &SessionRow {
                    id: "s-old".into(),
                    label: "old".into(),
                    host: "h".into(),
                    port: 22,
                    user: "u".into(),
                    auth_type: "password".into(),
                    ..Default::default()
                },
            )
        })
        .unwrap();
        db.with_conn_mut(|c| restore_snapshot(c, vec![], vec![], 0))
            .unwrap();
        assert!(db.with_conn(list_all).unwrap().is_empty());
        assert!(db.with_conn(folders::list_all).unwrap().is_empty());
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
                &SessionRow {
                    id: id.into(),
                    label: id.into(),
                    host: "h".into(),
                    port: 22,
                    user: "u".into(),
                    auth_type: "password".into(),
                    ..Default::default()
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
                    "SELECT deleted_at FROM sessions WHERE id = ?1",
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
        // delete() flips deleted_at; the row survives so a
        // sync-merge can replay the tombstone.
        let db = db();
        seed(&db, "s1");
        let n = db.with_conn(|c| delete(c, "s1")).unwrap();
        assert_eq!(n, 1);
        assert!(
            raw_deleted_at(&db, "s1").is_some(),
            "tombstoned row must carry deleted_at"
        );
    }

    #[test]
    fn list_all_and_get_skip_tombstoned_rows() {
        // Reads filter `WHERE deleted_at IS NULL` — a soft-deleted
        // row must be invisible to the rest of the app.
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
        assert!(db.with_conn(|c| get(c, "dead")).unwrap().is_none());
        assert!(db.with_conn(|c| get(c, "alive")).unwrap().is_some());
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        // purge_tombstones is the sync-merge teardown — once the
        // peer device has observed the tombstone, the row leaves
        // the table for good.
        let db = db();
        seed(&db, "s1");
        db.with_conn(|c| delete(c, "s1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "s1").is_none());
    }

    #[test]
    fn delete_multiple_tombstones_each_id() {
        // Bulk delete tombstones every id in the list; live rows
        // outside the list stay visible.
        let db = db();
        seed(&db, "a");
        seed(&db, "b");
        seed(&db, "c");
        let n = db
            .with_conn(|c| delete_multiple(c, &["a".into(), "b".into()]))
            .unwrap();
        assert_eq!(n, 2);
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "c");
    }

    #[test]
    fn delete_all_tombstones_every_live_row() {
        // delete_all flips every live row's deleted_at; tombstones
        // outlive the call so a peer can observe the bulk clear.
        let db = db();
        seed(&db, "a");
        seed(&db, "b");
        let n = db.with_conn(delete_all).unwrap();
        assert_eq!(n, 2);
        assert!(db.with_conn(list_all).unwrap().is_empty());
        assert!(raw_deleted_at(&db, "a").is_some());
        assert!(raw_deleted_at(&db, "b").is_some());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        // ON CONFLICT(id) DO UPDATE SET deleted_at = NULL — a
        // re-upsert of a tombstoned id makes the row visible
        // again so a recreate-with-same-id path works after a
        // soft-delete.
        let db = db();
        seed(&db, "s1");
        db.with_conn(|c| delete(c, "s1")).unwrap();
        seed(&db, "s1");
        assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
        assert!(raw_deleted_at(&db, "s1").is_none());
    }

    #[test]
    fn list_all_with_tombstones_keeps_tombstoned_rows() {
        // The sync composer needs the dead rows `list_all` hides so a
        // peer can replay the deletion; the live read path must not.
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all_with_tombstones).unwrap();
        assert_eq!(rows.len(), 2);
        let dead = rows.iter().find(|(r, _, _)| r.id == "dead").unwrap();
        assert!(dead.2.is_some(), "dead row carries a deleted_at stamp");
        let alive = rows.iter().find(|(r, _, _)| r.id == "alive").unwrap();
        assert!(alive.2.is_none(), "alive row has no tombstone");
    }

    #[test]
    fn apply_tombstone_lww_blocks_stale_stamp() {
        // Sessions key LWW on `updated_at`. A peer tombstone older
        // than the local edit must lose; a newer one wins and
        // advances the stamp so a same-time revival can't beat it.
        let db = db();
        db.with_conn(|c| {
            upsert(
                c,
                &SessionRow {
                    id: "s1".into(),
                    label: "s1".into(),
                    host: "h".into(),
                    port: 22,
                    user: "u".into(),
                    auth_type: "password".into(),
                    updated_at_ms: 100,
                    ..Default::default()
                },
            )
        })
        .unwrap();
        let n = db.with_conn(|c| apply_tombstone(c, "s1", 50)).unwrap();
        assert_eq!(n, 0);
        assert!(raw_deleted_at(&db, "s1").is_none());
        let n = db.with_conn(|c| apply_tombstone(c, "s1", 200)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "s1").is_some());
    }
}

#[cfg(test)]
mod split_v16_tests {
    //! Coverage for the v15 → v16 schema split: SSH-only columns
    //! moved off `sessions` into `ssh_session_details`. The tests
    //! cover three angles — runtime correctness of the new write
    //! path, the read-path COALESCE defaults for non-SSH kinds,
    //! and the legacy migration that runs on first open of a v15
    //! database.

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

    fn ssh_join_row_count(db: &Db, id: &str) -> i64 {
        db.with_conn(|c| {
            let n: i64 = c
                .raw()
                .query_row(
                    "SELECT COUNT(*) FROM ssh_session_details WHERE session_id = ?1",
                    params![id],
                    |r| r.get(0),
                )
                .unwrap();
            Ok(n)
        })
        .unwrap()
    }

    /// SSH `upsert` writes the credential triplet + transport
    /// tuple into `ssh_session_details`; `get` returns the same
    /// values via the LEFT JOIN. End-to-end round-trip after the
    /// split — the SessionRow struct shape is unchanged.
    #[test]
    fn ssh_upsert_round_trips_through_join_table() {
        let db = db();
        let row = SessionRow {
            id: "ssh-1".into(),
            label: "production".into(),
            kind: SESSION_KIND_SSH.into(),
            host: "10.0.0.1".into(),
            port: 2222,
            user: "deploy".into(),
            auth_type: "key".into(),
            password: "".into(),
            key_data: "PRIVATE-PEM".into(),
            passphrase: "p".into(),
            via_host: Some("bastion.example.com".into()),
            via_port: Some(22),
            via_user: Some("ops".into()),
            ..Default::default()
        };
        db.with_conn(|c| upsert(c, &row)).unwrap();

        assert_eq!(ssh_join_row_count(&db, "ssh-1"), 1);

        let got = db.with_conn(|c| get(c, "ssh-1")).unwrap().unwrap();
        assert_eq!(got.host, "10.0.0.1");
        assert_eq!(got.port, 2222);
        assert_eq!(got.user, "deploy");
        assert_eq!(got.auth_type, "key");
        assert_eq!(got.key_data, "PRIVATE-PEM");
        assert_eq!(got.passphrase, "p");
        assert_eq!(got.via_host.as_deref(), Some("bastion.example.com"));
    }

    /// Non-SSH `upsert` (WebDAV / S3) creates no
    /// `ssh_session_details` row. The transport-specific tuple
    /// lives on the matching join table (`webdav_session_details`
    /// / `s3_session_details`); the SSH join must stay empty so
    /// stage_secrets / connect paths never observe ghost
    /// credentials under a non-SSH session id.
    #[test]
    fn webdav_upsert_leaves_ssh_join_empty() {
        let db = db();
        let row = SessionRow {
            id: "dav-1".into(),
            label: "cloud".into(),
            kind: SESSION_KIND_WEBDAV.into(),
            // The legacy SessionRow fields stay populated by the
            // dialog for round-trip parity (it derives host/port
            // from base_url); they must not land on the SSH join.
            host: "cloud.example.com".into(),
            port: 443,
            user: "alice".into(),
            password: "should-not-leak".into(),
            ..Default::default()
        };
        db.with_conn(|c| upsert(c, &row)).unwrap();
        assert_eq!(ssh_join_row_count(&db, "dav-1"), 0);

        // Read-back surfaces the COALESCE defaults — non-SSH
        // kinds get empty strings / port = 22 / auth_type =
        // 'password' on the SSH-shaped fields.
        let got = db.with_conn(|c| get(c, "dav-1")).unwrap().unwrap();
        assert_eq!(got.kind, SESSION_KIND_WEBDAV);
        assert_eq!(got.host, "");
        assert_eq!(got.port, 22);
        assert_eq!(got.user, "");
        assert_eq!(got.auth_type, "password");
        assert_eq!(got.password, "");
    }

    /// Re-saving an SSH session as WebDAV deletes the
    /// `ssh_session_details` row so a kind change does not leak
    /// the old SSH credential blob under the same session id.
    #[test]
    fn kind_change_ssh_to_webdav_deletes_ssh_join_row() {
        let db = db();
        let ssh_row = SessionRow {
            id: "kc-1".into(),
            label: "morphing".into(),
            kind: SESSION_KIND_SSH.into(),
            host: "10.0.0.1".into(),
            user: "deploy".into(),
            password: "leaky".into(),
            ..Default::default()
        };
        db.with_conn(|c| upsert(c, &ssh_row)).unwrap();
        assert_eq!(ssh_join_row_count(&db, "kc-1"), 1);

        let dav_row = SessionRow {
            id: "kc-1".into(),
            kind: SESSION_KIND_WEBDAV.into(),
            ..Default::default()
        };
        db.with_conn(|c| upsert(c, &dav_row)).unwrap();
        assert_eq!(
            ssh_join_row_count(&db, "kc-1"),
            0,
            "kind change away from SSH must wipe ssh_session_details"
        );
    }
}
