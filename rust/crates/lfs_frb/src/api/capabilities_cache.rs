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
