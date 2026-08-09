/// Unit tests extracted from security/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn wire_name_round_trip() {
    for tier in [
        SecurityTier::Plaintext,
        SecurityTier::Keychain,
        SecurityTier::Hardware,
        SecurityTier::Paranoid,
    ] {
        assert_eq!(SecurityTier::from_wire_name(tier.wire_name()), Some(tier));
    }
}

#[test]
fn from_wire_name_rejects_unknown() {
    assert_eq!(SecurityTier::from_wire_name(""), None);
    assert_eq!(SecurityTier::from_wire_name("L4"), None);
    assert_eq!(SecurityTier::from_wire_name("plaintext "), None);
    // `keychain_with_password` is not a tier wire name in the
    // bank-style model — a password-gated Keychain rides the
    // `modifiers.password` flag — so it parses as unknown.
    assert_eq!(SecurityTier::from_wire_name("keychain_with_password"), None);
}

#[test]
fn predicate_accessors() {
    assert!(SecurityTier::Paranoid.is_paranoid());
    assert!(!SecurityTier::Plaintext.is_paranoid());
    assert!(SecurityTier::Hardware.has_hardware_vault());
    assert!(!SecurityTier::Keychain.has_hardware_vault());
    assert!(SecurityTier::Keychain.has_keychain());
    assert!(SecurityTier::Hardware.has_keychain());
    assert!(!SecurityTier::Plaintext.has_keychain());
    assert!(!SecurityTier::Paranoid.has_keychain());
}

#[test]
fn modifiers_is_valid_for_tier_hardware_requires_password() {
    // The Hardware tier rejects `password=false` outright;
    // biometric is an optional shortcut, never a replacement.
    let no_pw = SecurityTierModifiers {
        password: false,
        biometric: false,
    };
    assert!(!no_pw.is_valid_for_tier(SecurityTier::Hardware));
    // Same bag is valid on every non-Hardware tier.
    assert!(no_pw.is_valid_for_tier(SecurityTier::Plaintext));
    assert!(no_pw.is_valid_for_tier(SecurityTier::Keychain));
    // Paranoid does not branch through this predicate (it has
    // its own mandatory-password property), but the helper
    // still accepts it for symmetry.
    assert!(no_pw.is_valid_for_tier(SecurityTier::Paranoid));

    let with_pw = SecurityTierModifiers {
        password: true,
        biometric: false,
    };
    assert!(with_pw.is_valid_for_tier(SecurityTier::Hardware));

    // Biometric without password is still invalid for every
    // tier — the cross-cutting biometric → password rule
    // composes with the Hardware-specific rule.
    let bad = SecurityTierModifiers {
        password: false,
        biometric: true,
    };
    assert!(!bad.is_valid_for_tier(SecurityTier::Hardware));
    assert!(!bad.is_valid_for_tier(SecurityTier::Keychain));
}

#[test]
fn defaults_match_dart() {
    let d = SecurityTierModifiers::default();
    assert!(!d.password);
    assert!(!d.biometric);
}

#[test]
fn json_shape_matches_dart_keys() {
    let m = SecurityTierModifiers {
        password: true,
        biometric: true,
    };
    let json = m.to_json_map();
    assert!(json.contains_key("password"));
    assert!(json.contains_key("biometric"));
    // The emitter carries exactly `password` + `biometric` — no
    // stray keys leak into the on-disk shape.
    assert_eq!(json.len(), 2);
}

#[test]
fn modifiers_json_round_trip() {
    let original = SecurityTierModifiers {
        password: true,
        biometric: true,
    };
    let map = original.to_json_map();
    let json: serde_json::Map<String, serde_json::Value> =
        map.into_iter().map(|(k, v)| (k.to_string(), v)).collect();
    let decoded = SecurityTierModifiers::from_json_map(&json);
    assert_eq!(decoded, original);
}

#[test]
fn modifiers_from_json_ignores_unknown_keys() {
    // Only `password` / `biometric` are read. Any other key in a
    // hand-edited config must be silently ignored rather than
    // blow up the decode.
    let mut json = serde_json::Map::new();
    json.insert("password".into(), serde_json::Value::Bool(true));
    json.insert("biometric".into(), serde_json::Value::Bool(false));
    json.insert("biometric_shortcut".into(), serde_json::Value::Bool(true));
    json.insert(
        "pin_length".into(),
        serde_json::Value::Number(serde_json::Number::from(6i64)),
    );
    let m = SecurityTierModifiers::from_json_map(&json);
    assert!(m.password);
    assert!(!m.biometric);
}

#[test]
fn config_json_round_trip() {
    let original = SecurityConfig {
        // Bank-style T1 + password — Keychain tier composed
        // with the `password` modifier.
        tier: SecurityTier::Keychain,
        modifiers: SecurityTierModifiers {
            password: true,
            biometric: false,
        },
    };
    let value = original.to_json_value();
    let decoded = SecurityConfig::from_json_value(&value);
    assert_eq!(decoded, original);
}

#[test]
fn config_from_json_unknown_tier_falls_back_to_plaintext() {
    let value = serde_json::json!({
        "tier": "tier-from-the-future",
        "modifiers": { "password": true },
    });
    let c = SecurityConfig::from_json_value(&value);
    // Falls through to plaintext so the caller routes into the
    // wizard instead of silently picking an unintended tier.
    assert_eq!(c.tier, SecurityTier::Plaintext);
}

#[test]
fn config_predicates_match_dart() {
    for (tier, password, paranoid, plaintext, kc, hw, secret) in [
        (
            SecurityTier::Plaintext,
            false,
            false,
            true,
            false,
            false,
            false,
        ),
        (
            SecurityTier::Keychain,
            false,
            false,
            false,
            true,
            false,
            false,
        ),
        // Bank-style T1 + password — `has_user_secret` flips on
        // the modifier, not on a dedicated tier value.
        (
            SecurityTier::Keychain,
            true,
            false,
            false,
            true,
            false,
            true,
        ),
        // Hardware always reports `has_user_secret == true`
        // regardless of the password modifier value on disk —
        // T2 is mandatory-password by design (the password
        // is the primary gate, biometric is the optional
        // shortcut). A stored `password=false` on a Hardware
        // config is treated as drift and overridden by the
        // mandatory-password invariant when the predicate runs.
        (
            SecurityTier::Hardware,
            false,
            false,
            false,
            false,
            true,
            true,
        ),
        (
            SecurityTier::Hardware,
            true,
            false,
            false,
            false,
            true,
            true,
        ),
        (
            SecurityTier::Paranoid,
            false,
            true,
            false,
            false,
            false,
            true,
        ),
    ] {
        let cfg = SecurityConfig {
            tier,
            modifiers: SecurityTierModifiers {
                password,
                ..SecurityTierModifiers::default()
            },
        };
        assert_eq!(cfg.is_paranoid(), paranoid, "{tier:?} pw={password}");
        assert_eq!(cfg.is_plaintext(), plaintext, "{tier:?} pw={password}");
        assert_eq!(cfg.uses_keychain(), kc, "{tier:?} pw={password}");
        assert_eq!(cfg.uses_hardware_vault(), hw, "{tier:?} pw={password}");
        assert_eq!(cfg.has_user_secret(), secret, "{tier:?} pw={password}");
    }
}

#[test]
fn config_to_json_uses_snake_case_tier_name() {
    let cfg = SecurityConfig {
        tier: SecurityTier::Keychain,
        modifiers: SecurityTierModifiers {
            password: true,
            ..SecurityTierModifiers::default()
        },
    };
    let json = cfg.to_json_value();
    assert_eq!(json.get("tier").and_then(|v| v.as_str()), Some("keychain"),);
    // The password modifier is what carries the "T1 + password"
    // signal in the bank-style v3 wire shape.
    assert_eq!(
        json.get("modifiers")
            .and_then(|m| m.get("password"))
            .and_then(|v| v.as_bool()),
        Some(true),
    );
}

#[test]
fn map_wizard_choice_plaintext_carries_no_secret() {
    let r = map_wizard_choice(WizardTier::Plaintext, false, false, None);
    assert_eq!(r.tier, SecurityTier::Plaintext);
    assert_eq!(r.master_password, None);
    assert_eq!(r.short_password, None);
    assert_eq!(r.pin, None);
    assert!(!r.modifiers.password);
    assert!(!r.modifiers.biometric);
}

#[test]
fn map_wizard_choice_keychain_picks_by_password_flag() {
    let no_pw = map_wizard_choice(WizardTier::Keychain, false, false, None);
    assert_eq!(no_pw.tier, SecurityTier::Keychain);
    assert_eq!(no_pw.short_password, None);

    let with_pw = map_wizard_choice(WizardTier::Keychain, true, false, Some("hunter2".into()));
    // Bank-style: T1 + password is `Keychain` + the password
    // modifier, not a dedicated tier value.
    assert_eq!(with_pw.tier, SecurityTier::Keychain);
    assert!(with_pw.modifiers.password);
    assert_eq!(with_pw.short_password, Some("hunter2".into()));
    assert_eq!(with_pw.pin, None);
    assert_eq!(with_pw.master_password, None);
}

#[test]
fn map_wizard_choice_hardware_routes_secret_into_master_password_slot() {
    // Canonical slot for the Hardware tier is `master_password`
    // — the typed secret is the primary unlock gate, not a
    // separate PIN. Biometric is the optional shortcut on top.
    let r = map_wizard_choice(WizardTier::Hardware, true, true, Some("hunter2".into()));
    assert_eq!(r.tier, SecurityTier::Hardware);
    assert_eq!(r.master_password.as_deref(), Some("hunter2"));
    assert_eq!(r.pin, None);
    assert_eq!(r.short_password, None);
    assert!(r.modifiers.password);
    assert!(r.modifiers.biometric);
}

#[test]
fn map_wizard_choice_hardware_force_pins_password_modifier_on() {
    // A stale caller that asked for Hardware with the
    // password modifier off still lands on a config that
    // carries `password=true` — the tier-level "always
    // password-gated" rule overrides the wizard input.
    let r = map_wizard_choice(WizardTier::Hardware, false, false, Some("pw".into()));
    assert_eq!(r.tier, SecurityTier::Hardware);
    assert!(r.modifiers.password);
    assert_eq!(r.master_password.as_deref(), Some("pw"));
    assert_eq!(r.pin, None);
}

#[test]
fn map_wizard_choice_paranoid_routes_secret_into_master_slot() {
    let r = map_wizard_choice(WizardTier::Paranoid, true, false, Some("longphrase".into()));
    assert_eq!(r.tier, SecurityTier::Paranoid);
    assert_eq!(r.master_password, Some("longphrase".into()));
    assert_eq!(r.pin, None);
    assert_eq!(r.short_password, None);
}
