/// Unit tests extracted from security/hardware_tier_vault.rs
/// Declared via `#[path] mod tests;` in the source file.
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
    assert!(decode_linux_blob(r#"{"v":1}"#).is_err());
    assert!(decode_linux_blob(r#"{"v":1,"salt":"YQ=="}"#).is_err());
    assert!(decode_linux_blob(r#"{"v":1,"sealed":"YQ=="}"#).is_err());
}

#[test]
fn decode_rejects_non_string_fields() {
    assert!(decode_linux_blob(r#"{"v":1,"salt":1,"sealed":"YQ=="}"#).is_err());
    assert!(decode_linux_blob(r#"{"v":1,"salt":"YQ==","sealed":[]}"#).is_err());
}

#[test]
fn decode_rejects_invalid_base64() {
    let blob = r#"{"v":1,"salt":"!!!","sealed":"YQ=="}"#;
    assert!(decode_linux_blob(blob).is_err());
}

#[test]
fn decode_rejects_empty_decoded_bytes() {
    // A legitimate seal is never zero-length; a tampered file
    // with empty fields must not parse as a valid blob.
    assert!(decode_linux_blob(r#"{"v":1,"salt":"","sealed":""}"#).is_err());
}

#[test]
fn encode_round_trip_includes_version() {
    // The inner `"v":1` field is the disambiguator for future
    // shape changes — every freshly-encoded envelope must carry
    // it as a parseable u64 that matches the constant the
    // decoder validates against.
    let salt = vec![0x11u8; 32];
    let sealed = vec![0x22u8; 64];
    let blob = encode_linux_blob(&salt, &sealed);
    let value: Value = serde_json::from_str(&blob).unwrap();
    let version = value
        .as_object()
        .and_then(|o| o.get("v"))
        .and_then(Value::as_u64)
        .expect("encoded blob exposes a numeric inner version");
    assert_eq!(version, LINUX_BLOB_INNER_VERSION);
    // Round-trip stays lossless even with the version field.
    let decoded = decode_linux_blob(&blob).unwrap();
    assert_eq!(decoded.salt, salt);
    assert_eq!(decoded.sealed, sealed);
}

#[test]
fn decode_rejects_unknown_inner_version() {
    // A future inner shape signalled by `v:99` must be rejected
    // here rather than parsed into a v1 `LinuxBlob` against
    // potentially incompatible salt / sealed bytes.
    let blob = r#"{"v":99,"salt":"YQ==","sealed":"YQ=="}"#;
    let err = decode_linux_blob(blob).expect_err("future version is rejected");
    assert!(
        err.contains("unknown inner version"),
        "error names the version mismatch: {err}"
    );
}

#[test]
fn decode_rejects_missing_inner_version() {
    // A pre-spec envelope with no `v` field also routes through
    // the corrupt-state cascade — no silent acceptance of a
    // shape the encoder never produced.
    let blob = r#"{"salt":"YQ==","sealed":"YQ=="}"#;
    let err = decode_linux_blob(blob).expect_err("missing version is rejected");
    assert!(
        err.contains("missing inner version"),
        "error names the missing field: {err}"
    );
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

#[cfg(target_os = "linux")]
#[test]
fn linux_overlay_is_stored_returns_false_for_fresh_dir() {
    // A fresh support_dir has no overlay file; the probe must
    // not panic on a missing path and reports `false`.
    let dir = tempfile::TempDir::new().unwrap();
    assert!(!super::linux::is_biometric_password_stored(
        dir.path().to_str().unwrap()
    ));
}

#[cfg(target_os = "linux")]
#[test]
fn linux_overlay_clear_on_missing_file_is_ok() {
    // The wizard / tier-reset cascade calls clear without
    // branching on pre-existence — missing target = success.
    let dir = tempfile::TempDir::new().unwrap();
    super::linux::clear_biometric_password(dir.path().to_str().unwrap()).expect("clear noop");
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn linux_overlay_store_errors_when_tpm_unavailable() {
    use lfs_os_security::linux::tpm::{probe, TpmConfig, TpmProbeResult};
    // Skip on hosts that actually have a working TPM — those
    // exercise the success path through the per-platform
    // validation matrix instead.
    if matches!(probe(&TpmConfig::default()), TpmProbeResult::Available) {
        return;
    }
    let dir = tempfile::TempDir::new().unwrap();
    let result =
        super::linux::store_biometric_password(dir.path().to_str().unwrap(), b"hunter2").await;
    assert!(matches!(
        result,
        Err(super::linux::LinuxVaultError::TpmUnavailable(_))
    ));
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn linux_overlay_read_returns_none_when_file_absent() {
    // No overlay file → caller falls back to the typed password
    // path. Does not consult the TPM or fprintd.
    let dir = tempfile::TempDir::new().unwrap();
    let result = super::linux::read_biometric_password(dir.path().to_str().unwrap()).await;
    assert!(matches!(result, Ok(None)));
}

#[cfg(target_os = "linux")]
#[test]
fn linux_overlay_file_name_matches_wipe_registry() {
    // The wipe-registry tripwire (`every_known_artefact_is_in_managed_files`)
    // cross-references this constant. A rename here without a
    // matching MANAGED_FILES entry would leave an orphan file
    // behind on every wipe.
    assert_eq!(
        super::linux::BIO_PASSWORD_FILE,
        "hardware_vault_password_overlay_linux.bin"
    );
}

/// fprintd hash determinism — same enrolment state must yield
/// the same auth value byte-for-byte across processes. Without
/// this invariant the seal at install time and the unseal at
/// unlock time would derive different keys and the user would
/// be locked out of the overlay on the very next launch. The
/// formula lives in `lfs_core::platform::linux::fprintd::get_enrolment_hash`
/// (SHA-256 of sorted-`:`-joined finger names); we re-derive it
/// here without consulting fprintd so the test is hermetic.
#[cfg(target_os = "linux")]
#[test]
fn fprintd_hash_formula_is_deterministic() {
    use sha2::{Digest, Sha256};
    fn derive(fingers: &[&str]) -> [u8; 32] {
        let mut sorted: Vec<String> = fingers.iter().map(|s| (*s).to_string()).collect();
        sorted.sort();
        let joined = sorted.join(":");
        let mut hasher = Sha256::new();
        hasher.update(joined.as_bytes());
        let digest = hasher.finalize();
        let mut out = [0u8; 32];
        out.copy_from_slice(&digest);
        out
    }
    let a = derive(&["right-index", "left-thumb"]);
    let b = derive(&["left-thumb", "right-index"]);
    assert_eq!(a, b, "sort order must not affect the hash");
    let c = derive(&["right-index"]);
    assert_ne!(
        a, c,
        "dropping an enrolled finger must flip the hash so the overlay invalidates"
    );
}
