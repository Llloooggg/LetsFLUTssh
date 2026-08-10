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

pub mod biometric_key_vault;
pub mod capabilities;
pub mod capabilities_cache;
pub mod capabilities_orchestrator;
pub mod capabilities_persister;
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
pub mod prompt_registry;
pub mod recovery;
pub mod recovery_prompt;
pub mod tier_machine;
pub mod tier_transition_marker;
pub mod tier_unlock_orchestrator;
pub mod wipe;
pub mod wipe_keychain;

/// Named security tiers. Mirror of the Dart enum case-for-case.
///
/// The user-facing UI presents four numbered tiers (T0–T2) on a
/// linear "more backend = higher number" ladder, plus a separate
/// `Paranoid` branch shown as an alternative. Comparison
/// operators (`<` / `>`) are intentionally NOT implemented — the
/// "paranoid is alternative not stronger" semantics rule out a
/// total order. Use the predicate accessors (`has_keychain`,
/// `has_hardware_vault`, `is_paranoid`) for branch logic.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SecurityTier {
    /// T0 — bare DB on disk, file permissions only.
    Plaintext,
    /// T1 — DB key in OS secure storage; auto-unlock on launch.
    /// User-typed password gate is the orthogonal
    /// `SecurityTierModifiers::password` switch (bank-style model);
    /// "T1 + password" is `Keychain` + `modifiers.password = true`,
    /// not its own enum variant.
    Keychain,
    /// T2 — DB key wrapped by hardware-bound vault; the
    /// `password` modifier optionally adds a typed-password layer
    /// on top, the `biometric` modifier optionally lets the user
    /// release that password via a biometric prompt instead of
    /// typing it.
    Hardware,
    /// Alternative branch — master password + Argon2id, never
    /// stored in OS. Biometric forbidden by design (a stored
    /// derived key would break the "no-OS-trust" contract).
    Paranoid,
}

impl SecurityTier {
    pub fn is_paranoid(self) -> bool {
        matches!(self, SecurityTier::Paranoid)
    }

    pub fn has_keychain(self) -> bool {
        matches!(self, SecurityTier::Keychain | SecurityTier::Hardware)
    }

    pub fn has_hardware_vault(self) -> bool {
        matches!(self, SecurityTier::Hardware)
    }

    /// Wire name used by the Dart-side JSON config (snake_case to
    /// match `lib/core/config/app_config.dart::_tierToString`). Any
    /// drift here breaks round-trip with installs whose `config.json`
    /// already carries a tier string written by the Dart writer.
    ///
    /// The bank-style model has no `keychain_with_password` tier — a
    /// password-gated Keychain install is `keychain` +
    /// `modifiers.password = true`, so the credential rides the
    /// modifier bag rather than a dedicated tier wire string.
    pub fn wire_name(self) -> &'static str {
        match self {
            SecurityTier::Plaintext => "plaintext",
            SecurityTier::Keychain => "keychain",
            SecurityTier::Hardware => "hardware",
            SecurityTier::Paranoid => "paranoid",
        }
    }

    pub fn from_wire_name(name: &str) -> Option<Self> {
        match name {
            "plaintext" => Some(SecurityTier::Plaintext),
            "keychain" => Some(SecurityTier::Keychain),
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
///
/// The bag carries exactly `password` + `biometric`. Any other key
/// in a hand-edited config JSON is ignored on read (see
/// [`SecurityTierModifiers::from_json_map`]) rather than rejected,
/// so an unrecognised field never wedges config decode.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct SecurityTierModifiers {
    pub password: bool,
    pub biometric: bool,
}

impl SecurityTierModifiers {
    /// True when the modifier bag is valid for the given tier.
    ///
    /// Cross-cutting invariant: `biometric → password` (biometric is
    /// the shortcut that releases the typed password from an
    /// OS-managed slot, never a replacement). Callers always carry a
    /// tier in hand at the validation site — wizard mapping, config
    /// decode, settings apply — so there is no tier-independent
    /// overload. A bag that needs to be validated without a tier is a
    /// code smell.
    pub fn is_valid_for_tier(self, tier: SecurityTier) -> bool {
        if self.biometric && !self.password {
            return false;
        }
        // Hardware tier: password is optional (TPM/SE/StrongBox
        // provides hardware binding); biometric gate still requires
        // password if enabled.
        _ = tier;
        true
    }

    /// Render to the same JSON shape `SecurityTierModifiers.toJson`
    /// emits Dart-side. Used by the tier machine when it
    /// snapshots config back to the `app_configs` store.
    pub fn to_json_map(self) -> BTreeMap<&'static str, serde_json::Value> {
        let mut m: BTreeMap<&'static str, serde_json::Value> = BTreeMap::new();
        m.insert("password", serde_json::Value::Bool(self.password));
        m.insert("biometric", serde_json::Value::Bool(self.biometric));
        m
    }

    /// Inverse of [`to_json_map`] — read the bag from a JSON object.
    /// Mirrors `SecurityTierModifiers.fromJson` Dart-side: missing
    /// fields fall back to defaults, and any key other than
    /// `password` / `biometric` is silently ignored so an unknown or
    /// hand-edited field never wedges decode.
    pub fn from_json_map(json: &serde_json::Map<String, serde_json::Value>) -> Self {
        let d = SecurityTierModifiers::default();
        SecurityTierModifiers {
            password: json
                .get("password")
                .and_then(|v| v.as_bool())
                .unwrap_or(d.password),
            biometric: json
                .get("biometric")
                .and_then(|v| v.as_bool())
                .unwrap_or(d.biometric),
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
    /// True when the tier stores the DB key in the OS keychain.
    /// Used by code paths that need to decide between "read from
    /// keychain" and "derive fresh". The bank-style password
    /// modifier is orthogonal: `Keychain` covers both passwordless
    /// T1 and T1 + typed password.
    pub fn uses_keychain(&self) -> bool {
        matches!(self.tier, SecurityTier::Keychain)
    }

    /// True when the tier binds the key to a hardware-bound vault.
    pub fn uses_hardware_vault(&self) -> bool {
        matches!(self.tier, SecurityTier::Hardware)
    }

    /// True when the config has any user-typed secret on the unlock
    /// path. Paranoid is mandatory-password by definition; Hardware
    /// flips on `modifiers.password` (optional — TPM/SE/StrongBox
    /// provides hardware binding, password is defense-in-depth).
    /// Keychain flips on the explicit password modifier.
    pub fn has_user_secret(&self) -> bool {
        match self.tier {
            SecurityTier::Paranoid => true,
            SecurityTier::Hardware | SecurityTier::Keychain => self.modifiers.password,
            SecurityTier::Plaintext => false,
        }
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
/// `master_password` / `short_password` / `pin` the
/// `_applyTierChange` cascade expects for the chosen tier.
///
/// Exactly one of `master_password` / `short_password` / `pin`
/// carries the typed secret per tier: Hardware and Paranoid use
/// `master_password`, Keychain + password uses `short_password`,
/// Plaintext carries no secret at all. The `pin` slot survives
/// for the legacy short-password flavour of the wizard that the
/// codebase no longer ships but kept the field shape stable for.
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
/// place across the Dart wizard + the in-flight tier machine.
#[must_use]
pub fn map_wizard_choice(
    chosen: WizardTier,
    password: bool,
    biometric: bool,
    typed_secret: Option<String>,
) -> MappedSetupChoice {
    // Hardware always carries the password modifier — the typed
    // secret is the primary unlock gate and `is_valid_for_tier`
    // rejects the (Hardware, password=false) combination. The
    // wizard upstream still surfaces a checkbox today; the
    // upcoming Dart wizard flip force-pins the flag for the
    // Hardware row. Pinning Rust-side keeps the
    // `SecurityConfig` shape invariant even if a stale caller
    // sends `password=false`.
    let effective_password = match chosen {
        WizardTier::Hardware => true,
        _ => password,
    };
    let modifiers = SecurityTierModifiers {
        password: effective_password,
        biometric,
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
            // Bank-style: T1 + password is `Keychain` with
            // `modifiers.password = true` — the credential rides the
            // modifier bag, there is no dedicated password-gated tier.
            tier: SecurityTier::Keychain,
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
            // The typed secret is the primary unlock gate for
            // Hardware; it lands in `master_password` exclusively.
            // Biometric is the optional shortcut layer that releases
            // this password from an OS-managed slot, never a separate
            // PIN.
            master_password: typed_secret,
            short_password: None,
            pin: None,
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
#[path = "../../tests/unit/security_mod.rs"]
mod tests;
