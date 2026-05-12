//! FRB adapter for `lfs_os_security::linux::tpm_ssh` (Linux ESAPI
//! driver) and the silent-variant `lfs_os_security::windows::ncrypt_ssh`
//! path (Windows PCP, no UI policy). Mirrors the Hello / Enclave /
//! PKCS#11 shapes so the Dart key-manager wizard reaches both
//! platforms through one dispatch layer.
//!
//! Cfg-gated so non-Linux / non-Windows builds compile to stubs
//! that surface the typed `DbTpmSshProbeResult::Unsupported`
//! envelope. The Dart wizard hides its toolbar entry on those
//! platforms via the capability ladder anyway; the stub keeps the
//! FRB worker pool cfg-clean.

use crate::api::frb_err;

/// FRB mirror of `lfs_os_security::linux::tpm_ssh::TpmSshAlgorithm`
/// (Linux) / `lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo`
/// (Windows). Stays a discriminator enum across the boundary so the
/// Dart side can pattern-match on the variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbTpmSshAlgorithm {
    /// ECDSA P-256 — preferred default; widest TPM support.
    EcdsaP256,
    /// RSA-2048 PKCS#1 v1.5 — older-server compatibility fallback.
    /// RSA generation on a typical fTPM takes 2-10 s; the wizard
    /// surfaces a progress spinner.
    Rsa2048,
}

/// FRB-tagged outcome of the probe step. The Dart wizard renders
/// the matching localized reason when the host can't reach a TPM.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DbTpmSshProbeResult {
    /// Probe round-trip completed — chip is reachable and the SSH
    /// key path is ready.
    Available,
    /// `/dev/tpmrm0` (or the override) is missing. No TPM or fTPM
    /// disabled in firmware.
    DeviceNodeMissing,
    /// App cannot reach the TPM device node — Linux only, typically
    /// because the user is not in the `tss` group. The Dart wizard
    /// surfaces the documented remediation
    /// (`sudo usermod -a -G tss $USER && newgrp tss`).
    NoPermission,
    /// `tpm2-tools` binary is missing (subprocess backend only).
    BinaryMissing,
    /// `getcap` or `createprimary` returned non-zero — usually
    /// firmware-disabled.
    ProbeFailed,
    /// Build target without TPM support (macOS, iOS, Android — the
    /// wizard hides the toolbar entry on those).
    Unsupported,
}

/// Storage mode chosen at generate time. The Dart wizard's radio
/// step writes one of these into the create call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbTpmSshStorageMode {
    /// Wrapped blob in app data (default; portable across
    /// reinstalls). Linux only; Windows CNG always uses the PCP
    /// persistent store internally.
    Blob,
    /// Persistent NV handle (TPM RAM). Faster signing; consumes one
    /// of the chip's persistent slots. Linux only.
    PersistentHandle,
}

/// Bundled input for [`tpm_ssh_generate`]. The wizard composes the
/// fields from its radio + text-field state.
#[derive(Debug, Clone)]
pub struct DbTpmSshGenerateArgs {
    pub label: String,
    pub algo: DbTpmSshAlgorithm,
    /// `Some(pin_bytes)` when the wizard's "Protect with PIN"
    /// checkbox is set; `None` for headless / no-PIN keys.
    pub pin: Option<String>,
    pub storage: DbTpmSshStorageMode,
    /// Persistent NV handle in the `0x81010001..0x8101FFFF` range
    /// when `storage = PersistentHandle`. Ignored for `Blob`.
    pub persistent_handle: Option<u32>,
    /// When `true` on Windows + the FRB layer picks
    /// `lfs_os_security::windows::ncrypt_ssh::create_silent` →
    /// silent TPM key without `NCRYPT_UI_POLICY_PROPERTY`. The
    /// Linux path ignores this — `silent_tpm` is a Windows-only
    /// switch because the Linux ESAPI driver has no Hello-prompt
    /// concept to disable.
    pub silent_tpm: bool,
}

/// Result of [`tpm_ssh_generate`]. Carries the new DB row id +
/// the authorized_keys-shaped public-key line for the user to paste
/// on the server, mirroring the Hello / Enclave / PKCS#11 shapes.
#[derive(Debug, Clone)]
pub struct DbTpmSshImportResult {
    pub key_id: String,
    pub label: String,
    pub authorized_keys_line: String,
}

/// Listing entry mirror of `lfs_os_security::linux::tpm_ssh::TpmSshKey`
/// (Linux) / `TpmSilentKeyHandle` (Windows). Used by the key-manager
/// info popover.
#[derive(Debug, Clone)]
pub struct DbTpmKeyMeta {
    pub key_id: String,
    pub label: String,
    pub algo: DbTpmSshAlgorithm,
    pub provider: String,
    /// `Some(handle)` for persistent-NV-handle storage; `None` for
    /// on-disk blob mode.
    pub persistent_handle: Option<u32>,
    pub pin_required: bool,
}

/// Probe whether TPM 2.0 SSH signing is reachable on this host.
#[flutter_rust_bridge::frb]
pub async fn tpm_ssh_probe() -> Result<DbTpmSshProbeResult, String> {
    #[cfg(target_os = "linux")]
    {
        tokio::task::spawn_blocking(probe_native_linux)
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::TPM, &format!("spawn_blocking: {e}")))
    }
    #[cfg(target_os = "windows")]
    {
        tokio::task::spawn_blocking(probe_native_windows)
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::TPM, &format!("spawn_blocking: {e}")))
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        Ok(DbTpmSshProbeResult::Unsupported)
    }
}

#[cfg(target_os = "linux")]
fn probe_native_linux() -> DbTpmSshProbeResult {
    use lfs_os_security::linux::tpm::{self, TpmConfig};
    let cfg = TpmConfig::default();
    match tpm::probe(&cfg) {
        tpm::TpmProbeResult::Available => DbTpmSshProbeResult::Available,
        tpm::TpmProbeResult::DeviceNodeMissing => DbTpmSshProbeResult::DeviceNodeMissing,
        tpm::TpmProbeResult::BinaryMissing => DbTpmSshProbeResult::BinaryMissing,
        tpm::TpmProbeResult::ProbeFailed => {
            // `tss` group membership is the most common cause of a
            // probe failure on a host that *does* have a TPM device
            // node. Best-effort hint: when the device is present but
            // not openable, surface the `NoPermission` discriminator
            // so the Dart wizard routes the user at the
            // `tpmSshUnavailableNoPermission` copy with the
            // `usermod -a -G tss` snippet.
            if std::fs::OpenOptions::new()
                .read(true)
                .open(&cfg.device)
                .is_err()
                && std::path::Path::new(&cfg.device).exists()
            {
                DbTpmSshProbeResult::NoPermission
            } else {
                DbTpmSshProbeResult::ProbeFailed
            }
        }
    }
}

#[cfg(target_os = "windows")]
fn probe_native_windows() -> DbTpmSshProbeResult {
    // The Windows silent-variant probe reuses the Hello probe — it
    // mints a throw-away key under MS_PLATFORM_KEY_STORAGE_PROVIDER
    // and checks the hardware tier. If the provider is reachable the
    // silent path is reachable too (no UI policy = no Hello dependency).
    use lfs_os_security::windows::ncrypt_ssh::{self, TpmTier, UnavailableReason};
    match ncrypt_ssh::probe_availability() {
        Ok(TpmTier::Hardware) | Ok(TpmTier::SoftwareKsp) => DbTpmSshProbeResult::Available,
        Err(UnavailableReason::ProviderUnavailable(_)) => DbTpmSshProbeResult::DeviceNodeMissing,
        Err(_) => DbTpmSshProbeResult::ProbeFailed,
    }
}

/// Generate a fresh TPM-bound SSH key + persist it as an `ssh_keys`
/// row. Routes to the Linux ESAPI driver on Linux and the Windows
/// PCP silent path on Windows.
pub async fn tpm_ssh_generate(args: DbTpmSshGenerateArgs) -> Result<DbTpmSshImportResult, String> {
    #[cfg(target_os = "linux")]
    {
        let outcome = tokio::task::spawn_blocking({
            let args = args.clone();
            move || generate_native_linux(&args)
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &format!("spawn_blocking: {e}")))??;
        persist_row(outcome).await
    }
    #[cfg(target_os = "windows")]
    {
        let outcome = tokio::task::spawn_blocking({
            let args = args.clone();
            move || generate_native_windows(&args)
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &format!("spawn_blocking: {e}")))??;
        persist_row(outcome).await
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = args;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "TPM 2.0 SSH keys are available on Linux + Windows only",
        ))
    }
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
struct GenerateOutcome {
    label: String,
    key_type: String,
    authorized_keys_line: String,
    backend_columns: BackendColumns,
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
struct BackendColumns {
    tpm_blob: Option<Vec<u8>>,
    tpm_handle: Option<u32>,
    tpm_provider: String,
    tpm_pin_required: bool,
    cng_key_name: Option<String>,
}

#[cfg(target_os = "linux")]
fn generate_native_linux(args: &DbTpmSshGenerateArgs) -> Result<GenerateOutcome, String> {
    use lfs_os_security::linux::tpm::TpmConfig;
    use lfs_os_security::linux::tpm_ssh::{self, TpmSshAlgorithm};
    let alg = match args.algo {
        DbTpmSshAlgorithm::EcdsaP256 => TpmSshAlgorithm::EcdsaP256,
        DbTpmSshAlgorithm::Rsa2048 => TpmSshAlgorithm::Rsa2048,
    };
    let cfg = TpmConfig::default();
    let pin_bytes = args.pin.as_ref().map(|p| p.as_bytes().to_vec());
    let key = tpm_ssh::generate(&cfg, alg, pin_bytes.as_deref())
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?;
    let (wire_blob, wire_algo, key_type) = match key.public.clone() {
        tpm_ssh::TpmSshPublicKey::EcdsaP256 { uncompressed_65 } => (
            lfs_core::ssh::wire::encode_public_ecdsa_p256(&uncompressed_65)
                .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?,
            "ecdsa-sha2-nistp256",
            "ecdsa-sha2-nistp256".to_string(),
        ),
        tpm_ssh::TpmSshPublicKey::Rsa2048 { exponent, modulus } => (
            lfs_core::ssh::wire::encode_public_rsa(&modulus, &exponent),
            "ssh-rsa",
            "rsa-2048".to_string(),
        ),
    };
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let b64 = STANDARD.encode(&wire_blob);
    let authorized_keys_line = if args.label.is_empty() {
        format!("{wire_algo} {b64}")
    } else {
        format!("{wire_algo} {b64} {}", args.label)
    };
    let blob_bytes = match key.storage {
        tpm_ssh::TpmSshStorage::Blob { public, private } => Some(
            tpm_ssh::pack_envelope(&public, &private)
                .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?,
        ),
        tpm_ssh::TpmSshStorage::PersistentHandle(_) => None,
    };
    let handle = match args.storage {
        // Persistent-handle mode is wizard-only in v1; the generate
        // call always produces a blob and a follow-up
        // `tpm_ssh_make_persistent` promotes it. v1 wizard surfaces
        // the radio but the make-persistent path returns a typed
        // "not-on-libtss2-7.5" error until the v2 bump verifies it
        // on a real chip. `persistent_handle` carried here for the
        // future call site.
        DbTpmSshStorageMode::Blob => None,
        DbTpmSshStorageMode::PersistentHandle => args.persistent_handle,
    };
    Ok(GenerateOutcome {
        label: args.label.clone(),
        key_type,
        authorized_keys_line,
        backend_columns: BackendColumns {
            tpm_blob: blob_bytes,
            tpm_handle: handle,
            tpm_provider: "tss-esapi".into(),
            tpm_pin_required: args.pin.is_some(),
            cng_key_name: None,
        },
    })
}

#[cfg(target_os = "windows")]
fn generate_native_windows(args: &DbTpmSshGenerateArgs) -> Result<GenerateOutcome, String> {
    use lfs_os_security::windows::ncrypt_ssh::{self, HelloPublicKey, SshKeyAlgo};
    let algo = match args.algo {
        DbTpmSshAlgorithm::EcdsaP256 => SshKeyAlgo::EcdsaP256,
        DbTpmSshAlgorithm::Rsa2048 => SshKeyAlgo::Rsa2048,
    };
    // The wizard's "silent_tpm" path is the only Windows arm — the
    // Hello-gated variant lands under the Hello wizard
    // (`hello_ssh_generate`). PIN is not collected on Windows: the
    // silent variant is unattended by definition.
    let _ = args.pin;
    let handle = ncrypt_ssh::create_silent(&args.label, algo)
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?;
    let material = ncrypt_ssh::public_key_material_silent(&handle)
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?;
    let (wire_blob, wire_algo, key_type) = match material {
        HelloPublicKey::EcdsaP256 { uncompressed_65 } => (
            lfs_core::ssh::wire::encode_public_ecdsa_p256(&uncompressed_65)
                .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?,
            "ecdsa-sha2-nistp256",
            "ecdsa-sha2-nistp256".to_string(),
        ),
        HelloPublicKey::EcdsaP384 { .. } => {
            return Err(frb_err::wire(
                frb_err::kind::TPM,
                "ECDSA P-384 is not exposed by the silent TPM wizard",
            ));
        }
        HelloPublicKey::Rsa2048 { exponent, modulus } => (
            lfs_core::ssh::wire::encode_public_rsa(&modulus, &exponent),
            "ssh-rsa",
            "rsa-2048".to_string(),
        ),
    };
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let b64 = STANDARD.encode(&wire_blob);
    let authorized_keys_line = if args.label.is_empty() {
        format!("{wire_algo} {b64}")
    } else {
        format!("{wire_algo} {b64} {}", args.label)
    };
    Ok(GenerateOutcome {
        label: handle.label.clone(),
        key_type,
        authorized_keys_line,
        backend_columns: BackendColumns {
            tpm_blob: None,
            tpm_handle: None,
            tpm_provider: "cng-pcp".into(),
            tpm_pin_required: false,
            cng_key_name: Some(handle.credential_name),
        },
    })
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
async fn persist_row(outcome: GenerateOutcome) -> Result<DbTpmSshImportResult, String> {
    let columns = outcome.backend_columns;
    let label = outcome.label.clone();
    let key_type = outcome.key_type.clone();
    let line = outcome.authorized_keys_line.clone();
    let inserted = crate::api::db::run_db_mut(move |conn| {
        let row = lfs_core::db::ssh_keys::SshKeyRow {
            id: lfs_core::id::random_handle_hex_32(),
            label: label.clone(),
            private_key: String::new(),
            public_key: line.clone(),
            key_type: key_type.clone(),
            is_generated: true,
            created_at_ms: now_unix_ms(),
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: lfs_core::db::ssh_keys::AgentPolicy::Ask,
            backend: lfs_core::db::ssh_keys::KeyBackend::Tpm,
            pkcs11_uri: None,
            pkcs11_module_path: None,
            pkcs11_token_serial: None,
            pkcs11_object_id: None,
            pkcs11_object_label: None,
            enclave_tag: None,
            hello_credential_name: None,
            tpm_blob: columns.tpm_blob,
            tpm_handle: columns.tpm_handle,
            tpm_provider: Some(columns.tpm_provider),
            tpm_pin_required: columns.tpm_pin_required,
            cng_key_name: columns.cng_key_name,
            keystore_alias: None,
            keystore_strongbox: false,
            keystore_user_auth_required: false,
            keystore_platform: None,
        };
        lfs_core::db::ssh_keys::import_key_for_merge(conn, &row)
    })
    .await?;
    Ok(DbTpmSshImportResult {
        key_id: inserted,
        label: outcome.label,
        authorized_keys_line: outcome.authorized_keys_line,
    })
}

/// Import a wrapped TPM blob (`.tpm` file, TSS2 PRIVATE KEY format),
/// then persist it as an `ssh_keys` row. Linux only — Windows CNG
/// owns its own keystore and there's no portable import shape.
pub async fn tpm_ssh_import_blob(blob: Vec<u8>, label: String) -> Result<String, String> {
    #[cfg(target_os = "linux")]
    {
        let outcome = tokio::task::spawn_blocking({
            let blob = blob.clone();
            let label = label.clone();
            move || import_native_linux(&blob, &label)
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &format!("spawn_blocking: {e}")))??;
        let result = persist_row(outcome).await?;
        Ok(result.key_id)
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = blob;
        let _ = label;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "TPM blob import is available on Linux only",
        ))
    }
}

#[cfg(target_os = "linux")]
fn import_native_linux(blob: &[u8], label: &str) -> Result<GenerateOutcome, String> {
    use lfs_os_security::linux::tpm_ssh;
    let key = tpm_ssh::import_blob(blob)
        .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?;
    let (wire_blob, wire_algo, key_type) = match key.public.clone() {
        tpm_ssh::TpmSshPublicKey::EcdsaP256 { uncompressed_65 } => (
            lfs_core::ssh::wire::encode_public_ecdsa_p256(&uncompressed_65)
                .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?,
            "ecdsa-sha2-nistp256",
            "ecdsa-sha2-nistp256".to_string(),
        ),
        tpm_ssh::TpmSshPublicKey::Rsa2048 { exponent, modulus } => (
            lfs_core::ssh::wire::encode_public_rsa(&modulus, &exponent),
            "ssh-rsa",
            "rsa-2048".to_string(),
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
    let blob_bytes = match key.storage {
        tpm_ssh::TpmSshStorage::Blob { public, private } => Some(
            tpm_ssh::pack_envelope(&public, &private)
                .map_err(|e| frb_err::wire(frb_err::kind::TPM, &e.to_string()))?,
        ),
        tpm_ssh::TpmSshStorage::PersistentHandle(_) => None,
    };
    Ok(GenerateOutcome {
        label: label.to_string(),
        key_type,
        authorized_keys_line,
        backend_columns: BackendColumns {
            tpm_blob: blob_bytes,
            tpm_handle: None,
            tpm_provider: "tss-esapi".into(),
            // Imported blobs may carry a PIN-binding — we cannot
            // tell without trying a sign. v1 wizard surfaces the
            // import as no-PIN by default; the connect path's
            // first sign attempt will surface a `pin incorrect` /
            // `lockout` reason if the blob is PIN-bound and no PIN
            // is staged. v2 tracks this via the `policy` field on
            // the TSS2 PRIVATE KEY ASN.1 envelope.
            tpm_pin_required: false,
            cng_key_name: None,
        },
    })
}

/// Promote a wrapped-blob TPM key to a persistent NV handle. Linux
/// only. v1 returns the typed
/// `Error::Tpm("...libtss2 7.5 requires a real-device verification pass...")`
/// — the persistent-handle path is the wizard's stretch goal pending
/// the v2 tss-esapi minor bump verification.
pub async fn tpm_ssh_make_persistent(key_id: String, handle: u32) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    {
        let _ = handle;
        let _ = key_id;
        Err(frb_err::wire(
            frb_err::kind::TPM,
            "persistent-handle promotion requires a real-device verification pass",
        ))
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (key_id, handle);
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Persistent NV handles are Linux-only",
        ))
    }
}

/// Evict a persistent NV handle back to TPM RAM. Linux only;
/// shares the v1 caveat with [`tpm_ssh_make_persistent`].
pub async fn tpm_ssh_evict(key_id: String) -> Result<(), String> {
    let _ = key_id;
    Err(frb_err::wire(
        frb_err::kind::TPM,
        "persistent-handle eviction requires a real-device verification pass",
    ))
}

/// Enumerate TPM-bound `ssh_keys` rows for the key-manager listing.
/// Reads the DB row directly — does not re-probe the chip.
pub async fn tpm_ssh_list() -> Result<Vec<DbTpmKeyMeta>, String> {
    let rows = crate::api::db::run_db(lfs_core::db::ssh_keys::list_all).await?;
    Ok(rows
        .into_iter()
        .filter(|r| r.backend == lfs_core::db::ssh_keys::KeyBackend::Tpm)
        .map(|r| DbTpmKeyMeta {
            key_id: r.id,
            label: r.label,
            algo: if r.key_type.starts_with("rsa") || r.key_type == "ssh-rsa" {
                DbTpmSshAlgorithm::Rsa2048
            } else {
                DbTpmSshAlgorithm::EcdsaP256
            },
            provider: r.tpm_provider.unwrap_or_else(|| "tss-esapi".into()),
            persistent_handle: r.tpm_handle,
            pin_required: r.tpm_pin_required,
        })
        .collect())
}

/// Soft-delete a TPM-bound `ssh_keys` row + (best-effort) free the
/// chip-side material. On Linux blob mode this is a no-op chip-side
/// — the wrapped blob lives in the DB row and disappears with it.
/// On Linux persistent-handle mode the chip-side eviction is the
/// `make_persistent` companion (v2 work). On Windows the
/// `cng_key_name` corresponds to a CNG persistent key — `NCryptDeleteKey`
/// fires here.
pub async fn tpm_ssh_delete(key_id: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        // Resolve the row's CNG name first so we can delete the
        // chip-side material before the DB tombstone lands.
        let lookup_id = key_id.clone();
        let row =
            crate::api::db::run_db(move |c| lfs_core::db::ssh_keys::get(c, &lookup_id)).await?;
        if let Some(row) = row {
            if let Some(name) = row.cng_key_name.clone() {
                let algo = match row.key_type.as_str() {
                    "rsa" | "ssh-rsa" | "rsa-2048" => {
                        lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo::Rsa2048
                    }
                    _ => lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo::EcdsaP256,
                };
                let handle = lfs_os_security::windows::ncrypt_ssh::TpmSilentKeyHandle {
                    credential_name: name,
                    algo,
                    label: String::new(),
                };
                let _ = tokio::task::spawn_blocking(move || {
                    lfs_os_security::windows::ncrypt_ssh::delete_silent(&handle)
                })
                .await
                .map_err(|e| frb_err::wire(frb_err::kind::TPM, &format!("spawn_blocking: {e}")))?;
            }
        }
    }
    crate::api::db::run_db(move |c| lfs_core::db::ssh_keys::delete(c, &key_id))
        .await
        .map(|_| ())
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
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
    fn unsupported_platform_returns_for_non_linux_non_windows() {
        if cfg!(not(any(target_os = "linux", target_os = "windows"))) {
            let rt = tokio::runtime::Runtime::new().unwrap();
            let res = rt.block_on(tpm_ssh_probe()).unwrap();
            assert_eq!(res, DbTpmSshProbeResult::Unsupported);
        }
    }

    #[test]
    fn db_tpm_ssh_algorithm_variants_distinct() {
        assert_ne!(DbTpmSshAlgorithm::EcdsaP256, DbTpmSshAlgorithm::Rsa2048);
    }
}
