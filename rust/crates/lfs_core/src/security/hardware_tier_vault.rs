//! Disk-blob format owner for the L3 hardware-tier vault's Linux
//! TPM2 path.
//!
//! `HardwareTierVault` (Dart) seals the DB key under a TPM primary
//! with `HMAC(salt, pin)` as the auth value, then persists the
//! sealed blob + salt as a JSON envelope in `hardware_vault.bin`
//! under app-support. Method-channel platforms (Apple / Android /
//! Windows) keep the wrapped key inside the native plugin and only
//! ride the salt-file half of the contract; this module covers the
//! Linux flavour where the whole blob lands Dart-side and the salt
//! is co-located with the sealed bytes.
//!
//! Wire format (JSON object, UTF-8 bytes on disk):
//! ```json
//! { "salt": "<base64>", "sealed": "<base64>" }
//! ```
//!
//! What stays Dart-side: the TPM CLI shell-out
//! (`TpmClient.seal` / `unseal` driving `tpm2-tools`), the
//! method-channel calls into the per-platform native vault plugin,
//! the standalone `hardware_vault_salt.bin` write/read for the
//! method-channel platforms, and the file I/O for both flavours.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::Value;

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
}
