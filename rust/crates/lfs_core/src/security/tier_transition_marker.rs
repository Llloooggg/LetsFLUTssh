//! Crash-recovery marker the security-tier switcher writes before
//! re-keying the DB.
//!
//! `SecurityTierSwitcher` (Dart) generates a fresh random DB key,
//! writes the target config's JSON to `.tier-transition-pending`,
//! re-keys the DB, then runs the per-tier wrapper / config-persist
//! steps and finally deletes the marker. If the process dies between
//! the rekey and the marker clear, the next launch reads the marker
//! body and either completes or rolls back the pending switch — the
//! DB at that point is encrypted under the new key while
//! `config.json` may still describe the old tier.
//!
//! This module owns the marker file's I/O — write (atomic + 0600),
//! read (string body, `None` when absent), clear (idempotent on
//! missing). Body shape is opaque to this module; the Dart caller
//! treats it as the target tier's marker payload.

use std::fs;
use std::path::Path;

use crate::path::write_bytes_atomic;

/// File name stored under the platform's app-support directory.
/// Mirror of the Dart-side `_markerFileName` constant.
pub const MARKER_FILE_NAME: &str = ".tier-transition-pending";

/// Wire-format magic + version stamped at the head of every marker
/// emit. A reader that finds a foreign file at the marker path (a
/// hostile drop, leftover from an unrelated tool) skips it as if
/// absent — only files the writer here emitted reach the switcher.
const MAGIC: &[u8; 4] = b"LFTM";
const VERSION: u8 = 1;
const HEADER_LEN: usize = MAGIC.len() + 1;

/// Read the marker payload, or `None` when the marker is absent.
/// Any I/O failure (broken support-dir probe, permission flap)
/// returns `None` so a corrupt marker never blocks startup — the
/// switcher falls back to "no pending transition" and proceeds with
/// the on-disk config. A magic / version mismatch is treated the
/// same way: the file is not one we wrote, so we must not act on it.
pub fn read(support_dir: &Path) -> Option<String> {
    let path = support_dir.join(MARKER_FILE_NAME);
    if !path.exists() {
        return None;
    }
    let bytes = crate::path::read_bytes_secure(&path).ok()?;
    if bytes.len() < HEADER_LEN || &bytes[..MAGIC.len()] != MAGIC {
        return None;
    }
    if bytes[MAGIC.len()] != VERSION {
        return None;
    }
    String::from_utf8(bytes[HEADER_LEN..].to_vec()).ok()
}

/// Write the marker with [`payload`] as its body. Routes through
/// [`write_bytes_atomic`] so the file lands at the same 0600 perms
/// the rest of `app-support` enforces; the random tmp-suffix path
/// keeps concurrent switches (e.g. user double-clicks the apply
/// button) from colliding on the intermediate file.
pub fn write(support_dir: &Path, payload: &str) -> Result<(), String> {
    crate::path::create_dir_all_secure(support_dir)?;
    let mut buf = Vec::with_capacity(HEADER_LEN + payload.len());
    buf.extend_from_slice(MAGIC);
    buf.push(VERSION);
    buf.extend_from_slice(payload.as_bytes());
    write_bytes_atomic(&support_dir.join(MARKER_FILE_NAME), &buf)
}

/// Drop the marker. Idempotent on a missing file — startup callers
/// invoke this regardless of whether a transition was pending.
pub fn clear(support_dir: &Path) -> Result<(), String> {
    let path = support_dir.join(MARKER_FILE_NAME);
    if !path.exists() {
        return Ok(());
    }
    fs::remove_file(&path).map_err(|e| format!("delete {}: {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn read_returns_none_when_marker_absent() {
        let dir = TempDir::new().unwrap();
        assert_eq!(read(dir.path()), None);
    }

    #[test]
    fn write_then_read_round_trips_payload() {
        let dir = TempDir::new().unwrap();
        let body = r#"{"target":"keychain"}"#;
        write(dir.path(), body).unwrap();
        assert_eq!(read(dir.path()).as_deref(), Some(body));
    }

    #[test]
    fn write_overwrites_existing_marker() {
        let dir = TempDir::new().unwrap();
        write(dir.path(), "first").unwrap();
        write(dir.path(), "second").unwrap();
        assert_eq!(read(dir.path()).as_deref(), Some("second"));
    }

    #[test]
    fn read_rejects_file_without_magic() {
        let dir = TempDir::new().unwrap();
        // A leftover from an unrelated tool / hostile drop. Read
        // must treat it as absent so the switcher does not act on
        // an attacker-shaped payload.
        std::fs::write(dir.path().join(MARKER_FILE_NAME), b"{\"target\":\"x\"}").unwrap();
        assert!(read(dir.path()).is_none());
    }

    #[test]
    fn read_rejects_unknown_version() {
        let dir = TempDir::new().unwrap();
        let mut bytes = Vec::from(*MAGIC);
        bytes.push(VERSION + 1);
        bytes.extend_from_slice(b"body");
        std::fs::write(dir.path().join(MARKER_FILE_NAME), &bytes).unwrap();
        assert!(read(dir.path()).is_none());
    }

    #[test]
    fn read_rejects_truncated_header() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join(MARKER_FILE_NAME), b"LF").unwrap();
        assert!(read(dir.path()).is_none());
    }

    #[test]
    fn clear_removes_existing_marker() {
        let dir = TempDir::new().unwrap();
        write(dir.path(), "x").unwrap();
        clear(dir.path()).unwrap();
        assert!(read(dir.path()).is_none());
    }

    #[test]
    fn clear_is_idempotent_on_missing() {
        let dir = TempDir::new().unwrap();
        clear(dir.path()).unwrap();
    }

    #[test]
    fn write_creates_parent_dir_when_missing() {
        // Production callers point at the platform app-support dir
        // (always exists), but tests pass a fresh temp dir that may
        // not yet exist. The writer must create it rather than
        // throwing on `ENOENT`.
        let parent = TempDir::new().unwrap();
        let support = parent.path().join("not-yet-created");
        write(&support, "x").unwrap();
        assert_eq!(read(&support).as_deref(), Some("x"));
    }

    #[cfg(unix)]
    #[test]
    fn write_lands_marker_at_owner_only_perms() {
        use std::os::unix::fs::PermissionsExt;
        let dir = TempDir::new().unwrap();
        write(dir.path(), "x").unwrap();
        let mode = std::fs::metadata(dir.path().join(MARKER_FILE_NAME))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
    }
}
