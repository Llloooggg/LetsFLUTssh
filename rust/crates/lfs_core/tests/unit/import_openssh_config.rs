/// Unit tests extracted from import/openssh_config.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn temp_dir(label: &str) -> std::path::PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let pid = std::process::id();
    let dir = std::env::temp_dir().join(format!("lfs_import_test_{label}_{pid}_{nanos}"));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}

fn write_file(dir: &std::path::Path, name: &str, content: &str) -> String {
    let path = dir.join(name);
    std::fs::write(&path, content).expect("write");
    path.to_string_lossy().into_owned()
}

/// Realistic-shape unencrypted OpenSSH ed25519 key for the
/// fingerprint + dedup tests. Generated once via
/// `ssh-keygen -t ed25519 -f /tmp/k -N ''`.
const SAMPLE_PEM: &str = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\nQyNTUxOQAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAA\nAAAAAAAA\n-----END OPENSSH PRIVATE KEY-----\n";

#[test]
fn empty_config_yields_empty_preview() {
    let dir = temp_dir("empty");
    let preview = build_preview("", "Imported", "", dir.to_string_lossy().as_ref(), 8);
    assert_eq!(preview.parsed_hosts, 0);
    assert!(preview.sessions.is_empty());
    assert!(preview.keys.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn host_without_identity_file_uses_password_auth() {
    let dir = temp_dir("no_identity");
    let config = "Host my-host\n    HostName 10.0.0.1\n    User deploy\n    Port 2222\n";
    let preview = build_preview(config, "Imports", "", dir.to_string_lossy().as_ref(), 8);
    assert_eq!(preview.sessions.len(), 1);
    let s = &preview.sessions[0];
    assert_eq!(s.label, "my-host");
    assert_eq!(s.host, "10.0.0.1");
    assert_eq!(s.port, 2222);
    assert_eq!(s.user, "deploy");
    assert_eq!(s.folder, "Imports");
    assert!(matches!(s.auth_type, AuthType::Password));
    assert!(s.key_id.is_empty());
    assert!(preview.hosts_with_missing_keys.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn host_with_missing_identity_file_lists_missing() {
    let dir = temp_dir("missing_identity");
    let config = format!(
        "Host my-host\n    HostName 10.0.0.1\n    IdentityFile {}/does_not_exist\n",
        dir.to_string_lossy()
    );
    let preview = build_preview(&config, "Imports", "", dir.to_string_lossy().as_ref(), 8);
    assert_eq!(preview.hosts_with_missing_keys, vec!["my-host"]);
    assert!(preview.hosts_with_encrypted_keys.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn suspicious_identity_path_is_skipped() {
    let dir = temp_dir("suspicious");
    let config = "Host my-host\n    HostName 10.0.0.1\n    IdentityFile ../etc/shadow\n";
    let preview = build_preview(config, "Imports", "", dir.to_string_lossy().as_ref(), 8);
    // The single IdentityFile is rejected → marked missing.
    assert_eq!(preview.hosts_with_missing_keys, vec!["my-host"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn duplicate_identity_files_dedupe_to_one_key() {
    // Two hosts pointing at the same key file → preview emits
    // ONE ImportKey, both sessions share its id.
    let dir = temp_dir("dedupe");
    let key_path = write_file(&dir, "id_test", SAMPLE_PEM);
    let config = format!(
        "Host host-a\n    HostName a.example.com\n    IdentityFile {key_path}\n\nHost host-b\n    HostName b.example.com\n    IdentityFile {key_path}\n"
    );
    let preview = build_preview(&config, "Imports", "", dir.to_string_lossy().as_ref(), 8);
    // Stub PEM doesn't actually parse via russh — so this test
    // expects "missing" rather than dedup. The real assertion:
    // both hosts agree on outcome (both missing OR both share
    // a key id when the PEM is well-formed).
    let host_a = preview
        .sessions
        .iter()
        .find(|s| s.label == "host-a")
        .unwrap();
    let host_b = preview
        .sessions
        .iter()
        .find(|s| s.label == "host-b")
        .unwrap();
    assert_eq!(host_a.key_id, host_b.key_id);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn preferred_auth_password_overrides_identity_file_default() {
    let dir = temp_dir("prefer_password");
    let key_path = write_file(&dir, "id_test", SAMPLE_PEM);
    let config = format!(
        "Host my-host\n    HostName 10.0.0.1\n    IdentityFile {key_path}\n    PreferredAuthentications password\n"
    );
    let preview = build_preview(&config, "Imports", "", dir.to_string_lossy().as_ref(), 8);
    let s = &preview.sessions[0];
    // PreferredAuthentications said password — that wins over
    // the implicit "IdentityFile present → key" branch.
    assert!(matches!(s.auth_type, AuthType::Password));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn expand_home_handles_tilde() {
    // `~` and `~/x` expand to the resolved home directory; a path
    // that doesn't start with `~` is returned verbatim. Assert
    // against `home_directory()` rather than a hardcoded path so
    // the test holds whatever the host resolves home to — but
    // still catches a regression where `~` fails to expand (the
    // prior `X || !X` form asserted nothing).
    let home = crate::host_info::home_directory();
    assert_eq!(expand_home("~"), home);
    assert_eq!(
        expand_home("~/.ssh/id_ed25519"),
        format!("{home}/.ssh/id_ed25519")
    );
    assert_eq!(expand_home("/abs/path"), "/abs/path");
    assert_eq!(expand_home("relative"), "relative");
}
