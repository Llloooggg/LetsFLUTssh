//! Wire-shape mirror of `lfs_core::security::capabilities::SecurityCapabilities`
//! consumed by the orchestrator FRB shim. The cache itself
//! (`view` / `set` / `clear`) lives Rust-side under
//! `lfs_core::security::capabilities_cache::instance` — the live
//! `SecurityProvider` state arrives on the Dart side via the
//! `SecurityCapabilitiesChanged` bus event the orchestrator
//! publishes after every probe, so an explicit FRB read /
//! write / clear surface is unnecessary.

use lfs_core::security::capabilities as caps;

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

#[cfg(test)]
mod tests {
    use super::*;

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
}
