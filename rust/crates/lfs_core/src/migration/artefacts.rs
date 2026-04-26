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
/// stamped by the config writer on every write. A missing field, a
/// non-integer value, or malformed JSON is treated as corrupt
/// (returns `Err`); the runner surfaces the fatal error to the
/// caller which routes the user through the reset dialog.
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
            _ => Err(format!(
                "{}: missing or non-integer {}",
                Self::FILE_NAME,
                Self::VERSION_FIELD
            )),
        }
    }
}

/// `credentials.kdf` — Argon2id parameter blob written by the KDF
/// writer. Self-versioned inside the file via `'LFKD'` magic +
/// version byte; the framework just registers the file's presence
/// so the migration runner has a complete world view. A future
/// format bump registers a proper migration that reads the inner
/// version byte.
pub struct KdfArtefact;

impl KdfArtefact {
    pub const FILE_NAME: &'static str = "credentials.kdf";
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
        Ok(self.target_version())
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

    #[test]
    fn config_missing_version_field_is_fatal() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("config.json"), br#"{"theme": "dark"}"#).unwrap();
        let err = ConfigArtefact.read_version(dir.path()).unwrap_err();
        assert!(err.contains("missing"));
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
    fn kdf_present_returns_target() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("credentials.kdf"), b"\x4cFKD\x01...").unwrap();
        assert_eq!(
            KdfArtefact.read_version(dir.path()).unwrap(),
            SchemaVersions::KDF
        );
    }
}
