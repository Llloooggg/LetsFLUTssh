//! FRB adapter for `lfs_core::import::openssh_config`.
//!
//! Sync — every step is bounded local-fs / string work. The
//! Dart wrapper takes the returned wire types and constructs the
//! Flutter-side `Session` / `SshKeyEntry` / `ImportResult`
//! models without hitting Rust again.

// Re-using `DbOpenSshAuthType` from the parser shim — same wire
// shape so the Dart side maps once. The From impl lives in
// `crate::api::ssh_config`.
use crate::api::ssh_config::DbOpenSshAuthType;

#[derive(Debug, Clone)]
pub struct DbOpenSshImportSession {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: u32,
    pub user: String,
    pub auth_type: DbOpenSshAuthType,
    pub key_id: String,
}

#[derive(Debug, Clone)]
pub struct DbOpenSshImportKey {
    pub id: String,
    pub label: String,
    pub private_pem: String,
    pub public_openssh: String,
    pub key_type: String,
    pub fingerprint: String,
    pub created_at_unix_ms: i64,
}

#[derive(Debug, Clone)]
pub struct DbOpenSshImportPreview {
    pub sessions: Vec<DbOpenSshImportSession>,
    pub keys: Vec<DbOpenSshImportKey>,
    pub parsed_hosts: u32,
    pub hosts_with_missing_keys: Vec<String>,
    pub hosts_with_encrypted_keys: Vec<String>,
}

/// Parse an OpenSSH config blob and produce the import preview.
/// `base_dir` anchors relative `Include` paths (Dart passes
/// `<home>/.ssh` by convention); `key_label_suffix` is the
/// date-stamp the importer appends to suggested key labels.
#[flutter_rust_bridge::frb(sync)]
pub fn openssh_config_build_preview(
    config_content: String,
    folder_label: String,
    key_label_suffix: String,
    base_dir: String,
    max_include_depth: u32,
) -> DbOpenSshImportPreview {
    let preview = lfs_core::import::openssh_config::build_preview(
        &config_content,
        &folder_label,
        &key_label_suffix,
        &base_dir,
        max_include_depth as usize,
    );
    DbOpenSshImportPreview {
        sessions: preview
            .sessions
            .into_iter()
            .map(|s| DbOpenSshImportSession {
                id: s.id,
                label: s.label,
                folder: s.folder,
                host: s.host,
                port: s.port as u32,
                user: s.user,
                auth_type: s.auth_type.into(),
                key_id: s.key_id,
            })
            .collect(),
        keys: preview
            .keys
            .into_iter()
            .map(|k| DbOpenSshImportKey {
                id: k.id,
                label: k.label,
                private_pem: k.private_pem,
                public_openssh: k.public_openssh,
                key_type: k.key_type,
                fingerprint: k.fingerprint,
                created_at_unix_ms: k.created_at_unix_ms,
            })
            .collect(),
        parsed_hosts: preview.parsed_hosts,
        hosts_with_missing_keys: preview.hosts_with_missing_keys,
        hosts_with_encrypted_keys: preview.hosts_with_encrypted_keys,
    }
}

/// Expand a leading `~` in `path` against the user's home
/// directory. Surface used by the Dart `OpenSshConfigImporter.expandHome`
/// callers (settings dialogs, key-manager forms).
#[flutter_rust_bridge::frb(sync)]
pub fn openssh_config_expand_home(path: String) -> String {
    lfs_core::import::openssh_config::expand_home(&path)
}

/// Read the OpenSSH config at `path` from disk and produce the
/// import preview. `base_dir` defaults to the file's parent
/// directory when empty, so `Include` directives resolve relative
/// to the picked config. Returns `None` for missing files / I/O
/// errors / non-UTF-8 content — every "nothing to show" outcome
/// the Dart caller would surface as the silent fallthrough.
pub async fn openssh_config_build_preview_from_path(
    path: String,
    folder_label: String,
    key_label_suffix: String,
    base_dir: String,
    max_include_depth: u32,
) -> Option<DbOpenSshImportPreview> {
    tokio::task::spawn_blocking(move || {
        let p = std::path::PathBuf::from(path);
        lfs_core::import::openssh_config::build_preview_from_path(
            &p,
            &folder_label,
            &key_label_suffix,
            &base_dir,
            max_include_depth as usize,
        )
        .map(|preview| DbOpenSshImportPreview {
            sessions: preview
                .sessions
                .into_iter()
                .map(|s| DbOpenSshImportSession {
                    id: s.id,
                    label: s.label,
                    folder: s.folder,
                    host: s.host,
                    port: s.port as u32,
                    user: s.user,
                    auth_type: s.auth_type.into(),
                    key_id: s.key_id,
                })
                .collect(),
            keys: preview
                .keys
                .into_iter()
                .map(|k| DbOpenSshImportKey {
                    id: k.id,
                    label: k.label,
                    private_pem: k.private_pem,
                    public_openssh: k.public_openssh,
                    key_type: k.key_type,
                    fingerprint: k.fingerprint,
                    created_at_unix_ms: k.created_at_unix_ms,
                })
                .collect(),
            parsed_hosts: preview.parsed_hosts,
            hosts_with_missing_keys: preview.hosts_with_missing_keys,
            hosts_with_encrypted_keys: preview.hosts_with_encrypted_keys,
        })
    })
    .await
    .ok()
    .flatten()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_preview_empty_config_returns_empty_collections() {
        let p = openssh_config_build_preview(
            String::new(),
            "imported".into(),
            "2026-05-09".into(),
            "/tmp/nonexistent-base".into(),
            16,
        );
        assert!(p.sessions.is_empty());
        assert!(p.keys.is_empty());
        assert_eq!(p.parsed_hosts, 0);
        assert!(p.hosts_with_missing_keys.is_empty());
        assert!(p.hosts_with_encrypted_keys.is_empty());
    }

    #[test]
    fn build_preview_recognises_a_simple_host_block() {
        // Single Host stanza, no IdentityFile so the preview
        // emits the session shape under password auth and no key
        // entries.
        let cfg = "\
Host edge\n\
    HostName edge.example.com\n\
    User deploy\n\
    Port 2222\n";
        let p = openssh_config_build_preview(
            cfg.to_string(),
            "imported".into(),
            "2026-05-09".into(),
            "/tmp/nonexistent-base".into(),
            16,
        );
        assert!(p.parsed_hosts >= 1);
        assert_eq!(p.sessions.len(), 1);
        let s = &p.sessions[0];
        assert!(s.host.contains("edge.example.com"));
        assert_eq!(s.user, "deploy");
        assert_eq!(s.port, 2222);
    }

    #[test]
    fn expand_home_passes_a_plain_path_through() {
        // A path with no leading `~` returns unchanged.
        assert_eq!(
            openssh_config_expand_home("/etc/ssh/ssh_config".into()),
            "/etc/ssh/ssh_config"
        );
    }
}
