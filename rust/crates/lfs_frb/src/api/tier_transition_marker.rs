//! FRB adapter for `lfs_core::security::tier_transition_marker`.
//!
//! Sync — every op is a stat / a tiny write / an unlink. The
//! switcher invokes these around a real DB rekey (already on the
//! tokio blocking pool); the no-async-hop overhead matters for
//! the marker reads at startup that gate the wider unlock flow.
//! Operates on the app-support directory pinned at `config_store_init`.
//! Round-trip behaviour is covered against the explicit `&Path` API in
//! `lfs_core::security::tier_transition_marker`.

use lfs_core::security::master_password;
use lfs_core::security::tier_transition_marker as marker;

/// Read the marker payload, or `None` when the marker is absent.
/// Any I/O failure (or a missing pin) short-circuits to `None` so a
/// corrupt marker never blocks startup.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_transition_marker_read() -> Option<String> {
    let dir = master_password::try_pinned_support_dir().ok()?;
    marker::read(dir)
}

/// Write the marker with [`payload`] as its body. Atomic via tmp +
/// rename + 0600 hardening.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_transition_marker_write(payload: String) -> Result<(), String> {
    let dir = master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    marker::write(dir, &payload)
}

/// Drop the marker. Idempotent on a missing file.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_transition_marker_clear() -> Result<(), String> {
    let dir = master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    marker::clear(dir)
}
