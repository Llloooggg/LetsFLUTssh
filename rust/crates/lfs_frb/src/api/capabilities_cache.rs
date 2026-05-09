//! FRB adapter for `lfs_core::security::capabilities_cache`.
//!
//! Sync — every op is a Mutex grab + clone of the cached
//! snapshot or a JSON encode of one; the bus publication on
//! `set` / `clear` is a single broadcast `try_send`. The Dart
//! `SecurityProvider` reads through here on every Settings open
//! and wizard launch, so the no-async-hop overhead is worth more
//! than the FRB worker hop.
//!
//! What stays Dart-side: the actual platform plugin probes
//! (libsecret reachability ping, hardware-vault native channel
//! call, biometric API call, fprintd D-Bus call). The Rust
//! orchestrator drives them via prompt-registry round-trips and
//! pushes the snapshot into this cache.

use lfs_core::security::capabilities as caps;
use lfs_core::security::capabilities_cache::instance;

/// FRB mirror of `lfs_core::security::capabilities::SecurityCapabilities`.
/// Field shape matches the Dart `SecurityCapabilities` class
/// 1:1 — the Dart wrapper just unboxes into its own constructor.
#[derive(Debug, Clone)]
pub struct DbSecurityCapabilitiesSnapshot {
    pub keychain_available: bool,
    pub hardware_vault_available: bool,
    pub biometric_available: bool,
    pub fprintd_available: bool,
    pub is_linux_host: bool,
    /// Wire name (`"available"` / `"linuxNoSecretService"` /
    /// `"probeFailed"`) of the keychain probe outcome. Mirrors
    /// the Dart `KeyringProbeResult.name` getter byte-for-byte.
    pub keychain_probe_wire_name: String,
    /// Raw platform-specific hardware-vault detail code. The
    /// Dart `hardwareProbeDetailText` mapper converts this to
    /// localised reason copy.
    pub hardware_probe_code: String,
}

impl From<caps::SecurityCapabilities> for DbSecurityCapabilitiesSnapshot {
    fn from(c: caps::SecurityCapabilities) -> Self {
        Self {
            keychain_available: c.keychain_available,
            hardware_vault_available: c.hardware_vault_available,
            biometric_available: c.biometric_available,
            fprintd_available: c.fprintd_available,
            is_linux_host: c.is_linux_host,
            keychain_probe_wire_name: c.keychain_probe.wire_name().to_string(),
            hardware_probe_code: c.hardware_probe_code,
        }
    }
}

impl DbSecurityCapabilitiesSnapshot {
    fn into_core(self) -> Option<caps::SecurityCapabilities> {
        let probe = caps::KeyringProbeResult::from_wire_name(&self.keychain_probe_wire_name)?;
        Some(caps::SecurityCapabilities {
            keychain_available: self.keychain_available,
            hardware_vault_available: self.hardware_vault_available,
            biometric_available: self.biometric_available,
            fprintd_available: self.fprintd_available,
            is_linux_host: self.is_linux_host,
            keychain_probe: probe,
            hardware_probe_code: self.hardware_probe_code,
        })
    }
}

/// Read the cached `SecurityCapabilities` snapshot. Returns
/// `None` when the cache has not been seeded yet (cold start
/// before `probeCapabilities` runs the first time, or after an
/// explicit `clear`). Dart wrappers treat `None` as "render the
/// neutral 'probing…' state until the next set".
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_view() -> Option<DbSecurityCapabilitiesSnapshot> {
    instance().view().map(Into::into)
}

/// Push a freshly-probed snapshot into the cache. Publishes
/// `SecurityCapabilitiesChanged` (carrying the JSON) only when
/// the new snapshot differs from the cached one, so back-to-back
/// rechecks on a static host don't thrash subscribers.
///
/// Returns `Err` when the snapshot's `keychain_probe_wire_name`
/// is not one of the three known wire names — the Dart caller
/// always passes a `KeyringProbeResult.name` value, so this is
/// strictly defensive against codegen drift.
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_set(snapshot: DbSecurityCapabilitiesSnapshot) -> Result<(), String> {
    let wire = snapshot.keychain_probe_wire_name.clone();
    let core = snapshot
        .into_core()
        .ok_or_else(|| format!("unknown keychain_probe wire name: {wire}"))?;
    instance().set(core);
    Ok(())
}

/// Drop the cached snapshot. Publishes a
/// `SecurityCapabilitiesChanged` with empty `json` so subscribers
/// flip back to the neutral "probing…" state. No-op (no event
/// fires) when the cache is already empty.
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_clear() {
    instance().clear();
}

#[cfg(test)]
mod tests {
    use super::*;

    // The view / set / clear endpoints route through the
    // process-singleton cache + bus; covered by the Dart
    // `security_capabilities_test.dart` integration suite. The
    // standalone tests below pin the wire-shape `From` mapping +
    // `into_core` parser that crosses the FRB boundary on every
    // snapshot.

    #[test]
    fn from_core_carries_every_field() {
        let core = caps::SecurityCapabilities {
            keychain_available: true,
            hardware_vault_available: false,
            biometric_available: true,
            fprintd_available: true,
            is_linux_host: true,
            keychain_probe: caps::KeyringProbeResult::Available,
            hardware_probe_code: "ok".into(),
        };
        let snap: DbSecurityCapabilitiesSnapshot = core.into();
        assert!(snap.keychain_available);
        assert!(!snap.hardware_vault_available);
        assert!(snap.biometric_available);
        assert!(snap.fprintd_available);
        assert!(snap.is_linux_host);
        assert_eq!(snap.keychain_probe_wire_name, "available");
        assert_eq!(snap.hardware_probe_code, "ok");
    }

    #[test]
    fn into_core_returns_some_for_valid_wire_name() {
        let snap = DbSecurityCapabilitiesSnapshot {
            keychain_available: false,
            hardware_vault_available: false,
            biometric_available: false,
            fprintd_available: false,
            is_linux_host: false,
            keychain_probe_wire_name: "probeFailed".into(),
            hardware_probe_code: "neutral".into(),
        };
        assert!(snap.into_core().is_some());
    }

    #[test]
    fn into_core_returns_none_for_unknown_wire_name() {
        // The Dart caller emits `KeyringProbeResult.name` so this is
        // strictly defensive against codegen drift; pin the contract.
        let snap = DbSecurityCapabilitiesSnapshot {
            keychain_available: false,
            hardware_vault_available: false,
            biometric_available: false,
            fprintd_available: false,
            is_linux_host: false,
            keychain_probe_wire_name: "ghost-wire-name".into(),
            hardware_probe_code: String::new(),
        };
        assert!(snap.into_core().is_none());
    }

    #[test]
    fn from_core_into_core_round_trips_for_each_probe_variant() {
        for variant in [
            caps::KeyringProbeResult::Available,
            caps::KeyringProbeResult::LinuxNoSecretService,
            caps::KeyringProbeResult::ProbeFailed,
        ] {
            let core = caps::SecurityCapabilities {
                keychain_available: true,
                hardware_vault_available: false,
                biometric_available: false,
                fprintd_available: false,
                is_linux_host: false,
                keychain_probe: variant,
                hardware_probe_code: "x".into(),
            };
            let snap: DbSecurityCapabilitiesSnapshot = core.into();
            let back = snap.into_core().expect("round trip preserves wire name");
            assert_eq!(back.keychain_probe, variant);
        }
    }
}
