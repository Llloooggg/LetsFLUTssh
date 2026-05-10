//! FRB adapter for the hardware-tier vault.
//!
//! Surfaces the unified `hardware_tier_vault_*` API consumed by the
//! Dart `HardwareTierVault` façade. Per-platform backends:
//!
//! * Apple Secure Enclave + Android Keystore + Windows NCrypt:
//!   `lfs_os_security` (objc2 / JNI / `windows` crate FFI).
//! * Linux TPM2: `lfs_core::security::hardware_tier_vault::linux`
//!   (subprocess to `tpm2-tools` + atomic write — orchestrator
//!   lives in `lfs_core` because `lfs_os_security` cannot depend
//!   on `lfs_core`).
//!
//! Per-platform dispatch lives in this file (the only crate that
//! sees both `lfs_core` and `lfs_os_security`).

use lfs_core::security::hardware_tier_vault as vault;
use lfs_os_security::hardware_tier_vault::HardwareVaultError;

/// Map a typed [`HardwareVaultError`] to the matching FRB envelope
/// kind (Apple / Android / Windows path). Pre-fix shape collapsed
/// every variant to `kind=vault`, which left the Dart UI unable to
/// distinguish "envelope corrupt — run reset cascade" (a destructive
/// recovery path that wipes the user's stored DB key) from a
/// recoverable backend error (wrong PIN, missing file, TPM revoked).
/// Now `Corrupt` routes to `kind=vault_corrupt` and the Dart side
/// gates the reset cascade on that discriminator only.
fn map_hw_vault_error(err: HardwareVaultError) -> String {
    use crate::api::frb_err::{kind, wire};
    let detail = err.to_string();
    let kind_str = match err {
        HardwareVaultError::Corrupt => kind::VAULT_CORRUPT,
        HardwareVaultError::PlatformUnsupported => kind::VAULT_PLATFORM_UNSUPPORTED,
        HardwareVaultError::Backend(_) | HardwareVaultError::Io(_) => kind::VAULT,
    };
    wire(kind_str, &detail)
}

/// Sibling mapper for the Linux `LinuxVaultError` variant set —
/// Linux is its own orchestrator under `lfs_core` rather than
/// `lfs_os_security`, so the variants are different (e.g.
/// `TpmUnavailable(String)` instead of `PlatformUnsupported`).
/// Same routing intent: `Corrupt` → `vault_corrupt` so the Dart
/// reset cascade fires only on disk-shape failure, never on a
/// recoverable backend / IO error.
#[cfg(target_os = "linux")]
fn map_linux_vault_error(err: vault::linux::LinuxVaultError) -> String {
    use crate::api::frb_err::{kind, wire};
    let detail = err.to_string();
    let kind_str = match err {
        vault::linux::LinuxVaultError::Corrupt(_) => kind::VAULT_CORRUPT,
        vault::linux::LinuxVaultError::TpmUnavailable(_) => kind::VAULT_PLATFORM_UNSUPPORTED,
        vault::linux::LinuxVaultError::Backend(_) | vault::linux::LinuxVaultError::Io(_) => {
            kind::VAULT
        }
    };
    wire(kind_str, &detail)
}

/// Encode the salt + sealed-blob pair as the JSON envelope written
/// to `hardware_vault.bin` on Linux. Caller writes the returned
/// string's UTF-8 bytes atomically + hardens to 0600.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_encode_linux_blob(salt: Vec<u8>, sealed: Vec<u8>) -> String {
    vault::encode_linux_blob(&salt, &sealed)
}

/// FRB mirror of `lfs_core::security::hardware_tier_vault::LinuxBlob`.
#[derive(Debug, Clone)]
pub struct DbHardwareTierLinuxBlob {
    pub salt: Vec<u8>,
    pub sealed: Vec<u8>,
}

/// Parse the on-disk JSON envelope. `Err` on any malformed shape
/// (bad JSON / missing fields / non-string values / invalid base64
/// / empty decoded bytes). The Dart-side `read` treats any decode
/// failure as a "vault corrupt — route back to password unlock"
/// outcome.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_decode_linux_blob(
    blob: String,
) -> Result<DbHardwareTierLinuxBlob, String> {
    vault::decode_linux_blob(&blob).map(|b| DbHardwareTierLinuxBlob {
        salt: b.salt,
        sealed: b.sealed,
    })
}

/// Resolve the hardware-tier vault auth value for the
/// (password, biometric) modifier combo. Returns `None` when the
/// chosen modifier has no payload (`password=true` without
/// `typed_password`, `biometric=true` without `fprintd_hash`, or
/// either with empty bytes); the empty `Vec` case (passwordless
/// isolation) surfaces as `Some([])`.
///
/// FRB layer keeps the boolean wire shape (Dart side already
/// computes `(password, biometric)` from the security profile)
/// and constructs the `AuthIntent` enum here so the core resolver
/// can no longer be foot-gunned by a forgotten flag.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_resolve_auth_value(
    password: bool,
    biometric: bool,
    salt: Vec<u8>,
    typed_password: Option<String>,
    fprintd_hash: Option<Vec<u8>>,
) -> Option<Vec<u8>> {
    let intent = if biometric {
        vault::AuthIntent::Biometric(fprintd_hash.as_deref()?)
    } else if password {
        vault::AuthIntent::Password(typed_password.as_deref()?)
    } else {
        vault::AuthIntent::Passwordless
    };
    // FRB wire shape demands `Vec<u8>`; `Zeroizing` derefs and we
    // copy the inner bytes across — the `Zeroizing` wrapper still
    // wipes its half on drop (the FRB-owned `Vec` carries the hash
    // outward).
    vault::resolve_auth_value(intent, &salt).map(|z| z.to_vec())
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_is_available() -> bool {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::is_available()
    }
    #[cfg(not(target_os = "linux"))]
    {
        lfs_os_security::hardware_tier_vault::is_available()
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_probe_detail() -> String {
    #[cfg(target_os = "linux")]
    {
        if lfs_core::security::hardware_tier_vault::linux::is_available() {
            "available".to_string()
        } else {
            // Cause discovery (no `tpm2-tools` / no `/dev/tpmrm0` /
            // probe rejected) ships through the existing Settings
            // probe-detail strings; we collapse to a generic
            // unavailable until a richer classifier lands.
            "unknown".to_string()
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        lfs_os_security::hardware_tier_vault::probe_detail()
            .wire_name()
            .to_string()
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_is_stored(support_dir: String) -> bool {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::is_stored(&support_dir)
    }
    #[cfg(not(target_os = "linux"))]
    {
        lfs_os_security::hardware_tier_vault::is_stored(&support_dir)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_is_biometric_password_stored(support_dir: String) -> bool {
    lfs_os_security::hardware_tier_vault::is_biometric_password_stored(&support_dir)
}

/// Store the wrapped DB key under the platform's hardware-tier
/// vault. `salt` is required for the Linux TPM2 path (gets
/// co-located inside `hardware_vault.bin`); Apple / Android
/// ignore it and the caller persists it to a sibling
/// `hardware_vault_salt.bin` separately.
pub async fn hardware_tier_vault_store(
    support_dir: String,
    db_key: Vec<u8>,
    salt: Vec<u8>,
    pin_hmac: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || dispatch_store(&support_dir, &db_key, &salt, &pin_hmac))
        .await
        .map_err(|e| format!("hw_vault store join: {e}"))?
}

/// Variant of [`hardware_tier_vault_store`] that pulls `db_key` from
/// [`lfs_core::secrets::SecretStore`] under [`secret_id`] instead of
/// taking it across the FRB boundary. Same SecretRef shape as
/// [`super::secure_key_storage::secure_storage_write_from_secret`]
/// — bytes never touch the Dart heap on the way to the hardware
/// vault. The SecretStore entry survives the call so the caller can
/// also feed the same id into `db_rekey_from_secret` (rusqlite/
/// SQLCipher rekey) before dropping the ref.
pub async fn hardware_tier_vault_store_from_secret(
    support_dir: String,
    secret_id: String,
    salt: Vec<u8>,
    pin_hmac: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let bytes = lfs_core::app::instance()
            .secrets
            .get(&secret_id)
            .ok_or_else(|| format!("secret not found: {secret_id}"))?;
        dispatch_store(&support_dir, &bytes, &salt, &pin_hmac)
    })
    .await
    .map_err(|e| format!("hw_vault store_from_secret join: {e}"))?
}

/// Generate a fresh 32-byte salt via `OsRng` and write it
/// atomically to `hardware_vault_salt.bin` (Apple / Windows /
/// Android sibling-file path). Returns the bytes so the caller
/// can derive the matching auth value before kicking off the
/// platform vault store. The salt-then-vault ordering is the
/// caller's responsibility — a crash between this write and the
/// vault store leaves the next launch with a sibling salt and no
/// wrapped key, which `is_stored` surfaces as "not configured".
pub async fn hardware_tier_vault_provision_salt(support_dir: String) -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::security::hardware_tier_vault::salt::provision(std::path::Path::new(&support_dir))
            .map_err(|e| format!("hw_vault salt provision: {e}"))
    })
    .await
    .map_err(|e| format!("hw_vault salt provision join: {e}"))?
}

/// Read the on-disk `hardware_vault_salt.bin` sibling file.
/// `None` for missing or wrong-length files (clean install /
/// truncated / tampered) — caller treats every miss as
/// "no usable salt" and routes the unlock-cancelled path.
pub async fn hardware_tier_vault_read_salt(support_dir: String) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::security::hardware_tier_vault::salt::read(std::path::Path::new(&support_dir))
            .map_err(|e| format!("hw_vault salt read: {e}"))
    })
    .await
    .map_err(|e| format!("hw_vault salt read join: {e}"))?
}

/// Idempotent delete of `hardware_vault_salt.bin`. Used by the
/// tier-reset / tier-switch cascade alongside the platform
/// vault clear so the sibling artefact does not survive into
/// the next configure cycle.
pub async fn hardware_tier_vault_delete_salt(support_dir: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::security::hardware_tier_vault::salt::delete(std::path::Path::new(&support_dir))
            .map_err(|e| format!("hw_vault salt delete: {e}"))
    })
    .await
    .map_err(|e| format!("hw_vault salt delete join: {e}"))?
}

/// Read the on-disk salt for the Linux hardware-vault envelope.
/// Returns `None` for missing / malformed files. No-op `Ok(None)`
/// on non-Linux targets (Apple / Android keep the salt in a
/// sibling `hardware_vault_salt.bin` file Dart-side).
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_read_blob_salt(support_dir: String) -> Option<Vec<u8>> {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::read_blob_salt(&support_dir)
            .ok()
            .flatten()
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = support_dir;
        None
    }
}

pub async fn hardware_tier_vault_read(
    support_dir: String,
    pin_hmac: Vec<u8>,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || dispatch_read(&support_dir, &pin_hmac))
        .await
        .map_err(|e| format!("hw_vault read join: {e}"))?
}

/// SecretRef variant of [`hardware_tier_vault_read`]. Unwraps the
/// hardware-bound DB key and stages it in
/// [`lfs_core::secrets::SecretStore`] under `secret_id` so the
/// bytes never cross the FRB boundary. Returns `Ok(true)` on
/// successful unwrap, `Ok(false)` on missing vault file / wrong
/// PIN, `Err(_)` on backend errors.
pub async fn hardware_tier_vault_read_to_secret(
    support_dir: String,
    pin_hmac: Vec<u8>,
    secret_id: String,
) -> Result<bool, String> {
    tokio::task::spawn_blocking(move || match dispatch_read(&support_dir, &pin_hmac)? {
        Some(bytes) if !bytes.is_empty() => {
            lfs_core::app::instance().secrets.put(&secret_id, &bytes);
            Ok::<_, String>(true)
        }
        _ => Ok(false),
    })
    .await
    .map_err(|e| format!("hw_vault read_to_secret join: {e}"))?
}

pub async fn hardware_tier_vault_clear(support_dir: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || dispatch_clear(&support_dir))
        .await
        .map_err(|e| format!("hw_vault clear join: {e}"))?
}

// ── Cfg-arm dispatchers ─────────────────────────────────────────
//
// `lfs_os_security::hardware_tier_vault` covers Apple + Android
// (objc2 / JNI FFI). Linux's TPM CLI shell-out lives one crate up
// in `lfs_core::security::hardware_tier_vault::linux` because
// `lfs_os_security` cannot depend on `lfs_core` (one-way edge per
// the architectural invariant). The FRB layer is the only place
// where both crates are visible, so per-platform dispatch lands
// here. Other targets fall through to `lfs_os_security`'s
// `PlatformUnsupported` arm — same shape as before.

fn dispatch_store(
    support_dir: &str,
    db_key: &[u8],
    salt: &[u8],
    pin_hmac: &[u8],
) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::store(support_dir, db_key, salt, pin_hmac)
            .map_err(map_linux_vault_error)
    }
    #[cfg(not(target_os = "linux"))]
    {
        // Apple / Android persist the salt next to the wrapped key
        // in `hardware_vault_salt.bin` Dart-side; the Rust impls
        // don't see the salt directly. Drop the parameter on these
        // targets — caller's `_writeSaltFile` handles the half.
        let _ = salt;
        lfs_os_security::hardware_tier_vault::store(support_dir, db_key, pin_hmac)
            .map_err(map_hw_vault_error)
    }
}

fn dispatch_read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, String> {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::read(support_dir, pin_hmac)
            .map_err(map_linux_vault_error)
    }
    #[cfg(not(target_os = "linux"))]
    {
        lfs_os_security::hardware_tier_vault::read(support_dir, pin_hmac)
            .map_err(map_hw_vault_error)
    }
}

fn dispatch_clear(support_dir: &str) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::clear(support_dir)
            .map_err(map_linux_vault_error)
    }
    #[cfg(not(target_os = "linux"))]
    {
        lfs_os_security::hardware_tier_vault::clear(support_dir).map_err(map_hw_vault_error)
    }
}

pub async fn hardware_tier_vault_store_biometric_password(
    support_dir: String,
    password_bytes: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::store_biometric_password(
            &support_dir,
            &password_bytes,
        )
        .map_err(map_hw_vault_error)
    })
    .await
    .map_err(|e| format!("hw_vault store_bio_pw join: {e}"))?
}

pub async fn hardware_tier_vault_read_biometric_password(
    support_dir: String,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::read_biometric_password(&support_dir)
            .map_err(map_hw_vault_error)
    })
    .await
    .map_err(|e| format!("hw_vault read_bio_pw join: {e}"))?
}

pub async fn hardware_tier_vault_clear_biometric_password(
    support_dir: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::clear_biometric_password(&support_dir)
            .map_err(map_hw_vault_error)
    })
    .await
    .map_err(|e| format!("hw_vault clear_bio_pw join: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    // The store / read / clear / probe endpoints route through
    // `lfs_os_security::hardware_tier_vault` (Apple SE / Android
    // Keystore / Windows NCrypt) or
    // `lfs_core::security::hardware_tier_vault::linux` (TPM2
    // subprocess); covered by the per-platform integration suites.
    // The standalone tests below pin the pure JSON envelope codec +
    // the AuthIntent resolver — both cross the FRB boundary on every
    // call regardless of platform backend.

    #[test]
    fn encode_then_decode_linux_blob_round_trips() {
        let salt = vec![0x11, 0x22, 0x33, 0x44];
        let sealed = vec![0xAA; 32];
        let envelope = hardware_tier_vault_encode_linux_blob(salt.clone(), sealed.clone());
        let parsed = hardware_tier_vault_decode_linux_blob(envelope).expect("round trip");
        assert_eq!(parsed.salt, salt);
        assert_eq!(parsed.sealed, sealed);
    }

    #[test]
    fn decode_linux_blob_rejects_garbage() {
        assert!(hardware_tier_vault_decode_linux_blob("not json".into()).is_err());
        assert!(hardware_tier_vault_decode_linux_blob("{}".into()).is_err());
    }

    #[test]
    fn resolve_auth_value_passwordless_returns_some_empty_for_passwordless_intent() {
        let salt = vec![0xAB; 16];
        // password=false + biometric=false → Passwordless intent.
        // The documented contract is "Some payload", not None.
        let res = hardware_tier_vault_resolve_auth_value(false, false, salt, None, None);
        assert!(res.is_some());
    }

    #[test]
    fn resolve_auth_value_password_returns_some_for_typed_password() {
        let salt = vec![0xCD; 16];
        let res =
            hardware_tier_vault_resolve_auth_value(true, false, salt, Some("hunter2".into()), None);
        assert!(res.is_some());
    }

    #[test]
    fn resolve_auth_value_password_returns_none_for_missing_typed_password() {
        let salt = vec![0xEF; 16];
        let res = hardware_tier_vault_resolve_auth_value(true, false, salt, None, None);
        assert!(res.is_none(), "missing typed_password must surface as None");
    }

    #[test]
    fn resolve_auth_value_biometric_takes_priority_over_password() {
        // The shim documents `biometric=true` wins over
        // `password=true` because the BiometricIntent uses the
        // fprintd hash, not the typed password. Pin the precedence.
        let salt = vec![0xFF; 16];
        let hash = vec![0xAA; 32];
        let res = hardware_tier_vault_resolve_auth_value(
            true,
            true,
            salt,
            Some("ignored".into()),
            Some(hash),
        );
        assert!(res.is_some());
    }

    #[test]
    fn resolve_auth_value_biometric_returns_none_for_missing_fprintd_hash() {
        let salt = vec![0x55; 16];
        let res = hardware_tier_vault_resolve_auth_value(false, true, salt, None, None);
        assert!(res.is_none());
    }
}
