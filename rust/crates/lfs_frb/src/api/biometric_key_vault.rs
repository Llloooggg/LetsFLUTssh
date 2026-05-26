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
//!
//! All ops operate on the app-support directory pinned at
//! `config_store_init` (`master_password::try_pinned_support_dir`),
//! so the Dart caller no longer threads a path in.

#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_tpm_ready() -> bool {
    lfs_core::security::biometric_key_vault::linux::is_tpm_ready()
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_tpm_ready() -> bool {
    false
}

#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_is_stored() -> bool {
    let Ok(dir) = lfs_core::security::master_password::try_pinned_support_dir() else {
        return false;
    };
    lfs_core::security::biometric_key_vault::linux::is_stored(&dir.to_string_lossy())
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_is_stored() -> bool {
    false
}

/// Seal the SecretStore entry under `secret_id` into
/// `biometric_vault.tpm` (under the pinned support dir) keyed by the
/// current fprintd enrolment hash. Bytes never cross the FRB boundary.
#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_store_from_secret(secret_id: String) -> Result<(), String> {
    let dir = lfs_core::security::master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    let dir_str = dir.to_string_lossy();
    lfs_core::security::biometric_key_vault::linux::store_from_secret(&dir_str, &secret_id)
        .await
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_store_from_secret(_secret_id: String) -> Result<(), String> {
    Err("not supported on this platform".into())
}

/// Unseal `biometric_vault.tpm` (under the pinned support dir) into
/// the SecretStore under `secret_id`. Returns `true` when bytes were
/// staged, `false` for "no vault on disk / fprintd unavailable / wrong
/// auth (re-enrolment)" — the caller routes those cases back to
/// the master-password dialog.
#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_read_to_secret(secret_id: String) -> Result<bool, String> {
    let dir = lfs_core::security::master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    let dir_str = dir.to_string_lossy();
    lfs_core::security::biometric_key_vault::linux::read_to_secret(&dir_str, &secret_id)
        .await
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_read_to_secret(_secret_id: String) -> Result<bool, String> {
    Ok(false)
}

#[cfg(target_os = "linux")]
pub async fn biometric_vault_linux_clear() -> Result<(), String> {
    let dir = lfs_core::security::master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    lfs_core::security::biometric_key_vault::linux::clear(&dir.to_string_lossy())
        .map_err(|e| crate::api::frb_err::wire_str(crate::api::frb_err::kind::VAULT, &e))
}

#[cfg(not(target_os = "linux"))]
pub async fn biometric_vault_linux_clear() -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn tpm_ready_returns_a_bool_without_panic() {
        // On Linux the call probes tpm2-tools subprocess +
        // `/dev/tpm*`; on every other host the documented contract
        // is `false`. Both shapes are valid; pin the no-panic
        // contract.
        let _ = biometric_vault_linux_tpm_ready().await;
    }

    #[tokio::test]
    async fn is_stored_returns_false_without_a_vault() {
        // No vault file under the (unpinned or empty) support dir must
        // surface as `false` rather than panic — the cold-start probe
        // runs before any vault has been sealed.
        assert!(!biometric_vault_linux_is_stored().await);
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_store_from_secret_returns_err() {
        // Pin the cross-platform stub — Dart caller short-circuits
        // before reaching here, but the shim surfaces a clean error
        // for misrouted calls.
        let res = biometric_vault_linux_store_from_secret("ghost-id".into()).await;
        assert!(res.is_err());
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_read_to_secret_returns_ok_false() {
        // The non-Linux fallback returns `Ok(false)` (no vault on
        // this host) rather than `Err` — the Dart caller treats
        // `false` as "fall through to master-password".
        let res = biometric_vault_linux_read_to_secret("ghost-id".into()).await;
        assert!(matches!(res, Ok(false)));
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_clear_is_no_op_ok() {
        // Cross-platform clear collapses to `Ok(())` so wipe-all
        // routes that target this don't fail per platform.
        let res = biometric_vault_linux_clear().await;
        assert!(res.is_ok());
    }

    #[cfg(not(target_os = "linux"))]
    #[tokio::test]
    async fn non_linux_tpm_ready_returns_false() {
        assert!(!biometric_vault_linux_tpm_ready().await);
    }
}
