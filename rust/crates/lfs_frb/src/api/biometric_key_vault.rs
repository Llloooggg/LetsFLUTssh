//! FRB adapter for `lfs_core::security::biometric_key_vault`.
//!
//! Linux-only Rust orchestrator — Apple / Android / Windows reach
//! the biometric vault entirely through the unified
//! `secure_storage_*_biometric_from_secret` / `..._to_secret`
//! family in `lfs_frb::api::secure_key_storage`, which routes to
//! `lfs_os_security::secure_key_storage` (`SecAccessControl`
//! biometryCurrentSet on Apple, AndroidKeyStore wrap key on
//! Android, Credential Manager + Hello on Windows). The
//! Dart-side `BiometricKeyVault` cfg-dispatches `Platform.isLinux`
//! to the shims here; every other platform takes the existing
//! `secure_storage` route and the bytes never cross the FRB
//! boundary in either direction.
//!
//! Linux-fallback (no TPM on this host) goes to the same
//! `secure_storage_*_biometric_from_secret` family — libsecret-
//! backed via the `secret-service` crate inside
//! `lfs_os_security::secure_key_storage`. The Dart wrapper picks
//! the route via [`biometric_vault_linux_tpm_ready`].

#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_tpm_ready() -> bool {
    lfs_core::security::biometric_key_vault::linux::is_tpm_ready()
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_tpm_ready() -> bool {
    false
}

#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_is_stored(support_dir: String) -> bool {
    lfs_core::security::biometric_key_vault::linux::is_stored(&support_dir)
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_is_stored(_support_dir: String) -> bool {
    false
}

/// Seal the SecretStore entry under `secret_id` into
/// `support_dir/biometric_vault.tpm` keyed by the current fprintd
/// enrolment hash. Bytes never cross the FRB boundary.
#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_store_from_secret(
    support_dir: String,
    secret_id: String,
) -> Result<(), String> {
    lfs_core::security::biometric_key_vault::linux::store_from_secret(&support_dir, &secret_id)
        .await
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_store_from_secret(
    _support_dir: String,
    _secret_id: String,
) -> Result<(), String> {
    Err("not supported on this platform".into())
}

/// Unseal `support_dir/biometric_vault.tpm` into the SecretStore
/// under `secret_id`. Returns `true` when bytes were staged,
/// `false` for "no vault on disk / fprintd unavailable / wrong
/// auth (re-enrolment)" — the caller routes those cases back to
/// the master-password dialog.
#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_read_to_secret(
    support_dir: String,
    secret_id: String,
) -> Result<bool, String> {
    lfs_core::security::biometric_key_vault::linux::read_to_secret(&support_dir, &secret_id)
        .await
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_read_to_secret(
    _support_dir: String,
    _secret_id: String,
) -> Result<bool, String> {
    Ok(false)
}

#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_clear(support_dir: String) -> Result<(), String> {
    lfs_core::security::biometric_key_vault::linux::clear(&support_dir)
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_clear(_support_dir: String) -> Result<(), String> {
    Ok(())
}
