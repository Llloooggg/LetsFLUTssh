//! Concrete artefact wrappers the live app registers at startup.
//!
//! Each one is a thin wrapper that knows how to inspect its slice of
//! on-disk state and report the current version. The actual payload
//! reads / writes live in the artefact's storage class (config writer,
//! KDF blob writer, etc) — these wrappers exist only so the migration
//! runner can discover what is on disk.

use std::path::Path;

use serde_json::Value;

use super::{Artefact, SchemaVersions};

/// `config.json` payload format.
///
/// The file is plain JSON. The schema version is tracked via a top-
/// level `config_schema_version` field inside the JSON itself —
/// stamped by the config writer on every write since the v1 cutover.
/// **Pre-cutover installs wrote `config.json` with no version field
/// at all**, so a missing `config_schema_version` on a JSON object
/// that otherwise parses cleanly is treated as v1 (the implicit
/// pre-stamp version). Without this fallback an upgrade from any
/// pre-cutover install would land on the reset dialog with the
/// user's settings intact on disk but unreachable.
///
/// A non-integer value or malformed JSON is still corrupt → `Err`
/// → caller surfaces the reset dialog.
pub struct ConfigArtefact;

impl ConfigArtefact {
    pub const FILE_NAME: &'static str = "config.json";
    const VERSION_FIELD: &'static str = "config_schema_version";
}

impl Artefact for ConfigArtefact {
    fn id(&self) -> &'static str {
        Self::FILE_NAME
    }

    fn target_version(&self) -> i32 {
        SchemaVersions::CONFIG
    }

    fn read_version(&self, support_dir: &Path) -> Result<i32, String> {
        let file = support_dir.join(Self::FILE_NAME);
        if !file.exists() {
            return Ok(-1);
        }
        let bytes = std::fs::read(&file).map_err(|e| format!("read {}: {e}", Self::FILE_NAME))?;
        let value: Value = serde_json::from_slice(&bytes)
            .map_err(|e| format!("{}: parse: {e}", Self::FILE_NAME))?;
        let Value::Object(obj) = value else {
            return Err(format!("{}: not a JSON object", Self::FILE_NAME));
        };
        match obj.get(Self::VERSION_FIELD) {
            Some(Value::Number(n)) => n.as_i64().map(|v| v as i32).ok_or_else(|| {
                format!(
                    "{}: {} not representable as i32",
                    Self::FILE_NAME,
                    Self::VERSION_FIELD
                )
            }),
            // Missing field on a parseable JSON object = pre-cutover
            // install. Implicit v1.
            None => Ok(1),
            Some(_) => Err(format!(
                "{}: non-integer {}",
                Self::FILE_NAME,
                Self::VERSION_FIELD
            )),
        }
    }
}

/// `credentials.kdf` — Argon2id parameter blob written by the KDF
/// writer. Self-versioned inside the file via `'LFKD'` magic +
/// version byte; reading the on-disk version is what lets the
/// migration runner distinguish "up-to-date", "needs migration",
/// and "corrupt / wrong format".
///
/// Header layout (mirror of `master_password::encode_kdf_record`):
/// ```text
///   offset 0   magic 'LFKD'   (4 bytes)
///   offset 4   file version   (1 byte)
///   …          KDF params + salt
/// ```
///
/// A missing file → `-1` (no install). A 0-byte / sub-header file or
/// a wrong magic → fatal `Err`; the migration runner surfaces the
/// reset dialog rather than silently treating the artefact as
/// up-to-date and letting the first verify call fail with a cryptic
/// "decrypt failed" error. A future-version file (version byte
/// higher than the build's `SchemaVersions::KDF`) is reported as-is
/// so the migration runner can tell the user "newer install present,
/// please upgrade" instead of pretending it knows the format.
pub struct KdfArtefact;

impl KdfArtefact {
    pub const FILE_NAME: &'static str = "credentials.kdf";
    /// Mirror of `master_password::FILE_MAGIC`. Duplicated here so
    /// the migration framework can validate the artefact without
    /// pulling in the master-password module's read pipeline.
    const FILE_MAGIC: [u8; 4] = [0x4C, 0x46, 0x4B, 0x44]; // 'LFKD'
    /// Magic + version byte. Anything shorter is corrupt.
    const HEADER_MIN_LEN: usize = Self::FILE_MAGIC.len() + 1;
}

impl Artefact for KdfArtefact {
    fn id(&self) -> &'static str {
        Self::FILE_NAME
    }

    fn target_version(&self) -> i32 {
        SchemaVersions::KDF
    }

    fn read_version(&self, support_dir: &Path) -> Result<i32, String> {
        let file = support_dir.join(Self::FILE_NAME);
        if !file.exists() {
            return Ok(-1);
        }
        let bytes = std::fs::read(&file).map_err(|e| format!("read {}: {e}", Self::FILE_NAME))?;
        if bytes.len() < Self::HEADER_MIN_LEN {
            return Err(format!(
                "{}: truncated header ({} bytes, need ≥ {})",
                Self::FILE_NAME,
                bytes.len(),
                Self::HEADER_MIN_LEN
            ));
        }
        if bytes[..Self::FILE_MAGIC.len()] != Self::FILE_MAGIC {
            return Err(format!("{}: wrong magic", Self::FILE_NAME));
        }
        let version = bytes[Self::FILE_MAGIC.len()] as i32;
        Ok(version)
    }
}

#[cfg(test)]
mod tests {
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
}
