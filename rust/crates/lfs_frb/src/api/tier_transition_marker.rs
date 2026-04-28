//! FRB adapter for `lfs_core::security::tier_transition_marker`.
//!
//! Sync — every op is a stat / a tiny write / an unlink. The
//! switcher invokes these around a real DB rekey (already on the
//! tokio blocking pool); the no-async-hop overhead matters for
//! the marker reads at startup that gate the wider unlock flow.

use std::path::Path;

use lfs_core::security::tier_transition_marker as marker;

/// Read the marker payload, or `None` when the marker is absent.
/// Any I/O failure short-circuits to `None` so a corrupt marker
/// never blocks startup.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_transition_marker_read(support_dir: String) -> Option<String> {
    marker::read(Path::new(&support_dir))
}

/// Write the marker with [`payload`] as its body. Atomic via tmp +
/// rename + 0600 hardening — same shape as the Dart switcher's
/// previous `_writeMarker`.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_transition_marker_write(support_dir: String, payload: String) -> Result<(), String> {
    marker::write(Path::new(&support_dir), &payload)
}

/// Drop the marker. Idempotent on a missing file.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_transition_marker_clear(support_dir: String) -> Result<(), String> {
    marker::clear(Path::new(&support_dir))
}
