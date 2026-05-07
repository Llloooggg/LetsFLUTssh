//! Process-singleton cache for the [`SecurityCapabilities`]
//! snapshot the wizard + Settings cards render against.
//!
//! The Dart `probeCapabilities()` runs the platform plugin
//! probes (libsecret reachability, hardware-vault native channel,
//! biometric API, fprintd D-Bus) and pushes the resulting
//! snapshot through [`Cache::set`]; subscribers to
//! [`crate::bus::EventTopic::SecurityCapabilities`] re-snapshot
//! without polling.
//!
//! The cache itself is single-purpose state — it does NOT
//! persist. Persistence lives in `config.json` via
//! [`crate::config_store::Store`] so the existing migration +
//! atomic-write path covers it. The cache only holds the
//! in-memory snapshot the wizard + Settings cards consume +
//! fans changes out through the bus.

use std::sync::{Mutex, OnceLock};

use crate::bus::Event;
use crate::security::capabilities::SecurityCapabilities;

/// Cached snapshot guarded by the singleton's Mutex.
#[derive(Debug)]
struct Inner {
    /// `None` until the first [`Cache::set`] (or a successful
    /// hydration from `config.json`) — Dart wrappers treat
    /// `None` as "use defaults until probe completes".
    current: Option<SecurityCapabilities>,
}

impl Inner {
    const fn new() -> Self {
        Self { current: None }
    }
}

/// Process-singleton actor handle. Dart `probeCapabilities` shim
/// pushes via [`Cache::set`]; tests construct fresh instances via
/// [`Cache::for_tests`].
pub struct Cache {
    inner: Mutex<Inner>,
}

impl Cache {
    #[must_use]
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(Inner::new()),
        }
    }

    /// Snapshot of the cached capabilities. `None` when the cache
    /// has not been seeded yet — Dart wrappers treat that as "use
    /// defaults".
    #[must_use]
    pub fn view(&self) -> Option<SecurityCapabilities> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.current.clone()
    }

    /// Replace the cached snapshot. Publishes
    /// [`Event::SecurityCapabilitiesChanged`] only when the new
    /// snapshot differs from the current one — back-to-back
    /// identical pushes (a wizard recheck on a static host) don't
    /// thrash subscribers.
    ///
    /// Wire JSON in the bus event matches the
    /// `lfs_core::security::capabilities` snake_case format so a
    /// subscriber can rebuild the typed snapshot without a
    /// follow-up `view` call.
    pub fn set(&self, snapshot: SecurityCapabilities) {
        let changed = {
            let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
            let differs = g.current.as_ref() != Some(&snapshot);
            if differs {
                g.current = Some(snapshot.clone());
            }
            differs
        };
        if changed {
            let json = snapshot.to_json_value().to_string();
            crate::app::instance()
                .bus
                .publish(Event::SecurityCapabilitiesChanged { json });
        }
    }

    /// Drop the cached snapshot. Publishes a
    /// [`Event::SecurityCapabilitiesChanged`] carrying an empty
    /// string so subscribers can distinguish "explicit clear" from
    /// "fresh snapshot" — a wizard Recheck button is the canonical
    /// caller and wants the Settings cards to flip back to the
    /// neutral "probing…" state until the next [`Cache::set`].
    ///
    /// No-op when the cache is already empty (no event fires).
    pub fn clear(&self) {
        let was_present = {
            let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
            g.current.take().is_some()
        };
        if was_present {
            crate::app::instance()
                .bus
                .publish(Event::SecurityCapabilitiesChanged {
                    json: String::new(),
                });
        }
    }

    /// Test-only constructor — fresh actor instance, not the
    /// singleton. Used by unit tests so cases don't share state
    /// through [`instance`].
    #[cfg(test)]
    pub fn for_tests() -> Self {
        Self::new()
    }
}

impl Default for Cache {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton instance. Dart FRB shim reads route through
/// this; tests use [`Cache::for_tests`] instead.
static GLOBAL: OnceLock<Cache> = OnceLock::new();

pub fn instance() -> &'static Cache {
    GLOBAL.get_or_init(Cache::new)
}

#[cfg(test)]
mod tests {
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
}
