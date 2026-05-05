//! FRB adapter for `lfs_core::qr_compose` — typed QR-payload
//! composer that the `unified_export_controller` live size
//! estimator routes through.
//!
//! Sync — composition is a few hundred clones + a deflate pass,
//! sub-millisecond on realistic export selections (≤100 sessions
//! with optional config + tags + snippets). The controller calls
//! the size estimator on every checkbox toggle from synchronous
//! Riverpod-driven UI rebuilds, so the no-async-hop overhead is
//! load-bearing for the live "fits in QR" gauge.

use lfs_core::qr_compose;

use crate::api::archive::DbQrExportOptions;

/// FRB mirror of `qr_compose::QrSessionInput`. Folder paths,
/// passwords, key bytes, key-id refs are all pre-resolved by the
/// Dart caller (matches the in-memory composition the controller
/// already does for the dummy-session estimator path).
#[derive(Debug, Clone)]
pub struct DbQrSessionInput {
    pub id: String,
    pub label: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_id: Option<String>,
    pub key_data: String,
    pub folder_path: String,
}

impl From<DbQrSessionInput> for qr_compose::QrSessionInput {
    fn from(d: DbQrSessionInput) -> Self {
        Self {
            id: d.id,
            label: d.label,
            host: d.host,
            port: d.port,
            user: d.user,
            auth_type: d.auth_type,
            password: d.password,
            key_id: d.key_id,
            key_data: d.key_data,
            folder_path: d.folder_path,
        }
    }
}

/// FRB mirror of `qr_compose::QrTagInput`.
#[derive(Debug, Clone)]
pub struct DbQrTagInput {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
}

impl From<DbQrTagInput> for qr_compose::QrTagInput {
    fn from(d: DbQrTagInput) -> Self {
        Self {
            id: d.id,
            name: d.name,
            color: d.color,
        }
    }
}

/// FRB mirror of `qr_compose::QrSnippetInput`.
#[derive(Debug, Clone)]
pub struct DbQrSnippetInput {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
}

impl From<DbQrSnippetInput> for qr_compose::QrSnippetInput {
    fn from(d: DbQrSnippetInput) -> Self {
        Self {
            id: d.id,
            title: d.title,
            command: d.command,
            description: d.description,
        }
    }
}

/// FRB mirror of `qr_compose::QrManagerKeyEntry`.
#[derive(Debug, Clone)]
pub struct DbQrManagerKeyEntry {
    pub id: String,
    pub label: String,
    pub key_type: String,
    pub public_key: String,
    pub private_key: String,
}

impl From<DbQrManagerKeyEntry> for qr_compose::QrManagerKeyEntry {
    fn from(d: DbQrManagerKeyEntry) -> Self {
        Self {
            id: d.id,
            label: d.label,
            key_type: d.key_type,
            public_key: d.public_key,
            private_key: d.private_key,
        }
    }
}

/// FRB mirror of `qr_compose::QrSessionTagLink`.
#[derive(Debug, Clone)]
pub struct DbQrSessionTagLink {
    pub session_id: String,
    pub tag_id: String,
}

impl From<DbQrSessionTagLink> for qr_compose::QrSessionTagLink {
    fn from(d: DbQrSessionTagLink) -> Self {
        Self {
            session_id: d.session_id,
            tag_id: d.tag_id,
        }
    }
}

/// FRB mirror of `qr_compose::QrFolderTagLink`.
#[derive(Debug, Clone)]
pub struct DbQrFolderTagLink {
    pub folder_path: String,
    pub tag_id: String,
}

impl From<DbQrFolderTagLink> for qr_compose::QrFolderTagLink {
    fn from(d: DbQrFolderTagLink) -> Self {
        Self {
            folder_path: d.folder_path,
            tag_id: d.tag_id,
        }
    }
}

/// FRB mirror of `qr_compose::QrSessionSnippetLink`.
#[derive(Debug, Clone)]
pub struct DbQrSessionSnippetLink {
    pub session_id: String,
    pub snippet_id: String,
}

impl From<DbQrSessionSnippetLink> for qr_compose::QrSessionSnippetLink {
    fn from(d: DbQrSessionSnippetLink) -> Self {
        Self {
            session_id: d.session_id,
            snippet_id: d.snippet_id,
        }
    }
}

/// FRB mirror of `qr_compose::QrPayloadInput`. Crosses the
/// boundary as a flat struct so the Dart caller can build it
/// inline from the export-dialog selections.
#[derive(Debug, Clone)]
pub struct DbQrPayloadInput {
    pub options: DbQrExportOptions,
    pub sessions: Vec<DbQrSessionInput>,
    pub empty_folders: Vec<String>,
    pub config_json: Option<String>,
    pub known_hosts: String,
    pub tags: Vec<DbQrTagInput>,
    pub session_tags: Vec<DbQrSessionTagLink>,
    pub folder_tags: Vec<DbQrFolderTagLink>,
    pub snippets: Vec<DbQrSnippetInput>,
    pub session_snippets: Vec<DbQrSessionSnippetLink>,
    pub manager_key_entries: Vec<DbQrManagerKeyEntry>,
}

impl From<DbQrPayloadInput> for qr_compose::QrPayloadInput {
    fn from(d: DbQrPayloadInput) -> Self {
        Self {
            options: lfs_core::archive::QrExportOptions {
                include_sessions: d.options.include_sessions,
                include_config: d.options.include_config,
                include_known_hosts: d.options.include_known_hosts,
                include_passwords: d.options.include_passwords,
                include_embedded_keys: d.options.include_embedded_keys,
                include_manager_keys: d.options.include_manager_keys,
                include_all_manager_keys: d.options.include_all_manager_keys,
                include_tags: d.options.include_tags,
                include_snippets: d.options.include_snippets,
            },
            sessions: d.sessions.into_iter().map(Into::into).collect(),
            empty_folders: d.empty_folders,
            config_json: d.config_json,
            known_hosts: d.known_hosts,
            tags: d.tags.into_iter().map(Into::into).collect(),
            session_tags: d.session_tags.into_iter().map(Into::into).collect(),
            folder_tags: d.folder_tags.into_iter().map(Into::into).collect(),
            snippets: d.snippets.into_iter().map(Into::into).collect(),
            session_snippets: d.session_snippets.into_iter().map(Into::into).collect(),
            manager_key_entries: d.manager_key_entries.into_iter().map(Into::into).collect(),
        }
    }
}

/// Compose the v4 payload + deflate + base64url and return the
/// byte count. Same wire shape + alphabet as
/// `db_export_qr_payload` (production export); both producers
/// route through `lfs_core::qr_compose::compose_qr_payload`.
///
/// Used by the Dart `unified_export_controller` for the live
/// "fits in QR" gauge — single sync FRB call replaces the
/// per-toggle Dart-side JSON build + Rust deflate round-trip.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_estimate_export_size(input: DbQrPayloadInput) -> u32 {
    qr_compose::compose_and_size(&input.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_options() -> DbQrExportOptions {
        DbQrExportOptions {
            include_sessions: false,
            include_config: false,
            include_known_hosts: false,
            include_passwords: false,
            include_embedded_keys: false,
            include_manager_keys: false,
            include_all_manager_keys: false,
            include_tags: false,
            include_snippets: false,
        }
    }

    fn empty_payload() -> DbQrPayloadInput {
        DbQrPayloadInput {
            options: empty_options(),
            sessions: vec![],
            empty_folders: vec![],
            config_json: None,
            known_hosts: String::new(),
            tags: vec![],
            session_tags: vec![],
            folder_tags: vec![],
            snippets: vec![],
            session_snippets: vec![],
            manager_key_entries: vec![],
        }
    }

    // ── From conversions ──────────────────────────────────────

    #[test]
    fn db_qr_session_input_from_preserves_every_field() {
        let d = DbQrSessionInput {
            id: "s1".into(),
            label: "label".into(),
            host: "host.example".into(),
            port: 2222,
            user: "deploy".into(),
            auth_type: "key".into(),
            password: "secret".into(),
            key_id: Some("k-ext".into()),
            key_data: "PEM".into(),
            folder_path: "Prod/Web".into(),
        };
        let out: qr_compose::QrSessionInput = d.into();
        assert_eq!(out.id, "s1");
        assert_eq!(out.label, "label");
        assert_eq!(out.host, "host.example");
        assert_eq!(out.port, 2222);
        assert_eq!(out.user, "deploy");
        assert_eq!(out.auth_type, "key");
        assert_eq!(out.password, "secret");
        assert_eq!(out.key_id.as_deref(), Some("k-ext"));
        assert_eq!(out.key_data, "PEM");
        assert_eq!(out.folder_path, "Prod/Web");
    }

    #[test]
    fn db_qr_tag_input_from_preserves_every_field() {
        let d = DbQrTagInput {
            id: "t1".into(),
            name: "prod".into(),
            color: Some("#abcdef".into()),
        };
        let out: qr_compose::QrTagInput = d.into();
        assert_eq!(out.id, "t1");
        assert_eq!(out.name, "prod");
        assert_eq!(out.color.as_deref(), Some("#abcdef"));
    }

    #[test]
    fn db_qr_tag_input_from_preserves_none_color() {
        let d = DbQrTagInput {
            id: "t1".into(),
            name: "prod".into(),
            color: None,
        };
        let out: qr_compose::QrTagInput = d.into();
        assert!(out.color.is_none());
    }

    #[test]
    fn db_qr_snippet_input_from_preserves_every_field() {
        let d = DbQrSnippetInput {
            id: "sn1".into(),
            title: "list".into(),
            command: "ls -la".into(),
            description: "long-list".into(),
        };
        let out: qr_compose::QrSnippetInput = d.into();
        assert_eq!(out.id, "sn1");
        assert_eq!(out.title, "list");
        assert_eq!(out.command, "ls -la");
        assert_eq!(out.description, "long-list");
    }

    #[test]
    fn db_qr_manager_key_entry_from_preserves_every_field() {
        let d = DbQrManagerKeyEntry {
            id: "k1".into(),
            label: "manager-a".into(),
            key_type: "ed25519".into(),
            public_key: "PUB".into(),
            private_key: "PRIV".into(),
        };
        let out: qr_compose::QrManagerKeyEntry = d.into();
        assert_eq!(out.id, "k1");
        assert_eq!(out.label, "manager-a");
        assert_eq!(out.key_type, "ed25519");
        assert_eq!(out.public_key, "PUB");
        assert_eq!(out.private_key, "PRIV");
    }

    #[test]
    fn db_qr_session_tag_link_from_preserves_pair() {
        let d = DbQrSessionTagLink {
            session_id: "s1".into(),
            tag_id: "t1".into(),
        };
        let out: qr_compose::QrSessionTagLink = d.into();
        assert_eq!(out.session_id, "s1");
        assert_eq!(out.tag_id, "t1");
    }

    #[test]
    fn db_qr_folder_tag_link_from_preserves_pair() {
        let d = DbQrFolderTagLink {
            folder_path: "Prod/Web".into(),
            tag_id: "t1".into(),
        };
        let out: qr_compose::QrFolderTagLink = d.into();
        assert_eq!(out.folder_path, "Prod/Web");
        assert_eq!(out.tag_id, "t1");
    }

    #[test]
    fn db_qr_session_snippet_link_from_preserves_pair() {
        let d = DbQrSessionSnippetLink {
            session_id: "s1".into(),
            snippet_id: "sn1".into(),
        };
        let out: qr_compose::QrSessionSnippetLink = d.into();
        assert_eq!(out.session_id, "s1");
        assert_eq!(out.snippet_id, "sn1");
    }

    #[test]
    fn db_qr_payload_input_from_preserves_options_and_arrays() {
        let mut d = empty_payload();
        d.options.include_sessions = true;
        d.options.include_passwords = true;
        d.options.include_tags = true;
        d.options.include_all_manager_keys = true;
        d.sessions = vec![DbQrSessionInput {
            id: "s1".into(),
            label: "p1".into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            password: String::new(),
            key_id: None,
            key_data: String::new(),
            folder_path: String::new(),
        }];
        d.empty_folders = vec!["A".into(), "B/C".into()];
        d.config_json = Some(r#"{"k":"v"}"#.into());
        d.known_hosts = "host ssh-rsa K".into();
        d.tags = vec![DbQrTagInput {
            id: "t1".into(),
            name: "n".into(),
            color: None,
        }];
        d.manager_key_entries = vec![DbQrManagerKeyEntry {
            id: "k1".into(),
            label: "mk".into(),
            key_type: "ed25519".into(),
            public_key: "P".into(),
            private_key: "S".into(),
        }];
        let out: qr_compose::QrPayloadInput = d.into();
        assert!(out.options.include_sessions);
        assert!(out.options.include_passwords);
        assert!(out.options.include_tags);
        assert!(out.options.include_all_manager_keys);
        assert_eq!(out.sessions.len(), 1);
        assert_eq!(out.empty_folders, vec!["A".to_string(), "B/C".into()]);
        assert_eq!(out.config_json.as_deref(), Some(r#"{"k":"v"}"#));
        assert_eq!(out.known_hosts, "host ssh-rsa K");
        assert_eq!(out.tags.len(), 1);
        assert_eq!(out.manager_key_entries.len(), 1);
    }

    // ── qr_estimate_export_size ───────────────────────────────

    #[test]
    fn estimate_size_returns_non_zero_for_any_payload() {
        // Even an empty options payload carries v=4 which compresses
        // to a non-zero byte count after deflate + base64url.
        let n = qr_estimate_export_size(empty_payload());
        assert!(
            n > 0,
            "size must be > 0 (empty payload still has `v` field)"
        );
    }

    #[test]
    fn estimate_size_grows_with_content() {
        let baseline = qr_estimate_export_size(empty_payload());
        let mut p = empty_payload();
        p.options.include_sessions = true;
        p.sessions = vec![DbQrSessionInput {
            id: "s1".into(),
            label: "longer-session-label".into(),
            host: "long.host.example.com".into(),
            port: 22,
            user: "deploy".into(),
            auth_type: "password".into(),
            password: "x".repeat(200),
            key_id: None,
            key_data: String::new(),
            folder_path: String::new(),
        }];
        p.options.include_passwords = true;
        let with_session = qr_estimate_export_size(p);
        assert!(
            with_session > baseline,
            "adding a session must grow the estimate (baseline {baseline}, with {with_session})"
        );
    }
}
