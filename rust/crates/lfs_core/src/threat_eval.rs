//! Pure-function truth table for the security tier × modifier
//! threat model.
//!
//! Mirrors `lib/core/security/threat_vocabulary.dart::evaluate`
//! row-for-row. Every UI surface (per-tier popups, comparison
//! table, wizard hints) reads the same map this returns; keeping
//! the canonical truth table Rust-side stops it diverging
//! between frontends.
//!
//! See `docs/ARCHITECTURE.md §3.6` for the rationale behind each
//! row's ✓ / ✗ — this module does not duplicate that prose.

/// Normalised tier identifier independent of the full
/// `SecurityConfig` shape so the threat model can be reasoned
/// about for hypothetical combinations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThreatTier {
    Plaintext,
    Keychain,
    Hardware,
    Paranoid,
}

/// Input to [`evaluate`]. Bank-style modifiers — `biometric`
/// counts as `password` for truth-table purposes; the
/// distinction lives only in UI hints.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThreatModel {
    pub tier: ThreatTier,
    pub password: bool,
    pub biometric: bool,
}

/// One row in the threat truth table.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecurityThreat {
    ColdDiskTheft,
    KeyringFileTheft,
    OfflineBruteForce,
    BystanderUnlockedMachine,
    LiveRamForensicsLocked,
    OsKernelOrKeychainBreach,
}

/// Binary per-threat status. No "not applicable" marker — every
/// threat has a yes-or-no answer on every tier.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThreatStatus {
    Protects,
    DoesNotProtect,
}

/// Encode the canonical truth table. Returns the rows in the
/// same order callers iterate them — keeping order stable
/// across the FRB boundary lets the UI render side-by-side
/// comparison cells without re-sorting.
pub fn evaluate(model: ThreatModel) -> Vec<(SecurityThreat, ThreatStatus)> {
    let has_user_secret = model.tier == ThreatTier::Paranoid
        || (model.password
            && (model.tier == ThreatTier::Keychain || model.tier == ThreatTier::Hardware));

    fn yes(condition: bool) -> ThreatStatus {
        if condition {
            ThreatStatus::Protects
        } else {
            ThreatStatus::DoesNotProtect
        }
    }

    vec![
        (
            SecurityThreat::ColdDiskTheft,
            yes(model.tier != ThreatTier::Plaintext),
        ),
        (
            SecurityThreat::KeyringFileTheft,
            yes(model.tier == ThreatTier::Hardware
                || model.tier == ThreatTier::Paranoid
                || (model.tier == ThreatTier::Keychain && model.password)),
        ),
        (SecurityThreat::OfflineBruteForce, yes(has_user_secret)),
        (
            SecurityThreat::BystanderUnlockedMachine,
            yes(has_user_secret),
        ),
        (
            SecurityThreat::LiveRamForensicsLocked,
            yes(model.tier == ThreatTier::Paranoid
                || (model.tier == ThreatTier::Hardware && model.password)),
        ),
        (
            SecurityThreat::OsKernelOrKeychainBreach,
            yes(model.tier == ThreatTier::Paranoid
                || (model.tier == ThreatTier::Hardware && model.password)),
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup(rows: &[(SecurityThreat, ThreatStatus)], threat: SecurityThreat) -> ThreatStatus {
        rows.iter()
            .find(|(t, _)| *t == threat)
            .map(|(_, s)| *s)
            .expect("threat row present")
    }

    fn model(tier: ThreatTier, password: bool) -> ThreatModel {
        ThreatModel {
            tier,
            password,
            biometric: false,
        }
    }

    #[test]
    fn plaintext_tier_protects_nothing() {
        let rows = evaluate(model(ThreatTier::Plaintext, false));
        for (_, s) in &rows {
            assert_eq!(*s, ThreatStatus::DoesNotProtect);
        }
    }

    #[test]
    fn keychain_no_password_only_cold_disk() {
        let rows = evaluate(model(ThreatTier::Keychain, false));
        assert_eq!(
            lookup(&rows, SecurityThreat::ColdDiskTheft),
            ThreatStatus::Protects
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::KeyringFileTheft),
            ThreatStatus::DoesNotProtect
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::OfflineBruteForce),
            ThreatStatus::DoesNotProtect
        );
    }

    #[test]
    fn keychain_with_password_protects_keyring_and_brute_force() {
        let rows = evaluate(model(ThreatTier::Keychain, true));
        assert_eq!(
            lookup(&rows, SecurityThreat::ColdDiskTheft),
            ThreatStatus::Protects
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::KeyringFileTheft),
            ThreatStatus::Protects
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::OfflineBruteForce),
            ThreatStatus::Protects
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::BystanderUnlockedMachine),
            ThreatStatus::Protects
        );
        // Live RAM forensics + kernel breach still ✗ on T1+pw.
        assert_eq!(
            lookup(&rows, SecurityThreat::LiveRamForensicsLocked),
            ThreatStatus::DoesNotProtect
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::OsKernelOrKeychainBreach),
            ThreatStatus::DoesNotProtect
        );
    }

    #[test]
    fn hardware_no_password_protects_keyring_not_brute_force() {
        let rows = evaluate(model(ThreatTier::Hardware, false));
        assert_eq!(
            lookup(&rows, SecurityThreat::KeyringFileTheft),
            ThreatStatus::Protects
        );
        assert_eq!(
            lookup(&rows, SecurityThreat::OfflineBruteForce),
            ThreatStatus::DoesNotProtect
        );
    }

    #[test]
    fn hardware_with_password_protects_everything_except_nothing() {
        let rows = evaluate(model(ThreatTier::Hardware, true));
        for (_, s) in &rows {
            assert_eq!(*s, ThreatStatus::Protects);
        }
    }

    #[test]
    fn paranoid_protects_everything_regardless_of_password_flag() {
        for password in [false, true] {
            let rows = evaluate(model(ThreatTier::Paranoid, password));
            for (_, s) in &rows {
                assert_eq!(*s, ThreatStatus::Protects);
            }
        }
    }

    #[test]
    fn rows_returned_in_canonical_order() {
        let rows = evaluate(model(ThreatTier::Plaintext, false));
        let order: Vec<SecurityThreat> = rows.iter().map(|(t, _)| *t).collect();
        assert_eq!(
            order,
            vec![
                SecurityThreat::ColdDiskTheft,
                SecurityThreat::KeyringFileTheft,
                SecurityThreat::OfflineBruteForce,
                SecurityThreat::BystanderUnlockedMachine,
                SecurityThreat::LiveRamForensicsLocked,
                SecurityThreat::OsKernelOrKeychainBreach,
            ]
        );
    }
}
