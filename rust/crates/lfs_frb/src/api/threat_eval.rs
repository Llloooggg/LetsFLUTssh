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
