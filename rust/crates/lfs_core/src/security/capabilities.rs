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
mod tests {
    use super::*;

    fn sample() -> SecurityCapabilities {
        SecurityCapabilities {
            keychain_available: true,
            hardware_vault_available: true,
            biometric_available: false,
            fprintd_available: false,
            is_linux_host: true,
            keychain_probe: KeyringProbeResult::Available,
            hardware_probe_code: String::from("linuxTpmReady"),
        }
    }

    #[test]
    fn keyring_probe_wire_name_round_trip() {
        for variant in [
            KeyringProbeResult::Available,
            KeyringProbeResult::LinuxNoSecretService,
            KeyringProbeResult::ProbeFailed,
        ] {
            assert_eq!(
                KeyringProbeResult::from_wire_name(variant.wire_name()),
                Some(variant)
            );
        }
    }

    #[test]
    fn keyring_probe_rejects_unknown_wire_name() {
        assert_eq!(KeyringProbeResult::from_wire_name(""), None);
        assert_eq!(KeyringProbeResult::from_wire_name("Available"), None); // case-sensitive
        assert_eq!(KeyringProbeResult::from_wire_name("locked"), None);
    }

    #[test]
    fn capabilities_json_round_trips() {
        let original = sample();
        let value = original.to_json_value();
        let decoded = SecurityCapabilities::from_json_value(&value).unwrap();
        assert_eq!(decoded, original);
    }

    #[test]
    fn from_json_returns_none_for_non_object_root() {
        assert!(SecurityCapabilities::from_json_value(&json!([])).is_none());
        assert!(SecurityCapabilities::from_json_value(&json!("string")).is_none());
        assert!(SecurityCapabilities::from_json_value(&json!(null)).is_none());
    }

    #[test]
    fn from_json_returns_none_for_unknown_keychain_probe() {
        let value = json!({
            "keychain_available": true,
            "hardware_vault_available": false,
            "biometric_available": false,
            "fprintd_available": false,
            "is_linux_host": false,
            "keychain_probe": "future-variant-not-yet-known",
            "hardware_probe_code": "unknown",
        });
        assert!(SecurityCapabilities::from_json_value(&value).is_none());
    }

    #[test]
    fn from_json_returns_none_for_missing_required_strings() {
        // Both `keychain_probe` (enum) and `hardware_probe_code`
        // (raw string) are required — missing or non-string for
        // either fails the parse.
        let no_probe = json!({
            "hardware_probe_code": "x",
        });
        assert!(SecurityCapabilities::from_json_value(&no_probe).is_none());

        let probe_not_string = json!({
            "keychain_probe": 1,
            "hardware_probe_code": "x",
        });
        assert!(SecurityCapabilities::from_json_value(&probe_not_string).is_none());

        let no_hw = json!({
            "keychain_probe": "available",
        });
        assert!(SecurityCapabilities::from_json_value(&no_hw).is_none());

        let hw_not_string = json!({
            "keychain_probe": "available",
            "hardware_probe_code": ["x"],
        });
        assert!(SecurityCapabilities::from_json_value(&hw_not_string).is_none());
    }

    #[test]
    fn from_json_treats_missing_bools_as_false() {
        // Mirrors the Dart `json[k] == true` shape — a missing key
        // or a non-bool value lands at false rather than throwing.
        let value = json!({
            "keychain_probe": "available",
            "hardware_probe_code": "x",
        });
        let decoded = SecurityCapabilities::from_json_value(&value).unwrap();
        assert!(!decoded.keychain_available);
        assert!(!decoded.hardware_vault_available);
        assert!(!decoded.biometric_available);
        assert!(!decoded.fprintd_available);
        assert!(!decoded.is_linux_host);
    }

    #[test]
    fn from_json_treats_string_truthy_as_false() {
        // Defensive parse: `"true"` is a string, not a boolean.
        // Matches the Dart `json[k] == true` semantics — `==` on
        // a string never equals the literal `true`.
        let value = json!({
            "keychain_available": "true",
            "keychain_probe": "available",
            "hardware_probe_code": "x",
        });
        let decoded = SecurityCapabilities::from_json_value(&value).unwrap();
        assert!(!decoded.keychain_available);
    }

    #[test]
    fn defaults_match_dart_constructor() {
        let d = SecurityCapabilities::defaults();
        assert!(!d.keychain_available);
        assert!(!d.hardware_vault_available);
        assert!(!d.biometric_available);
        assert!(!d.fprintd_available);
        assert!(!d.is_linux_host);
        assert_eq!(d.keychain_probe, KeyringProbeResult::ProbeFailed);
        assert_eq!(d.hardware_probe_code, "unknown");
    }
}
