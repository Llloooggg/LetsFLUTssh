/// Unit tests extracted from threat_eval.rs
/// Declared via `#[path] mod tests;` in the source file.
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
