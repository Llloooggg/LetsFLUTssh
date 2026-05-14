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
/// [`SecurityTier::from_wire_name`] semantics — pre-v3 strings
/// (`keychain_with_password`) are not recognised; the
/// `ConfigV2ToV3` migration rewrites stored configs before this
/// reader sees them.
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
        // Pre-v3 wire string no longer recognised — ConfigV2ToV3
        // migration rewrites stored configs before the runtime
        // parses them, so this branch only fires on a
        // genuinely-malformed input from an external caller.
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
}
