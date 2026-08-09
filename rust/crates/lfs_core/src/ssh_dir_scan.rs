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
#[path = "../tests/unit/ssh_dir_scan.rs"]
mod tests;
