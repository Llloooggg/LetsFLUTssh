//! FRB adapter for `lfs_core::security::keychain_marker`.
//!
//! Sync everywhere — each op is a stat / a tiny write / an unlink.
//! The Dart facade `LinuxKeychainMarker` resolves the platform
//! `getApplicationSupportDirectory()` path once and passes it
//! through per call (same shape as the master-password verifier
//! shim), so this layer stays platform-agnostic.

use std::path::Path;

use lfs_core::security::keychain_marker;

/// True when the marker file is on disk under [`support_dir`] —
/// at least one prior session wrote a secret into the keychain
/// successfully. Callers gate libsecret probes on this on Linux.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_marker_exists(support_dir: String) -> bool {
    keychain_marker::exists(Path::new(&support_dir))
}

/// Lay down the marker after a successful keychain write.
/// Idempotent on a re-write. Hardens the file to owner-only perms
/// so the whole `app-support` directory keeps a single 0600
/// permission contract.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_marker_set(support_dir: String) -> Result<(), String> {
    keychain_marker::set(Path::new(&support_dir))
}

/// Drop the marker. Idempotent on a missing file.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_marker_clear(support_dir: String) -> Result<(), String> {
    keychain_marker::clear(Path::new(&support_dir))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn marker_lifecycle_set_then_exists_then_clear() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 tmp path").to_string();

        // Initial state: marker absent.
        assert!(!keychain_marker_exists(dir.clone()));

        // After set: marker present.
        keychain_marker_set(dir.clone()).expect("set");
        assert!(keychain_marker_exists(dir.clone()));

        // After clear: marker absent again.
        keychain_marker_clear(dir.clone()).expect("clear");
        assert!(!keychain_marker_exists(dir));
    }

    #[test]
    fn set_is_idempotent() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 tmp path").to_string();
        keychain_marker_set(dir.clone()).expect("first set");
        keychain_marker_set(dir.clone()).expect("second set must not error");
        assert!(keychain_marker_exists(dir));
    }

    #[test]
    fn clear_on_missing_marker_is_idempotent() {
        // Calling clear without a prior set must not surface an
        // error — the wipe / logout flow runs this unconditionally.
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 tmp path").to_string();
        keychain_marker_clear(dir).expect("clear on missing");
    }
}
