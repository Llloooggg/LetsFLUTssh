//! FRB adapter for `lfs_core::security::map_wizard_choice`.
//!
//! Sync — pure mapping over a tiny enum + 3 booleans. Lives in its
//! own module rather than under `security_config` because the
//! wizard-choice grammar is a one-shot transition between the
//! wizard's local enum and the persistence-layer's `SecurityTier`,
//! distinct from the long-lived `SecurityConfig` JSON envelope.
//!
//! Tier wire names cross the boundary as strings so a future
//! `SecurityTier` rename inside `lfs_core` lands without re-
//! generating bindings; same shape every other security-tier shim
//! uses.

use lfs_core::security::{self, WizardTier};

/// Wizard radio-set tier id, crossed as a string so the FRB
/// boundary doesn't drag in a separate enum mirror. Accepted values:
/// `plaintext`, `keychain`, `hardware`, `paranoid` — same wire names
/// the Dart `WizardTier.name` getter emits.
fn parse_wizard_tier(name: &str) -> Result<WizardTier, String> {
    match name {
        "plaintext" => Ok(WizardTier::Plaintext),
        "keychain" => Ok(WizardTier::Keychain),
        "hardware" => Ok(WizardTier::Hardware),
        "paranoid" => Ok(WizardTier::Paranoid),
        _ => Err(format!("unknown wizard tier wire name: {name}")),
    }
}

/// FRB-side mirror of `lfs_core::security::MappedSetupChoice`. The
/// `tier_wire_name` round-trips through the existing
/// `SecurityTier::from_wire_name` Dart-side; only one of
/// `master_password` / `short_password` / `pin` is ever
/// `Some(_)` per call (see [`map_wizard_choice`]'s contract).
#[derive(Debug, Clone)]
pub struct DbMappedSetupChoice {
    pub tier_wire_name: String,
    pub password: bool,
    pub biometric: bool,
    pub master_password: Option<String>,
    pub short_password: Option<String>,
    pub pin: Option<String>,
}

/// Translate the wizard's (`tier` + password + biometric + typed
/// secret) shape into the persistence-layer tier + typed secret the
/// `_applyTierChange` cascade expects. Returns `Err` for an unknown
/// `tier_wire_name` so the misuse surfaces instead of silently
/// picking a wrong tier.
#[flutter_rust_bridge::frb(sync)]
pub fn security_map_wizard_choice(
    tier_wire_name: String,
    password: bool,
    biometric: bool,
    typed_secret: Option<String>,
) -> Result<DbMappedSetupChoice, String> {
    let chosen = parse_wizard_tier(&tier_wire_name)?;
    let mapped = security::map_wizard_choice(chosen, password, biometric, typed_secret);
    Ok(DbMappedSetupChoice {
        tier_wire_name: mapped.tier.wire_name().to_string(),
        password: mapped.modifiers.password,
        biometric: mapped.modifiers.biometric,
        master_password: mapped.master_password,
        short_password: mapped.short_password,
        pin: mapped.pin,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_wizard_tier_wire_name_surfaces_err() {
        let res = security_map_wizard_choice("nonsense".into(), false, false, None);
        assert!(res.is_err());
    }

    #[test]
    fn plaintext_choice_carries_no_typed_secret() {
        let mapped =
            security_map_wizard_choice("plaintext".into(), false, false, None).expect("plaintext");
        assert_eq!(mapped.tier_wire_name, "plaintext");
        assert!(mapped.master_password.is_none());
        assert!(mapped.short_password.is_none());
        assert!(mapped.pin.is_none());
    }

    #[test]
    fn keychain_with_password_lands_typed_secret_in_short_password_slot() {
        // Bank-style: T1 + password puts the typed string in the
        // `short_password` slot (the typed secret is the unlock
        // string, not a long master password). Pin the slot so a
        // future tier-shape refactor can't silently re-route it.
        let mapped = security_map_wizard_choice(
            "keychain".into(),
            true,
            false,
            Some("hunter2-extended".into()),
        )
        .expect("keychain");
        assert!(mapped.password);
        assert!(mapped.master_password.is_none());
        assert_eq!(mapped.short_password.as_deref(), Some("hunter2-extended"));
        assert!(mapped.pin.is_none());
    }

    #[test]
    fn paranoid_lands_typed_secret_in_master_password_slot() {
        let mapped = security_map_wizard_choice(
            "paranoid".into(),
            true,
            false,
            Some("a-real-master-password".into()),
        )
        .expect("paranoid");
        assert_eq!(
            mapped.master_password.as_deref(),
            Some("a-real-master-password")
        );
        assert!(mapped.short_password.is_none());
        assert!(mapped.pin.is_none());
    }

    #[test]
    fn hardware_lands_typed_secret_in_pin_slot() {
        let mapped =
            security_map_wizard_choice("hardware".into(), true, false, Some("4321".into()))
                .expect("hardware");
        assert!(mapped.master_password.is_none());
        assert!(mapped.short_password.is_none());
        assert_eq!(mapped.pin.as_deref(), Some("4321"));
    }

    #[test]
    fn parse_wizard_tier_accepts_every_known_wire_name() {
        for n in ["plaintext", "keychain", "hardware", "paranoid"] {
            assert!(parse_wizard_tier(n).is_ok(), "{n} must parse");
        }
        assert!(parse_wizard_tier("ghost").is_err());
    }
}
