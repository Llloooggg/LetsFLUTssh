//! Concrete artefact wrappers the live app registers at startup.
//!
//! Each one is a thin wrapper that knows how to inspect its slice of
//! on-disk state and report the current version. The actual payload
//! reads / writes live in the artefact's storage class (config writer,
//! KDF blob writer, etc) — these wrappers exist only so the migration
//! runner can discover what is on disk.

use std::path::Path;

use serde_json::Value;

use super::{Artefact, Migration, SchemaVersions};

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

/// `config.json` v1 → v2: stamp `security_probe_cache` as an
/// explicit `null` when the v1 writer omitted the field, then bump
/// `config_schema_version` to 2.
///
/// Legacy installs wrote the field only when `security_probe_cache`
/// was `Some(_)`; on `None` they skipped it. That collapsed the
/// "never probed" / "probed-but-empty" semantics on round-trip
/// because `Option::None` and `field-absent` parsed identically.
/// v2 fixes the wire shape so the field is always present (object
/// or `null`); this migration carries every existing file across
/// the cutover so v2 readers see the same explicit shape v2
/// writers produce.
///
/// Atomic — writes via [`crate::path::write_bytes_atomic`] (tmp +
/// fsync + rename) so a crash mid-migration leaves the original v1
/// file untouched on disk.
pub struct ConfigV1ToV2;

impl Migration for ConfigV1ToV2 {
    fn artefact_id(&self) -> &'static str {
        ConfigArtefact::FILE_NAME
    }

    fn source_version(&self) -> i32 {
        1
    }

    fn target_version(&self) -> i32 {
        2
    }

    fn apply(&self, support_dir: &Path) -> Result<(), String> {
        let path = support_dir.join(ConfigArtefact::FILE_NAME);
        let bytes =
            std::fs::read(&path).map_err(|e| format!("read {}: {e}", ConfigArtefact::FILE_NAME))?;
        let mut value: Value = serde_json::from_slice(&bytes)
            .map_err(|e| format!("{}: parse: {e}", ConfigArtefact::FILE_NAME))?;
        let obj = value
            .as_object_mut()
            .ok_or_else(|| format!("{}: not a JSON object", ConfigArtefact::FILE_NAME))?;
        // Explicit-null entry — distinguishes "never probed" from
        // "probed-but-empty" on every subsequent round-trip.
        obj.entry("security_probe_cache").or_insert(Value::Null);
        obj.insert("config_schema_version".into(), Value::from(2));
        let serialised = serde_json::to_vec(&value)
            .map_err(|e| format!("{}: serialise: {e}", ConfigArtefact::FILE_NAME))?;
        crate::path::write_bytes_atomic(&path, &serialised)
            .map_err(|e| format!("{}: write: {e}", ConfigArtefact::FILE_NAME))?;
        Ok(())
    }
}

/// `config.json` v2 → v3: collapse the `keychain_with_password`
/// tier wire value into `keychain` + `security_modifiers.password
/// = true`. The earlier model had `keychain_with_password` as its
/// own tier enum value alongside the orthogonal `password` /
/// `biometric` modifiers — a half-finished migration to the
/// "bank-style" shape (one tier per key-storage strategy + a
/// password modifier on top). v3 finishes the collapse: every
/// stored config that carries the legacy wire value gets rewritten
/// to the bank-style shape on next startup. Reads written under v3
/// never see the legacy string again — the enum is dropped.
///
/// `security_modifiers` is created if absent and `password` is
/// force-set to `true`; any pre-existing modifier fields carry
/// over verbatim.
///
/// Atomic — writes via [`crate::path::write_bytes_atomic`] (tmp +
/// fsync + rename) so a crash mid-migration leaves the v2 file
/// untouched on disk and the runner re-attempts on next boot.
pub struct ConfigV2ToV3;

impl Migration for ConfigV2ToV3 {
    fn artefact_id(&self) -> &'static str {
        ConfigArtefact::FILE_NAME
    }

    fn source_version(&self) -> i32 {
        2
    }

    fn target_version(&self) -> i32 {
        3
    }

    fn apply(&self, support_dir: &Path) -> Result<(), String> {
        let path = support_dir.join(ConfigArtefact::FILE_NAME);
        let bytes =
            std::fs::read(&path).map_err(|e| format!("read {}: {e}", ConfigArtefact::FILE_NAME))?;
        let mut value: Value = serde_json::from_slice(&bytes)
            .map_err(|e| format!("{}: parse: {e}", ConfigArtefact::FILE_NAME))?;
        let obj = value
            .as_object_mut()
            .ok_or_else(|| format!("{}: not a JSON object", ConfigArtefact::FILE_NAME))?;
        // Rewrite the tier wire value if present + legacy.
        if obj.get("security_tier").and_then(Value::as_str) == Some("keychain_with_password") {
            obj.insert("security_tier".into(), Value::from("keychain"));
            // Force `security_modifiers.password = true`. Create the
            // sub-object if the v2 writer omitted it (legacy-default
            // installs that picked KeychainWithPassword without the
            // explicit modifiers shape).
            let modifiers = obj
                .entry("security_modifiers")
                .or_insert_with(|| Value::Object(Default::default()));
            if let Some(map) = modifiers.as_object_mut() {
                map.insert("password".into(), Value::Bool(true));
            } else {
                // The field exists but isn't an object — replace
                // outright with the canonical shape.
                let mut map = serde_json::Map::new();
                map.insert("password".into(), Value::Bool(true));
                *modifiers = Value::Object(map);
            }
        }
        obj.insert("config_schema_version".into(), Value::from(3));
        let serialised = serde_json::to_vec(&value)
            .map_err(|e| format!("{}: serialise: {e}", ConfigArtefact::FILE_NAME))?;
        crate::path::write_bytes_atomic(&path, &serialised)
            .map_err(|e| format!("{}: write: {e}", ConfigArtefact::FILE_NAME))?;
        Ok(())
    }
}

/// `config.json` v3 → v4: drop the legacy `biometric_shortcut`
/// and `pin_length` fields from `security_modifiers`. Both were
/// retained as backward-compat fields after the bank-style
/// password modifier landed: `biometric_shortcut` mirrored
/// `biometric` 1:1 (deprecated alias, no real consumer);
/// `pin_length` was advisory in the bank-style model and had no
/// runtime caller in either Dart or Rust. Dropping them on the
/// next read closes the legacy schema window so the runtime
/// struct stays slim — no parallel state to keep in sync, no
/// drift surface for future agents to step on.
///
/// Idempotent on already-stripped configs (the migration just
/// bumps the version stamp). Atomic — writes via
/// [`crate::path::write_bytes_atomic`] (tmp + fsync + rename) so
/// a crash mid-migration leaves the v3 file untouched.
pub struct ConfigV3ToV4;

impl Migration for ConfigV3ToV4 {
    fn artefact_id(&self) -> &'static str {
        ConfigArtefact::FILE_NAME
    }

    fn source_version(&self) -> i32 {
        3
    }

    fn target_version(&self) -> i32 {
        4
    }

    fn apply(&self, support_dir: &Path) -> Result<(), String> {
        let path = support_dir.join(ConfigArtefact::FILE_NAME);
        let bytes =
            std::fs::read(&path).map_err(|e| format!("read {}: {e}", ConfigArtefact::FILE_NAME))?;
        let mut value: Value = serde_json::from_slice(&bytes)
            .map_err(|e| format!("{}: parse: {e}", ConfigArtefact::FILE_NAME))?;
        let obj = value
            .as_object_mut()
            .ok_or_else(|| format!("{}: not a JSON object", ConfigArtefact::FILE_NAME))?;
        if let Some(modifiers) = obj.get_mut("security_modifiers") {
            if let Some(map) = modifiers.as_object_mut() {
                map.remove("biometric_shortcut");
                map.remove("pin_length");
            }
        }
        obj.insert("config_schema_version".into(), Value::from(4));
        let serialised = serde_json::to_vec(&value)
            .map_err(|e| format!("{}: serialise: {e}", ConfigArtefact::FILE_NAME))?;
        crate::path::write_bytes_atomic(&path, &serialised)
            .map_err(|e| format!("{}: write: {e}", ConfigArtefact::FILE_NAME))?;
        Ok(())
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

    // ── ConfigV1ToV2 ─────────────────────────────────────────────

    #[test]
    fn config_v1_to_v2_inserts_explicit_null_when_field_missing() {
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("config.json"),
            br#"{"config_schema_version":1,"theme":"dark"}"#,
        )
        .unwrap();
        ConfigV1ToV2.apply(dir.path()).expect("apply");
        let bytes = fs::read(dir.path().join("config.json")).unwrap();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        let obj = value.as_object().unwrap();
        assert_eq!(obj.get("config_schema_version"), Some(&Value::from(2)));
        assert_eq!(obj.get("security_probe_cache"), Some(&Value::Null));
        assert_eq!(obj.get("theme"), Some(&Value::String("dark".into())));
    }

    #[test]
    fn config_v1_to_v2_preserves_existing_security_probe_cache_value() {
        let dir = TempDir::new().unwrap();
        // A v1 file that already had a probe-cache object: the
        // migration must leave the cached object in place — only
        // bump the version and stamp `null` on missing field.
        fs::write(
            dir.path().join("config.json"),
            br#"{"config_schema_version":1,"security_probe_cache":{"keychain_probe":"available","hardware_probe_code":"ok"}}"#,
        )
        .unwrap();
        ConfigV1ToV2.apply(dir.path()).expect("apply");
        let bytes = fs::read(dir.path().join("config.json")).unwrap();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        let obj = value.as_object().unwrap();
        assert_eq!(obj.get("config_schema_version"), Some(&Value::from(2)));
        let cache = obj
            .get("security_probe_cache")
            .unwrap()
            .as_object()
            .unwrap();
        assert_eq!(
            cache.get("keychain_probe"),
            Some(&Value::String("available".into()))
        );
    }

    #[test]
    fn config_v1_through_runner_lands_at_current_version() {
        // Pin the framework path: a v1 file passes through the
        // run_on_startup runner and lands at the current
        // SchemaVersions::CONFIG. Counter equals the chain
        // length, so this test stays correct when a future
        // v3→v4 migration lands without a manual edit.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("config.json"),
            br#"{"config_schema_version":1,"theme":"dark"}"#,
        )
        .unwrap();
        let reg = super::super::registry::build_app_registry();
        let report = super::super::run_on_startup(dir.path(), &reg);
        assert!(!report.has_failures(), "report: {report:?}");
        let target = super::super::SchemaVersions::CONFIG;
        // Each step writes one Step entry in the runner report;
        // walking v1 → target costs (target - 1) steps.
        assert_eq!(report.migrated_count(), (target as usize) - 1);
        assert_eq!(ConfigArtefact.read_version(dir.path()).unwrap(), target);
    }

    #[test]
    fn config_v2_to_v3_collapses_legacy_keychain_with_password() {
        // v2-stamped config carrying the legacy
        // `keychain_with_password` tier wire value lands at v3
        // with the tier rewritten to `keychain` and
        // `security_modifiers.password` force-set to true.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("config.json"),
            br#"{
                "config_schema_version": 2,
                "security_tier": "keychain_with_password",
                "security_modifiers": {"password": false, "biometric": false}
            }"#,
        )
        .unwrap();
        ConfigV2ToV3.apply(dir.path()).expect("apply");
        let bytes = fs::read(dir.path().join("config.json")).unwrap();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        let obj = value.as_object().unwrap();
        assert_eq!(obj.get("config_schema_version"), Some(&Value::from(3)));
        assert_eq!(
            obj.get("security_tier").and_then(Value::as_str),
            Some("keychain"),
        );
        let modifiers = obj.get("security_modifiers").unwrap().as_object().unwrap();
        assert_eq!(modifiers.get("password"), Some(&Value::Bool(true)));
    }

    #[test]
    fn config_v2_to_v3_no_op_for_other_tiers() {
        // v2 file already on a non-legacy tier value passes
        // through unchanged except for the version bump.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("config.json"),
            br#"{
                "config_schema_version": 2,
                "security_tier": "hardware",
                "security_modifiers": {"password": true, "biometric": true}
            }"#,
        )
        .unwrap();
        ConfigV2ToV3.apply(dir.path()).expect("apply");
        let bytes = fs::read(dir.path().join("config.json")).unwrap();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        let obj = value.as_object().unwrap();
        assert_eq!(obj.get("config_schema_version"), Some(&Value::from(3)));
        assert_eq!(
            obj.get("security_tier").and_then(Value::as_str),
            Some("hardware"),
        );
        let modifiers = obj.get("security_modifiers").unwrap().as_object().unwrap();
        // The pre-existing modifier values must NOT get overwritten —
        // only `password` is force-set during the legacy-tier path.
        assert_eq!(modifiers.get("password"), Some(&Value::Bool(true)));
        assert_eq!(modifiers.get("biometric"), Some(&Value::Bool(true)));
    }

    #[test]
    fn config_v2_to_v3_creates_modifiers_when_absent() {
        // Legacy install that picked KeychainWithPassword without
        // ever materialising the `security_modifiers` sub-object —
        // migration must mint the object on the spot, not crash.
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("config.json"),
            br#"{
                "config_schema_version": 2,
                "security_tier": "keychain_with_password"
            }"#,
        )
        .unwrap();
        ConfigV2ToV3.apply(dir.path()).expect("apply");
        let bytes = fs::read(dir.path().join("config.json")).unwrap();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        let modifiers = value
            .as_object()
            .unwrap()
            .get("security_modifiers")
            .unwrap()
            .as_object()
            .unwrap();
        assert_eq!(modifiers.get("password"), Some(&Value::Bool(true)));
    }
}
