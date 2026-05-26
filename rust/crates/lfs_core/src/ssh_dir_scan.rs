//! Directory scanner for `~/.ssh` (or any directory the user
//! points at) that produces a list of PEM private-key candidates.
//!
//! Mirrors the Dart `SshDirKeyScanner.scan` flow exactly:
//!
//! 1. List the directory (non-recursive). Errors / missing dirs
//!    return an empty result so the UI shows a clean "no keys
//!    found" instead of a hard failure.
//! 2. Skip the obvious non-key siblings (`*.pub`, `config`,
//!    `authorized_keys*`, `known_hosts*`).
//! 3. For each remaining file, attempt to read it as a PEM
//!    private key — bail on size > [`MAX_KEY_FILE_BYTES`], on
//!    non-`PRIVATE KEY` payloads, or on PPK files that fail to
//!    decode (encrypted PPK falls into this bucket since the
//!    silent scan cannot prompt for a passphrase).
//!
//! PPK files are converted to OpenSSH PEM via
//! [`crate::keys::import_ppk`] so the rest of the import path
//! stays format-agnostic.

use crate::keys;

/// Per-file cap. Real SSH keys are < 4 KiB; the 32 KiB ceiling
/// matches the Dart `KeyFileHelper.maxKeyFileSize` and gives a
/// little headroom for PPK files that wrap the OpenSSH bytes.
pub const MAX_KEY_FILE_BYTES: u64 = 32_768;

/// One scan result — file path, PEM body (already converted from
/// PPK if needed), and the suggested label (basename) the
/// caller typically appends a date suffix to before persisting.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScannedKey {
    pub path: String,
    pub pem: String,
    pub suggested_label: String,
}

/// Walk `directory` and return every file that looks like a
/// usable PEM private key. Non-recursive — same semantics as
/// the Dart scanner.
pub fn scan(directory: &str) -> Vec<ScannedKey> {
    let mut paths = match std::fs::read_dir(directory) {
        Ok(rd) => rd
            .flatten()
            .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
            .filter_map(|e| e.path().to_str().map(String::from))
            .collect::<Vec<_>>(),
        Err(_) => return Vec::new(),
    };
    paths.sort();
    let mut result = Vec::new();
    for path in paths {
        let name = crate::path::basename(&path);
        if keys::is_obvious_non_key_filename(&name) {
            continue;
        }
        let Some(pem) = try_read_pem_key(&path) else {
            continue;
        };
        result.push(ScannedKey {
            path: path.clone(),
            pem,
            suggested_label: name,
        });
    }
    result
}

/// Read [`path`] and return its PEM body when it parses as an
/// unencrypted private key (or as an unencrypted PPK that
/// converts cleanly). Returns `None` for missing / oversized /
/// unreadable files, for files that are neither PEM nor PPK,
/// and for encrypted PPK (since the silent scan path cannot
/// prompt for a passphrase).
pub fn try_read_pem_key(path: &str) -> Option<String> {
    let metadata = std::fs::metadata(path).ok()?;
    if !metadata.is_file() {
        return None;
    }
    if metadata.len() > MAX_KEY_FILE_BYTES {
        return None;
    }
    let content = std::fs::read_to_string(path).ok()?;
    if keys::looks_like_ppk(&content) {
        // Silent path: encrypted PPK is rejected here; the
        // key-manager UI runs the passphrase-aware flow when
        // the user explicitly opens such a file.
        return keys::import_ppk(&content, None, "")
            .ok()
            .map(|km| km.private_pem);
    }
    if content.contains("PRIVATE KEY") {
        return Some(content);
    }
    None
}

#[cfg(test)]
mod tests {
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
}
