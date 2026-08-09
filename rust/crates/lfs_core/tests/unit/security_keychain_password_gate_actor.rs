/// Unit tests extracted from security/keychain_password_gate_actor.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::security::keychain_password_gate::{
    compute_gate_hmac, encode_disk_blob, random_salt_and_pepper,
};
use tempfile::TempDir;

/// Set up a fresh T1+pw gate config on disk + return the pepper
/// the test stand-in would inject. The actor surfaces the pepper
/// through the bus rather than a registry; this helper covers
/// the disk-state setup only.
fn setup_gate(dir: &Path, password: &[u8]) -> Vec<u8> {
    let (salt, pepper) = random_salt_and_pepper();
    let hmac = compute_gate_hmac(&pepper, &salt, password);
    let blob = encode_disk_blob(&salt, &hmac);
    std::fs::write(dir.join(HASH_FILE_NAME), blob).unwrap();
    pepper
}

#[tokio::test]
async fn verify_returns_false_when_hash_file_missing() {
    let dir = TempDir::new().unwrap();
    let result = verify_password(dir.path(), b"anything").await.unwrap();
    assert!(!result);
}

#[tokio::test]
async fn verify_returns_false_for_corrupt_blob() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join(HASH_FILE_NAME), b"not-json").unwrap();
    let result = verify_password(dir.path(), b"anything").await.unwrap();
    assert!(!result);
}

/// Backend-pepper-missing path: a fresh hash file is on disk
/// but `lfs_os_security::secure_key_storage::read(PEPPER_KEY)`
/// returns `Ok(None)`. Result must collapse to `Ok(false)` so
/// the rate limiter records the attempt; the function must not
/// surface the keychain miss as `Err`.
///
/// Test runs without bootstrapping a keychain — the call returns
/// `Ok(None)` in the libsecret CI fallback and on hosts with no
/// matching alias. Either way the asserted invariant holds.
#[tokio::test]
async fn verify_returns_false_when_pepper_absent() {
    let dir = TempDir::new().unwrap();
    let _pepper = setup_gate(dir.path(), b"hunter2");
    let result = verify_password(dir.path(), b"hunter2").await.unwrap();
    assert!(!result);
}

/// `is_configured` short-circuits to `false` on a fresh dir
/// (no hash file).
#[tokio::test]
async fn is_configured_false_when_no_hash_file() {
    let dir = TempDir::new().unwrap();
    let result = is_configured(dir.path()).await.unwrap();
    assert!(!result);
}

/// `build_persisted_rate_limiter` collapses an unconfigured
/// gate to `Ok(None)` so the Dart caller treats it as "no
/// rate limiter for this install" without needing to inspect
/// errors.
#[tokio::test]
async fn build_persisted_rate_limiter_returns_none_when_gate_absent() {
    let dir = TempDir::new().unwrap();
    let res = build_persisted_rate_limiter(dir.path()).await.unwrap();
    assert!(res.is_none());
}

/// On a configured gate the function mints a fresh id +
/// registers a slot in the `persisted_rate_limit_actor` so
/// the FRB status ops resolve against the registered limiter.
/// The HMAC bytes stay Rust-side — the test only observes the
/// id round-trip + a zero-baseline status snapshot.
#[tokio::test]
async fn build_persisted_rate_limiter_registers_slot_for_configured_gate() {
    let dir = TempDir::new().unwrap();
    let _pepper = setup_gate(dir.path(), b"hunter2");
    let id = build_persisted_rate_limiter(dir.path())
        .await
        .unwrap()
        .expect("configured gate yields an id");
    let snap = rl_actor::instance().status(&id);
    assert_eq!(snap.failure_count, 0);
    assert_eq!(snap.cooldown_remaining_ms, 0);
    rl_actor::instance().clear(&id);
}
