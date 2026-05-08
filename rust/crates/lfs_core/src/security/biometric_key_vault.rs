//! Biometric-tier vault — Linux orchestrator.
//!
//! Apple / Android / Windows route the biometric vault entirely
//! through `lfs_os_security::secure_key_storage::*_biometric` (SE
//! `kSecAccessControlBiometryCurrentSet`, AndroidKeyStore wrap key
//! with `setUserAuthenticationRequired`, Windows Credential Manager
//! gated by a Hello prompt). The DB key never crosses the FRB
//! boundary on those targets — `secure_storage_*_biometric_from_secret`
//! / `..._to_secret` shuttle bytes via the process-singleton
//! [`crate::secrets::SecretStore`].
//!
//! Linux had two leaks until this module landed:
//! 1. `BiometricKeyVault._linuxSeal` / `_linuxUnseal` opened the
//!    seal file Dart-side and pulled the unsealed DB key onto the
//!    Dart heap before staging it into the SecretStore.
//! 2. `FprintdClient.getEnrolmentHash` ran the `fprintd` D-Bus walk
//!    Dart-side via the pub.dev `dbus` package, then handed the
//!    32-byte digest back into the Rust `tpm::seal` call.
//!
//! Both now live here. The orchestrator pulls the DB-key bytes from
//! the SecretStore under the caller-supplied `secret_id`, derives
//! the fprintd enrolment hash via [`crate::platform::linux::fprintd`],
//! seals through [`lfs_os_security::linux::tpm`], and writes the
//! resulting blob to `support_dir/biometric_vault.tpm` atomically.
//! On read it does the reverse and stages the unsealed bytes into
//! the SecretStore under the caller-supplied target id — Dart sees
//! a boolean, not the bytes.
//!
//! The libsecret fallback (no TPM on this Linux box) is owned by
//! `lfs_os_security::secure_key_storage` and does not enter this
//! module — callers detect "TPM unavailable" via [`is_tpm_ready`]
//! and route to `secure_storage_write_biometric_from_secret` /
//! `..._read_biometric_to_secret` instead.

#[cfg(target_os = "linux")]
pub mod linux {
    use std::path::{Path, PathBuf};

    use crate::path::write_bytes_atomic;
    use crate::platform::linux::fprintd;
    use lfs_os_security::linux::tpm;

    /// Filename inside `support_dir` carrying the TPM-sealed blob.
    /// Matches the wipe-registry entry in
    /// `lfs_core::security::wipe::MANAGED_FILES`.
    const VAULT_FILE: &str = "biometric_vault.tpm";

    /// Errors the Linux biometric-vault orchestrator surfaces.
    /// Caller-visible failure mode is binary (`Ok(true)` =
    /// "vault yielded a key", `Ok(false)` = "no key on this path,
    /// fall back to the master-password dialog"); the typed error
    /// only fires for I/O / corruption that the caller logs.
    #[derive(Debug)]
    pub enum LinuxBioVaultError {
        /// `tpm2-tools` not reachable, `/dev/tpmrm0` missing, or the
        /// TPM rejected the seal call. Caller routes to the
        /// libsecret fallback.
        TpmUnavailable(String),
        /// fprintd service is not registered, has no default device,
        /// or no fingers are enrolled. Caller routes the user to
        /// `fprintd-enroll` / Settings.
        FprintdUnavailable,
        /// `tpm2_create` / `tpm2_unseal` ran but returned an error.
        Backend(String),
        /// File-IO surface — read / write / atomic-rename failed.
        Io(String),
        /// The caller-supplied SecretStore id was empty when a read
        /// was attempted, or the put-side id was missing on store.
        SecretStore(String),
    }

    impl std::fmt::Display for LinuxBioVaultError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::TpmUnavailable(s) => write!(f, "tpm unavailable: {s}"),
                Self::FprintdUnavailable => write!(f, "fprintd unavailable / no enrolled fingers"),
                Self::Backend(s) => write!(f, "tpm backend: {s}"),
                Self::Io(s) => write!(f, "io: {s}"),
                Self::SecretStore(s) => write!(f, "secret store: {s}"),
            }
        }
    }

    impl std::error::Error for LinuxBioVaultError {}

    fn vault_path(support_dir: &str) -> PathBuf {
        Path::new(support_dir).join(VAULT_FILE)
    }

    /// True when both `tpm2-tools` + `/dev/tpmrm0` are reachable.
    /// Caller uses this to decide between sealing through the TPM
    /// (this module) or falling back to the libsecret-backed
    /// `secure_storage_*_biometric` family.
    #[must_use]
    pub fn is_tpm_ready() -> bool {
        matches!(
            tpm::probe(&tpm::TpmConfig::default()),
            tpm::TpmProbeResult::Available
        )
    }

    /// True when `support_dir/biometric_vault.tpm` exists. Pure
    /// path-stat; does not invoke the TPM or fprintd.
    #[must_use]
    pub fn is_stored(support_dir: &str) -> bool {
        vault_path(support_dir).exists()
    }

    /// Pull the DB-key bytes from the process-singleton
    /// [`crate::secrets::SecretStore`] under `secret_id`, derive
    /// the fprintd enrolment hash, seal under TPM2 with that hash
    /// as the auth value, and write the sealed blob to
    /// `support_dir/biometric_vault.tpm` atomically.
    ///
    /// Bytes never cross the FRB boundary — caller stages them via
    /// `crypto_aes_gcm_random_key_to_secret` (or any other
    /// `*_to_secret` shim) and the SecretStore entry survives the
    /// call so downstream consumers (drift sqlcipher pragma) can
    /// still read it.
    pub async fn store_from_secret(
        support_dir: &str,
        secret_id: &str,
    ) -> Result<(), LinuxBioVaultError> {
        if !is_tpm_ready() {
            return Err(LinuxBioVaultError::TpmUnavailable(
                "tpm probe failed".into(),
            ));
        }
        let auth_hash = fprintd::get_enrolment_hash()
            .await
            .ok_or(LinuxBioVaultError::FprintdUnavailable)?;
        let bytes = crate::app::instance()
            .secrets
            .get(secret_id)
            .ok_or_else(|| LinuxBioVaultError::SecretStore(format!("missing id: {secret_id}")))?;
        let support_dir_owned = support_dir.to_string();
        // tpm::seal is a subprocess; create_dir_all + write_bytes_atomic
        // are sync std::fs. Park the whole blocking section on a
        // dedicated thread so the FRB worker can keep serving other
        // calls during the seal.
        tokio::task::spawn_blocking(move || -> Result<(), LinuxBioVaultError> {
            let sealed = tpm::seal(&tpm::TpmConfig::default(), &bytes, &auth_hash)
                .map_err(|e| LinuxBioVaultError::Backend(e.to_string()))?;
            let path = vault_path(&support_dir_owned);
            if let Some(parent) = path.parent() {
                crate::path::create_dir_all_secure(parent)
                    .map_err(|e| LinuxBioVaultError::Io(format!("mkdirp: {e}")))?;
            }
            write_bytes_atomic(&path, &sealed)
                .map_err(|e| LinuxBioVaultError::Io(format!("write: {e}")))?;
            Ok(())
        })
        .await
        .map_err(|e| LinuxBioVaultError::Io(format!("blocking task: {e}")))??;
        Ok(())
    }

    /// Read the sealed blob, derive the fprintd enrolment hash, and
    /// unseal. On success the unsealed bytes land in the
    /// [`crate::secrets::SecretStore`] under `secret_id`; the
    /// function returns `true`. Returns `false` when the vault file
    /// is absent, fprintd has no enrolled fingers, or the unseal
    /// fails (re-enrolment forced an auth-value mismatch) — the
    /// caller routes those cases to the master-password dialog.
    /// `Err(_)` only fires for I/O failures + TPM unreachable.
    pub async fn read_to_secret(
        support_dir: &str,
        secret_id: &str,
    ) -> Result<bool, LinuxBioVaultError> {
        let path = vault_path(support_dir);
        if !path.exists() {
            return Ok(false);
        }
        if !is_tpm_ready() {
            return Err(LinuxBioVaultError::TpmUnavailable(
                "tpm probe failed".into(),
            ));
        }
        let Some(auth_hash) = fprintd::get_enrolment_hash().await else {
            return Ok(false);
        };
        // tpm::unseal is a subprocess; std::fs::read is sync. Park
        // both on spawn_blocking so the FRB worker is free during
        // the unseal.
        let unsealed =
            tokio::task::spawn_blocking(move || -> Result<Option<Vec<u8>>, LinuxBioVaultError> {
                let blob = crate::path::read_bytes_secure(&path)
                    .map_err(|e| LinuxBioVaultError::Io(format!("read: {e}")))?;
                match tpm::unseal(&tpm::TpmConfig::default(), &blob, &auth_hash) {
                    Ok(plain) => Ok(Some(plain)),
                    // Treat unseal failure as "wrong auth /
                    // re-enrolment" — caller's documented "fall back"
                    // path. Strict taxonomy would parse tpm2-tools
                    // stderr; today the CLI only returns a generic
                    // backend error here.
                    Err(_) => Ok(None),
                }
            })
            .await
            .map_err(|e| LinuxBioVaultError::Io(format!("blocking task: {e}")))??;
        match unsealed {
            Some(plain) => {
                crate::app::instance().secrets.put(secret_id, &plain);
                Ok(true)
            }
            None => Ok(false),
        }
    }

    /// Drop the sealed blob. Best-effort — a failure to delete is
    /// logged by the caller but does not block the wipe / reset
    /// flow because the TPM-side primary key is regenerated on the
    /// next `store_from_secret` and the old blob becomes dead
    /// ciphertext.
    pub fn clear(support_dir: &str) -> Result<(), LinuxBioVaultError> {
        let path = vault_path(support_dir);
        if !path.exists() {
            return Ok(());
        }
        std::fs::remove_file(&path).map_err(|e| LinuxBioVaultError::Io(format!("remove: {e}")))?;
        Ok(())
    }
}

#[cfg(not(target_os = "linux"))]
pub mod linux {
    //! Stub for non-Linux builds. The FRB cfg-dispatch in
    //! `lfs_frb::api::biometric_key_vault` never reaches these on
    //! Apple / Android / Windows (those platforms route entirely
    //! through `secure_key_storage::*_biometric_from_secret`).
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
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
}
