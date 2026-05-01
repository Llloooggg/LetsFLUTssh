//! FRB adapter for the hardware-tier vault.
//!
//! Two surfaces:
//!
//! 1. **Linux blob format helpers** — `lfs_core::security::hardware_tier_vault`
//!    owns the JSON envelope the Dart side writes to
//!    `hardware_vault.bin` after the TPM seal call. Pure encode /
//!    decode + auth-value resolver; no I/O.
//! 2. **Apple Secure Enclave path** — `lfs_os_security::hardware_tier_vault`
//!    owns the SE keypair + ECIES-GCM wrap + on-disk envelope. The
//!    Dart layer dispatches to these on `Platform.isMacOS ||
//!    Platform.isIOS` instead of the existing
//!    `com.letsflutssh/hardware_vault` MethodChannel; the Swift
//!    plugin stays in place as the verification fallback until a
//!    real device confirms parity.
//!
//! Windows + Android still go through their MethodChannel plugins.
//! TPM CLI shell-out for Linux still lives Dart-side via
//! `TpmClient`.

use lfs_core::security::hardware_tier_vault as vault;
use lfs_os_security::hardware_tier_vault as apple_vault;

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

// ---- Apple Secure Enclave path -----------------------------------

/// Apple-side `isAvailable` probe — runs an LAContext +
/// `SecKeyCreateRandomKey` round-trip through the Secure Enclave.
/// Returns `false` on non-Apple targets (Linux uses the TPM2 path,
/// Windows / Android keep their MethodChannel plugins).
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_apple_is_available() -> bool {
    apple_vault::is_available()
}

/// Apple-side classified probe — returns the wire string the Dart
/// `HardwareProbeDetail` enum already parses (`available`,
/// `macosNoSecureEnclave`, `macosPasscodeNotSet`,
/// `macosSigningIdentityMissing`, `macosGeneric`, or `unknown` on
/// non-Apple targets).
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_apple_probe_detail() -> String {
    apple_vault::probe_detail().wire_name().to_string()
}

/// True when the Apple primary vault file
/// (`hardware_vault_apple.bin`) exists under `support_dir`. Pure
/// path-stat — does not invoke the SE.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_apple_is_stored(support_dir: String) -> bool {
    apple_vault::is_stored(&support_dir)
}

/// Wrap `db_key` against the Apple primary SE key + write the
/// `(pin_hmac, wrapped)` envelope under `support_dir`. `pin_hmac`
/// MAY be empty for the passwordless-T2 flow.
pub async fn hardware_tier_vault_apple_store(
    support_dir: String,
    db_key: Vec<u8>,
    pin_hmac: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        apple_vault::store(&support_dir, &db_key, &pin_hmac).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("apple store join: {e}"))?
}

/// Unwrap the DB key from the Apple vault envelope. Returns
/// `Ok(None)` on missing vault file, malformed envelope, or
/// PIN HMAC mismatch (so the caller can surface the same "wrong
/// PIN" path either way without distinguishing). Backend SE errors
/// (passcode reset, SE key missing after a previous `clear`)
/// surface as `Err`.
pub async fn hardware_tier_vault_apple_read(
    support_dir: String,
    pin_hmac: Vec<u8>,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        apple_vault::read(&support_dir, &pin_hmac).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("apple read join: {e}"))?
}

/// Drop the Apple vault file + the SE primary key + the biometric
/// overlay (key + file). Best-effort: any sub-step that fails is
/// swallowed; the user-facing semantics is "vault cleared" either
/// way.
pub async fn hardware_tier_vault_apple_clear(support_dir: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || apple_vault::clear(&support_dir).map_err(|e| e.to_string()))
        .await
        .map_err(|e| format!("apple clear join: {e}"))?
}

/// Wrap `password_bytes` under the biometric overlay SE key (gated
/// by `kSecAccessControlBiometryCurrentSet`) and write the overlay
/// envelope. Reading the overlay later surfaces the system
/// biometric prompt automatically.
pub async fn hardware_tier_vault_apple_store_biometric_password(
    support_dir: String,
    password_bytes: Vec<u8>,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        apple_vault::store_biometric_password(&support_dir, &password_bytes)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("apple store_bio_pw join: {e}"))?
}

/// Unwrap the biometric overlay password — invokes the system
/// biometric prompt. Returns `Ok(None)` when the overlay file is
/// missing; cancellation / wrong finger / vault-key revocation
/// surface as `Err`.
pub async fn hardware_tier_vault_apple_read_biometric_password(
    support_dir: String,
) -> Result<Option<Vec<u8>>, String> {
    tokio::task::spawn_blocking(move || {
        apple_vault::read_biometric_password(&support_dir).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("apple read_bio_pw join: {e}"))?
}

/// Drop the biometric overlay (key + file) without touching the
/// primary vault.
pub async fn hardware_tier_vault_apple_clear_biometric_password(
    support_dir: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        apple_vault::clear_biometric_password(&support_dir).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("apple clear_bio_pw join: {e}"))?
}

/// True when the biometric overlay file exists.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_tier_vault_apple_is_biometric_password_stored(support_dir: String) -> bool {
    apple_vault::is_biometric_password_stored(&support_dir)
}
