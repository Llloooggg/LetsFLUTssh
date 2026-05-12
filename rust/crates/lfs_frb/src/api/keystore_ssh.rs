//! FRB adapter for `lfs_os_security::android::keystore_signer` —
//! Android Hardware Keystore / StrongBox SSH key probe, generate,
//! list, delete, and the persist-to-`ssh_keys` import path. Mirrors
//! the Hello / Enclave / PKCS#11 / TPM shapes so the Dart
//! key-manager wizard reaches every hardware backend through one
//! dispatch layer.
//!
//! Cfg-gated so non-Android builds compile to stubs that surface
//! the typed `DbKeystoreProbeResult::Unsupported` envelope. The
//! Dart wizard hides its toolbar entry on those platforms via the
//! capability ladder anyway, but the stub keeps the FRB worker
//! pool cfg-clean.

use crate::api::frb_err;

/// FRB mirror of `lfs_os_security::android::keystore_signer::KeystoreAlgo`.
/// Stays a discriminator enum across the boundary so the Dart side
/// can pattern-match on the variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbKeystoreAlgo {
    /// ECDSA P-256 — the only uniformly StrongBox-eligible algorithm
    /// across the project's min-SDK; preferred default.
    EcdsaP256,
    /// Ed25519 — Android 13+ only (KeyMint v2). StrongBox NOT
    /// guaranteed; the wizard surfaces an honest "TEE only" label.
    Ed25519,
    /// RSA-2048 PKCS#1 v1.5 — widest TEE compatibility. RSA-3072 /
    /// 4096 intentionally absent — StrongBox refuses them and the
    /// SSH wizard does not surface the weaker-than-TEE fallback.
    Rsa2048,
}

/// FRB-tagged outcome of the probe step. The Dart wizard renders
/// disabled-with-reason when biometric is missing or the device
/// build target is not Android.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DbKeystoreProbeResult {
    /// Probe completed; AndroidKeyStore is reachable and the
    /// `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)` answer
    /// was `BIOMETRIC_SUCCESS`. `strongbox_available` reports the
    /// device's `FEATURE_STRONGBOX_KEYSTORE` capability — a
    /// necessary-but-not-sufficient condition for a successful
    /// `setIsStrongBoxBacked(true)` generate.
    Available { strongbox_available: bool },
    /// Biometric is not enrolled / device PIN missing. The wizard
    /// routes the user at Settings → Security.
    BiometricNotEnrolled,
    /// Non-Android build target. Toolbar entry stays hidden.
    Unsupported,
    /// Catch-all for unexpected JVM exceptions.
    Other(String),
}

/// Bundled input for [`keystore_ssh_generate`].
#[derive(Debug, Clone)]
pub struct DbKeystoreGenerateArgs {
    pub label: String,
    pub algo: DbKeystoreAlgo,
    /// `true` requests StrongBox HSM at create time. The device may
    /// still refuse via `StrongBoxUnavailableException`; the actual
    /// outcome lands in the result's `strongbox` field for honest
    /// badge rendering.
    pub strongbox: bool,
}

/// Result of [`keystore_ssh_generate`]. Carries the new DB row id +
/// the authorized_keys-shaped public-key line for the user to paste
/// on the server. `strongbox` reports whether StrongBox actually
/// accepted the request.
#[derive(Debug, Clone)]
pub struct DbKeystoreImportResult {
    pub key_id: String,
    pub label: String,
    pub authorized_keys_line: String,
    /// Actual StrongBox acceptance — drives the row's
    /// `keystore_strongbox` column and the badge label split.
    pub strongbox: bool,
    /// Capture-time `Build.MODEL` + Android version string.
    pub platform: Option<String>,
}

/// Typed outcome of [`keystore_ssh_generate`]. The
/// `StrongBoxUnavailable` arm fires when the user toggled
/// StrongBox HSM and the device refused
/// `setIsStrongBoxBacked(true)` via `StrongBoxUnavailableException`.
/// The Dart wizard surfaces a confirmation dialog asking the user
/// to explicitly approve a TEE-backed key; no automatic downgrade.
#[derive(Debug, Clone)]
pub enum DbKeystoreGenerateOutcome {
    /// Key was generated + persisted as an `ssh_keys` row.
    Generated(DbKeystoreImportResult),
    /// StrongBox HSM was requested but the device refused.
    /// No key was generated and no DB row was inserted. The caller
    /// asks the user whether to retry with `strongbox = false`.
    StrongBoxUnavailable,
}

/// Listing entry mirror for the "orphan recovery" path the wizard
/// could offer when the DB row is gone but the AndroidKeyStore
/// still holds the alias. Not wired today (no traversal API on
/// AndroidKeyStore's alias enumeration that survives uninstall);
/// the struct stays here for shape parity with the Hello / TPM
/// surfaces.
#[derive(Debug, Clone)]
pub struct DbKeystoreOrphan {
    pub keystore_alias: String,
    pub algo: DbKeystoreAlgo,
}

/// Probe whether Android Hardware Keystore SSH signing is reachable
/// on this host. The probe checks both StrongBox-capability and
/// biometric-enrolment so the wizard can route the user at the
/// matching remediation.
#[flutter_rust_bridge::frb]
pub async fn keystore_ssh_probe() -> Result<DbKeystoreProbeResult, String> {
    #[cfg(target_os = "android")]
    {
        let strongbox =
            lfs_os_security::android::keystore_signer::probe_strongbox().map_err(|e| {
                frb_err::wire(frb_err::kind::KEYSTORE, &format!("probe strongbox: {e}"))
            })?;
        let biometric_outcome = lfs_os_security::android::biometric::can_authenticate()
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::KEYSTORE, &e))?;
        // BIOMETRIC_SUCCESS = 0; everything else is some flavour of
        // missing / unavailable. We surface only the
        // `BiometricNotEnrolled` arm separately because the wizard
        // routes the user at Settings → Security on that one case.
        if biometric_outcome == 0 {
            Ok(DbKeystoreProbeResult::Available {
                strongbox_available: strongbox,
            })
        } else {
            Ok(DbKeystoreProbeResult::BiometricNotEnrolled)
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        Ok(DbKeystoreProbeResult::Unsupported)
    }
}

/// Generate a fresh AndroidKeyStore-bound SSH key + persist it as
/// an `ssh_keys` row. Fires the BiometricPrompt the next time the
/// row is used to sign; the generate call itself does not prompt
/// (the user has already authenticated to reach this surface).
pub async fn keystore_ssh_generate(
    args: DbKeystoreGenerateArgs,
) -> Result<DbKeystoreGenerateOutcome, String> {
    #[cfg(target_os = "android")]
    {
        let label = args.label.clone();
        let alias = format!("lfs-keystore-{}", lfs_core::id::random_handle_hex_32());
        let algo = args.algo;
        let request_sb = args.strongbox;
        let outcome = match generate_native(&alias, algo, request_sb).await? {
            GenerateNativeOutcome::Generated(o) => o,
            GenerateNativeOutcome::StrongBoxUnavailable => {
                return Ok(DbKeystoreGenerateOutcome::StrongBoxUnavailable);
            }
        };
        let line = outcome.authorized_keys_line.clone();
        let label_for_row = outcome.label.clone();
        let key_type = outcome.key_type.clone();
        let platform = outcome.platform.clone();
        let actual_sb = outcome.actual_strongbox;
        let alias_for_row = alias.clone();
        let inserted = crate::api::db::run_db_mut(move |conn| {
            let row = lfs_core::db::ssh_keys::SshKeyRow {
                id: lfs_core::id::random_handle_hex_32(),
                label: label_for_row.clone(),
                private_key: String::new(),
                public_key: line.clone(),
                key_type: key_type.clone(),
                is_generated: true,
                created_at_ms: now_unix_ms(),
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: lfs_core::db::ssh_keys::AgentPolicy::Ask,
                backend: lfs_core::db::ssh_keys::KeyBackend::Keystore,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: None,
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: Some(alias_for_row.clone()),
                keystore_strongbox: actual_sb,
                keystore_user_auth_required: true,
                keystore_platform: platform.clone(),
            };
            lfs_core::db::ssh_keys::import_key_for_merge(conn, &row)
        })
        .await?;
        Ok(DbKeystoreGenerateOutcome::Generated(
            DbKeystoreImportResult {
                key_id: inserted,
                label,
                authorized_keys_line: outcome.authorized_keys_line,
                strongbox: actual_sb,
                platform: outcome.platform,
            },
        ))
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = args;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Android Hardware Keystore is available on Android only",
        ))
    }
}

#[cfg(target_os = "android")]
struct GenerateOutcome {
    label: String,
    key_type: String,
    authorized_keys_line: String,
    actual_strongbox: bool,
    platform: Option<String>,
}

#[cfg(target_os = "android")]
enum GenerateNativeOutcome {
    Generated(GenerateOutcome),
    StrongBoxUnavailable,
}

#[cfg(target_os = "android")]
async fn generate_native(
    alias: &str,
    algo: DbKeystoreAlgo,
    strongbox: bool,
) -> Result<GenerateNativeOutcome, String> {
    use lfs_os_security::android::keystore_signer as ks;
    let ks_algo = match algo {
        DbKeystoreAlgo::EcdsaP256 => ks::KeystoreAlgo::EcdsaP256,
        DbKeystoreAlgo::Ed25519 => ks::KeystoreAlgo::Ed25519,
        DbKeystoreAlgo::Rsa2048 => ks::KeystoreAlgo::Rsa2048,
    };
    let gen = match ks::generate(alias.to_string(), ks_algo, strongbox)
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::KEYSTORE, &e))?
    {
        ks::GenerateOutcome::Generated(g) => g,
        ks::GenerateOutcome::StrongBoxUnavailable => {
            return Ok(GenerateNativeOutcome::StrongBoxUnavailable);
        }
    };
    let (wire_blob, key_type, wire_algo) = match algo {
        DbKeystoreAlgo::EcdsaP256 => (
            lfs_core::ssh::wire::encode_public_ecdsa_p256(&gen.public_bytes)
                .map_err(|e| frb_err::wire(frb_err::kind::KEYSTORE, &e.to_string()))?,
            "ecdsa-sha2-nistp256".to_string(),
            "ecdsa-sha2-nistp256",
        ),
        DbKeystoreAlgo::Ed25519 => (
            lfs_core::ssh::wire::encode_public_ed25519(&gen.public_bytes)
                .map_err(|e| frb_err::wire(frb_err::kind::KEYSTORE, &e.to_string()))?,
            "ssh-ed25519".to_string(),
            "ssh-ed25519",
        ),
        DbKeystoreAlgo::Rsa2048 => {
            // Kotlin returns `[u32-BE len_e || e_be || u32-BE len_n || n_be]`
            // — same shape as the SSH-wire mpint envelope without the
            // sign-bit normalisation. We unpack and re-wrap via
            // `encode_public_rsa`.
            let (modulus, exponent) = unpack_rsa_envelope(&gen.public_bytes).map_err(|e| {
                frb_err::wire(frb_err::kind::KEYSTORE, &format!("rsa envelope: {e}"))
            })?;
            (
                lfs_core::ssh::wire::encode_public_rsa(&modulus, &exponent),
                "rsa-2048".to_string(),
                "ssh-rsa",
            )
        }
    };
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let b64 = STANDARD.encode(&wire_blob);
    let label = format!("Keystore {}", short_alias(alias));
    let authorized_keys_line = format!("{wire_algo} {b64} {label}");
    Ok(GenerateNativeOutcome::Generated(GenerateOutcome {
        label,
        key_type,
        authorized_keys_line,
        actual_strongbox: gen.actual_strongbox,
        platform: gen.platform,
    }))
}

#[cfg(target_os = "android")]
fn unpack_rsa_envelope(bytes: &[u8]) -> Result<(Vec<u8>, Vec<u8>), String> {
    if bytes.len() < 8 {
        return Err("envelope too short".into());
    }
    let e_len = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as usize;
    if 4 + e_len + 4 > bytes.len() {
        return Err("e_len overflow".into());
    }
    let e = &bytes[4..4 + e_len];
    let n_len_off = 4 + e_len;
    let n_len = u32::from_be_bytes([
        bytes[n_len_off],
        bytes[n_len_off + 1],
        bytes[n_len_off + 2],
        bytes[n_len_off + 3],
    ]) as usize;
    let n_start = n_len_off + 4;
    if n_start + n_len != bytes.len() {
        return Err("n_len mismatch".into());
    }
    let n = &bytes[n_start..n_start + n_len];
    Ok((n.to_vec(), e.to_vec()))
}

#[cfg(target_os = "android")]
fn short_alias(alias: &str) -> String {
    // Trim the `lfs-keystore-` prefix + keep the first 8 hex chars.
    alias
        .strip_prefix("lfs-keystore-")
        .map(|s| s.chars().take(8).collect::<String>())
        .unwrap_or_else(|| alias.to_string())
}

/// Delete the AndroidKeyStore alias referenced by the row at
/// `key_id` + soft-delete the DB row. Mirrors the Hello / Enclave /
/// PKCS#11 patterns. Hardware-bound keys never reach the export
/// surface, so this is the sole removal path.
pub async fn keystore_ssh_delete(key_id: String) -> Result<(), String> {
    #[cfg(target_os = "android")]
    {
        let lookup_id = key_id.clone();
        let row =
            crate::api::db::run_db(move |c| lfs_core::db::ssh_keys::get(c, &lookup_id)).await?;
        if let Some(row) = row {
            if let Some(alias) = row.keystore_alias.clone() {
                let _ = lfs_os_security::android::keystore_signer::delete(alias).await;
            }
        }
        crate::api::db::run_db(move |c| lfs_core::db::ssh_keys::delete(c, &key_id))
            .await
            .map(|_| ())
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = key_id;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Android Hardware Keystore is available on Android only",
        ))
    }
}

#[cfg(target_os = "android")]
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unsupported_platform_returns_for_non_android() {
        if cfg!(not(target_os = "android")) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            let res = rt.block_on(keystore_ssh_probe()).unwrap();
            assert_eq!(res, DbKeystoreProbeResult::Unsupported);
        }
    }

    #[test]
    fn db_keystore_algo_variants_distinct() {
        assert_ne!(DbKeystoreAlgo::EcdsaP256, DbKeystoreAlgo::Ed25519);
        assert_ne!(DbKeystoreAlgo::EcdsaP256, DbKeystoreAlgo::Rsa2048);
        assert_ne!(DbKeystoreAlgo::Ed25519, DbKeystoreAlgo::Rsa2048);
    }
}
