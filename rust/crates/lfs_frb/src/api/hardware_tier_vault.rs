//! FRB adapter for `lfs_core::security::hardware_tier_vault`.
//!
//! Sync — every op is a base64 encode/decode + a small JSON parse.
//! Worth the no-async-hop overhead since the L3 unlock dialog
//! drives the encode/decode on each store / read pass.
//!
//! Method-channel + TPM CLI shell-out paths stay Dart-side; this
//! module covers the Linux-flavour disk-blob format only.

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
