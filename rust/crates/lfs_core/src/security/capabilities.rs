//! `SecurityCapabilities` snapshot — the OS / hardware capability
//! probe result the wizard caches inside `config.json` so a fresh
//! app start can serve the Settings cards straight from the
//! snapshot instead of paying the real probe cost on every launch.
//!
//! This module owns the JSON wire format only — the actual probes
//! (libsecret reachability, hardware-vault native-channel pings,
//! biometric availability, fprintd presence) live Dart-side
//! because each of them rides on a platform plugin. Dart calls
//! [`to_json_value`] before persisting + [`from_json_value`] after
//! reading, so the serialization shape stays in sync with future
//! field bumps even when the per-tier ports land at different times.
//!
//! Wire format (one scalar per key, enums as their stable Dart
//! `name`):
//! ```json
//! {
//!   "keychain_available":       <bool>,
//!   "hardware_vault_available": <bool>,
//!   "biometric_available":      <bool>,
//!   "fprintd_available":        <bool>,
//!   "is_linux_host":            <bool>,
//!   "keychain_probe":           "available" | "linuxNoSecretService" | "probeFailed",
//!   "hardware_probe_code":      <string>
//! }
//! ```

use serde_json::{json, Value};

/// Mirror of the Dart `KeyringProbeResult` enum. The wire names
/// match the Dart `.name` getter byte-for-byte so the same string
/// round-trips through both languages.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum KeyringProbeResult {
    /// Keychain reachable — Linux gdbus ping returned 0; non-Linux
    /// live write/read/delete round-trip succeeded.
    Available,
    /// Linux `gdbus` ping failed — no session bus / no daemon /
    /// no `gdbus` binary. UI shows "install a keyring daemon".
    LinuxNoSecretService,
    /// Non-Linux keychain returned an error (rare). UI shows the
    /// generic fallback copy.
    ProbeFailed,
}

impl KeyringProbeResult {
    pub fn wire_name(self) -> &'static str {
        match self {
            KeyringProbeResult::Available => "available",
            KeyringProbeResult::LinuxNoSecretService => "linuxNoSecretService",
            KeyringProbeResult::ProbeFailed => "probeFailed",
        }
    }

    pub fn from_wire_name(name: &str) -> Option<Self> {
        match name {
            "available" => Some(KeyringProbeResult::Available),
            "linuxNoSecretService" => Some(KeyringProbeResult::LinuxNoSecretService),
            "probeFailed" => Some(KeyringProbeResult::ProbeFailed),
            _ => None,
        }
    }
}

/// Snapshot of every capability the wizard needs to decide which
/// tiers + modifiers to offer on this device.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SecurityCapabilities {
    pub keychain_available: bool,
    pub hardware_vault_available: bool,
    pub biometric_available: bool,
    pub fprintd_available: bool,
    pub is_linux_host: bool,
    pub keychain_probe: KeyringProbeResult,
    pub hardware_probe_code: String,
}

impl SecurityCapabilities {
    /// Conservative default — every probe in its "not yet run /
    /// not available" state. Used by the Dart wrappers as the
    /// constructor default + as the fallback when a malformed
    /// snapshot is rejected.
    pub fn defaults() -> Self {
        Self {
            keychain_available: false,
            hardware_vault_available: false,
            biometric_available: false,
            fprintd_available: false,
            is_linux_host: false,
            keychain_probe: KeyringProbeResult::ProbeFailed,
            hardware_probe_code: String::from("unknown"),
        }
    }

    /// Whether the biometric modifier is offerable on this host.
    /// On Linux either the platform biometric API or fprintd
    /// suffices (the wizard accepts the looser disjunction so a
    /// fingerprint reader behind fprintd still unlocks the toggle
    /// even when local_auth doesn't enumerate the device); every
    /// other platform requires the platform biometric API.
    ///
    /// Password-dependency ("biometric requires password") is a UX
    /// rule the wizard enforces separately — not a capability fact.
    #[must_use]
    pub fn can_offer_biometric_modifier(&self) -> bool {
        if self.is_linux_host {
            self.biometric_available || self.fprintd_available
        } else {
            self.biometric_available
        }
    }

    /// Render to the JSON shape the Dart wizard's `toJson` emits.
    pub fn to_json_value(&self) -> Value {
        json!({
            "keychain_available": self.keychain_available,
            "hardware_vault_available": self.hardware_vault_available,
            "biometric_available": self.biometric_available,
            "fprintd_available": self.fprintd_available,
            "is_linux_host": self.is_linux_host,
            "keychain_probe": self.keychain_probe.wire_name(),
            "hardware_probe_code": self.hardware_probe_code,
        })
    }

    /// Parse the JSON snapshot. Returns `None` for any malformed
    /// shape — the file lives inside `config.json`, which the user
    /// can edit, and a partial / corrupted block must degrade to
    /// "no cache" so the next call reprobes fresh. We never parse
    /// past a bad type into a default.
    ///
    /// Mirrors the Dart `fromJson` strictness exactly:
    ///   * top-level must be an object
    ///   * `keychain_probe` must be a string that maps to a known
    ///     enum case
    ///   * `hardware_probe_code` must be a string
    ///   * every boolean field defaults to `false` when missing or
    ///     non-bool (matches `json[k] == true` Dart-side)
    pub fn from_json_value(value: &Value) -> Option<Self> {
        let obj = value.as_object()?;
        let probe_name = obj.get("keychain_probe").and_then(|v| v.as_str())?;
        let probe = KeyringProbeResult::from_wire_name(probe_name)?;
        let hardware_code = obj
            .get("hardware_probe_code")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())?;
        Some(SecurityCapabilities {
            keychain_available: bool_or_false(obj.get("keychain_available")),
            hardware_vault_available: bool_or_false(obj.get("hardware_vault_available")),
            biometric_available: bool_or_false(obj.get("biometric_available")),
            fprintd_available: bool_or_false(obj.get("fprintd_available")),
            is_linux_host: bool_or_false(obj.get("is_linux_host")),
            keychain_probe: probe,
            hardware_probe_code: hardware_code,
        })
    }
}

fn bool_or_false(value: Option<&Value>) -> bool {
    matches!(value, Some(Value::Bool(true)))
}
#[cfg(test)]
#[path = "../../tests/unit/security_capabilities.rs"]
mod tests;
