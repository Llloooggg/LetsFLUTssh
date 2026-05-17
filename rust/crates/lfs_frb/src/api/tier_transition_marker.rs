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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_returns_none_for_missing_marker() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 path").to_string();
        assert!(tier_transition_marker_read(dir).is_none());
    }

    #[test]
    fn write_then_read_round_trips_payload() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 path").to_string();
        tier_transition_marker_write(dir.clone(), "switch-from=plaintext".into()).expect("write");
        assert_eq!(
            tier_transition_marker_read(dir),
            Some("switch-from=plaintext".to_string())
        );
    }

    #[test]
    fn write_overwrites_previous_payload() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 path").to_string();
        tier_transition_marker_write(dir.clone(), "first".into()).expect("write 1");
        tier_transition_marker_write(dir.clone(), "second".into()).expect("write 2");
        assert_eq!(tier_transition_marker_read(dir), Some("second".to_string()));
    }

    #[test]
    fn clear_removes_existing_marker_and_is_idempotent_when_absent() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let dir = tmp.path().to_str().expect("utf-8 path").to_string();
        tier_transition_marker_write(dir.clone(), "x".into()).expect("write");
        tier_transition_marker_clear(dir.clone()).expect("clear once");
        assert!(tier_transition_marker_read(dir.clone()).is_none());
        // Idempotent — clear on a missing marker is OK.
        tier_transition_marker_clear(dir).expect("clear twice");
    }
}
