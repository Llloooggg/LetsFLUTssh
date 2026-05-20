//! FRB adapter for `lfs_core::security::{SecurityTier, SecurityConfig,
//! SecurityTierModifiers}` JSON encode/decode + typed enum mirror.
//!
//! Sync — every op is a tiny JSON serialise / parse + a few enum
//! lookups. Wire shape on both sides: JSON-string payloads cross
//! the boundary so a future field bump lands inside `lfs_core`
//! without re-generating bindings.

use lfs_core::security::{SecurityConfig, SecurityTier, SecurityTierModifiers};

/// FRB-visible mirror of [`lfs_core::security::SecurityTier`].
/// Carries the four bank-style tier values across the boundary as a
/// typed enum; Dart consumers pattern-match directly rather than
/// round-tripping the wire-string through a `.fromWireName` helper.
///
/// FRB codegen lowers each variant to camelCase Dart matching the
/// wire grammar `SecurityTier::wire_name` round-trips byte-identically
/// (`plaintext` / `keychain` / `hardware` / `paranoid`). None of the
/// variants collide with a Dart reserved word so the `.name` getter
/// matches the wire byte for every value — the dedicated
/// [`security_tier_to_wire`] helper still exists so callers route
/// through the canonical grammar instead of relying on the camelCase
/// coincidence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DbSecurityTier {
    Plaintext,
    Keychain,
    Hardware,
    Paranoid,
}

impl From<SecurityTier> for DbSecurityTier {
    fn from(value: SecurityTier) -> Self {
        match value {
            SecurityTier::Plaintext => DbSecurityTier::Plaintext,
            SecurityTier::Keychain => DbSecurityTier::Keychain,
            SecurityTier::Hardware => DbSecurityTier::Hardware,
            SecurityTier::Paranoid => DbSecurityTier::Paranoid,
        }
    }
}

impl From<DbSecurityTier> for SecurityTier {
    fn from(value: DbSecurityTier) -> Self {
        match value {
            DbSecurityTier::Plaintext => SecurityTier::Plaintext,
            DbSecurityTier::Keychain => SecurityTier::Keychain,
            DbSecurityTier::Hardware => SecurityTier::Hardware,
            DbSecurityTier::Paranoid => SecurityTier::Paranoid,
        }
    }
}

/// Parse a stored tier wire-string into the typed enum. Returns
/// `None` for an unknown / empty string so the caller can decide
/// whether to fall through to plaintext (config-load path) or
/// surface the misuse (typed FRB caller). Mirrors the
/// [`SecurityTier::from_wire_name`] semantics — only the four tier
/// wire names are recognised; a password-gated Keychain rides the
/// `modifiers.password` flag, so there is no `keychain_with_password`
/// wire string to parse.
#[flutter_rust_bridge::frb(sync)]
pub fn security_tier_from_wire(value: String) -> Option<DbSecurityTier> {
    SecurityTier::from_wire_name(&value).map(Into::into)
}

/// Wire value the typed enum lowers to. The FRB sync shim around
/// [`SecurityTier::wire_name`] — Dart-side consumers route through
/// this helper instead of `.name` so any future variant added to a
/// build whose Dart name diverges from the wire grammar (a keyword
/// collision forces FRB to append `_`) keeps the on-wire byte
/// canonical.
#[flutter_rust_bridge::frb(sync)]
pub fn security_tier_to_wire(value: DbSecurityTier) -> String {
    let core: SecurityTier = value.into();
    core.wire_name().to_owned()
}

/// Encode the `SecurityConfig` blob persisted under
/// `config.json::security`. Returns the minified JSON string —
/// caller `jsonDecode`s into a `Map<String, dynamic>` for the
/// existing `app_config.dart` consumers. Takes the typed
/// [`DbSecurityTier`] so the wire-name validation lives Rust-side
/// and the Dart caller can't pass a typo.
#[flutter_rust_bridge::frb(sync)]
pub fn security_config_to_json(tier: DbSecurityTier, password: bool, biometric: bool) -> String {
    let cfg = SecurityConfig {
        tier: tier.into(),
        modifiers: SecurityTierModifiers {
            password,
            biometric,
        },
    };
    cfg.to_json_value().to_string()
}

/// Encode the modifiers blob alone — used by callers that want to
/// re-serialise `SecurityTierModifiers` without going through the
/// outer `SecurityConfig` wrapper.
#[flutter_rust_bridge::frb(sync)]
pub fn security_tier_modifiers_to_json(password: bool, biometric: bool) -> String {
    let m = SecurityTierModifiers {
        password,
        biometric,
    };
    let map = m.to_json_map();
    let value: serde_json::Map<String, serde_json::Value> =
        map.into_iter().map(|(k, v)| (k.to_string(), v)).collect();
    serde_json::Value::Object(value).to_string()
}

/// Compose the JSON payload every tier-apply method writes into the
/// crash-recovery marker file before driving
/// `SecurityTierSwitcher::switch_tier_from_secret`. Bundles the
/// snake-case tier wire-name + modifier object so a crash-recovery
/// path at next launch reconstructs the target config and picks the
/// matching unlock prompt.
///
/// Wire shape: `{"tier": <wire>, "mods": {"password": …, "biometric": …}}`.
/// Single source of truth for the marker grammar — the Dart caller
/// hands the typed tier + modifier flags in, the Rust side emits the
/// canonical string, no Dart-side `jsonEncode` / `jsonDecode` round-
/// trip on the apply path.
#[flutter_rust_bridge::frb(sync)]
pub fn security_tier_marker_payload(
    tier: DbSecurityTier,
    password: bool,
    biometric: bool,
) -> String {
    let core: SecurityTier = tier.into();
    let m = SecurityTierModifiers {
        password,
        biometric,
    };
    let mods_map: serde_json::Map<String, serde_json::Value> = m
        .to_json_map()
        .into_iter()
        .map(|(k, v)| (k.to_string(), v))
        .collect();
    let mut obj = serde_json::Map::new();
    obj.insert(
        "tier".into(),
        serde_json::Value::String(core.wire_name().to_owned()),
    );
    obj.insert("mods".into(), serde_json::Value::Object(mods_map));
    serde_json::Value::Object(obj).to_string()
}

/// Flat DTO for a parsed `SecurityConfig` — typed tier + per-modifier
/// scalars, returned across the FRB boundary so the Dart caller can
/// rebuild its own `SecurityConfig` instance without re-importing
/// the enum from a generated file. The tier rides as a typed
/// [`DbSecurityTier`] (no wire-string round-trip on the Dart side).
#[derive(Debug, Clone)]
pub struct DbSecurityConfig {
    pub tier: DbSecurityTier,
    pub password: bool,
    pub biometric: bool,
}

/// Parse the `security` JSON object. Mirrors `SecurityConfig.fromJson`
/// Dart-side: an unknown / missing tier string falls through to
/// `plaintext` so the caller routes into the wizard rather than
/// silently picking an unintended tier; missing modifiers fall back
/// to defaults.
#[flutter_rust_bridge::frb(sync)]
pub fn security_config_from_json(json: String) -> Option<DbSecurityConfig> {
    let value: serde_json::Value = serde_json::from_str(&json).ok()?;
    let cfg = SecurityConfig::from_json_value(&value);
    Some(DbSecurityConfig {
        tier: cfg.tier.into(),
        password: cfg.modifiers.password,
        biometric: cfg.modifiers.biometric,
    })
}

/// FRB-side mirror of just the modifiers block.
#[derive(Debug, Clone)]
pub struct DbSecurityTierModifiers {
    pub password: bool,
    pub biometric: bool,
}

#[flutter_rust_bridge::frb(sync)]
pub fn security_tier_modifiers_from_json(json: String) -> Option<DbSecurityTierModifiers> {
    let value: serde_json::Value = serde_json::from_str(&json).ok()?;
    let map = value.as_object()?;
    let m = SecurityTierModifiers::from_json_map(map);
    Some(DbSecurityTierModifiers {
        password: m.password,
        biometric: m.biometric,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tier_round_trip_via_typed_enum() {
        // The four bank-style tiers round-trip through the typed
        // FRB mirror without re-touching the wire string.
        for tier in [
            DbSecurityTier::Plaintext,
            DbSecurityTier::Keychain,
            DbSecurityTier::Hardware,
            DbSecurityTier::Paranoid,
        ] {
            let wire = security_tier_to_wire(tier);
            assert_eq!(security_tier_from_wire(wire), Some(tier));
        }
    }

    #[test]
    fn tier_from_wire_rejects_unknown() {
        assert_eq!(security_tier_from_wire("".into()), None);
        assert_eq!(security_tier_from_wire("L4".into()), None);
        // `keychain_with_password` is not a tier wire name in the
        // bank-style model — a password-gated Keychain rides the
        // `modifiers.password` flag — so it parses as unknown.
        assert_eq!(
            security_tier_from_wire("keychain_with_password".into()),
            None
        );
    }

    #[test]
    fn config_to_json_then_from_json_round_trips_every_field() {
        let json = security_config_to_json(DbSecurityTier::Keychain, true, false);
        let parsed = security_config_from_json(json).expect("decode");
        assert_eq!(parsed.tier, DbSecurityTier::Keychain);
        assert!(parsed.password);
        assert!(!parsed.biometric);
    }

    #[test]
    fn config_from_json_falls_back_to_plaintext_for_unknown_tier() {
        // Documented contract — unknown / missing tier falls
        // through to plaintext so the caller routes into the
        // wizard rather than silently picking an unintended tier.
        let parsed = security_config_from_json(r#"{"tier": "nonsense"}"#.into())
            .expect("missing tier defaults rather than None");
        assert_eq!(parsed.tier, DbSecurityTier::Plaintext);
    }

    #[test]
    fn config_from_json_returns_none_for_garbage() {
        // Pure parse failures (non-JSON input) collapse to None;
        // the Dart load path treats that as "no config in this
        // file, fall through to defaults".
        assert!(security_config_from_json("not json".into()).is_none());
    }

    #[test]
    fn modifiers_to_json_then_from_json_round_trips_both_flags() {
        let json = security_tier_modifiers_to_json(true, true);
        let parsed = security_tier_modifiers_from_json(json).expect("decode");
        assert!(parsed.password);
        assert!(parsed.biometric);
    }

    #[test]
    fn modifiers_to_json_emits_object_shape() {
        let json = security_tier_modifiers_to_json(false, true);
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid JSON");
        assert!(parsed.is_object());
    }

    #[test]
    fn tier_marker_payload_bundles_tier_and_modifiers() {
        let payload = security_tier_marker_payload(DbSecurityTier::Hardware, true, true);
        let parsed: serde_json::Value = serde_json::from_str(&payload).expect("payload must parse");
        let obj = parsed.as_object().expect("object root");
        assert_eq!(obj.get("tier").and_then(|v| v.as_str()), Some("hardware"));
        let mods = obj
            .get("mods")
            .and_then(|v| v.as_object())
            .expect("mods sub-object");
        assert_eq!(mods.get("password").and_then(|v| v.as_bool()), Some(true));
        assert_eq!(mods.get("biometric").and_then(|v| v.as_bool()), Some(true));
    }

    #[test]
    fn tier_marker_payload_omits_no_keys() {
        // Even when both flags are false the modifier sub-object
        // carries the explicit `false` fields — the crash-recovery
        // parser keys off presence, not truthiness.
        let payload = security_tier_marker_payload(DbSecurityTier::Plaintext, false, false);
        let parsed: serde_json::Value = serde_json::from_str(&payload).expect("payload must parse");
        let mods = parsed
            .get("mods")
            .and_then(|v| v.as_object())
            .expect("mods sub-object");
        assert_eq!(mods.get("password").and_then(|v| v.as_bool()), Some(false));
        assert_eq!(mods.get("biometric").and_then(|v| v.as_bool()), Some(false));
    }
}
