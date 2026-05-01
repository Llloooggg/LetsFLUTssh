//! Security tier model — pure data scaffold.
//!
//! Mirrors the Dart-side `SecurityTier` enum + `SecurityTierModifiers`
//! struct so the in-flight tier-machine port has typed primitives to
//! return to FRB callers. Today the canonical source of truth still
//! lives Dart-side (`lib/core/security/security_tier.dart`); the
//! `lfs_core::security::tier::Machine` actor that owns the
//! tier-state transitions reuses these enums when it lands so the
//! Dart-side wrappers can shrink to FRB-DTO mirrors with no
//! behavioural divergence.
//!
//! Why introduce the types now: every other actor under `lfs_core`
//! that needs to reason about the running tier (master-password
//! verifier, hardware-tier composer, biometric vault) will publish
//! events keyed off this enum. Landing the enum first keeps the bus
//! event surface stable across the multi-arc tier-machine port.

use std::collections::BTreeMap;

pub mod capabilities;
pub mod capabilities_cache;
pub mod capabilities_orchestrator;
pub mod credential_prompt;
pub mod hardware_tier_vault;
pub mod hardware_vault_probe_prompt;
pub mod hardware_vault_seal_prompt;
pub mod hardware_vault_unlock_prompt;
pub mod keychain_marker;
pub mod keychain_password_gate;
pub mod keychain_password_gate_actor;
pub mod keychain_probe_prompt;
pub mod master_password;
pub mod persisted_rate_limit;
pub mod persisted_rate_limit_actor;
pub mod tier_machine;
pub mod tier_transition_marker;
pub mod tier_unlock_orchestrator;
pub mod wipe;
pub mod wipe_keychain;

/// Named security tiers. Mirror of the Dart enum case-for-case.
///
/// The user-facing UI presents four numbered tiers (L0–L3) on a
/// linear "more backend = higher number" ladder, plus a separate
/// `Paranoid` branch shown as an alternative. Comparison
/// operators (`<` / `>`) are intentionally NOT implemented — the
/// "paranoid is alternative not stronger" semantics rule out a
/// total order. Use the predicate accessors (`has_keychain`,
/// `has_hardware_vault`, `is_paranoid`) for branch logic.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SecurityTier {
    /// L0 — bare DB on disk, file permissions only.
    Plaintext,
    /// L1 — DB key in OS secure storage; auto-unlock on launch.
    Keychain,
    /// L2 — L1 + short user-typed password gate (UX, not crypto).
    KeychainWithPassword,
    /// L3 — DB key wrapped by hardware-bound vault; PIN +
    /// optional biometric prompt.
    Hardware,
    /// Alternative branch — master password + Argon2id, never
    /// stored in OS. Biometric forbidden by design.
    Paranoid,
}

impl SecurityTier {
    pub fn is_paranoid(self) -> bool {
        matches!(self, SecurityTier::Paranoid)
    }

    pub fn has_keychain(self) -> bool {
        matches!(
            self,
            SecurityTier::Keychain | SecurityTier::KeychainWithPassword | SecurityTier::Hardware
        )
    }

    pub fn has_hardware_vault(self) -> bool {
        matches!(self, SecurityTier::Hardware)
    }

    /// Wire name used by the Dart-side JSON config (snake_case to
    /// match `lib/core/config/app_config.dart::_tierToString`). Any
    /// drift here breaks round-trip with installs whose `config.json`
    /// already carries a tier string written by the Dart writer.
    pub fn wire_name(self) -> &'static str {
        match self {
            SecurityTier::Plaintext => "plaintext",
            SecurityTier::Keychain => "keychain",
            SecurityTier::KeychainWithPassword => "keychain_with_password",
            SecurityTier::Hardware => "hardware",
            SecurityTier::Paranoid => "paranoid",
        }
    }

    pub fn from_wire_name(name: &str) -> Option<Self> {
        match name {
            "plaintext" => Some(SecurityTier::Plaintext),
            "keychain" => Some(SecurityTier::Keychain),
            "keychain_with_password" => Some(SecurityTier::KeychainWithPassword),
            "hardware" => Some(SecurityTier::Hardware),
            "paranoid" => Some(SecurityTier::Paranoid),
            _ => None,
        }
    }
}

/// Orthogonal per-tier switches. Mirrors the Dart bag.
///
/// Invariant: `biometric` requires `password`. Biometric is a
/// shortcut that releases the stored password from a biometric-gated
/// OS slot, never a replacement for typing the password. The Dart
/// wizard enforces this; the Rust copy of the predicate enables the
/// tier machine to validate config the same way.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SecurityTierModifiers {
    pub password: bool,
    pub biometric: bool,
    /// Deprecated alias kept in sync with `biometric` so v1
    /// persisted configs keep round-tripping through the wizard.
    pub biometric_shortcut: bool,
    /// Hardware-tier PIN length cell count (4..=8). Advisory only
    /// in the bank-style password model; the wizard renders a
    /// digit cell grid at this length when the user picks the
    /// hardware tier.
    pub pin_length: u8,
}

impl Default for SecurityTierModifiers {
    fn default() -> Self {
        Self {
            password: false,
            biometric: false,
            biometric_shortcut: false,
            pin_length: 6,
        }
    }
}

impl SecurityTierModifiers {
    /// True when the modifier bag satisfies the biometric →
    /// password invariant.
    pub fn is_valid(self) -> bool {
        if self.biometric && !self.password {
            return false;
        }
        (4..=8).contains(&self.pin_length)
    }

    /// Render to the same JSON shape `SecurityTierModifiers.toJson`
    /// emits Dart-side. Used by the tier machine when it
    /// snapshots config back to the `app_configs` store.
    pub fn to_json_map(self) -> BTreeMap<&'static str, serde_json::Value> {
        let mut m: BTreeMap<&'static str, serde_json::Value> = BTreeMap::new();
        m.insert("password", serde_json::Value::Bool(self.password));
        m.insert("biometric", serde_json::Value::Bool(self.biometric));
        m.insert(
            "biometric_shortcut",
            serde_json::Value::Bool(self.biometric_shortcut),
        );
        m.insert(
            "pin_length",
            serde_json::Value::Number(serde_json::Number::from(self.pin_length as i64)),
        );
        m
    }

    /// Inverse of [`to_json_map`] — read the bag from a JSON object.
    /// Mirrors `SecurityTierModifiers.fromJson` Dart-side: missing
    /// fields fall back to defaults; `biometric` falls back to
    /// `biometric_shortcut` so v1-persisted configs round-trip
    /// without a migration step; `pin_length` outside 4..=8 clamps
    /// back to the default rather than crashing the PIN widget.
    pub fn from_json_map(json: &serde_json::Map<String, serde_json::Value>) -> Self {
        let d = SecurityTierModifiers::default();
        let biometric_shortcut = json
            .get("biometric_shortcut")
            .and_then(|v| v.as_bool())
            .unwrap_or(d.biometric_shortcut);
        let biometric = json
            .get("biometric")
            .and_then(|v| v.as_bool())
            .unwrap_or(biometric_shortcut);
        let raw_pin = json
            .get("pin_length")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32)
            .unwrap_or(d.pin_length as i32);
        let pin_length = if !(4..=8).contains(&raw_pin) {
            d.pin_length
        } else {
            raw_pin as u8
        };
        SecurityTierModifiers {
            password: json
                .get("password")
                .and_then(|v| v.as_bool())
                .unwrap_or(d.password),
            biometric,
            biometric_shortcut,
            pin_length,
        }
    }
}

/// Complete security configuration — tier + modifiers. Mirror of the
/// Dart `SecurityConfig` class. Persists as `"security_tier"` +
/// `"security_modifiers"` fields inside the existing `config.json`.
///
/// The "not yet configured" state is represented by `AppConfig.security
/// == None` Dart-side, not by any distinguished `SecurityConfig` value
/// — the [`defaults`] convenience here is a placeholder for code paths
/// that need *some* concrete instance before the wizard or inference
/// resolves the real one, never a "wizard has not run" sentinel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SecurityConfig {
    pub tier: SecurityTier,
    pub modifiers: SecurityTierModifiers,
}

impl SecurityConfig {
    pub const fn defaults() -> Self {
        Self {
            tier: SecurityTier::Plaintext,
            modifiers: SecurityTierModifiers {
                password: false,
                biometric: false,
                biometric_shortcut: false,
                pin_length: 6,
            },
        }
    }

    pub fn is_paranoid(&self) -> bool {
        self.tier.is_paranoid()
    }
    pub fn is_plaintext(&self) -> bool {
        matches!(self.tier, SecurityTier::Plaintext)
    }

    /// True when the tier stores the DB key in an OS keychain slot of
    /// any kind (L1 or L2). Used by code paths that need to decide
    /// between "read from keychain" and "derive fresh".
    pub fn uses_keychain(&self) -> bool {
        matches!(
            self.tier,
            SecurityTier::Keychain | SecurityTier::KeychainWithPassword
        )
    }

    /// True when the tier binds the key to a hardware-bound vault.
    pub fn uses_hardware_vault(&self) -> bool {
        matches!(self.tier, SecurityTier::Hardware)
    }

    /// True when the tier has any user-typed secret on the unlock
    /// path (password, PIN, or master password).
    pub fn has_user_secret(&self) -> bool {
        matches!(
            self.tier,
            SecurityTier::KeychainWithPassword | SecurityTier::Hardware | SecurityTier::Paranoid
        )
    }

    pub fn to_json_value(&self) -> serde_json::Value {
        let mut m = serde_json::Map::new();
        m.insert(
            "tier".into(),
            serde_json::Value::String(self.tier.wire_name().into()),
        );
        m.insert(
            "modifiers".into(),
            serde_json::Value::Object(
                self.modifiers
                    .to_json_map()
                    .into_iter()
                    .map(|(k, v)| (k.to_string(), v))
                    .collect(),
            ),
        );
        serde_json::Value::Object(m)
    }

    /// Inverse of [`to_json_value`]. Mirrors Dart
    /// `SecurityConfig.fromJson`: an unknown / missing tier string
    /// falls through to plaintext so the caller routes into the
    /// wizard rather than silently picking an unintended tier.
    pub fn from_json_value(value: &serde_json::Value) -> Self {
        let d = SecurityConfig::defaults();
        let Some(obj) = value.as_object() else {
            return d;
        };
        let tier = obj
            .get("tier")
            .and_then(|v| v.as_str())
            .and_then(SecurityTier::from_wire_name)
            .unwrap_or(d.tier);
        let modifiers = obj
            .get("modifiers")
            .and_then(|v| v.as_object())
            .map(SecurityTierModifiers::from_json_map)
            .unwrap_or(d.modifiers);
        SecurityConfig { tier, modifiers }
    }
}

/// Wizard radio-set tier identifier. Mirrors the Dart `WizardTier`
/// enum case-for-case. Lives in `security` (not in a separate
/// `wizard` module) because the only consumer is the wizard-choice
/// mapper that returns into the `SecurityTier` namespace.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum WizardTier {
    Plaintext,
    Keychain,
    Hardware,
    Paranoid,
}

/// Output of [`map_wizard_choice`] — a tier-machine-ready
/// configuration plus the typed secret routed into whichever of
/// `master_password` / `short_password` / `pin` the legacy
/// `_applyTierChange` cascade expects for the chosen tier.
///
/// Only one of `master_password` / `short_password` / `pin` is ever
/// `Some(_)` per call — the wizard never returns a configuration
/// that asks two of those slots to coexist.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MappedSetupChoice {
    pub tier: SecurityTier,
    pub modifiers: SecurityTierModifiers,
    pub master_password: Option<String>,
    pub short_password: Option<String>,
    pub pin: Option<String>,
}

/// Translate the wizard's (T0/T1/T2/Paranoid + password + biometric +
/// typed secret) shape into the persistence-layer `SecurityTier` +
/// typed secret the current `_applyTierChange` cascade expects.
///
/// Pure mapping — no I/O, no platform calls. Lives Rust-side so the
/// tier-choice grammar (which slot the typed secret routes into,
/// which tier variant is picked when password is on/off) stays one
/// place across the Dart wizard + the in-flight tier machine. The
/// `biometric_shortcut` field on `SecurityTierModifiers` mirrors
/// `biometric` 1:1 here — same semantics as the Dart constructor's
/// implicit `biometricShortcut: biometric`.
#[must_use]
pub fn map_wizard_choice(
    chosen: WizardTier,
    password: bool,
    biometric: bool,
    typed_secret: Option<String>,
) -> MappedSetupChoice {
    let modifiers = SecurityTierModifiers {
        password,
        biometric,
        biometric_shortcut: biometric,
        pin_length: SecurityTierModifiers::default().pin_length,
    };
    match chosen {
        WizardTier::Plaintext => MappedSetupChoice {
            tier: SecurityTier::Plaintext,
            modifiers,
            master_password: None,
            short_password: None,
            pin: None,
        },
        WizardTier::Keychain if password => MappedSetupChoice {
            tier: SecurityTier::KeychainWithPassword,
            modifiers,
            master_password: None,
            short_password: typed_secret,
            pin: None,
        },
        WizardTier::Keychain => MappedSetupChoice {
            tier: SecurityTier::Keychain,
            modifiers,
            master_password: None,
            short_password: None,
            pin: None,
        },
        WizardTier::Hardware => MappedSetupChoice {
            tier: SecurityTier::Hardware,
            modifiers,
            master_password: None,
            short_password: None,
            pin: typed_secret,
        },
        WizardTier::Paranoid => MappedSetupChoice {
            tier: SecurityTier::Paranoid,
            modifiers,
            master_password: typed_secret,
            short_password: None,
            pin: None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_name_round_trip() {
        for tier in [
            SecurityTier::Plaintext,
            SecurityTier::Keychain,
            SecurityTier::KeychainWithPassword,
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
    }

    #[test]
    fn predicate_accessors() {
        assert!(SecurityTier::Paranoid.is_paranoid());
        assert!(!SecurityTier::Plaintext.is_paranoid());
        assert!(SecurityTier::Hardware.has_hardware_vault());
        assert!(!SecurityTier::Keychain.has_hardware_vault());
        assert!(SecurityTier::Keychain.has_keychain());
        assert!(SecurityTier::KeychainWithPassword.has_keychain());
        assert!(SecurityTier::Hardware.has_keychain());
        assert!(!SecurityTier::Plaintext.has_keychain());
        assert!(!SecurityTier::Paranoid.has_keychain());
    }

    #[test]
    fn modifiers_invariant() {
        let valid = SecurityTierModifiers {
            password: true,
            biometric: true,
            biometric_shortcut: true,
            pin_length: 6,
        };
        assert!(valid.is_valid());

        let bad_biometric = SecurityTierModifiers {
            password: false,
            biometric: true,
            biometric_shortcut: true,
            pin_length: 6,
        };
        assert!(!bad_biometric.is_valid());

        let bad_pin = SecurityTierModifiers {
            password: true,
            biometric: false,
            biometric_shortcut: false,
            pin_length: 3,
        };
        assert!(!bad_pin.is_valid());
    }

    #[test]
    fn defaults_match_dart() {
        let d = SecurityTierModifiers::default();
        assert!(!d.password);
        assert!(!d.biometric);
        assert!(!d.biometric_shortcut);
        assert_eq!(d.pin_length, 6);
    }

    #[test]
    fn json_shape_matches_dart_keys() {
        let m = SecurityTierModifiers {
            password: true,
            biometric: true,
            biometric_shortcut: true,
            pin_length: 4,
        };
        let json = m.to_json_map();
        assert!(json.contains_key("password"));
        assert!(json.contains_key("biometric"));
        assert!(json.contains_key("biometric_shortcut"));
        assert!(json.contains_key("pin_length"));
    }

    #[test]
    fn modifiers_json_round_trip() {
        let original = SecurityTierModifiers {
            password: true,
            biometric: true,
            biometric_shortcut: true,
            pin_length: 5,
        };
        let map = original.to_json_map();
        let json: serde_json::Map<String, serde_json::Value> =
            map.into_iter().map(|(k, v)| (k.to_string(), v)).collect();
        let decoded = SecurityTierModifiers::from_json_map(&json);
        assert_eq!(decoded, original);
    }

    #[test]
    fn modifiers_from_json_falls_back_to_biometric_shortcut() {
        // v1 persisted configs only carry `biometric_shortcut`.
        // The decoder fills `biometric` from it so the bank-style
        // wizard reads as if the user opted in.
        let mut json = serde_json::Map::new();
        json.insert("password".into(), serde_json::Value::Bool(true));
        json.insert("biometric_shortcut".into(), serde_json::Value::Bool(true));
        let m = SecurityTierModifiers::from_json_map(&json);
        assert!(m.biometric);
        assert!(m.biometric_shortcut);
    }

    #[test]
    fn modifiers_from_json_clamps_oob_pin() {
        let mut json = serde_json::Map::new();
        json.insert(
            "pin_length".into(),
            serde_json::Value::Number(serde_json::Number::from(99i64)),
        );
        let m = SecurityTierModifiers::from_json_map(&json);
        // Clamps back to default rather than crashing the PIN widget
        // with a 99-cell render.
        assert_eq!(m.pin_length, 6);
    }

    #[test]
    fn config_json_round_trip() {
        let original = SecurityConfig {
            tier: SecurityTier::KeychainWithPassword,
            modifiers: SecurityTierModifiers {
                password: true,
                biometric: false,
                biometric_shortcut: false,
                pin_length: 6,
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
        for (tier, paranoid, plaintext, kc, hw, secret) in [
            (SecurityTier::Plaintext, false, true, false, false, false),
            (SecurityTier::Keychain, false, false, true, false, false),
            (
                SecurityTier::KeychainWithPassword,
                false,
                false,
                true,
                false,
                true,
            ),
            (SecurityTier::Hardware, false, false, false, true, true),
            (SecurityTier::Paranoid, true, false, false, false, true),
        ] {
            let cfg = SecurityConfig {
                tier,
                modifiers: SecurityTierModifiers::default(),
            };
            assert_eq!(cfg.is_paranoid(), paranoid, "{tier:?}");
            assert_eq!(cfg.is_plaintext(), plaintext, "{tier:?}");
            assert_eq!(cfg.uses_keychain(), kc, "{tier:?}");
            assert_eq!(cfg.uses_hardware_vault(), hw, "{tier:?}");
            assert_eq!(cfg.has_user_secret(), secret, "{tier:?}");
        }
    }

    #[test]
    fn config_to_json_uses_snake_case_tier_name() {
        let cfg = SecurityConfig {
            tier: SecurityTier::KeychainWithPassword,
            modifiers: SecurityTierModifiers::default(),
        };
        let json = cfg.to_json_value();
        assert_eq!(
            json.get("tier").and_then(|v| v.as_str()),
            Some("keychain_with_password")
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
        assert_eq!(with_pw.tier, SecurityTier::KeychainWithPassword);
        assert_eq!(with_pw.short_password, Some("hunter2".into()));
        assert_eq!(with_pw.pin, None);
        assert_eq!(with_pw.master_password, None);
    }

    #[test]
    fn map_wizard_choice_hardware_routes_secret_into_pin_slot() {
        let r = map_wizard_choice(WizardTier::Hardware, false, true, Some("123456".into()));
        assert_eq!(r.tier, SecurityTier::Hardware);
        assert_eq!(r.pin, Some("123456".into()));
        assert_eq!(r.short_password, None);
        assert_eq!(r.master_password, None);
        assert!(r.modifiers.biometric);
        assert!(r.modifiers.biometric_shortcut);
    }

    #[test]
    fn map_wizard_choice_paranoid_routes_secret_into_master_slot() {
        let r = map_wizard_choice(WizardTier::Paranoid, true, false, Some("longphrase".into()));
        assert_eq!(r.tier, SecurityTier::Paranoid);
        assert_eq!(r.master_password, Some("longphrase".into()));
        assert_eq!(r.pin, None);
        assert_eq!(r.short_password, None);
    }

    #[test]
    fn map_wizard_choice_biometric_shortcut_mirrors_biometric() {
        // Mirrors the Dart constructor's implicit
        // `biometricShortcut: biometric` — same boolean lands on
        // both fields. Catches accidental divergence if either
        // field is rewired separately later.
        for biometric in [false, true] {
            let r = map_wizard_choice(WizardTier::Hardware, true, biometric, None);
            assert_eq!(r.modifiers.biometric, biometric);
            assert_eq!(r.modifiers.biometric_shortcut, biometric);
        }
    }
}
