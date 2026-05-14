//! FRB adapter for `lfs_core::security::capabilities`.
//!
//! Sync — encode is a small JSON serialise + a few enum lookups,
//! decode is a parse + per-field type-check. The wizard probes
//! capabilities once on open and caches the result, so the
//! per-call work happens at most a handful of times per session;
//! the no-async-hop overhead matters less than the simpler API.
//!
//! Wire shape on both sides: the Dart caller hands the FRB-typed
//! `DbSecurityCapabilities` struct in / out of the boundary and
//! lets FRB encode / decode the JSON string. The persisted shape
//! lives entirely Rust-side under `lfs_core::security::capabilities`,
//! so a future schema bump lands inside `lfs_core` without churn
//! to the Dart consumer surface.

use lfs_core::security::capabilities::{
    KeyringProbeResult as CoreKeyringProbeResult, SecurityCapabilities,
};

/// FRB-visible mirror of
/// `lfs_core::security::capabilities::KeyringProbeResult`. FRB
/// codegen emits this as a Dart `enum` so the wire-name string
/// round-trip never lands on the Dart side — one enum on each
/// side of the boundary, generated once.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DbKeyringProbeResult {
    /// Keychain reachable — Linux zbus connect against
    /// `org.freedesktop.secrets` returned ok; non-Linux live
    /// write/read/delete round-trip succeeded.
    Available,
    /// Linux secret-service unreachable — no session bus / no
    /// daemon / `zbus` connect failed. UI shows "install a
    /// keyring daemon".
    LinuxNoSecretService,
    /// Non-Linux keychain returned an error (rare). UI shows the
    /// generic fallback copy.
    ProbeFailed,
}

impl From<CoreKeyringProbeResult> for DbKeyringProbeResult {
    fn from(value: CoreKeyringProbeResult) -> Self {
        match value {
            CoreKeyringProbeResult::Available => DbKeyringProbeResult::Available,
            CoreKeyringProbeResult::LinuxNoSecretService => {
                DbKeyringProbeResult::LinuxNoSecretService
            }
            CoreKeyringProbeResult::ProbeFailed => DbKeyringProbeResult::ProbeFailed,
        }
    }
}

impl From<DbKeyringProbeResult> for CoreKeyringProbeResult {
    fn from(value: DbKeyringProbeResult) -> Self {
        match value {
            DbKeyringProbeResult::Available => CoreKeyringProbeResult::Available,
            DbKeyringProbeResult::LinuxNoSecretService => {
                CoreKeyringProbeResult::LinuxNoSecretService
            }
            DbKeyringProbeResult::ProbeFailed => CoreKeyringProbeResult::ProbeFailed,
        }
    }
}

/// FRB-side mirror of the `SecurityCapabilities` snapshot. The
/// flat DTO carries every wizard-visible field plus the typed
/// `DbKeyringProbeResult` enum (no wire-name string round-trip on
/// the Dart side).
#[derive(Debug, Clone)]
pub struct DbSecurityCapabilities {
    pub keychain_available: bool,
    pub hardware_vault_available: bool,
    pub biometric_available: bool,
    pub fprintd_available: bool,
    pub is_linux_host: bool,
    pub keychain_probe: DbKeyringProbeResult,
    pub hardware_probe_code: String,
}

impl From<SecurityCapabilities> for DbSecurityCapabilities {
    fn from(c: SecurityCapabilities) -> Self {
        Self {
            keychain_available: c.keychain_available,
            hardware_vault_available: c.hardware_vault_available,
            biometric_available: c.biometric_available,
            fprintd_available: c.fprintd_available,
            is_linux_host: c.is_linux_host,
            keychain_probe: c.keychain_probe.into(),
            hardware_probe_code: c.hardware_probe_code,
        }
    }
}

impl From<DbSecurityCapabilities> for SecurityCapabilities {
    fn from(c: DbSecurityCapabilities) -> Self {
        SecurityCapabilities {
            keychain_available: c.keychain_available,
            hardware_vault_available: c.hardware_vault_available,
            biometric_available: c.biometric_available,
            fprintd_available: c.fprintd_available,
            is_linux_host: c.is_linux_host,
            keychain_probe: c.keychain_probe.into(),
            hardware_probe_code: c.hardware_probe_code,
        }
    }
}

/// Conservative default snapshot — every probe in its "not yet
/// run / not available" state. Used by the wizard call sites
/// that need a `DbSecurityCapabilities` instance before the real
/// probe has run (loading-state placeholder + tests).
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_defaults() -> DbSecurityCapabilities {
    SecurityCapabilities::defaults().into()
}

/// Encode a [`DbSecurityCapabilities`] snapshot into the JSON
/// wire format the wizard persists inside `config.json` under
/// `security_probe_cache`. Returns the minified JSON string —
/// caller stores it as a Dart `Map<String, dynamic>` after a
/// `jsonDecode` round-trip.
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_to_json(caps: DbSecurityCapabilities) -> String {
    SecurityCapabilities::from(caps).to_json_value().to_string()
}

/// Wizard rule — true when the biometric modifier toggle should
/// be offerable on this host. On Linux either the platform
/// biometric API or fprintd suffices; every other platform
/// requires the platform biometric API. Mirrors
/// `SecurityCapabilities::can_offer_biometric_modifier` byte-for-
/// byte.
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_can_offer_biometric_modifier(caps: DbSecurityCapabilities) -> bool {
    SecurityCapabilities::from(caps).can_offer_biometric_modifier()
}

/// Parse a `security_probe_cache` JSON snapshot. Returns `None` for
/// any malformed shape (non-object root, unknown enum case,
/// missing required strings) so the Dart caller falls through to
/// "no cache" and reprobes.
#[flutter_rust_bridge::frb(sync)]
pub fn security_capabilities_from_json(json: String) -> Option<DbSecurityCapabilities> {
    let value: serde_json::Value = serde_json::from_str(&json).ok()?;
    SecurityCapabilities::from_json_value(&value).map(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> DbSecurityCapabilities {
        DbSecurityCapabilities {
            keychain_available: true,
            hardware_vault_available: false,
            biometric_available: true,
            fprintd_available: false,
            is_linux_host: false,
            keychain_probe: DbKeyringProbeResult::Available,
            hardware_probe_code: "ok".into(),
        }
    }

    #[test]
    fn keyring_probe_round_trip_through_core() {
        // Pins the `From` mapping in both directions — a future
        // variant added to `CoreKeyringProbeResult` without a
        // matching arm here is a non-exhaustive-match compile
        // error, not a silent dropped case at runtime.
        for variant in [
            DbKeyringProbeResult::Available,
            DbKeyringProbeResult::LinuxNoSecretService,
            DbKeyringProbeResult::ProbeFailed,
        ] {
            let core: CoreKeyringProbeResult = variant.into();
            let back: DbKeyringProbeResult = core.into();
            assert_eq!(back, variant);
        }
    }

    #[test]
    fn to_json_then_from_json_round_trips_every_field() {
        let s = security_capabilities_to_json(sample());
        let parsed = security_capabilities_from_json(s).expect("decode");
        assert!(parsed.keychain_available);
        assert!(!parsed.hardware_vault_available);
        assert!(parsed.biometric_available);
        assert!(!parsed.fprintd_available);
        assert!(!parsed.is_linux_host);
        assert_eq!(parsed.keychain_probe, DbKeyringProbeResult::Available);
        assert_eq!(parsed.hardware_probe_code, "ok");
    }

    #[test]
    fn from_json_returns_none_for_garbage_input() {
        assert!(security_capabilities_from_json("not json at all".into()).is_none());
    }

    #[test]
    fn defaults_match_core_defaults() {
        let d = security_capabilities_defaults();
        assert!(!d.keychain_available);
        assert!(!d.hardware_vault_available);
        assert!(!d.biometric_available);
        assert!(!d.fprintd_available);
        assert!(!d.is_linux_host);
        assert_eq!(d.keychain_probe, DbKeyringProbeResult::ProbeFailed);
        assert_eq!(d.hardware_probe_code, "unknown");
    }

    #[test]
    fn can_offer_biometric_modifier_follows_platform_rule() {
        // Linux: either platform biometric API or fprintd is enough.
        let linux_bio = DbSecurityCapabilities {
            is_linux_host: true,
            biometric_available: true,
            ..sample()
        };
        assert!(security_capabilities_can_offer_biometric_modifier(
            linux_bio
        ));
        let linux_fprintd = DbSecurityCapabilities {
            is_linux_host: true,
            biometric_available: false,
            fprintd_available: true,
            ..sample()
        };
        assert!(security_capabilities_can_offer_biometric_modifier(
            linux_fprintd
        ));
        let linux_none = DbSecurityCapabilities {
            is_linux_host: true,
            biometric_available: false,
            fprintd_available: false,
            ..sample()
        };
        assert!(!security_capabilities_can_offer_biometric_modifier(
            linux_none
        ));
        // Non-Linux: only the platform biometric API counts.
        let mac_bio = DbSecurityCapabilities {
            is_linux_host: false,
            biometric_available: true,
            ..sample()
        };
        assert!(security_capabilities_can_offer_biometric_modifier(mac_bio));
        let mac_no_bio = DbSecurityCapabilities {
            is_linux_host: false,
            biometric_available: false,
            fprintd_available: true,
            ..sample()
        };
        assert!(!security_capabilities_can_offer_biometric_modifier(
            mac_no_bio
        ));
    }
}
