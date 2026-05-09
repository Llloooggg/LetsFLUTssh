//! FRB adapter for `lfs_core::security::{SecurityTier, SecurityConfig,
//! SecurityTierModifiers}` JSON encode/decode.
//!
//! Sync — every op is a tiny JSON serialise / parse + a few enum
//! lookups. Wire shape on both sides: JSON-string payloads cross
//! the boundary so a future field bump lands inside `lfs_core`
//! without re-generating bindings.

use lfs_core::security::{SecurityConfig, SecurityTier, SecurityTierModifiers};

/// Encode the `SecurityConfig` blob persisted under
/// `config.json::security`. Returns the minified JSON string —
/// caller `jsonDecode`s into a `Map<String, dynamic>` for the
/// existing `app_config.dart` consumers.
///
/// `tier_wire_name` must be one of `plaintext`, `keychain`,
/// `hardware`, `paranoid`. Unknown wire names surface as `Err`
/// so the caller surfaces the misuse instead of silently picking
/// plaintext.
#[flutter_rust_bridge::frb(sync)]
pub fn security_config_to_json(
    tier_wire_name: String,
    password: bool,
    biometric: bool,
) -> Result<String, String> {
    let tier = SecurityTier::from_wire_name(&tier_wire_name)
        .ok_or_else(|| format!("unknown tier wire name: {tier_wire_name}"))?;
    let cfg = SecurityConfig {
        tier,
        modifiers: SecurityTierModifiers {
            password,
            biometric,
        },
    };
    Ok(cfg.to_json_value().to_string())
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

/// Flat DTO for a parsed `SecurityConfig` — tier wire name +
/// per-modifier scalars, returned across the FRB boundary so the
/// Dart caller can rebuild its own `SecurityConfig` instance
/// without re-importing the enum from a generated file.
#[derive(Debug, Clone)]
pub struct DbSecurityConfig {
    pub tier_wire_name: String,
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
        tier_wire_name: cfg.tier.wire_name().to_string(),
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
    fn config_to_json_then_from_json_round_trips_every_field() {
        let json = security_config_to_json("keychain".into(), true, false).expect("encode");
        let parsed = security_config_from_json(json).expect("decode");
        assert_eq!(parsed.tier_wire_name, "keychain");
        assert!(parsed.password);
        assert!(!parsed.biometric);
    }

    #[test]
    fn config_to_json_rejects_unknown_tier_wire_name() {
        let res = security_config_to_json("ghost-tier".into(), false, false);
        assert!(res.is_err());
    }

    #[test]
    fn config_from_json_falls_back_to_plaintext_for_unknown_tier() {
        // Documented contract — unknown / missing tier falls
        // through to plaintext so the caller routes into the
        // wizard rather than silently picking an unintended tier.
        let parsed = security_config_from_json(r#"{"tier": "nonsense"}"#.into())
            .expect("missing tier defaults rather than None");
        assert_eq!(parsed.tier_wire_name, "plaintext");
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
