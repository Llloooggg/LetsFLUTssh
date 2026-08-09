/// Unit tests extracted from security/capabilities.rs
/// Declared via `#[path] mod tests;` in the source file.
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

#[test]
fn linux_offers_biometric_when_either_platform_or_fprintd_available() {
    let mut caps = sample();
    caps.is_linux_host = true;
    caps.biometric_available = false;
    caps.fprintd_available = true;
    assert!(caps.can_offer_biometric_modifier());

    caps.fprintd_available = false;
    caps.biometric_available = true;
    assert!(caps.can_offer_biometric_modifier());

    caps.biometric_available = false;
    caps.fprintd_available = false;
    assert!(!caps.can_offer_biometric_modifier());
}

#[test]
fn non_linux_only_uses_platform_biometric() {
    let mut caps = sample();
    caps.is_linux_host = false;
    // fprintd-only on a Mac means nothing for the wizard.
    caps.biometric_available = false;
    caps.fprintd_available = true;
    assert!(!caps.can_offer_biometric_modifier());

    caps.biometric_available = true;
    assert!(caps.can_offer_biometric_modifier());
}
