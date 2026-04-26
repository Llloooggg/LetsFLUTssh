//! Canonical security threat vocabulary mirrored from the Dart
//! `core/security/threat_vocabulary.dart`.
//!
//! Every threat has a single fixed identifier the UI uses to
//! drive its l10n keys (`threatColdDiskTheft`,
//! `threatColdDiskTheftDescription`, ...). The truth table in
//! [`evaluate`] is the single source of truth for which
//! tier/modifier combos defeat which threats.

/// Discrete threat categories the app reasons about. Order is
/// user-facing — every UI surface renders threats in this exact
/// sequence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SecurityThreat {
    ColdDiskTheft,
    KeyringFileTheft,
    OfflineBruteForce,
    BystanderUnlockedMachine,
    LiveRamForensicsLocked,
    OsKernelOrKeychainBreach,
}

/// Whether a (tier, modifier) combination defeats the threat.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThreatStatus {
    /// ✓ — defeats the threat.
    Protects,
    /// ✗ — threat is not defended against.
    DoesNotProtect,
}

/// Normalised tier identifier used by the evaluator.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ThreatTier {
    Plaintext,
    Keychain,
    Hardware,
    Paranoid,
}

/// Input to [`evaluate`]. `password` covers the typed-secret
/// modifier (and biometric is structurally a shortcut for it,
/// hence `password=true` regardless of how the user authed).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThreatModel {
    pub tier: ThreatTier,
    pub password: bool,
    pub biometric: bool,
}

impl ThreatModel {
    pub fn new(tier: ThreatTier, password: bool, biometric: bool) -> Self {
        Self {
            tier,
            password,
            biometric,
        }
    }
}

/// Evaluate the canonical truth table from `ARCHITECTURE.md §3.6`.
///
/// | Threat                                | T0 | T1 | T1+pw | T2 | T2+pw | Paranoid |
/// |---------------------------------------|----|----|-------|----|-------|----------|
/// | Cold disk theft                       | ✗  | ✓  | ✓     | ✓  | ✓     | ✓        |
/// | Keyring / keychain file exfiltration  | ✗  | ✗  | ✓     | ✓  | ✓     | ✓        |
/// | Offline brute force                   | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
/// | Bystander at unlocked machine         | ✗  | ✗  | ✓     | ✗  | ✓     | ✓        |
/// | Live RAM forensics on locked machine  | ✗  | ✗  | ✗     | ✗  | ✓     | ✓        |
/// | OS kernel / keychain breach           | ✗  | ✗  | ✗     | ✗  | ✓     | ✓        |
///
/// Pure function — no I/O, no platform probes.
pub fn evaluate(model: ThreatModel) -> std::collections::HashMap<SecurityThreat, ThreatStatus> {
    let has_user_secret = model.tier == ThreatTier::Paranoid
        || (model.password
            && (model.tier == ThreatTier::Keychain || model.tier == ThreatTier::Hardware));

    let yes = |c: bool| {
        if c {
            ThreatStatus::Protects
        } else {
            ThreatStatus::DoesNotProtect
        }
    };

    let mut out = std::collections::HashMap::new();
    out.insert(
        SecurityThreat::ColdDiskTheft,
        yes(model.tier != ThreatTier::Plaintext),
    );
    out.insert(
        SecurityThreat::KeyringFileTheft,
        yes(model.tier == ThreatTier::Hardware
            || model.tier == ThreatTier::Paranoid
            || (model.tier == ThreatTier::Keychain && model.password)),
    );
    out.insert(SecurityThreat::OfflineBruteForce, yes(has_user_secret));
    out.insert(
        SecurityThreat::BystanderUnlockedMachine,
        yes(has_user_secret),
    );
    out.insert(
        SecurityThreat::LiveRamForensicsLocked,
        yes(model.tier == ThreatTier::Paranoid
            || (model.tier == ThreatTier::Hardware && model.password)),
    );
    out.insert(
        SecurityThreat::OsKernelOrKeychainBreach,
        yes(model.tier == ThreatTier::Paranoid
            || (model.tier == ThreatTier::Hardware && model.password)),
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use SecurityThreat::*;
    use ThreatStatus::*;
    use ThreatTier::*;

    fn case(tier: ThreatTier, password: bool) -> std::collections::HashMap<SecurityThreat, ThreatStatus> {
        evaluate(ThreatModel::new(tier, password, false))
    }

    #[test]
    fn t0_plaintext_protects_nothing() {
        let r = case(Plaintext, false);
        for t in [
            ColdDiskTheft,
            KeyringFileTheft,
            OfflineBruteForce,
            BystanderUnlockedMachine,
            LiveRamForensicsLocked,
            OsKernelOrKeychainBreach,
        ] {
            assert_eq!(r[&t], DoesNotProtect, "T0 should not protect {t:?}");
        }
    }

    #[test]
    fn t1_no_password() {
        let r = case(Keychain, false);
        assert_eq!(r[&ColdDiskTheft], Protects);
        assert_eq!(r[&KeyringFileTheft], DoesNotProtect);
        assert_eq!(r[&OfflineBruteForce], DoesNotProtect);
        assert_eq!(r[&BystanderUnlockedMachine], DoesNotProtect);
        assert_eq!(r[&LiveRamForensicsLocked], DoesNotProtect);
        assert_eq!(r[&OsKernelOrKeychainBreach], DoesNotProtect);
    }

    #[test]
    fn t1_with_password() {
        let r = case(Keychain, true);
        assert_eq!(r[&ColdDiskTheft], Protects);
        assert_eq!(r[&KeyringFileTheft], Protects);
        assert_eq!(r[&OfflineBruteForce], Protects);
        assert_eq!(r[&BystanderUnlockedMachine], Protects);
        assert_eq!(r[&LiveRamForensicsLocked], DoesNotProtect);
        assert_eq!(r[&OsKernelOrKeychainBreach], DoesNotProtect);
    }

    #[test]
    fn t2_no_password() {
        let r = case(Hardware, false);
        assert_eq!(r[&ColdDiskTheft], Protects);
        assert_eq!(r[&KeyringFileTheft], Protects);
        assert_eq!(r[&OfflineBruteForce], DoesNotProtect);
        assert_eq!(r[&BystanderUnlockedMachine], DoesNotProtect);
        assert_eq!(r[&LiveRamForensicsLocked], DoesNotProtect);
        assert_eq!(r[&OsKernelOrKeychainBreach], DoesNotProtect);
    }

    #[test]
    fn t2_with_password() {
        let r = case(Hardware, true);
        assert_eq!(r[&ColdDiskTheft], Protects);
        assert_eq!(r[&KeyringFileTheft], Protects);
        assert_eq!(r[&OfflineBruteForce], Protects);
        assert_eq!(r[&BystanderUnlockedMachine], Protects);
        assert_eq!(r[&LiveRamForensicsLocked], Protects);
        assert_eq!(r[&OsKernelOrKeychainBreach], Protects);
    }

    #[test]
    fn paranoid_protects_everything() {
        let r = case(Paranoid, false);
        for t in [
            ColdDiskTheft,
            KeyringFileTheft,
            OfflineBruteForce,
            BystanderUnlockedMachine,
            LiveRamForensicsLocked,
            OsKernelOrKeychainBreach,
        ] {
            assert_eq!(r[&t], Protects, "Paranoid should protect {t:?}");
        }
    }

    #[test]
    fn biometric_only_promotes_to_password_equivalent() {
        // biometric flag is informational — the security
        // properties come from the password column in the table.
        // Set it without password and confirm offlineBruteForce
        // stays ✗ (since password is false).
        let r = evaluate(ThreatModel::new(Hardware, false, true));
        assert_eq!(r[&OfflineBruteForce], DoesNotProtect);
    }
}
