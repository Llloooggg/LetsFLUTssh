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
#[cfg(not(target_os = "linux"))]
use lfs_os_security::hardware_tier_vault::HardwareVaultError;

/// Map a typed [`HardwareVaultError`] to the matching FRB envelope
/// kind (Apple / Android / Windows path). Pre-fix shape collapsed
/// every variant to `kind=vault`, which left the Dart UI unable to
/// distinguish "envelope corrupt — run reset cascade" (a destructive
/// recovery path that wipes the user's stored DB key) from a
/// recoverable backend error (wrong PIN, missing file, TPM revoked).
/// Now `Corrupt` routes to `kind=vault_corrupt` and the Dart side
/// gates the reset cascade on that discriminator only.
#[cfg(not(target_os = "linux"))]
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
        vault::linux::LinuxVaultError::TpmUnavailable(_)
        | vault::linux::LinuxVaultError::FprintdUnavailable => kind::VAULT_PLATFORM_UNSUPPORTED,
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
/// (password, biometric) modifier combo. Returns `None` when
/// the chosen modifier has no payload — `password=true` without
/// `typed_password`, `biometric=true` without `fprintd_hash`,
/// either with empty bytes, **or** `password=false &&
/// biometric=false` (the Hardware tier is always password-gated;
/// a "no-secret" call is a misuse).
///
/// FRB layer keeps the boolean wire shape (Dart side already
/// computes `(password, biometric)` from the security profile)
/// and constructs the `AuthIntent` enum here so the core
/// resolver can no longer be foot-gunned by a forgotten flag.
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
        // Hardware tier is always password-gated — no passwordless
        // arm. Routes "no secret" callers through the "modifier
        // resolution failed" branch (None) so the unlock path can
        // surface the password dialog rather than sealing under
        // an empty auth-value.
        return None;
    };
    // FRB wire shape demands `Vec<u8>`; `Zeroizing` derefs and we
    // copy the inner bytes across — the `Zeroizing` wrapper still
    // wipes its half on drop (the FRB-owned `Vec` carries the hash
    // outward).
    vault::resolve_auth_value(intent, &salt).map(|z| z.to_vec())
}

// The four probe endpoints below run as plain async FRB calls and
// route through `tokio::task::spawn_blocking`. The inner per-platform
// implementations are synchronous and may block: Windows wakes the
// TBS / TPM driver inside `NCryptOpenStorageProvider`, which can
// stall hundreds of milliseconds to several seconds on the cold-path;
// Apple Secure Enclave / Android Keystore probes are similarly
// blocking objc2 / JNI calls; Linux shells out to `tpm2-tools`.
// Marking these `#[frb(sync)]` would run them on the Dart UI isolate
// and freeze the UI for the same duration — so they intentionally
// stay async, mirroring the existing `store` / `read` / `clear`
// shims.

pub async fn hardware_tier_vault_is_available() -> bool {
    tokio::task::spawn_blocking(|| {
        #[cfg(target_os = "linux")]
        {
            lfs_core::security::hardware_tier_vault::linux::is_available()
        }
        #[cfg(not(target_os = "linux"))]
        {
            lfs_os_security::hardware_tier_vault::is_available()
        }
    })
    .await
    .unwrap_or(false)
}

pub async fn hardware_tier_vault_probe_detail() -> String {
    tokio::task::spawn_blocking(|| {
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
    })
    .await
    .unwrap_or_else(|_| "unknown".to_string())
}

pub async fn hardware_tier_vault_is_stored(support_dir: String) -> bool {
    tokio::task::spawn_blocking(move || {
        #[cfg(target_os = "linux")]
        {
            lfs_core::security::hardware_tier_vault::linux::is_stored(&support_dir)
        }
        #[cfg(not(target_os = "linux"))]
        {
            lfs_os_security::hardware_tier_vault::is_stored(&support_dir)
        }
    })
    .await
    .unwrap_or(false)
}

pub async fn hardware_tier_vault_is_biometric_password_stored(support_dir: String) -> bool {
    tokio::task::spawn_blocking(move || {
        #[cfg(target_os = "linux")]
        {
            lfs_core::security::hardware_tier_vault::linux::is_biometric_password_stored(
                &support_dir,
            )
        }
        #[cfg(not(target_os = "linux"))]
        {
            lfs_os_security::hardware_tier_vault::is_biometric_password_stored(&support_dir)
        }
    })
    .await
    .unwrap_or(false)
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

/// Combined provision-salt + derive-auth + store. Keeps the PIN
/// String inside the Rust process — it crosses FRB once into this
/// call, the HMAC happens here under the freshly provisioned salt,
/// and the auth value never leaves Rust. Mirrors the salt-then-vault
/// ordering documented on [`hardware_tier_vault_provision_salt`]:
/// a crash between the salt write and the platform store leaves the
/// `is_stored` probe surfacing "not configured" so the next attempt
/// re-provisions cleanly.
///
/// Empty `pin` resolves to an empty auth value — the passwordless
/// arm preserved for the bank-style modifier model. An attacker
/// still needs TPM / Secure Enclave access to unseal (cold-disk
/// theft is still mitigated); there is simply no user-typed gate
/// on top.
pub async fn hardware_tier_vault_store_with_pin(
    support_dir: String,
    db_key: Vec<u8>,
    pin: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let dir = std::path::Path::new(&support_dir);
        let salt = lfs_core::security::hardware_tier_vault::salt::provision(dir)
            .map_err(|e| format!("hw_vault salt provision: {e}"))?;
        let auth = derive_auth_for_pin(&pin, &salt);
        dispatch_store(&support_dir, &db_key, &salt, &auth)
    })
    .await
    .map_err(|e| format!("hw_vault store_with_pin join: {e}"))?
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

/// SecretRef + combined-PIN variant of [`hardware_tier_vault_store`].
/// Pulls the DB key from [`lfs_core::secrets::SecretStore`] under
/// `secret_id` and HMACs the typed `pin` under a freshly provisioned
/// salt — both the DB-key bytes and the auth value stay Rust-side.
/// PIN crosses FRB once into this call and never returns.
pub async fn hardware_tier_vault_store_from_secret_with_pin(
    support_dir: String,
    secret_id: String,
    pin: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let dir = std::path::Path::new(&support_dir);
        let bytes = lfs_core::app::instance()
            .secrets
            .get(&secret_id)
            .ok_or_else(|| format!("secret not found: {secret_id}"))?;
        let salt = lfs_core::security::hardware_tier_vault::salt::provision(dir)
            .map_err(|e| format!("hw_vault salt provision: {e}"))?;
        let auth = derive_auth_for_pin(&pin, &salt);
        dispatch_store(&support_dir, &bytes, &salt, &auth)
    })
    .await
    .map_err(|e| format!("hw_vault store_from_secret_with_pin join: {e}"))?
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

/// Combined read-salt + derive-auth + unseal. Resolves the on-disk
/// salt for the current target (Linux pulls it from inside
/// `hardware_vault.bin`; Apple / Android / Windows read the sibling
/// `hardware_vault_salt.bin`), HMACs `pin` under that salt, and asks
/// the platform vault to unwrap the DB key. PIN crosses FRB once
/// into this call and never returns.
///
/// `Ok(None)` covers every miss the existing
/// [`hardware_tier_vault_read`] returns `Ok(None)` for (missing
/// salt / vault, wrong PIN). Empty `pin` derives the empty
/// auth value — a vault sealed under the passwordless arm unseals
/// the same way.
pub async fn hardware_tier_vault_read_with_pin(
    support_dir: String,
    pin: String,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        let Some(salt) = read_existing_salt(&support_dir)? else {
            return Ok(None);
        };
        let auth = derive_auth_for_pin(&pin, &salt);
        dispatch_read(&support_dir, &auth)
    })
    .await
    .map_err(|e| format!("hw_vault read_with_pin join: {e}"))?
}

/// Derive the platform-vault auth value from a user-typed PIN +
/// per-install salt. Routes the non-empty path through
/// [`lfs_core::security::hardware_tier_vault::resolve_auth_value`]
/// so the HMAC composition lives one place across the password-only
/// and combined-PIN paths. Empty PIN short-circuits to an empty
/// auth value — the passwordless arm; `resolve_auth_value` rejects
/// an empty `AuthIntent::Password` payload as "modifier resolution
/// failed", and the combined call needs the stable empty-bytes
/// shape so a vault sealed passwordless unseals passwordless.
fn derive_auth_for_pin(pin: &str, salt: &[u8]) -> Vec<u8> {
    if pin.is_empty() {
        return Vec::new();
    }
    lfs_core::security::hardware_tier_vault::resolve_auth_value(
        lfs_core::security::hardware_tier_vault::AuthIntent::Password(pin),
        salt,
    )
    // The empty-payload arm is unreachable above; resolve falls
    // through to the password HMAC and returns `Some`.
    .map(|z| z.to_vec())
    .unwrap_or_default()
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
    #[cfg(target_os = "linux")]
    {
        // Linux overlay is async — the fprintd D-Bus probe + TPM2
        // seal both happen inside the orchestrator (the seal half
        // already `spawn_blocking`s itself).
        lfs_core::security::hardware_tier_vault::linux::store_biometric_password(
            &support_dir,
            &password_bytes,
        )
        .await
        .map_err(map_linux_vault_error)
    }
    #[cfg(not(target_os = "linux"))]
    {
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
}

pub async fn hardware_tier_vault_read_biometric_password(
    support_dir: String,
) -> Result<Option<Vec<u8>>, String> {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::read_biometric_password(&support_dir)
            .await
            .map_err(map_linux_vault_error)
    }
    #[cfg(not(target_os = "linux"))]
    {
        tokio::task::spawn_blocking(move || {
            lfs_os_security::hardware_tier_vault::read_biometric_password(&support_dir)
                .map_err(map_hw_vault_error)
        })
        .await
        .map_err(|e| format!("hw_vault read_bio_pw join: {e}"))?
    }
}

pub async fn hardware_tier_vault_clear_biometric_password(
    support_dir: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        #[cfg(target_os = "linux")]
        {
            lfs_core::security::hardware_tier_vault::linux::clear_biometric_password(&support_dir)
                .map_err(map_linux_vault_error)
        }
        #[cfg(not(target_os = "linux"))]
        {
            lfs_os_security::hardware_tier_vault::clear_biometric_password(&support_dir)
                .map_err(map_hw_vault_error)
        }
    })
    .await
    .map_err(|e| format!("hw_vault clear_bio_pw join: {e}"))?
}

// ── v6 → v7 password-set wizard ────────────────────────────────
//
// The migration leaves a Hardware-tier install with the wrapped key
// sealed under the empty PIN-HMAC: there is no live password the
// bootstrap could derive from. The wizard runs once, asks the user
// for a fresh password, and re-seals the same DB key under the new
// auth value. The plaintext DB key never crosses the FRB boundary —
// it is unsealed, re-sealed, and dropped all inside the
// `spawn_blocking` task.
//
// Re-seal contract:
// 1. Read the on-disk salt (Linux: inside the envelope; others:
//    sibling `hardware_vault_salt.bin`).
// 2. Read the existing vault under `pin_hmac = HMAC(salt, "")`.
// 3. Clear the vault (drops the platform-bound persistent key on
//    NCrypt / Keystore / SE; drops the on-disk envelope on every
//    target) and any sibling salt file.
// 4. Provision a fresh salt, derive `pin_hmac = HMAC(new_salt, pw)`,
//    store the same DB key under the new auth value.
// 5. On full success, clear the marker so the next bootstrap routes
//    the regular unlock path.
//
// Any step short of (5) leaves the marker in place and the previous
// vault state intact (steps 3/4 are atomic on disk) so a crash mid-
// re-seal lets the user retry rather than wiping their data.

/// True when the v6 → v7 password-set wizard needs to run before
/// the regular Hardware-tier unlock path. Sync because the probe is
/// a pure path-stat under the pinned support_dir — bootstrap calls
/// this once before `unlock_hardware` to avoid a rate-limited
/// round-trip against a vault that no live password can unseal.
/// Returns `false` when the pin is missing (cold-start ordering
/// misorder), mirroring the path-absent shape so a misordered call
/// never spuriously kicks off the wizard.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_password_set_wizard_required() -> bool {
    let Ok(dir) = lfs_core::app::instance().support_dir() else {
        return false;
    };
    vault::hardware_password_set_wizard_required(dir)
}

/// Clear the v6 → v7 password-set marker. Idempotent — a missing
/// target is treated as success. Caller fires this only after the
/// re-seal succeeded; surfacing the call separately keeps the
/// wizard widget's success path explicit (no hidden side effect
/// inside `reseal_with_password`).
pub async fn hardware_tier_vault_clear_password_set_marker(
    support_dir: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        vault::clear_v6_v7_password_set_marker(std::path::Path::new(&support_dir))
            .map_err(|e| format!("clear hw v7 marker: {e}"))
    })
    .await
    .map_err(|e| format!("clear hw v7 marker join: {e}"))?
}

/// Re-seal the Hardware-tier vault under a freshly-typed password.
///
/// Used by the v6 → v7 password-set wizard. Reads the existing
/// vault under the empty PIN-HMAC the migration left behind, drops
/// the vault + sibling salt, provisions a fresh salt, and re-stores
/// the same DB key under `HMAC(new_salt, new_password)`.
///
/// Returns `Err(_)` if any step fails — the marker stays in place
/// (the caller never reaches the `clear_password_set_marker` call),
/// the vault is either fully under the empty PIN-HMAC (steps 1-2
/// failed) or fully under the new password (steps 3-5 succeeded).
/// A new-password that arrives empty short-circuits as
/// `Err("password must not be empty")` — the contract mirrors
/// `unlock_hardware`'s typed-secret invariant.
pub async fn hardware_tier_vault_reseal_with_password(
    support_dir: String,
    new_password: String,
) -> Result<(), String> {
    if new_password.is_empty() {
        return Err("password must not be empty".to_string());
    }
    tokio::task::spawn_blocking(move || reseal_blocking(&support_dir, &new_password))
        .await
        .map_err(|e| format!("hw_vault reseal join: {e}"))?
}

fn reseal_blocking(support_dir: &str, new_password: &str) -> Result<(), String> {
    let dir = std::path::Path::new(support_dir);
    // Step 1 — read salt the migration left behind.
    let old_salt = read_existing_salt(support_dir)?
        .ok_or_else(|| "reseal: no salt on disk (vault was already wiped)".to_string())?;
    // Step 2 — unseal with empty PIN-HMAC. The v6 vault was sealed
    // under HMAC(salt, "") which `resolve_auth_value` rejects as
    // "no secret"; we compute the same empty-payload HMAC inline
    // here so the read path mirrors what v6 wrote.
    let empty_pin_hmac = lfs_core::crypto::hmac_sha256(&old_salt, b"");
    let db_key = dispatch_read(support_dir, empty_pin_hmac.as_slice())?
        .ok_or_else(|| "reseal: vault read returned no key (already re-sealed?)".to_string())?;
    // Step 3 — drop the old vault + sibling salt so the salt-then-
    // vault provisioning below starts from a clean slate. Linux's
    // salt rides inside the envelope so `delete_salt` is a no-op
    // there; Apple / Android / Windows need both halves dropped.
    dispatch_clear(support_dir)?;
    #[cfg(not(target_os = "linux"))]
    {
        lfs_core::security::hardware_tier_vault::salt::delete(dir)
            .map_err(|e| format!("reseal: salt delete: {e}"))?;
    }
    // Step 4 — fresh salt + new auth value + store.
    let new_salt = lfs_core::security::hardware_tier_vault::salt::provision(dir)
        .map_err(|e| format!("reseal: salt provision: {e}"))?;
    let new_pin_hmac = lfs_core::crypto::hmac_sha256(&new_salt, new_password.as_bytes());
    dispatch_store(support_dir, &db_key, &new_salt, new_pin_hmac.as_slice())?;
    Ok(())
}

fn read_existing_salt(support_dir: &str) -> Result<Option<Vec<u8>>, String> {
    #[cfg(target_os = "linux")]
    {
        lfs_core::security::hardware_tier_vault::linux::read_blob_salt(support_dir)
            .map_err(map_linux_vault_error)
    }
    #[cfg(not(target_os = "linux"))]
    {
        lfs_core::security::hardware_tier_vault::salt::read(std::path::Path::new(support_dir))
            .map_err(|e| format!("reseal: salt read: {e}"))
    }
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
    fn resolve_auth_value_password_off_and_biometric_off_returns_none() {
        let salt = vec![0xAB; 16];
        // The Hardware tier is always password-gated — a caller
        // that asks for "no secret" is a misuse and the shim
        // surfaces None so the unlock path routes through the
        // password dialog rather than sealing under an empty
        // auth-value.
        let res = hardware_tier_vault_resolve_auth_value(false, false, salt, None, None);
        assert!(res.is_none());
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

    #[test]
    fn wizard_required_probe_keys_off_marker_file() {
        // The FRB shim is now a thin "read pinned support_dir →
        // delegate" wrapper; the marker-on-disk contract lives in
        // `vault::hardware_password_set_wizard_required` and the
        // `OnceLock`-based pin can only adopt one path per test
        // binary. Pin the contract on the core function directly
        // so per-test tempdirs work without colliding through the
        // shared singleton.
        let dir = tempfile::TempDir::new().unwrap();
        assert!(!vault::hardware_password_set_wizard_required(dir.path()));
        lfs_core::security::hardware_tier_vault::write_v6_v7_password_set_marker(dir.path())
            .unwrap();
        assert!(vault::hardware_password_set_wizard_required(dir.path()));
    }

    #[tokio::test]
    async fn clear_password_set_marker_drops_the_file() {
        // The wizard's success path is "re-seal + clear marker".
        // The clear shim is the second half; pin its semantics
        // (idempotent on missing, removes when present). Marker
        // probe runs through the core function — see the
        // wizard_required_probe_keys_off_marker_file comment.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().to_str().unwrap().to_string();
        lfs_core::security::hardware_tier_vault::write_v6_v7_password_set_marker(dir.path())
            .unwrap();
        assert!(vault::hardware_password_set_wizard_required(dir.path()));
        hardware_tier_vault_clear_password_set_marker(path)
            .await
            .expect("clear");
        assert!(!vault::hardware_password_set_wizard_required(dir.path()));
    }

    #[tokio::test]
    async fn clear_password_set_marker_is_idempotent_on_missing() {
        // Re-entrant safety: a wizard that already cleared the
        // marker but then has the caller retry the cleanup leg
        // must not blow up. Matches the underlying
        // `clear_v6_v7_password_set_marker` contract.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().to_str().unwrap().to_string();
        hardware_tier_vault_clear_password_set_marker(path)
            .await
            .expect("idempotent");
    }

    #[tokio::test]
    async fn reseal_with_empty_password_short_circuits_as_error() {
        // The Hardware tier is mandatory-password — the wizard's
        // re-seal call rejects an empty payload up front so the
        // dispatcher never writes a vault sealed under the same
        // empty PIN-HMAC the migration left behind.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().to_str().unwrap().to_string();
        let err = hardware_tier_vault_reseal_with_password(path, String::new())
            .await
            .unwrap_err();
        assert!(err.contains("empty"));
    }

    #[test]
    fn derive_auth_for_empty_pin_returns_empty_bytes() {
        // Combined-PIN store / read keeps the passwordless arm of
        // the bank-style modifier model: a vault sealed under an
        // empty user-typed PIN must unseal under the same empty
        // auth value. `resolve_auth_value` rejects empty payloads
        // as "modifier resolution failed" (None); the combined
        // call short-circuits to empty bytes instead so the
        // store / read pair agrees byte-for-byte.
        let salt = vec![0x11; 32];
        let auth = derive_auth_for_pin("", &salt);
        assert!(auth.is_empty());
    }

    #[test]
    fn derive_auth_for_pin_matches_resolve_auth_value() {
        // Non-empty PIN routes through
        // `lfs_core::security::hardware_tier_vault::resolve_auth_value`
        // so the HMAC composition lives one place across the
        // password-only and combined-PIN paths. Pin equality so a
        // future refactor that re-implements the HMAC inline would
        // surface as a test failure.
        let salt = vec![0x22; 32];
        let pin = "hunter2";
        let combined = derive_auth_for_pin(pin, &salt);
        let expected = lfs_core::security::hardware_tier_vault::resolve_auth_value(
            lfs_core::security::hardware_tier_vault::AuthIntent::Password(pin),
            &salt,
        )
        .expect("non-empty password resolves")
        .to_vec();
        assert_eq!(combined, expected);
    }

    #[test]
    fn derive_auth_for_pin_is_salt_sensitive() {
        // Different salts produce different auth values for the
        // same typed PIN — the salt is what keeps the sealed blob
        // device-specific even when two users pick the same PIN.
        let pin = "1234";
        let a = derive_auth_for_pin(pin, &[0x00; 32]);
        let b = derive_auth_for_pin(pin, &[0x01; 32]);
        assert_ne!(a, b);
    }
}
