//! T2 hardware-tier vault — Linux TPM2 path orchestrator + shared
//! blob-format helpers.
//!
//! Apple / Android live behind `lfs_os_security::hardware_tier_vault`
//! (objc2 / JNI FFI). Linux's TPM CLI shell-out lives one crate up in
//! `lfs_os_security::linux::tpm`; the [`linux`] submodule below
//! orchestrates the full store / read / clear flow Rust-internal so
//! the DB key never crosses the FRB boundary on this path either.
//!
//! Wire format (JSON object, UTF-8 bytes on disk):
//! ```json
//! { "salt": "<base64>", "sealed": "<base64>" }
//! ```
//!
//! `encode_linux_blob` / `decode_linux_blob` cover the wire shape;
//! [`linux::store`] / [`linux::read`] / [`linux::clear`] cover the
//! end-to-end orchestration.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::Value;

use crate::crypto::hmac_sha256;

/// Decoded blob payload — the salt + TPM-sealed DB-key bytes the
/// vault read from `hardware_vault.bin`.
#[derive(Debug, Clone)]
pub struct LinuxBlob {
    pub salt: Vec<u8>,
    pub sealed: Vec<u8>,
}

/// Encode the salt + sealed-blob pair as the JSON envelope written
/// to `hardware_vault.bin` on Linux. Caller writes the returned
/// string's UTF-8 bytes atomically — the file lives next to the
/// other 0600-hardened secret files under app-support.
#[must_use]
pub fn encode_linux_blob(salt: &[u8], sealed: &[u8]) -> String {
    // Hand-build the literal so the field order is stable
    // ({"salt": …, "sealed": …}) — explicit shape protects the
    // wire-format docs from a future serde-default flip.
    format!(
        "{{\"salt\":\"{}\",\"sealed\":\"{}\"}}",
        STANDARD.encode(salt),
        STANDARD.encode(sealed)
    )
}

/// Parse the on-disk JSON envelope. Returns `Err` for malformed
/// JSON, missing fields, non-string values, invalid base64, or
/// empty decoded bytes (a legitimate seal is never zero-length).
/// The Dart-side `read` treats any decode failure as a "vault is
/// empty / corrupt" outcome and routes the user back to the
/// password unlock dialog.
pub fn decode_linux_blob(blob: &str) -> Result<LinuxBlob, String> {
    let value: Value = serde_json::from_str(blob).map_err(|e| format!("blob: parse JSON: {e}"))?;
    let obj = value
        .as_object()
        .ok_or_else(|| String::from("blob: not a JSON object"))?;
    let salt_b64 = obj
        .get("salt")
        .and_then(|v| v.as_str())
        .ok_or_else(|| String::from("blob: missing salt field"))?;
    let sealed_b64 = obj
        .get("sealed")
        .and_then(|v| v.as_str())
        .ok_or_else(|| String::from("blob: missing sealed field"))?;
    let salt = STANDARD
        .decode(salt_b64.as_bytes())
        .map_err(|e| format!("blob: salt decode: {e}"))?;
    let sealed = STANDARD
        .decode(sealed_b64.as_bytes())
        .map_err(|e| format!("blob: sealed decode: {e}"))?;
    if salt.is_empty() || sealed.is_empty() {
        return Err(String::from("blob: empty salt or sealed"));
    }
    Ok(LinuxBlob { salt, sealed })
}

/// Hardware-tier vault auth-value source. Replaces the prior
/// `(password: bool, biometric: bool, typed_password, fprintd_hash)`
/// boolean-flag API where a forgotten `password=true` flag could
/// silently degrade to an empty `Vec`. Now a single enum:
///
/// * `Passwordless` — isolation only; no user-typed gate.
/// * `Password(pw)` — `HMAC(salt, pw)` over typed bytes.
/// * `Biometric(hash)` — `HMAC(salt, hash)` over a fprintd-derived
///   hash. The wizard invariant still expects the user has set a
///   master password too, but the resolver treats biometric as the
///   authoritative source when chosen.
#[derive(Debug, Clone, Copy)]
pub enum AuthIntent<'a> {
    Passwordless,
    Password(&'a str),
    Biometric(&'a [u8]),
}

/// Resolve the hardware-tier vault auth value for an `AuthIntent`.
/// Returns `None` for an empty payload (empty typed password / empty
/// biometric hash) — callers surface `None` as "modifier resolution
/// failed → treat as cancelled unlock" so we never silently fall
/// back to an empty auth.
#[must_use]
pub fn resolve_auth_value(intent: AuthIntent<'_>, salt: &[u8]) -> Option<zeroize::Zeroizing<Vec<u8>>> {
    match intent {
        AuthIntent::Passwordless => Some(zeroize::Zeroizing::new(Vec::new())),
        AuthIntent::Password("") | AuthIntent::Biometric([]) => None,
        AuthIntent::Password(pw) => Some(hmac_sha256(salt, pw.as_bytes())),
        AuthIntent::Biometric(hash) => Some(hmac_sha256(salt, hash)),
    }
}

/// Linux TPM2 store / read / clear orchestrator. Mirrors the Apple
/// / Android shape in `lfs_os_security::hardware_tier_vault` so
/// every platform's hardware-tier vault has a Rust-internal
/// orchestrator and the DB key never lands on the Dart heap on the
/// store / read paths.
#[cfg(target_os = "linux")]
pub mod linux {
    use std::path::{Path, PathBuf};

    use crate::path::write_bytes_atomic;
    use lfs_os_security::linux::tpm::{self, TpmConfig};

    /// Filename inside `support_dir` carrying the encoded blob.
    /// Matches the wipe-registry entry in
    /// `lfs_core::security::wipe::MANAGED_FILES`.
    const VAULT_FILE: &str = "hardware_vault.bin";

    /// Errors the Linux orchestrator surfaces.
    #[derive(Debug)]
    pub enum LinuxVaultError {
        /// `tpm2-tools` not reachable, `/dev/tpmrm0` missing, or the
        /// TPM rejected the seal call.
        TpmUnavailable(String),
        /// `tpm2_create` / `tpm2_unseal` ran but returned an error.
        Backend(String),
        /// File-IO surface — read / write / atomic-rename failed.
        Io(String),
        /// On-disk blob malformed (missing JSON fields, bad base64,
        /// etc.). Caller routes to "vault corrupt" recovery.
        Corrupt(String),
    }

    impl std::fmt::Display for LinuxVaultError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::TpmUnavailable(s) => write!(f, "tpm unavailable: {s}"),
                Self::Backend(s) => write!(f, "tpm backend: {s}"),
                Self::Io(s) => write!(f, "io: {s}"),
                Self::Corrupt(s) => write!(f, "corrupt: {s}"),
            }
        }
    }

    impl std::error::Error for LinuxVaultError {}

    fn vault_path(support_dir: &str) -> PathBuf {
        Path::new(support_dir).join(VAULT_FILE)
    }

    /// True when `tpm2-tools` + `/dev/tpmrm0` are both reachable.
    /// Mirrors `lfs_os_security::hardware_tier_vault::is_available`
    /// for non-Apple targets so the cfg-arm dispatch in the FRB
    /// shim can route Linux through here.
    #[must_use]
    pub fn is_available() -> bool {
        matches!(
            tpm::probe(&TpmConfig::default()),
            tpm::TpmProbeResult::Available
        )
    }

    /// True when `support_dir/hardware_vault.bin` exists. Pure
    /// path-stat; does not invoke the TPM.
    #[must_use]
    pub fn is_stored(support_dir: &str) -> bool {
        vault_path(support_dir).exists()
    }

    /// Seal `db_key` under TPM-2.0 keyed by the caller-derived
    /// `pin_hmac` (`HMAC(salt, pin)` over the freshly-generated
    /// `salt` — same pre-derivation Apple / Android callers do
    /// today). Writes `{salt, sealed}` JSON envelope to
    /// `support_dir/hardware_vault.bin` atomically. `pin_hmac` MAY
    /// be empty for the passwordless flow — caller and unseal
    /// must agree.
    ///
    /// Linux co-locates the salt inside the envelope rather than
    /// using a sibling `hardware_vault_salt.bin` file (Apple /
    /// Android pattern). Caller still owns the salt — see
    /// [`read_blob_salt`] for the unlock-side reverse.
    pub fn store(
        support_dir: &str,
        db_key: &[u8],
        salt: &[u8],
        pin_hmac: &[u8],
    ) -> Result<(), LinuxVaultError> {
        if !is_available() {
            return Err(LinuxVaultError::TpmUnavailable("tpm probe failed".into()));
        }
        let sealed = tpm::seal(&TpmConfig::default(), db_key, pin_hmac)
            .map_err(|e| LinuxVaultError::Backend(e.to_string()))?;
        let body = super::encode_linux_blob(salt, &sealed);
        let blob = lfs_os_security::hardware_tier_vault::prepend_envelope_header(
            lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
            body.as_bytes(),
        );
        let path = vault_path(support_dir);
        if let Some(parent) = path.parent() {
            crate::path::create_dir_all_secure(parent)
                .map_err(|e| LinuxVaultError::Io(format!("mkdirp: {e}")))?;
        }
        write_bytes_atomic(&path, &blob).map_err(|e| LinuxVaultError::Io(format!("write: {e}")))?;
        Ok(())
    }

    /// Read `support_dir/hardware_vault.bin`, decode the salt +
    /// sealed pair, and unseal under the caller-derived `pin_hmac`.
    /// Caller MUST first read the on-disk salt via
    /// [`read_blob_salt`] and derive `pin_hmac = HMAC(salt, pin)`
    /// against it; the function does NOT re-derive.
    ///
    /// Returns:
    /// * `Ok(Some(bytes))` — successful unseal, plaintext key bytes.
    /// * `Ok(None)` — vault file absent, or wrong PIN / re-enrolment
    ///   forced TPM-key invalidation. Caller routes to "needs
    ///   password unlock".
    /// * `Err(_)` — file present but corrupt, or TPM unreachable.
    pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, LinuxVaultError> {
        let path = vault_path(support_dir);
        if !path.exists() {
            return Ok(None);
        }
        let raw = std::fs::read(&path).map_err(|e| LinuxVaultError::Io(format!("read: {e}")))?;
        let body = lfs_os_security::hardware_tier_vault::parse_envelope_header(
            &raw,
            lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
        )
        .map_err(|_| LinuxVaultError::Corrupt("envelope header mismatch".into()))?;
        let text = std::str::from_utf8(body)
            .map_err(|e| LinuxVaultError::Corrupt(format!("utf8: {e}")))?;
        let decoded = super::decode_linux_blob(text).map_err(LinuxVaultError::Corrupt)?;
        match tpm::unseal(&TpmConfig::default(), &decoded.sealed, pin_hmac) {
            Ok(bytes) => Ok(Some(bytes)),
            // Wrong auth or TPM-key invalidation surfaces as a
            // generic backend error from `tpm2-tools`. Map to
            // `Ok(None)` so the unlock UI routes back to password
            // entry, matching the Apple `read` contract for "wrong
            // PIN".
            Err(_) => Ok(None),
        }
    }

    /// Read just the salt half of the on-disk envelope so the
    /// unlock dialog can derive `pin_hmac = HMAC(salt, pin)`
    /// before calling [`read`]. Returns `Ok(None)` for missing /
    /// malformed files.
    pub fn read_blob_salt(support_dir: &str) -> Result<Option<Vec<u8>>, LinuxVaultError> {
        let path = vault_path(support_dir);
        if !path.exists() {
            return Ok(None);
        }
        let raw = std::fs::read(&path).map_err(|e| LinuxVaultError::Io(format!("read: {e}")))?;
        let body = lfs_os_security::hardware_tier_vault::parse_envelope_header(
            &raw,
            lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
        )
        .map_err(|_| LinuxVaultError::Corrupt("envelope header mismatch".into()))?;
        let text = std::str::from_utf8(body)
            .map_err(|e| LinuxVaultError::Corrupt(format!("utf8: {e}")))?;
        let decoded = super::decode_linux_blob(text).map_err(LinuxVaultError::Corrupt)?;
        Ok(Some(decoded.salt))
    }

    /// Drop `support_dir/hardware_vault.bin`. Best-effort —
    /// missing-file is `Ok(())`, file-system errors propagate.
    pub fn clear(support_dir: &str) -> Result<(), LinuxVaultError> {
        let path = vault_path(support_dir);
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(LinuxVaultError::Io(format!("remove: {e}"))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_decode_round_trips() {
        let salt = vec![0x33u8; 32];
        let sealed = vec![0x44u8; 96];
        let blob = encode_linux_blob(&salt, &sealed);
        let decoded = decode_linux_blob(&blob).unwrap();
        assert_eq!(decoded.salt, salt);
        assert_eq!(decoded.sealed, sealed);
    }

    #[test]
    fn decode_rejects_malformed_json() {
        assert!(decode_linux_blob("not-json").is_err());
        assert!(decode_linux_blob("[]").is_err());
    }

    #[test]
    fn decode_rejects_missing_fields() {
        assert!(decode_linux_blob("{}").is_err());
        assert!(decode_linux_blob(r#"{"salt":"YQ=="}"#).is_err());
        assert!(decode_linux_blob(r#"{"sealed":"YQ=="}"#).is_err());
    }

    #[test]
    fn decode_rejects_non_string_fields() {
        assert!(decode_linux_blob(r#"{"salt":1,"sealed":"YQ=="}"#).is_err());
        assert!(decode_linux_blob(r#"{"salt":"YQ==","sealed":[]}"#).is_err());
    }

    #[test]
    fn decode_rejects_invalid_base64() {
        let blob = r#"{"salt":"!!!","sealed":"YQ=="}"#;
        assert!(decode_linux_blob(blob).is_err());
    }

    #[test]
    fn decode_rejects_empty_decoded_bytes() {
        // A legitimate seal is never zero-length; a tampered file
        // with empty fields must not parse as a valid blob.
        assert!(decode_linux_blob(r#"{"salt":"","sealed":""}"#).is_err());
    }

    #[test]
    fn resolve_passwordless_returns_empty_vec() {
        let salt = vec![0x01u8; 32];
        let v = resolve_auth_value(AuthIntent::Passwordless, &salt);
        assert_eq!(v.map(|z| z.to_vec()), Some(Vec::new()));
    }

    #[test]
    fn resolve_password_branch_hmacs_typed_secret() {
        let salt = vec![0x02u8; 32];
        let with_pw = resolve_auth_value(AuthIntent::Password("hunter2"), &salt);
        let manual = hmac_sha256(&salt, b"hunter2");
        assert_eq!(with_pw.map(|z| z.to_vec()), Some(manual.to_vec()));
    }

    #[test]
    fn resolve_password_branch_rejects_empty_secret() {
        let salt = vec![0x03u8; 32];
        assert_eq!(resolve_auth_value(AuthIntent::Password(""), &salt), None);
    }

    #[test]
    fn resolve_biometric_branch_hmacs_fprintd_hash() {
        let salt = vec![0x04u8; 32];
        let hash = vec![0xAB; 32];
        let v = resolve_auth_value(AuthIntent::Biometric(&hash), &salt);
        let manual = hmac_sha256(&salt, &hash);
        assert_eq!(v.map(|z| z.to_vec()), Some(manual.to_vec()));
    }

    #[test]
    fn resolve_biometric_branch_rejects_empty_hash() {
        let salt = vec![0x05u8; 32];
        assert_eq!(resolve_auth_value(AuthIntent::Biometric(&[]), &salt), None);
    }
}
