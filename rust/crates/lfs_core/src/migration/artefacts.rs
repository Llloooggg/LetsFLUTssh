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

/// `security_pass_hash.bin` — keychain password gate. Wire format
/// is a single-line JSON envelope `{"v": N, "salt": "<b64>", "hmac":
/// "<b64>"}`. The `v` field is the schema marker; missing field on
/// an otherwise-parseable object is the implicit pre-version v1
/// (mirrors the [`ConfigArtefact`] pre-cutover fallback). Anything
/// else (bad JSON, non-object, non-integer `v`, base64 decode
/// failure on the hmac/salt fields) is corrupt → caller routes the
/// reset cascade.
pub struct PassGateArtefact;

impl PassGateArtefact {
    pub const FILE_NAME: &'static str = "security_pass_hash.bin";
    const VERSION_FIELD: &'static str = "v";
}

impl Artefact for PassGateArtefact {
    fn id(&self) -> &'static str {
        Self::FILE_NAME
    }

    fn target_version(&self) -> i32 {
        SchemaVersions::PASS_GATE
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
            // Missing field on a parseable object = pre-version
            // install. Implicit v1 (matches the
            // `decode_disk_blob` accept-on-missing branch).
            None => Ok(1),
            Some(_) => Err(format!(
                "{}: non-integer {}",
                Self::FILE_NAME,
                Self::VERSION_FIELD
            )),
        }
    }
}

/// `hardware_vault_salt.bin` — raw 32-byte salt sibling-file used by
/// the Apple / Android hardware vault paths (Linux co-locates the
/// salt inside the vault envelope so the salt file does not exist
/// there). The on-disk shape is unversioned plaintext bytes; the
/// only health probe is "file present and has the canonical
/// length". Since v1 is the only shape, presence implies v1; an
/// unexpected length surfaces as corrupt so the runner can route
/// the reset cascade rather than silently treating a truncated
/// salt as up-to-date.
pub struct HwSaltArtefact;

impl HwSaltArtefact {
    pub const FILE_NAME: &'static str = "hardware_vault_salt.bin";
    /// Canonical salt length stamped by every Apple / Android
    /// vault writer. A different size on disk = corrupt.
    const EXPECTED_LEN: u64 = 32;
}

impl Artefact for HwSaltArtefact {
    fn id(&self) -> &'static str {
        Self::FILE_NAME
    }

    fn target_version(&self) -> i32 {
        SchemaVersions::HW_SALT
    }

    fn read_version(&self, support_dir: &Path) -> Result<i32, String> {
        let file = support_dir.join(Self::FILE_NAME);
        let meta = match std::fs::metadata(&file) {
            Ok(m) => m,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(-1),
            Err(e) => return Err(format!("stat {}: {e}", Self::FILE_NAME)),
        };
        if meta.len() != Self::EXPECTED_LEN {
            return Err(format!(
                "{}: unexpected length ({} bytes, want {})",
                Self::FILE_NAME,
                meta.len(),
                Self::EXPECTED_LEN
            ));
        }
        Ok(1)
    }
}

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
        // The Artefact contract reserves `< 1` for "absent" (-1) and
        // requires every other sub-1 value to be a corrupt-state `Err`,
        // not a made-up version. A literal `0` version byte is a
        // corrupt header — surface it so the runner routes the user
        // through reset instead of walking a migration chain from 0.
        if version < 1 {
            return Err(format!(
                "{}: invalid schema version {version} (must be ≥ 1)",
                Self::FILE_NAME
            ));
        }
        Ok(version)
    }
}
#[cfg(test)]
#[path = "../../tests/unit/migration_artefacts.rs"]
mod tests;
