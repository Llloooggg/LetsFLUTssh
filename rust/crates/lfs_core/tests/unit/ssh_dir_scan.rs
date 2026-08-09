/// Unit tests extracted from ssh_dir_scan.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn temp_dir(label: &str) -> std::path::PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let pid = std::process::id();
    let dir = std::env::temp_dir().join(format!("lfs_ssh_dir_scan_{label}_{pid}_{nanos}"));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}

fn write_file(dir: &std::path::Path, name: &str, content: &[u8]) -> String {
    let path = dir.join(name);
    std::fs::write(&path, content).expect("write");
    path.to_string_lossy().into_owned()
}

#[test]
fn missing_directory_returns_empty() {
    let result = scan("/path/that/almost/certainly/does/not/exist/lfs_test");
    assert!(result.is_empty());
}

#[test]
fn pem_file_is_picked_up() {
    let dir = temp_dir("pem_only");
    write_file(
        &dir,
        "id_ed25519",
        b"-----BEGIN PRIVATE KEY-----\nbody\n-----END PRIVATE KEY-----\n",
    );
    let result = scan(dir.to_string_lossy().as_ref());
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].suggested_label, "id_ed25519");
    assert!(result[0].pem.contains("PRIVATE KEY"));
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn obvious_non_keys_are_skipped() {
    let dir = temp_dir("non_keys");
    write_file(&dir, "id_ed25519", b"-----BEGIN PRIVATE KEY-----\n");
    // Even if a forbidden path *contains* PRIVATE KEY, it must skip.
    write_file(&dir, "id_ed25519.pub", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "known_hosts", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "known_hosts.old", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "authorized_keys", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "authorized_keys2", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "config", b"-----BEGIN PRIVATE KEY-----\n");
    let result = scan(dir.to_string_lossy().as_ref());
    let labels: Vec<_> = result.iter().map(|k| k.suggested_label.as_str()).collect();
    assert_eq!(labels, vec!["id_ed25519"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn oversized_files_are_rejected() {
    let dir = temp_dir("oversized");
    // 64 KiB > MAX_KEY_FILE_BYTES (32 KiB).
    let mut blob = Vec::with_capacity(64 * 1024);
    blob.extend_from_slice(b"-----BEGIN PRIVATE KEY-----\n");
    blob.extend(std::iter::repeat_n(b'A', 64 * 1024));
    write_file(&dir, "huge", &blob);
    let result = scan(dir.to_string_lossy().as_ref());
    assert!(result.is_empty());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn non_pem_garbage_is_omitted() {
    let dir = temp_dir("garbage");
    write_file(
        &dir,
        "real_key",
        b"-----BEGIN PRIVATE KEY-----\nbody\n-----END PRIVATE KEY-----\n",
    );
    write_file(&dir, "garbage", b"this is just some text\n");
    write_file(&dir, "another", b"\xff\xfe\x00\x01binary\xee\xee");
    let result = scan(dir.to_string_lossy().as_ref());
    let labels: Vec<_> = result.iter().map(|k| k.suggested_label.as_str()).collect();
    assert_eq!(labels, vec!["real_key"]);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn results_are_sorted_alphabetically() {
    let dir = temp_dir("sorted");
    write_file(&dir, "z_last", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "a_first", b"-----BEGIN PRIVATE KEY-----\n");
    write_file(&dir, "m_middle", b"-----BEGIN PRIVATE KEY-----\n");
    let result = scan(dir.to_string_lossy().as_ref());
    let labels: Vec<_> = result.iter().map(|k| k.suggested_label.as_str()).collect();
    assert_eq!(labels, vec!["a_first", "m_middle", "z_last"]);
    std::fs::remove_dir_all(&dir).ok();
}
