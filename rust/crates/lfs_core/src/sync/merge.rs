//! Last-write-wins merge between a peer-snapshot
//! [`crate::archive::PendingImport`] and the local SQLCipher DB.
//!
//! The orchestrator pulls the encrypted `.lfs` from the WebDAV
//! remote, runs it through
//! [`crate::archive::read_archive_to_pending`], and hands the
//! resulting pending state here. This module folds the peer's
//! rows into the local DB with per-row LWW resolution against the
//! row's `updated_at` (or `created_at` for tables that don't
//! carry an explicit update timestamp — `ssh_keys`, `tags`,
//! `sftp_bookmarks`).
//!
//! # LWW rules (per table)
//!
//! | Table | Field consulted |
//! |---|---|
//! | `sessions` | `max(updated_at, deleted_at)` |
//! | `snippets` | `max(updated_at, deleted_at)` |
//! | `ssh_keys` | `max(created_at, deleted_at)` |
//! | `tags` | `max(created_at, deleted_at)` |
//! | `sftp_bookmarks` | `max(created_at, deleted_at)` |
//!
//! Local-only rows are kept (the peer hasn't seen them yet; the
//! next push surfaces them). Peer-only rows are inserted.
//!
//! # Tombstone replay caveat (v1 wire format)
//!
//! The current `.lfs` archive shape emits **live rows only** —
//! [`crate::archive::compose::build_sessions_value`] and its
//! siblings filter `deleted_at IS NULL` before serialising. A
//! peer device cannot observe a tombstone the source device
//! stamped through this v1 path; cross-device deletion replay
//! lands when the export pipeline grows a `deleted_at` field
//! per row. Documented here so the gap is visible to the next
//! reader.
//!
//! # M2M join tables
//!
//! `session_tags`, `folder_tags`, and `session_snippets` carry
//! no timestamps — the rows are weak references between two
//! timestamped parents. The merge unions the local + pending
//! edges via `INSERT OR IGNORE`: every edge either side knows
//! about survives. Removal of an edge is not replayed because
//! the wire format does not carry a "this edge was deleted"
//! marker. A peer device that unlinks a tag from a session
//! does NOT propagate the unlink through v1 sync; the user
//! re-unlinks on the second device. Documented as a known
//! v1 limitation in `docs/ARCHITECTURE.md` Sync §.
//!
//! # Transaction discipline
//!
//! The merge runs inside a single SQLite transaction so a
//! mid-merge error rolls back the entire fold. Callers route
//! through [`crate::db::Db::with_conn_mut`] which gives the
//! merge a `&mut Connection`; the function opens a
//! `rusqlite::Transaction` against that handle and either
//! commits the whole fold or rolls back to the pre-merge
//! state.

use crate::archive::{apply_pending_to_db, ApplyMode, ApplyOptions, ApplyOutcome, PendingImport};
use crate::db::Connection;
use crate::error::Error;

/// Per-kind counters the orchestrator surfaces to the UI after
/// a successful pull. Each counter increments only when the
/// peer's row actually displaces (or inserts) something
/// locally — a pending row whose timestamp is older than the
/// local row is a no-op and does not count.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MergeOutcome {
    pub sessions_merged: u32,
    pub keys_merged: u32,
    pub tags_merged: u32,
    pub snippets_merged: u32,
    pub bookmarks_merged: u32,
    pub session_tag_edges_merged: u32,
    pub folder_tag_edges_merged: u32,
    pub session_snippet_edges_merged: u32,
    /// Errors collected during the merge (per-row parse / DAO
    /// failures). The transaction commits even if a few rows
    /// failed — same shape as the import-apply driver in
    /// [`crate::archive::apply`].
    pub errors: Vec<String>,
}

/// Fold `pending` into `conn`'s live tables under LWW. Thin wrapper
/// around [`apply_pending_to_db`] with [`ApplyMode::Sync`]; the
/// unified driver runs the merge inside one transaction and routes
/// every per-kind branch through the same helper set the archive-
/// import path uses (LWW gates inside each helper guard the
/// peer-newer-wins contract).
///
/// Per-row parse failures land in [`MergeOutcome::errors`]; the
/// transaction still commits so a single corrupt entry in a 500-row
/// pull does not abort the whole merge. Catastrophic DB errors
/// (transaction begin/commit failure, schema mismatch) bubble up as
/// `Err`.
pub fn merge_pending_into_local(
    conn: &mut Connection,
    pending: &PendingImport,
) -> Result<MergeOutcome, Error> {
    let mut outcome = ApplyOutcome::default();
    // ApplyOptions is ignored under Sync mode (the orchestrator
    // always applies every entry the peer carried); supply a default
    // for the unified entry's signature.
    let options = ApplyOptions::default();
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    apply_pending_to_db(
        conn,
        pending,
        ApplyMode::Sync,
        &options,
        now_ms,
        &mut outcome,
    )?;
    Ok(MergeOutcome::from_apply_outcome(outcome))
}

impl MergeOutcome {
    /// Project the unified [`ApplyOutcome`] onto the sync-shape
    /// counters Dart's `lfs_frb::api::sync` adapter consumes. The
    /// per-kind shape matches the pre-unification fields one-for-one;
    /// new v3 child-table counters land on
    /// [`MergeOutcome::bookmarks_merged`] (SFTP bookmarks) and stay
    /// projected straight from the unified outcome.
    pub fn from_apply_outcome(o: ApplyOutcome) -> Self {
        Self {
            sessions_merged: o.sessions_applied as u32,
            keys_merged: o.keys_applied as u32,
            tags_merged: o.tags_applied as u32,
            snippets_merged: o.snippets_applied as u32,
            bookmarks_merged: o.sftp_bookmarks_applied as u32,
            session_tag_edges_merged: o.session_tags_applied as u32,
            folder_tag_edges_merged: o.folder_tags_applied as u32,
            session_snippet_edges_merged: o.session_snippets_applied as u32,
            errors: o.errors,
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::archive::PendingImport;
    use crate::db::{bootstrap_schema, sessions, snippets, ssh_keys, tags, Connection, Db};

    fn fresh_db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn pending_with(sessions_json: Option<&str>) -> PendingImport {
        PendingImport {
            manifest_json: None,
            sessions_json: sessions_json.map(String::from),
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
        }
    }

    #[test]
    fn merge_inserts_peer_only_session() {
        let db = fresh_db();
        let json = r#"[{
            "id":"s1","label":"prod","folder":"",
            "host":"h.example.com","port":22,"user":"root",
            "auth_type":"password","password":"pw",
            "key_path":"","key_data":"","passphrase":"",
            "created_at":"2024-01-01T00:00:00.000Z",
            "updated_at":"2024-01-01T00:00:00.000Z"
        }]"#;
        let pending = pending_with(Some(json));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 1);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "s1");
        assert_eq!(rows[0].label, "prod");
    }

    #[test]
    fn merge_skips_stale_peer_session() {
        // Local has s1 with updated_at = 1700000000000; peer has the
        // same id with an older updated_at. LWW must keep the local
        // shape.
        let db = fresh_db();
        let row = sessions::SessionRow {
            id: "s1".into(),
            label: "local-label".into(),
            host: "local.example.com".into(),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            password: "local-pw".into(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
        let peer_json = r#"[{
            "id":"s1","label":"peer-label","folder":"",
            "host":"peer.example.com","port":22,"user":"root",
            "auth_type":"password","password":"peer-pw",
            "key_path":"","key_data":"","passphrase":"",
            "created_at":"2023-01-01T00:00:00.000Z",
            "updated_at":"2023-01-01T00:00:00.000Z"
        }]"#;
        let pending = pending_with(Some(peer_json));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 0);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows[0].label, "local-label");
    }

    #[test]
    fn merge_overwrites_with_newer_peer_session() {
        let db = fresh_db();
        let row = sessions::SessionRow {
            id: "s1".into(),
            label: "old".into(),
            host: "h".into(),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
        let peer_json = r#"[{
            "id":"s1","label":"new","folder":"",
            "host":"h","port":22,"user":"root",
            "auth_type":"password","password":"",
            "key_path":"","key_data":"","passphrase":"",
            "created_at":"2024-01-01T00:00:00.000Z",
            "updated_at":"2030-01-01T00:00:00.000Z"
        }]"#;
        let pending = pending_with(Some(peer_json));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 1);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows[0].label, "new");
    }

    #[test]
    fn merge_keeps_local_only_session() {
        let db = fresh_db();
        let row = sessions::SessionRow {
            id: "local-only".into(),
            label: "kept".into(),
            host: "h".into(),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
        let pending = pending_with(Some("[]"));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 0);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "local-only");
    }

    #[test]
    fn merge_session_tag_edges_are_unioned() {
        let db = fresh_db();
        // Seed two tags + one session on the local side.
        let session = sessions::SessionRow {
            id: "s1".into(),
            label: "s1".into(),
            host: "h".into(),
            user: "u".into(),
            port: 22,
            auth_type: "password".into(),
            created_at_ms: 1,
            updated_at_ms: 1,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &session)).unwrap();
        let t_local = tags::TagRow {
            id: "t1".into(),
            name: "local".into(),
            color: None,
            created_at_ms: 1,
        };
        let t_peer = tags::TagRow {
            id: "t2".into(),
            name: "peer".into(),
            color: None,
            created_at_ms: 1,
        };
        db.with_conn(|c| tags::upsert(c, &t_local)).unwrap();
        db.with_conn(|c| tags::upsert(c, &t_peer)).unwrap();
        db.with_conn(|c| tags::link_session_tag(c, "s1", "t1"))
            .unwrap();
        // Peer also knows the same session and links it to t2.
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: None,
            tags_json: None,
            session_tags_json: Some(r#"[{"session_id":"s1","tag_id":"t2"}]"#.into()),
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
        };
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.session_tag_edges_merged, 1);
        let ids = db
            .with_conn(|c| tags::list_session_tag_ids(c, "s1"))
            .unwrap();
        assert!(ids.contains(&"t1".to_string()));
        assert!(ids.contains(&"t2".to_string()));
    }

    #[test]
    fn merge_keys_skips_stale_peer_row() {
        let db = fresh_db();
        let row = ssh_keys::SshKeyRow {
            id: "k1".into(),
            label: "local".into(),
            private_key: "P".into(),
            public_key: "P".into(),
            key_type: "ed25519".into(),
            is_generated: true,
            created_at_ms: 1_700_000_000_000,
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
        };
        db.with_conn(|c| ssh_keys::upsert(c, &row)).unwrap();
        let peer = r#"[{
            "id":"k1","label":"peer","private_key":"X","public_key":"X",
            "key_type":"ed25519","is_generated":true,
            "created_at":"2020-01-01T00:00:00.000Z"
        }]"#;
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: Some(peer.into()),
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
        };
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.keys_merged, 0);
        let rows = db.with_conn(ssh_keys::list_all).unwrap();
        assert_eq!(rows[0].label, "local");
    }

    #[test]
    fn merge_snippets_overwrites_when_peer_newer() {
        let db = fresh_db();
        let local = snippets::SnippetRow {
            id: "sn1".into(),
            title: "old".into(),
            command: "echo old".into(),
            description: String::new(),
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        db.with_conn(|c| snippets::upsert(c, &local)).unwrap();
        let peer = r#"[{
            "id":"sn1","title":"new","command":"echo new","description":"",
            "created_at":"2020-01-01T00:00:00.000Z",
            "updated_at":"2030-01-01T00:00:00.000Z"
        }]"#;
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: Some(peer.into()),
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
        };
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.snippets_merged, 1);
        let rows = db.with_conn(snippets::list_all).unwrap();
        assert_eq!(rows[0].title, "new");
    }
}
