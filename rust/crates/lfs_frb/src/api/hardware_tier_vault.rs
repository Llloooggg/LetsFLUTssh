//! FRB adapter for the hardware-tier vault.
//!
//! Surfaces the unified `hardware_tier_vault_*` API consumed by the
//! Dart `HardwareTierVault` façade plus the small Linux blob
//! encode/decode helpers the TPM CLI driver still needs Dart-side.
//! Apple SE / Android Keystore implementations live in
//! `lfs_os_security`; Windows + Linux TPM still route through
//! Flutter MethodChannel plugins.

use lfs_core::security::hardware_tier_vault as vault;

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
/// (password, biometric) modifier combo. Returns `None` for an
/// inconsistent request (`password=true` without `typed_password`,
/// `biometric=true` without `fprintd_hash`); the empty `Vec` case
/// (passwordless isolation) surfaces as `Some([])`.
///
/// Same auth-value grammar the Linux TPM seal + the Apple /
/// Android / Windows method-channel plugins all derive against —
/// having the resolver Rust-side keeps every platform's vault
/// agreeing on the byte shape.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_resolve_auth_value(
    password: bool,
    biometric: bool,
    salt: Vec<u8>,
    typed_password: Option<String>,
    fprintd_hash: Option<Vec<u8>>,
) -> Option<Vec<u8>> {
    vault::resolve_auth_value(
        password,
        biometric,
        &salt,
        typed_password.as_deref(),
        fprintd_hash.as_deref(),
    )
}

// ---- Unified per-OS dispatch -------------------------------------
//
// Generic functions that route through `lfs_os_security::hardware_tier_vault`'s
// cfg-dispatched public API: Apple targets land on `apple::*`,
// Android targets land on `crate::android::hardware_vault::*`,
// every other target returns a `PlatformUnsupported` error. The
// Dart side calls these uniformly and only branches per-platform
// for the genuinely-different paths (Linux TPM2 via `TpmClient`,
// Windows hardware_vault MethodChannel until a Win Tier 4 Rust
// port lands).

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_is_available() -> bool {
    lfs_os_security::hardware_tier_vault::is_available()
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_probe_detail() -> String {
    lfs_os_security::hardware_tier_vault::probe_detail()
        .wire_name()
        .to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_is_stored(support_dir: String) -> bool {
    lfs_os_security::hardware_tier_vault::is_stored(&support_dir)
}

#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_is_biometric_password_stored(support_dir: String) -> bool {
    lfs_os_security::hardware_tier_vault::is_biometric_password_stored(&support_dir)
}

pub async fn hardware_tier_vault_store(
    support_dir: String,
    db_key: Vec<u8>,
    pin_hmac: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::store(&support_dir, &db_key, &pin_hmac)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hw_vault store join: {e}"))?
}

/// Variant of [`hardware_tier_vault_store`] that pulls `db_key` from
/// [`lfs_core::secrets::SecretStore`] under [`secret_id`] instead of
/// taking it across the FRB boundary. Same SecretRef shape as
/// [`super::secure_key_storage::secure_storage_write_from_secret`]
/// — bytes never touch the Dart heap on the way to the hardware
/// vault. The SecretStore entry survives the call so the caller can
/// also feed `secrets_take(id)` into drift's sqlcipher rekey before
/// dropping the ref.
pub async fn hardware_tier_vault_store_from_secret(
    support_dir: String,
    secret_id: String,
    pin_hmac: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let bytes = lfs_core::app::instance()
            .secrets
            .get(&secret_id)
            .ok_or_else(|| format!("secret not found: {secret_id}"))?;
        lfs_os_security::hardware_tier_vault::store(&support_dir, &bytes, &pin_hmac)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hw_vault store_from_secret join: {e}"))?
}

pub async fn hardware_tier_vault_read(
    support_dir: String,
    pin_hmac: Vec<u8>,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::read(&support_dir, &pin_hmac)
            .map_err(|e| e.to_string())
    })
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
    tokio::task::spawn_blocking(move || {
        match lfs_os_security::hardware_tier_vault::read(&support_dir, &pin_hmac)
            .map_err(|e| e.to_string())?
        {
            Some(bytes) if !bytes.is_empty() => {
                lfs_core::app::instance().secrets.put(&secret_id, &bytes);
                Ok::<_, String>(true)
            }
            _ => Ok(false),
        }
    })
    .await
    .map_err(|e| format!("hw_vault read_to_secret join: {e}"))?
}

pub async fn hardware_tier_vault_clear(support_dir: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::clear(&support_dir).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hw_vault clear join: {e}"))?
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
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hw_vault store_bio_pw join: {e}"))?
}

pub async fn hardware_tier_vault_read_biometric_password(
    support_dir: String,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::read_biometric_password(&support_dir)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hw_vault read_bio_pw join: {e}"))?
}

pub async fn hardware_tier_vault_clear_biometric_password(
    support_dir: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_os_security::hardware_tier_vault::clear_biometric_password(&support_dir)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("hw_vault clear_bio_pw join: {e}"))?
}
