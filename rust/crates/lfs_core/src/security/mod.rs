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

pub mod master_password;

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
}
