//! Cross-class libsecret-noise gate for Linux installs.
//!
//! Background — `flutter_secure_storage` on Linux uses libsecret,
//! which emits a non-recoverable `g_warning` to stderr the moment
//! it cannot talk to a running / unlocked keyring daemon. That
//! makes a cold `containsKey` / `read` on a system where the
//! keyring was never touched (WSL, containers, minimal desktops
//! without `gnome-keyring-daemon` / `kwalletd`) spam stderr on
//! every launch.
//!
//! This module owns the on-disk marker file every keychain-using
//! class consults before issuing a libsecret probe: the marker is
//! laid down only after a successful keychain *write*, so a
//! subsequent `read` is safe to attempt.
//!
//! The marker itself holds nothing sensitive (`'1'`), but sits next
//! to `credentials.*` in the app-support dir at 0600 so the whole
//! directory keeps a single permission contract.
//!
//! Mirror of the Dart-side `LinuxKeychainMarker` class — the Dart
//! façade is now a thin wrapper that resolves the platform
//! `getApplicationSupportDirectory()` path and delegates each op
//! across the FRB boundary.

use std::fs;
use std::path::Path;

use crate::path::harden_file_perms;

/// File name stored under the platform's app-support directory.
/// Mirror of the Dart-side `_fileName` constant.
pub const MARKER_FILE_NAME: &str = "keychain_enabled";

/// True when the marker file is on disk under [`support_dir`],
/// meaning at least one prior session wrote a secret into the
/// keychain successfully. Callers use this as the gate before any
/// `containsKey` / `read` on Linux to avoid triggering libsecret
/// warnings in absence of the keyring daemon.
///
/// The Dart facade short-circuits to `true` on non-Linux platforms
/// before reaching this function — the keyring APIs on macOS /
/// Windows / mobile do not emit stderr warnings the same way, so
/// no gating is needed there. Keeping that platform branch Dart-side
/// keeps this Rust surface platform-agnostic.
pub fn exists(support_dir: &Path) -> bool {
    support_dir.join(MARKER_FILE_NAME).exists()
}

/// Lay down the marker after a successful keychain write. Safe to
/// call from multiple keychain-using classes — the file is a flag,
/// not a counter; idempotent on a re-write.
///
/// Writes `'1'` and chmods the file to owner-only via
/// [`harden_file_perms`] so the whole `app-support` directory keeps
/// a single 0600 permission contract.
pub fn set(support_dir: &Path) -> Result<(), String> {
    fs::create_dir_all(support_dir)
        .map_err(|e| format!("create {}: {e}", support_dir.display()))?;
    let path = support_dir.join(MARKER_FILE_NAME);
    fs::write(&path, b"1").map_err(|e| format!("write {}: {e}", path.display()))?;
    // Best-effort harden — same posture as the Dart writer (log + swallow).
    let _ = harden_file_perms(&path);
    Ok(())
}

/// Drop the marker when the last keychain entry across all users is
/// removed. Called from `SecureKeyStorage.deleteKey` Dart-side — see
/// the full lifecycle contract there. Other classes do NOT clear on
/// their own delete because a different class may still have an
/// entry on disk. Idempotent on a missing file.
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
    fn exists_is_false_when_marker_absent() {
        let dir = TempDir::new().unwrap();
        assert!(!exists(dir.path()));
    }

    #[test]
    fn set_creates_marker_with_flag_payload() {
        let dir = TempDir::new().unwrap();
        set(dir.path()).unwrap();
        assert!(exists(dir.path()));
        let contents = std::fs::read(dir.path().join(MARKER_FILE_NAME)).unwrap();
        assert_eq!(contents, b"1");
    }

    #[test]
    fn set_is_idempotent() {
        let dir = TempDir::new().unwrap();
        set(dir.path()).unwrap();
        set(dir.path()).unwrap();
        assert!(exists(dir.path()));
    }

    #[test]
    fn clear_removes_existing_marker() {
        let dir = TempDir::new().unwrap();
        set(dir.path()).unwrap();
        clear(dir.path()).unwrap();
        assert!(!exists(dir.path()));
    }

    #[test]
    fn clear_is_idempotent_on_missing() {
        let dir = TempDir::new().unwrap();
        // Never set — clear must not error on a missing file.
        clear(dir.path()).unwrap();
        assert!(!exists(dir.path()));
    }

    #[test]
    fn set_creates_parent_dir_if_missing() {
        // Production callers point at the platform app-support dir,
        // which the OS creates on first launch — but tests pass a
        // fresh temp dir path that may not yet exist. The writer must
        // create it rather than throwing on `ENOENT`.
        let parent = TempDir::new().unwrap();
        let support = parent.path().join("not-yet-created");
        set(&support).unwrap();
        assert!(exists(&support));
    }

    #[cfg(unix)]
    #[test]
    fn set_lands_marker_at_owner_only_perms() {
        use std::os::unix::fs::PermissionsExt;
        let dir = TempDir::new().unwrap();
        set(dir.path()).unwrap();
        let mode = std::fs::metadata(dir.path().join(MARKER_FILE_NAME))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
    }
}
