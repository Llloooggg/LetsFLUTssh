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
