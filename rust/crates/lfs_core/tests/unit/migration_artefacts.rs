/// Unit tests extracted from migration/artefacts.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::fs;
use tempfile::TempDir;

#[test]
fn config_absent_returns_minus_one() {
    let dir = TempDir::new().unwrap();
    assert_eq!(ConfigArtefact.read_version(dir.path()).unwrap(), -1);
}

#[test]
fn config_present_at_v1() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("config.json"),
        br#"{"config_schema_version": 1, "theme": "dark"}"#,
    )
    .unwrap();
    assert_eq!(ConfigArtefact.read_version(dir.path()).unwrap(), 1);
}

/// Pre-cutover installs wrote `config.json` with no version
/// field. The artefact must report that as v1 so the upgrade
/// path doesn't trigger a reset that would wipe the user's
/// settings out from under them.
#[test]
fn config_missing_version_field_is_implicit_v1() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("config.json"), br#"{"theme": "dark"}"#).unwrap();
    assert_eq!(ConfigArtefact.read_version(dir.path()).unwrap(), 1);
}

/// Non-integer value in the version field is still fatal — that
/// can only mean a corrupted writer or a deliberate tamper, not
/// a legitimate pre-cutover install (which would have no field
/// at all, not a string in its place).
#[test]
fn config_non_integer_version_field_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("config.json"),
        br#"{"config_schema_version": "v1"}"#,
    )
    .unwrap();
    let err = ConfigArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("non-integer"));
}

#[test]
fn config_malformed_json_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("config.json"), b"not json").unwrap();
    let err = ConfigArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("parse"));
}

#[test]
fn config_non_object_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("config.json"), b"[1,2,3]").unwrap();
    let err = ConfigArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("object"));
}

#[test]
fn kdf_absent_returns_minus_one() {
    let dir = TempDir::new().unwrap();
    assert_eq!(KdfArtefact.read_version(dir.path()).unwrap(), -1);
}

#[test]
fn kdf_present_returns_inner_version_byte() {
    let dir = TempDir::new().unwrap();
    // `LFKD` + version 0x01 + opaque payload — the writer's
    // canonical shape at the current schema cutover.
    fs::write(dir.path().join("credentials.kdf"), b"LFKD\x01rest").unwrap();
    assert_eq!(
        KdfArtefact.read_version(dir.path()).unwrap(),
        SchemaVersions::KDF
    );
}

// ── PassGateArtefact ─────────────────────────────────────────

#[test]
fn pass_gate_absent_returns_minus_one() {
    let dir = TempDir::new().unwrap();
    assert_eq!(PassGateArtefact.read_version(dir.path()).unwrap(), -1);
}

#[test]
fn pass_gate_with_explicit_v1_returns_one() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("security_pass_hash.bin"),
        br#"{"v":1,"salt":"YQ==","hmac":"YQ=="}"#,
    )
    .unwrap();
    assert_eq!(PassGateArtefact.read_version(dir.path()).unwrap(), 1);
}

/// `decode_disk_blob` accepts a missing `v` field as the
/// pre-version legacy install; the artefact wrapper must agree
/// so the runner doesn't trip the corrupt-recovery cascade for
/// users who upgraded over a v0 disk blob.
#[test]
fn pass_gate_missing_version_field_is_implicit_v1() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("security_pass_hash.bin"),
        br#"{"salt":"YQ==","hmac":"YQ=="}"#,
    )
    .unwrap();
    assert_eq!(PassGateArtefact.read_version(dir.path()).unwrap(), 1);
}

#[test]
fn pass_gate_non_integer_version_field_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("security_pass_hash.bin"),
        br#"{"v":"v1","salt":"YQ==","hmac":"YQ=="}"#,
    )
    .unwrap();
    let err = PassGateArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("non-integer"));
}

#[test]
fn pass_gate_malformed_json_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("security_pass_hash.bin"), b"not json").unwrap();
    let err = PassGateArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("parse"));
}

#[test]
fn pass_gate_non_object_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("security_pass_hash.bin"), b"[1,2,3]").unwrap();
    let err = PassGateArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("object"));
}

/// A future-version blob on disk reports the future version raw.
/// The runner promotes it to `Report::future_versions` so the
/// caller can surface the "newer install present" dialog.
#[test]
fn pass_gate_future_version_returns_that_version() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("security_pass_hash.bin"),
        br#"{"v":9,"salt":"YQ==","hmac":"YQ=="}"#,
    )
    .unwrap();
    assert_eq!(PassGateArtefact.read_version(dir.path()).unwrap(), 9);
}

// ── HwSaltArtefact ───────────────────────────────────────────

#[test]
fn hw_salt_absent_returns_minus_one() {
    let dir = TempDir::new().unwrap();
    assert_eq!(HwSaltArtefact.read_version(dir.path()).unwrap(), -1);
}

#[test]
fn hw_salt_present_at_canonical_len_returns_v1() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("hardware_vault_salt.bin"),
        vec![0u8; 32].as_slice(),
    )
    .unwrap();
    assert_eq!(HwSaltArtefact.read_version(dir.path()).unwrap(), 1);
}

/// A salt file at the wrong length means a truncated write or
/// tamper. Returning v1 here would let the unlock path read a
/// bogus salt and run HMAC over garbage; the typed `Err` routes
/// the reset dialog instead.
#[test]
fn hw_salt_wrong_length_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(
        dir.path().join("hardware_vault_salt.bin"),
        vec![0u8; 16].as_slice(),
    )
    .unwrap();
    let err = HwSaltArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("unexpected length"));
}

#[test]
fn hw_salt_empty_file_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("hardware_vault_salt.bin"), b"").unwrap();
    let err = HwSaltArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("unexpected length"));
}

/// A version byte higher than the running build means the user
/// downgraded after installing a newer release. The runner gets
/// the raw value so it can surface a "newer install present"
/// dialog instead of silently re-running migrations against a
/// format the build doesn't understand.
#[test]
fn kdf_present_with_future_version_byte_returns_that_version() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("credentials.kdf"), b"LFKD\x09rest").unwrap();
    assert_eq!(KdfArtefact.read_version(dir.path()).unwrap(), 9);
}

/// Magic mismatch is fatal — that can only mean a corrupted
/// writer or a deliberate tamper. Returning `target_version`
/// here would let the migration runner skip the artefact and
/// the first `verify_and_derive` call would fail with a generic
/// "decrypt error" the user cannot diagnose.
#[test]
fn kdf_with_wrong_magic_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("credentials.kdf"), b"XXXX\x01rest").unwrap();
    let err = KdfArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("magic"));
}

/// A file too short to even hold the header is corrupt; the
/// runner surfaces the reset dialog rather than treating the
/// stub as up-to-date.
#[test]
fn kdf_with_truncated_header_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("credentials.kdf"), b"LF").unwrap();
    let err = KdfArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("truncated"));
}

/// Empty file is a special case of truncated — same outcome.
#[test]
fn kdf_empty_file_is_fatal() {
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("credentials.kdf"), b"").unwrap();
    let err = KdfArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("truncated"));
}

#[test]
fn kdf_zero_version_byte_is_fatal() {
    // The Artefact contract reserves `< 1` for absence (-1); a
    // literal 0 version byte is corrupt state and must surface as
    // Err, not a made-up version the runner would migrate from.
    let dir = TempDir::new().unwrap();
    fs::write(dir.path().join("credentials.kdf"), b"LFKD\x00rest").unwrap();
    let err = KdfArtefact.read_version(dir.path()).unwrap_err();
    assert!(err.contains("invalid schema version 0"));
}
