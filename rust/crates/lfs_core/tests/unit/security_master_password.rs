/// Unit tests extracted from security/master_password.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use tempfile::TempDir;

fn fast_params() -> KdfParams {
    // Argon2id minimums per the crate's `Params::new` constraints
    // — memory floor is 8 KiB. Keeps unit tests under a second
    // each instead of the production 400ms+ profile.
    KdfParams {
        memory_kib: 8,
        iterations: 1,
        parallelism: 1,
    }
}

#[test]
fn encode_decode_kdf_record_round_trip() {
    let params = KdfParams::defaults();
    let salt = [7u8; SALT_LENGTH];
    let bytes = encode_kdf_record(&params, &salt);
    let decoded = decode_kdf_record(&bytes).unwrap();
    assert_eq!(decoded.params.memory_kib, params.memory_kib);
    assert_eq!(decoded.params.iterations, params.iterations);
    assert_eq!(decoded.params.parallelism, params.parallelism);
    assert_eq!(decoded.salt, salt);
}

#[test]
fn decode_rejects_bad_magic() {
    let mut bytes = encode_kdf_record(&KdfParams::defaults(), &[1u8; SALT_LENGTH]);
    bytes[0] = 0x00;
    let err = decode_kdf_record(&bytes).unwrap_err();
    assert!(err.contains("bad magic"));
}

#[test]
fn decode_rejects_unknown_version() {
    let mut bytes = encode_kdf_record(&KdfParams::defaults(), &[1u8; SALT_LENGTH]);
    bytes[FILE_MAGIC.len()] = 0xFF;
    let err = decode_kdf_record(&bytes).unwrap_err();
    assert!(err.contains("unsupported version"));
}

#[test]
fn decode_rejects_oversize_memory() {
    let bad = KdfParams {
        memory_kib: ARGON2ID_MAX_MEMORY_KIB + 1,
        iterations: 2,
        parallelism: 1,
    };
    let bytes = encode_kdf_record(&bad, &[0u8; SALT_LENGTH]);
    let err = decode_kdf_record(&bytes).unwrap_err();
    assert!(err.contains("memory"));
}

#[test]
fn enable_persists_and_verify_round_trips() {
    let dir = TempDir::new().unwrap();
    let params = fast_params();
    let key = enable(dir.path(), b"secret", &params).unwrap();
    assert!(is_enabled(dir.path()));
    let got = verify_and_derive(dir.path(), b"secret").unwrap().unwrap();
    assert_eq!(got, key);
}

#[test]
fn verify_returns_none_on_wrong_password() {
    let dir = TempDir::new().unwrap();
    enable(dir.path(), b"right", &fast_params()).unwrap();
    let got = verify_and_derive(dir.path(), b"wrong").unwrap();
    assert!(got.is_none());
}

#[test]
fn change_password_rotates_and_old_stops_working() {
    let dir = TempDir::new().unwrap();
    let params = fast_params();
    enable(dir.path(), b"v1", &params).unwrap();
    let new_key = change_password(dir.path(), b"v1", b"v2", &params).unwrap();
    assert!(verify_and_derive(dir.path(), b"v1").unwrap().is_none());
    let again = verify_and_derive(dir.path(), b"v2").unwrap().unwrap();
    assert_eq!(again, new_key);
}

#[test]
fn change_password_rejects_wrong_old() {
    let dir = TempDir::new().unwrap();
    enable(dir.path(), b"right", &fast_params()).unwrap();
    let err = change_password(dir.path(), b"wrong", b"new", &fast_params()).unwrap_err();
    assert!(err.contains("incorrect"));
}

#[test]
fn disable_drops_kdf_and_verifier_only() {
    let dir = TempDir::new().unwrap();
    enable(dir.path(), b"x", &fast_params()).unwrap();
    std::fs::write(dir.path().join(KEY_FILE_NAME), b"keep").unwrap();
    disable(dir.path()).unwrap();
    assert!(!dir.path().join(KDF_FILE_NAME).exists());
    assert!(!dir.path().join(VERIFIER_FILE_NAME).exists());
    assert!(dir.path().join(KEY_FILE_NAME).exists());
}

#[test]
fn reset_drops_everything() {
    let dir = TempDir::new().unwrap();
    enable(dir.path(), b"x", &fast_params()).unwrap();
    std::fs::write(dir.path().join(KEY_FILE_NAME), b"to-go").unwrap();
    reset(dir.path()).unwrap();
    assert!(!dir.path().join(KDF_FILE_NAME).exists());
    assert!(!dir.path().join(VERIFIER_FILE_NAME).exists());
    assert!(!dir.path().join(KEY_FILE_NAME).exists());
}

#[test]
fn verify_and_derive_errors_when_disabled() {
    let dir = TempDir::new().unwrap();
    let err = verify_and_derive(dir.path(), b"anything").unwrap_err();
    assert!(err.contains("not enabled"));
}

#[test]
fn derive_key_from_disk_matches_verify() {
    let dir = TempDir::new().unwrap();
    let params = fast_params();
    let key = enable(dir.path(), b"p", &params).unwrap();
    let again = derive_key_from_disk(dir.path(), b"p").unwrap();
    assert_eq!(again, key);
}

#[cfg(unix)]
#[test]
fn enable_writes_files_with_owner_only_perms() {
    // The Dart `writeBytesAtomic` always called `hardenFilePerms`
    // on the temp file before rename — without the matching
    // chmod 0600 in the Rust write_atomic, the credentials.kdf
    // and credentials.verify files would land at the default
    // umask (typically 0644, world-readable). That would be a
    // security regression for installs migrated from the Dart
    // writer. Confirm the Rust write keeps 0600 parity.
    use std::os::unix::fs::PermissionsExt;
    let dir = TempDir::new().unwrap();
    enable(dir.path(), b"x", &fast_params()).unwrap();
    for name in [KDF_FILE_NAME, VERIFIER_FILE_NAME] {
        let p = dir.path().join(name);
        let mode = std::fs::metadata(&p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "{name} did not land at 0600 (got {mode:o})");
    }
}
