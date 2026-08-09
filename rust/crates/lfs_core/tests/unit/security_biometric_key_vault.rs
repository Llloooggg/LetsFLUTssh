//! Unit tests extracted from security/biometric_key_vault
//!
//! Declared via `#[path] mod tests;` in the source file.

use super::linux::*;

/// Construct a fresh tempdir for each test — the orchestrator
/// writes `biometric_vault.tpm` into the support_dir we hand
/// in, and isolation between tests means a parallel `cargo
/// test` run never sees a sibling test's seal blob.
fn tempdir() -> tempfile::TempDir {
    tempfile::tempdir().expect("tempdir")
}

#[test]
fn is_stored_returns_false_for_fresh_support_dir() {
    let dir = tempdir();
    assert!(!is_stored(dir.path().to_str().unwrap()));
}

#[test]
fn clear_is_a_noop_when_nothing_is_stored() {
    let dir = tempdir();
    // No vault file present — clear should not error.
    clear(dir.path().to_str().unwrap()).expect("clear noop");
}

#[tokio::test]
async fn store_from_secret_errors_when_tpm_unavailable() {
    // Most CI hosts have no TPM2 device + tpm2-tools; the
    // orchestrator must surface `TpmUnavailable` rather than
    // panicking or silently writing a corrupt blob. Hosts that
    // *do* have a TPM exercise the success path through the
    // Dart smoke + the per-platform validation matrix.
    if is_tpm_ready() {
        return;
    }
    let dir = tempdir();
    // Stage a fake key in the SecretStore so the orchestrator
    // gets past the SecretStore lookup before hitting the TPM.
    let _ = crate::app::init();
    let app = crate::app::instance();
    app.secrets.put("test.bio_vault.unavailable", &[1u8; 32]);
    let result =
        store_from_secret(dir.path().to_str().unwrap(), "test.bio_vault.unavailable").await;
    assert!(matches!(result, Err(LinuxBioVaultError::TpmUnavailable(_))));
    app.secrets.drop_id("test.bio_vault.unavailable");
}

#[tokio::test]
async fn read_to_secret_returns_false_when_vault_file_absent() {
    let dir = tempdir();
    let result = read_to_secret(dir.path().to_str().unwrap(), "test.bio_vault.absent").await;
    assert!(!result.unwrap());
}
