/// Unit tests extracted from security/capabilities_cache.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::security::capabilities::KeyringProbeResult;

fn sample(probe: KeyringProbeResult) -> SecurityCapabilities {
    SecurityCapabilities {
        keychain_available: matches!(probe, KeyringProbeResult::Available),
        hardware_vault_available: false,
        biometric_available: false,
        fprintd_available: false,
        is_linux_host: true,
        keychain_probe: probe,
        hardware_probe_code: "available".into(),
    }
}

#[test]
fn view_starts_empty() {
    let c = Cache::for_tests();
    assert!(c.view().is_none());
}

#[test]
fn set_then_view_round_trips() {
    let c = Cache::for_tests();
    let snap = sample(KeyringProbeResult::Available);
    c.set(snap.clone());
    assert_eq!(c.view(), Some(snap));
}

#[test]
fn clear_drops_cached_snapshot() {
    let c = Cache::for_tests();
    c.set(sample(KeyringProbeResult::Available));
    assert!(c.view().is_some());
    c.clear();
    assert!(c.view().is_none());
}

#[test]
fn clear_on_empty_is_noop() {
    let c = Cache::for_tests();
    c.clear();
    assert!(c.view().is_none());
}

#[test]
fn set_with_identical_snapshot_keeps_value() {
    // Identical-set is allowed (the "no event" branch is the
    // bus-side concern; the cached state still equals the
    // snapshot afterwards).
    let c = Cache::for_tests();
    let snap = sample(KeyringProbeResult::Available);
    c.set(snap.clone());
    c.set(snap.clone());
    assert_eq!(c.view(), Some(snap));
}

#[test]
fn set_with_different_snapshot_replaces_value() {
    let c = Cache::for_tests();
    c.set(sample(KeyringProbeResult::Available));
    let next = sample(KeyringProbeResult::ProbeFailed);
    c.set(next.clone());
    assert_eq!(c.view(), Some(next));
}
