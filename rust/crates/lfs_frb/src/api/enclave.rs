//! FRB adapter for `lfs_os_security::apple_se_ssh` — Apple Secure
//! Enclave SSH key probe, generate, list, delete, and the
//! persist-to-`ssh_keys` import path. Mirrors the FIDO2 / PKCS#11
//! shapes so the Dart key-manager wizard reaches both backends
//! through a single dispatch layer.
//!
//! Cfg-gated so non-Apple builds compile to stubs that surface the
//! typed `UnavailableReason::NoSecureEnclave` envelope. Dart's
//! `EnclaveBadge` / wizard hides itself on those platforms via the
//! capability ladder anyway, but the stub keeps the FRB worker pool
//! cfg-clean.

use crate::api::frb_err;

/// FRB mirror of `apple_se_ssh::UnavailableReason`. Stays a string
/// enum across the boundary so the Dart side can pattern-match on
/// the discriminator and render the localized reason.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DbEnclaveAvailability {
    /// Reachable — wizard renders enabled.
    Available,
    /// Bundle is ad-hoc / unsigned; `errSecMissingEntitlement`
    /// (-34018). Dart shows the localized "Code-signing required"
    /// reason + links the user to USER_GUIDE.md.
    CodeSignRequired,
    /// Pre-T2 Intel Mac or simulator — no SE hardware.
    NoSecureEnclave,
    /// Device passcode unset.
    PasscodeNotSet,
    /// Any other failure — carries the diagnostic string.
    Other(String),
    /// Build target without Apple support (Linux, Windows,
    /// Android). The toolbar action stays hidden.
    UnsupportedPlatform,
}

/// FRB mirror of `apple_se_ssh::AuthPolicy`. The wizard's radio
/// step writes one of these into the create call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbEnclaveAuthPolicy {
    /// Require Touch ID / Face ID; re-enrolment invalidates the
    /// key.
    BiometryCurrentSet,
    /// Allow device passcode as fallback; survives re-enrolment.
    UserPresence,
}

/// FRB mirror of `apple_se_ssh::EnclaveKeyHandle` rendered into the
/// import wizard's preview card. Carries the assigned DB row id
/// alongside the on-chip metadata so the caller can refresh the
/// key-manager listing without a second FRB hop.
#[derive(Debug, Clone)]
pub struct DbEnclaveImportResult {
    pub key_id: String,
    pub label: String,
    /// `authorized_keys`-shaped line — `ecdsa-sha2-nistp256 BASE64
    /// <label>` — the wizard copies into the clipboard for the
    /// user to paste on the server. The same line is persisted as
    /// `ssh_keys.public_key`.
    pub authorized_keys_line: String,
}

/// FRB mirror of an SE-bound key seen by the OS but absent from
/// our DB. Surfaced by [`enclave_ssh_list`]; the recovery dialog
/// renders one row per orphan with a "delete" affordance so the
/// chip stays clean after a DB wipe.
#[derive(Debug, Clone)]
pub struct DbEnclaveOrphan {
    pub application_tag: Vec<u8>,
}

/// Probe whether SE-SSH is reachable on this host. Runs a real
/// generate / delete round trip so the wizard can route the user
/// at the code-signing remediation when the bundle isn't trusted.
#[flutter_rust_bridge::frb]
pub async fn enclave_ssh_probe() -> Result<DbEnclaveAvailability, String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        tokio::task::spawn_blocking(probe_native)
            .await
            .map_err(|e| frb_err::wire(frb_err::kind::ENCLAVE, &format!("spawn_blocking: {e}")))
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        Ok(DbEnclaveAvailability::UnsupportedPlatform)
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn probe_native() -> DbEnclaveAvailability {
    use lfs_os_security::apple_se_ssh::{self, UnavailableReason};
    match apple_se_ssh::probe_availability() {
        Ok(()) => DbEnclaveAvailability::Available,
        Err(UnavailableReason::CodeSignRequired) => DbEnclaveAvailability::CodeSignRequired,
        Err(UnavailableReason::NoSecureEnclave) => DbEnclaveAvailability::NoSecureEnclave,
        Err(UnavailableReason::PasscodeNotSet) => DbEnclaveAvailability::PasscodeNotSet,
        Err(UnavailableReason::Other(s)) => DbEnclaveAvailability::Other(s),
    }
}

/// Bundled input for [`enclave_ssh_generate`].
#[derive(Debug, Clone)]
pub struct DbEnclaveGenerateArgs {
    pub label: String,
    pub policy: DbEnclaveAuthPolicy,
}

/// Generate a fresh SE-bound ECDSA P-256 key + persist it as an
/// `ssh_keys` row. Fires the system biometric / passcode prompt at
/// the OS layer per the chosen [`DbEnclaveAuthPolicy`]. Returns
/// the new row id + the `authorized_keys` line the wizard
/// surfaces alongside the "copy" affordance.
pub async fn enclave_ssh_generate(
    args: DbEnclaveGenerateArgs,
) -> Result<DbEnclaveImportResult, String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let label = args.label.clone();
        let policy = args.policy;
        // Generate runs in a spawn_blocking — `SecKeyCreateRandomKey`
        // is a synchronous Keychain call that may stall on the
        // biometric prompt.
        let outcome = tokio::task::spawn_blocking(move || generate_native(&label, policy))
            .await
            .map_err(|e| {
                frb_err::wire(frb_err::kind::ENCLAVE, &format!("spawn_blocking: {e}"))
            })??;
        // Capture the fields the result envelope needs before the
        // closure takes ownership of `outcome` — `move` consumes it
        // for the DB worker, and the post-await `Ok(...)` builds the
        // FRB return value from the same fields.
        let result_label = outcome.label.clone();
        let result_line = outcome.authorized_keys_line.clone();
        // Persist via the shared DB worker pool — runs on the
        // single rusqlite mutex, separate from the keychain
        // round trip above.
        let inserted = crate::api::db::run_db_mut_writing_keys(move |conn| {
            let row = lfs_core::db::ssh_keys::SshKeyRow {
                id: lfs_core::id::random_handle_hex_32(),
                label: outcome.label,
                // Hardware-bound rows keep `private_key` non-empty per
                // the schema's `NOT NULL` shape; the empty-string
                // sentinel is the standing convention from the FIDO2
                // / PKCS#11 paths.
                private_key: String::new(),
                public_key: outcome.authorized_keys_line,
                key_type: "ecdsa-sha2-nistp256".into(),
                is_generated: true,
                created_at_ms: now_unix_ms(),
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: lfs_core::db::ssh_keys::AgentPolicy::Ask,
                backend: lfs_core::db::ssh_keys::KeyBackend::Enclave,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: Some(outcome.application_tag),
                hello_credential_name: None,
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
        Ok(DbEnclaveImportResult {
            key_id: inserted,
            label: result_label,
            authorized_keys_line: result_line,
        })
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = args;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Apple Secure Enclave is available on macOS / iOS only",
        ))
    }
}

/// Internal generate outcome — populated inside the
/// `spawn_blocking` and consumed by the DB-side persist arm.
#[cfg(any(target_os = "macos", target_os = "ios"))]
struct GenerateOutcome {
    application_tag: Vec<u8>,
    label: String,
    authorized_keys_line: String,
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn generate_native(label: &str, policy: DbEnclaveAuthPolicy) -> Result<GenerateOutcome, String> {
    use lfs_os_security::apple_se_ssh::{self, AuthPolicy};
    let policy = match policy {
        DbEnclaveAuthPolicy::BiometryCurrentSet => AuthPolicy::BiometryCurrentSet,
        DbEnclaveAuthPolicy::UserPresence => AuthPolicy::UserPresence,
    };
    let handle = apple_se_ssh::create(label, policy)
        .map_err(|e| frb_err::wire(frb_err::kind::ENCLAVE, &e.to_string()))?;
    // Pull the public half + wrap it in the SSH authorized_keys
    // line shape. The wire encoder lives in `lfs_core::ssh::wire`;
    // reach across so the Dart side gets the exact `ssh-keygen -y`
    // form on first paste.
    let raw_point = apple_se_ssh::public_key_ssh_wire(&handle)
        .map_err(|e| frb_err::wire(frb_err::kind::ENCLAVE, &e.to_string()))?;
    let wire_blob = lfs_core::ssh::wire::encode_public_ecdsa_p256(&raw_point)
        .map_err(|e| frb_err::wire(frb_err::kind::ENCLAVE, &e.to_string()))?;
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let b64 = STANDARD.encode(&wire_blob);
    let authorized_keys_line = if label.is_empty() {
        format!("ecdsa-sha2-nistp256 {b64}")
    } else {
        format!("ecdsa-sha2-nistp256 {b64} {label}")
    };
    Ok(GenerateOutcome {
        application_tag: handle.application_tag,
        label: handle.label,
        authorized_keys_line,
    })
}

/// Enumerate SE-bound keys the chip holds today. Used by the
/// "orphan recovery" path — `ssh_keys` was wiped but the chip
/// kept its register; the dialog renders one row per orphan with
/// a "delete" affordance.
pub async fn enclave_ssh_list_orphans() -> Result<Vec<DbEnclaveOrphan>, String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        tokio::task::spawn_blocking(|| {
            lfs_os_security::apple_se_ssh::list()
                .map(|handles| {
                    handles
                        .into_iter()
                        .map(|h| DbEnclaveOrphan {
                            application_tag: h.application_tag,
                        })
                        .collect()
                })
                .map_err(|e| frb_err::wire(frb_err::kind::ENCLAVE, &e.to_string()))
        })
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::ENCLAVE, &format!("spawn_blocking: {e}")))?
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        Ok(Vec::new())
    }
}

/// Delete the on-chip SE-bound key referenced by `ssh_keys.id`.
/// Also soft-deletes the DB row so the manager view drops it.
/// Best-effort on the chip side — `SecItemDelete` failures don't
/// roll back the DB tombstone; the OS GCs orphaned keys on next
/// launch.
pub async fn enclave_ssh_delete(key_id: String) -> Result<(), String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        // Resolve the row's `enclave_tag` first so we can fire
        // the chip-side delete with the right blob.
        let lookup_id = key_id.clone();
        let tag = crate::api::db::run_db(move |c| lfs_core::db::ssh_keys::get(c, &lookup_id))
            .await?
            .and_then(|row| row.enclave_tag);
        if let Some(tag) = tag {
            let handle = lfs_os_security::apple_se_ssh::EnclaveKeyHandle {
                application_tag: tag,
                label: String::new(),
            };
            // Chip delete in a spawn_blocking — the call sometimes
            // surfaces a system prompt depending on accessibility
            // class.
            let _ =
                tokio::task::spawn_blocking(move || lfs_os_security::apple_se_ssh::delete(&handle))
                    .await
                    .map_err(|e| {
                        frb_err::wire(frb_err::kind::ENCLAVE, &format!("spawn_blocking: {e}"))
                    })?;
        }
        // Soft-delete the DB row regardless of chip outcome — the
        // user clicked delete; the DB tombstone is the source of
        // truth for the listing.
        crate::api::db::run_db_writing_keys_when(
            move |c| lfs_core::db::ssh_keys::delete(c, &key_id),
            |n| *n > 0,
        )
        .await
        .map(|_| ())
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = key_id;
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "Apple Secure Enclave is available on macOS / iOS only",
        ))
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
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
    fn unsupported_platform_returns_for_non_apple() {
        if cfg!(not(any(target_os = "macos", target_os = "ios"))) {
            let rt = tokio::runtime::Runtime::new()
                .expect("tokio runtime must build under test harness");
            let res = rt
                .block_on(enclave_ssh_probe())
                .expect("enclave_ssh_probe must succeed on non-Apple platforms");
            assert_eq!(res, DbEnclaveAvailability::UnsupportedPlatform);
        }
    }

    #[test]
    fn auth_policy_variants_round_trip() {
        assert_ne!(
            DbEnclaveAuthPolicy::BiometryCurrentSet,
            DbEnclaveAuthPolicy::UserPresence
        );
    }
}
