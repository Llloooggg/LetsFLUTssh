//! FRB adapter for `lfs_core::threat_eval`. Synchronous —
//! pure-function truth table over a tiny enum input.

#[derive(Debug, Clone, Copy)]
pub enum DbThreatTier {
    Plaintext,
    Keychain,
    Hardware,
    Paranoid,
}

impl From<DbThreatTier> for lfs_core::threat_eval::ThreatTier {
    fn from(t: DbThreatTier) -> Self {
        match t {
            DbThreatTier::Plaintext => lfs_core::threat_eval::ThreatTier::Plaintext,
            DbThreatTier::Keychain => lfs_core::threat_eval::ThreatTier::Keychain,
            DbThreatTier::Hardware => lfs_core::threat_eval::ThreatTier::Hardware,
            DbThreatTier::Paranoid => lfs_core::threat_eval::ThreatTier::Paranoid,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum DbSecurityThreat {
    ColdDiskTheft,
    KeyringFileTheft,
    OfflineBruteForce,
    BystanderUnlockedMachine,
    LiveRamForensicsLocked,
    OsKernelOrKeychainBreach,
}

impl From<lfs_core::threat_eval::SecurityThreat> for DbSecurityThreat {
    fn from(t: lfs_core::threat_eval::SecurityThreat) -> Self {
        use lfs_core::threat_eval::SecurityThreat as S;
        match t {
            S::ColdDiskTheft => DbSecurityThreat::ColdDiskTheft,
            S::KeyringFileTheft => DbSecurityThreat::KeyringFileTheft,
            S::OfflineBruteForce => DbSecurityThreat::OfflineBruteForce,
            S::BystanderUnlockedMachine => DbSecurityThreat::BystanderUnlockedMachine,
            S::LiveRamForensicsLocked => DbSecurityThreat::LiveRamForensicsLocked,
            S::OsKernelOrKeychainBreach => DbSecurityThreat::OsKernelOrKeychainBreach,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum DbThreatStatus {
    Protects,
    DoesNotProtect,
}

impl From<lfs_core::threat_eval::ThreatStatus> for DbThreatStatus {
    fn from(s: lfs_core::threat_eval::ThreatStatus) -> Self {
        match s {
            lfs_core::threat_eval::ThreatStatus::Protects => DbThreatStatus::Protects,
            lfs_core::threat_eval::ThreatStatus::DoesNotProtect => DbThreatStatus::DoesNotProtect,
        }
    }
}

#[derive(Debug, Clone)]
pub struct DbThreatRow {
    pub threat: DbSecurityThreat,
    pub status: DbThreatStatus,
}

#[flutter_rust_bridge::frb(sync)]
pub fn threat_evaluate(tier: DbThreatTier, password: bool, biometric: bool) -> Vec<DbThreatRow> {
    let model = lfs_core::threat_eval::ThreatModel {
        tier: tier.into(),
        password,
        biometric,
    };
    lfs_core::threat_eval::evaluate(model)
        .into_iter()
        .map(|(t, s)| DbThreatRow {
            threat: t.into(),
            status: s.into(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn protects(rows: &[DbThreatRow], threat: DbSecurityThreat) -> bool {
        rows.iter().any(|r| {
            std::mem::discriminant(&r.threat) == std::mem::discriminant(&threat)
                && matches!(r.status, DbThreatStatus::Protects)
        })
    }

    #[test]
    fn plaintext_tier_does_not_protect_against_disk_theft() {
        // Plaintext mode is the no-encryption baseline; the table
        // says it protects against nothing on the cold-disk axis.
        let rows = threat_evaluate(DbThreatTier::Plaintext, false, false);
        assert!(!protects(&rows, DbSecurityThreat::ColdDiskTheft));
    }

    #[test]
    fn paranoid_protects_against_offline_brute_force() {
        // Argon2id master-password mode: the strongest tier
        // protects against the offline-brute-force axis even
        // without biometric.
        let rows = threat_evaluate(DbThreatTier::Paranoid, true, false);
        assert!(protects(&rows, DbSecurityThreat::OfflineBruteForce));
    }

    #[test]
    fn keychain_protects_against_cold_disk_theft() {
        // OS-keychain tier wraps the DB key in
        // `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (or
        // libsecret on Linux); a stolen disk without OS auth can't
        // recover it.
        let rows = threat_evaluate(DbThreatTier::Keychain, false, false);
        assert!(protects(&rows, DbSecurityThreat::ColdDiskTheft));
    }

    #[test]
    fn evaluate_returns_a_row_for_every_security_threat() {
        // The truth table covers every threat axis; the row
        // count must match the enum cardinality so the UI's
        // per-threat tile list never silently drops a row.
        let rows = threat_evaluate(DbThreatTier::Plaintext, false, false);
        // 6 SecurityThreat variants — see DbSecurityThreat above.
        assert_eq!(rows.len(), 6);
    }
}
