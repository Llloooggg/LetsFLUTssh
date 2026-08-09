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
        // ColdDiskTheft: protects against a stolen offline drive.
        // Any tier above Plaintext encrypts the credential store
        // at rest, so the wrapped key alone is not enough to read
        // the credentials without the wrapping key.
        (
            SecurityThreat::ColdDiskTheft,
            yes(model.tier != ThreatTier::Plaintext),
        ),
        // KeyringFileTheft: protects against an attacker who reads
        // the OS keychain file directly (T1 stores the wrapping key
        // there in plaintext — lost to a disk attacker). T2 seals
        // the blob with the hardware chip (chip refuses export);
        // T1 + master password adds a user-secret KDF on top so
        // the keychain blob alone is no longer the whole secret.
        (
            SecurityThreat::KeyringFileTheft,
            yes(model.tier == ThreatTier::Hardware
                || model.tier == ThreatTier::Paranoid
                || (model.tier == ThreatTier::Keychain && model.password)),
        ),
        // OfflineBruteForce: protects against an attacker who has
        // the full encrypted blob and grinds candidate passwords
        // offline. Only a user-known secret (master password on
        // T1/T2, or Paranoid's required passphrase) introduces an
        // Argon2id cost factor an offline attacker cannot skip.
        (SecurityThreat::OfflineBruteForce, yes(has_user_secret)),
        // BystanderUnlockedMachine: protects against someone with
        // physical access to an unlocked session who tries to use
        // the app. Same condition as offline brute-force — the
        // user-known secret is required at unlock time, so an OS
        // session alone is not enough to read credentials.
        (
            SecurityThreat::BystanderUnlockedMachine,
            yes(has_user_secret),
        ),
        // LiveRamForensicsLocked: protects against RAM-scraping a
        // locked-screen machine. Requires the wrapping key to be
        // held by the chip (T2) plus a user secret on top so the
        // unlocked-but-screen-locked state still demands re-auth.
        // Paranoid achieves the same via its mandatory passphrase.
        (
            SecurityThreat::LiveRamForensicsLocked,
            yes(model.tier == ThreatTier::Paranoid
                || (model.tier == ThreatTier::Hardware && model.password)),
        ),
        // OsKernelOrKeychainBreach: protects against compromise of
        // the OS keychain service or kernel itself. Same gating as
        // RAM forensics — the credential decrypt must hinge on a
        // secret the OS keychain never sees in cleartext, which
        // only T2 + password or Paranoid achieves.
        (
            SecurityThreat::OsKernelOrKeychainBreach,
            yes(model.tier == ThreatTier::Paranoid
                || (model.tier == ThreatTier::Hardware && model.password)),
        ),
    ]
}
#[cfg(test)]
#[path = "../tests/unit/threat_eval.rs"]
mod tests;
