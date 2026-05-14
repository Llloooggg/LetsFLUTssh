//! FRB adapter for `lfs_os_security::windows::ncrypt_ssh` — Windows
//! Hello (NCrypt / Microsoft Platform Crypto Provider) SSH key
//! probe, generate, list, delete, and the persist-to-`ssh_keys`
//! import path. Mirrors the Apple Secure Enclave + PKCS#11 shapes so
//! the Dart key-manager UI reaches every hardware backend through
//! one dispatch layer.
//!
//! Cfg-gated so non-Windows builds compile to stubs that surface the
//! typed `DbHelloProbeResult::Unsupported` envelope. Dart's
//! `HelloBadge` / wizard hides itself on those platforms via the
//! capability ladder anyway, but the stub keeps the FRB worker pool
//! cfg-clean.

use crate::api::frb_err;

/// FRB mirror of `lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo`.
/// Stays a string-tag enum across the boundary so the Dart side can
/// pattern-match on the discriminator.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbHelloAlgo {
    /// ECDSA P-256 — preferred default; widest TPM support.
    EcdsaP256,
    /// ECDSA P-384 — TPM-firmware-dependent. Probe before exposing.
    EcdsaP384,
    /// RSA-2048 PKCS#1 v1.5 — older-server fallback.
    Rsa2048,
}

/// FRB mirror of `lfs_os_security::windows::ncrypt_ssh::TpmTier`.
/// Drives the wizard's honest-label rendering on the
/// `SoftwareKsp` rung-6 path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbHelloTpmTier {
    /// TPM-backed key — strongest binding.
    Hardware,
    /// PCP software KSP fallback — honest "Software-gated" label in
    /// the UI per the capability ladder.
    SoftwareKsp,
}

/// FRB-tagged result of `hello_ssh_probe`. Mirror of the Rust
/// `UnavailableReason` plus the `Ok` arm carrying the TPM tier.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DbHelloProbeResult {
    /// Probe round-trip completed. `tier` says whether the host has
    /// TPM 2.0 or fell back to the software KSP.
    Available { tier: DbHelloTpmTier },
    /// `MS_PLATFORM_KEY_STORAGE_PROVIDER` could not be opened. Most
    /// commonly: no TPM, GPO blocked, or Win < 10 1607.
    ProviderUnavailable(String),
    /// Hello is not configured — finalize step surfaced
    /// `NTE_USER_CANCELLED`. Wizard routes the user at "Settings ->
    /// Sign-in options".
    HelloNotConfigured,
    /// Non-Windows build target. Toolbar entry stays hidden.
    Unsupported,
    /// Any other failure — carries the diagnostic string.
    Other(String),
}

/// Result of `hello_ssh_generate`. Carries the new DB row id + the
/// authorized_keys-shaped public-key line for the user to paste on
/// the server. Same shape as the SE / PKCS#11 wizards.
#[derive(Debug, Clone)]
pub struct DbHelloImportResult {
    pub key_id: String,
    pub label: String,
    pub authorized_keys_line: String,
    /// TPM tier resolved at create time. Surfaced so the
    /// "Software-gated" warning persists into the Complete step.
    pub tier: DbHelloTpmTier,
}

/// Listing entry mirror of
/// `lfs_os_security::windows::ncrypt_ssh::HelloKeyHandle`. Surfaced
/// by the "orphan recovery" path the wizard offers when the DB row
/// is gone but the TPM still holds the persistent key.
#[derive(Debug, Clone)]
pub struct DbHelloOrphan {
    pub credential_name: String,
    pub algo: DbHelloAlgo,
}

/// Bundled input for [`hello_ssh_generate`].
#[derive(Debug, Clone)]
pub struct DbHelloGenerateArgs {
    pub label: String,
    pub algo: DbHelloAlgo,
}

/// Probe whether Hello-SSH is reachable on this host. Runs a real
/// generate / delete round trip so the wizard can route the user at
/// the correct remediation.
#[flutter_rust_bridge::frb]
pub async fn hello_ssh_probe() -> Result<DbHelloProbeResult, String> {
    #[cfg(target_os = "windows")]
    {
        tokio::task::spawn_blocking(probe_native)
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &format!("spawn_blocking: {e}")))
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(DbHelloProbeResult::Unsupported)
    }
}

#[cfg(target_os = "windows")]
fn probe_native() -> DbHelloProbeResult {
    use lfs_os_security::windows::ncrypt_ssh::{self, TpmTier, UnavailableReason};
    match ncrypt_ssh::probe_availability() {
        Ok(TpmTier::Hardware) => DbHelloProbeResult::Available {
            tier: DbHelloTpmTier::Hardware,
        },
        Ok(TpmTier::SoftwareKsp) => DbHelloProbeResult::Available {
            tier: DbHelloTpmTier::SoftwareKsp,
        },
        Err(UnavailableReason::ProviderUnavailable(s)) => {
            DbHelloProbeResult::ProviderUnavailable(s)
        }
        Err(UnavailableReason::HelloNotConfigured) => DbHelloProbeResult::HelloNotConfigured,
        Err(UnavailableReason::UnsupportedPlatform) => DbHelloProbeResult::Unsupported,
        Err(UnavailableReason::Other(s)) => DbHelloProbeResult::Other(s),
    }
}

/// Generate a fresh Hello-bound SSH key + persist it as an
/// `ssh_keys` row. Fires the OS Hello prompt inside the call per
/// the UI policy set at create time.
pub async fn hello_ssh_generate(args: DbHelloGenerateArgs) -> Result<DbHelloImportResult, String> {
    #[cfg(target_os = "windows")]
    {
        let label = args.label.clone();
        let algo = args.algo;
        let outcome = tokio::task::spawn_blocking(move || generate_native(&label, algo))
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &format!("spawn_blocking: {e}")))??;
        // Capture the fields the result envelope needs before the
        // closure takes ownership of `outcome` — `move` consumes it
        // for the DB worker, and the post-await `Ok(...)` builds the
        // FRB return value from the same fields.
        let result_label = outcome.label.clone();
        let result_line = outcome.authorized_keys_line.clone();
        let result_tier = outcome.tier;
        let inserted = crate::api::db::run_db_mut_writing_keys(move |conn| {
            let row = lfs_core::db::ssh_keys::SshKeyRow {
                id: lfs_core::id::random_handle_hex_32(),
                label: outcome.label,
                // Hardware-bound rows keep `private_key` non-empty
                // per the schema's `NOT NULL` shape; the empty-string
                // sentinel matches the FIDO2 / PKCS#11 / Enclave
                // paths.
                private_key: String::new(),
                public_key: outcome.authorized_keys_line,
                key_type: outcome.key_type,
                is_generated: true,
                created_at_ms: now_unix_ms(),
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: lfs_core::db::ssh_keys::AgentPolicy::Ask,
                backend: lfs_core::db::ssh_keys::KeyBackend::Hello,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: Some(outcome.credential_name),
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: None,
                keystore_strongbox: false,
                keystore_user_auth_required: false,
                keystore_platform: None,
                imported_as_stub: false,
            };
            lfs_core::db::ssh_keys::import_key_for_merge(conn, &row)
        })
        .await?;
        Ok(DbHelloImportResult {
            key_id: inserted,
            label: result_label,
            authorized_keys_line: result_line,
            tier: result_tier,
        })
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = args;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Windows Hello is available on Windows only",
        ))
    }
}

#[cfg(target_os = "windows")]
struct GenerateOutcome {
    credential_name: String,
    label: String,
    key_type: String,
    authorized_keys_line: String,
    tier: DbHelloTpmTier,
}

#[cfg(target_os = "windows")]
fn generate_native(label: &str, algo: DbHelloAlgo) -> Result<GenerateOutcome, String> {
    use lfs_os_security::windows::ncrypt_ssh::{self, HelloPublicKey, SshKeyAlgo};
    let nc_algo = match algo {
        DbHelloAlgo::EcdsaP256 => SshKeyAlgo::EcdsaP256,
        DbHelloAlgo::EcdsaP384 => SshKeyAlgo::EcdsaP384,
        DbHelloAlgo::Rsa2048 => SshKeyAlgo::Rsa2048,
    };
    let handle = ncrypt_ssh::create(label, nc_algo)
        .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &e.to_string()))?;
    // Pull the public half + wrap it via the shared SSH wire
    // helpers (`lfs_core::ssh::wire`).
    let material = ncrypt_ssh::public_key_material(&handle)
        .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &e.to_string()))?;
    let (wire_blob, key_type, wire_algo) = match material {
        HelloPublicKey::EcdsaP256 { uncompressed_65 } => (
            lfs_core::ssh::wire::encode_public_ecdsa_p256(&uncompressed_65)
                .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &e.to_string()))?,
            "ecdsa-sha2-nistp256".to_string(),
            "ecdsa-sha2-nistp256",
        ),
        HelloPublicKey::EcdsaP384 { uncompressed_97 } => (
            lfs_core::ssh::wire::encode_public_ecdsa_p384(&uncompressed_97)
                .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &e.to_string()))?,
            "ecdsa-sha2-nistp384".to_string(),
            "ecdsa-sha2-nistp384",
        ),
        HelloPublicKey::Rsa2048 { exponent, modulus } => (
            lfs_core::ssh::wire::encode_public_rsa(&modulus, &exponent),
            "rsa-2048".to_string(),
            "ssh-rsa",
        ),
    };
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let b64 = STANDARD.encode(&wire_blob);
    let authorized_keys_line = if label.is_empty() {
        format!("{wire_algo} {b64}")
    } else {
        format!("{wire_algo} {b64} {label}")
    };
    // TPM tier — best-effort second probe via the same provider.
    // We don't re-probe per-key (probe_availability cycles a
    // throwaway key); reuse the wizard's earlier probe result via
    // the UI state when needed. For the immediate "Software-gated"
    // toast, re-probe now so the create path reports the actual
    // tier the key landed at.
    let tier = match ncrypt_ssh::probe_availability() {
        Ok(ncrypt_ssh::TpmTier::Hardware) => DbHelloTpmTier::Hardware,
        _ => DbHelloTpmTier::SoftwareKsp,
    };
    Ok(GenerateOutcome {
        credential_name: handle.credential_name,
        label: handle.label,
        key_type,
        authorized_keys_line,
        tier,
    })
}

/// Enumerate Hello-bound persisted keys that the TPM holds. Used by
/// the "orphan recovery" path when the DB lost the row but the chip
/// still holds it.
pub async fn hello_ssh_list_orphans() -> Result<Vec<DbHelloOrphan>, String> {
    #[cfg(target_os = "windows")]
    {
        tokio::task::spawn_blocking(|| {
            lfs_os_security::windows::ncrypt_ssh::list()
                .map(|handles| {
                    handles
                        .into_iter()
                        .map(|h| DbHelloOrphan {
                            credential_name: h.credential_name,
                            algo: match h.algo {
                                lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo::EcdsaP256 => {
                                    DbHelloAlgo::EcdsaP256
                                }
                                lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo::EcdsaP384 => {
                                    DbHelloAlgo::EcdsaP384
                                }
                                lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo::Rsa2048 => {
                                    DbHelloAlgo::Rsa2048
                                }
                            },
                        })
                        .collect()
                })
                .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &e.to_string()))
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::HELLO, &format!("spawn_blocking: {e}")))?
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(Vec::new())
    }
}

/// Delete the Hello-bound on-TPM key referenced by `ssh_keys.id`.
/// Also soft-deletes the DB row so the manager view drops it.
/// Mirrors the Apple Secure Enclave + PKCS#11 patterns.
pub async fn hello_ssh_delete(key_id: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let lookup_id = key_id.clone();
        let row =
            crate::api::db::run_db(move |c| lfs_core::db::ssh_keys::get(c, &lookup_id)).await?;
        if let Some(row) = row {
            if let (Some(name), Ok(algo)) = (
                row.hello_credential_name.clone(),
                lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo::from_key_type(&row.key_type),
            ) {
                let handle = lfs_os_security::windows::ncrypt_ssh::HelloKeyHandle {
                    credential_name: name,
                    algo,
                    label: String::new(),
                };
                let _ = tokio::task::spawn_blocking(move || {
                    lfs_os_security::windows::ncrypt_ssh::delete(&handle)
                })
                .await
                .map_err(|e| {
                    frb_err::wire(frb_err::kind::HELLO, &format!("spawn_blocking: {e}"))
                })?;
            }
        }
        crate::api::db::run_db_writing_keys_when(
            move |c| lfs_core::db::ssh_keys::delete(c, &key_id),
            |n| *n > 0,
        )
        .await
        .map(|_| ())
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = key_id;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Windows Hello is available on Windows only",
        ))
    }
}

#[cfg(target_os = "windows")]
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
    fn unsupported_platform_returns_for_non_windows() {
        if cfg!(not(target_os = "windows")) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            let res = rt.block_on(hello_ssh_probe()).unwrap();
            assert_eq!(res, DbHelloProbeResult::Unsupported);
        }
    }

    #[test]
    fn db_hello_algo_variants_distinct() {
        assert_ne!(DbHelloAlgo::EcdsaP256, DbHelloAlgo::EcdsaP384);
        assert_ne!(DbHelloAlgo::EcdsaP256, DbHelloAlgo::Rsa2048);
    }
}
