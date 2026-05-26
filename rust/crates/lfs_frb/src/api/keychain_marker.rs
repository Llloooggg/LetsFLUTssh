//! FRB adapter for `lfs_core::security::keychain_marker`.
//!
//! Sync everywhere — each op is a stat / a tiny write / an unlink.
//! Operates on the app-support directory pinned at `config_store_init`
//! (`master_password::try_pinned_support_dir`), so callers no longer
//! thread a path in. Path-specific behaviour is covered against the
//! explicit `&Path` API in `lfs_core::security::keychain_marker`.

use lfs_core::security::keychain_marker;
use lfs_core::security::master_password;

/// True when the marker file is on disk under the pinned support dir —
/// at least one prior session wrote a secret into the keychain
/// successfully. Callers gate libsecret probes on this on Linux. A
/// missing pin (misordered startup) collapses to `false`.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_marker_exists() -> bool {
    match master_password::try_pinned_support_dir() {
        Ok(dir) => keychain_marker::exists(dir),
        Err(_) => false,
    }
}

/// Lay down the marker after a successful keychain write.
/// Idempotent on a re-write. Hardens the file to owner-only perms
/// so the whole `app-support` directory keeps a single 0600
/// permission contract.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_marker_set() -> Result<(), String> {
    let dir = master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    keychain_marker::set(dir)
}

/// Drop the marker. Idempotent on a missing file.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_marker_clear() -> Result<(), String> {
    let dir = master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    keychain_marker::clear(dir)
}
