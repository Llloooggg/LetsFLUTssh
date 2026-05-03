//! `.lfs` archive export orchestrator. Composes the on-disk archive
//! format Dart's `ExportImport` reads, but does the work entirely
//! inside Rust so plaintext credentials never round-trip through the
//! Dart heap during a user-initiated export.
//!
//! # Wire compatibility
//!
//! Output is byte-compatible with the existing Dart writer:
//!
//! - Stored-mode ZIP carrying named entries (manifest.json,
//!   sessions.json, keys.json, …).
//! - Optional outer encryption: `LFSE` magic (4) + version byte
//!   (`0x02` = Argon2id) + KdfParams (algorithm id + memory KiB +
//!   iters + parallelism, 10 bytes for Argon2id) + 32-byte salt +
//!   12-byte IV + AES-256-GCM ciphertext.
//!
//! # Boundary contract
//!
//! Every plaintext byte (session passwords / key PEM / passphrases)
//! is read straight from the encrypted DB into a Rust-owned `Vec<u8>`,
//! threaded through `serde_json::Value` for shape preservation, and
//! handed to AES-GCM. The Dart caller passes only the export options
//! plus the pre-serialised `config_json` string (since `config.json`
//! is file-based, not in `letsflutssh.db`) and receives the encrypted
//! archive bytes ready to write atomically.

use std::collections::{HashMap, HashSet};
use std::io::{Cursor, Read};

use rusqlite::Connection;
use serde_json::Value;
use zip::ZipArchive;

use crate::db::{folders, known_hosts};
use crate::error::Error;

pub mod apply;
pub mod compose;
pub mod envelope;
pub(crate) mod iso8601;
pub mod qr_compose;

pub use apply::{
    apply_pending_import, apply_pending_import_merge, ApplyOptions, ApplyResult, ImportMode,
};
pub use compose::{export_archive, ExportInput, ExportOptions};
pub use envelope::decrypt_archive_with_password;
pub use qr_compose::{qr_export_payload, qr_export_payload_size, QrExportInput, QrExportOptions};

use envelope::ENC_HEADER_MAGIC;

// ---- 5.6 import handle scaffolding -------------------------------
// The import flow is two-phase: Rust decrypts + parses the
// archive, the user reviews a sanitized preview in Dart, then
// the user confirms and Rust applies the cached blob through
// the DAO layer. The handle pattern keeps the decoded entries
// inside Rust so they never round-trip through the Dart heap as
// they would today (`core/import/import_service.dart` walks the
// decoded `ImportResult` Dart-side).
//
// Today the registry only owns the handle slot + sanitized
// preview shape; the apply driver lands in the next 5.6 commit
// alongside the Dart-side `ImportService` retire.

/// Stable handle id for an in-flight import. Allocated Dart-side
/// via `Uuid().v4()` so the same string flows through Riverpod
/// ownership before Rust finishes the decrypt.
pub type ImportHandleId = String;

/// Sanitized preview the FRB layer hands to Dart after
/// `import_decrypt` resolves. Carries counts + non-secret labels
/// so the preview dialog can render without ever materialising
/// session passwords / key PEM bytes on the Dart heap.
#[derive(Debug, Clone)]
pub struct ImportPreview {
    pub schema_version: i64,
    pub session_count: i64,
    pub session_labels: Vec<String>,
    pub manager_key_count: i64,
    pub tag_count: i64,
    pub snippet_count: i64,
    pub empty_folder_count: i64,
    pub has_config: bool,
    pub has_known_hosts: bool,
}

/// Decrypted-but-not-yet-applied import. Held inside the registry
/// under the caller-supplied handle id; the apply driver consumes
/// the entries in place. The actual entry payload is just the
/// raw JSON byte buffers extracted from the ZIP — the apply step
/// parses + writes per-entity through the DAO layer.
#[derive(Debug, Clone)]
pub struct PendingImport {
    pub manifest_json: Option<String>,
    pub sessions_json: Option<String>,
    pub keys_json: Option<String>,
    pub tags_json: Option<String>,
    pub session_tags_json: Option<String>,
    pub folder_tags_json: Option<String>,
    pub snippets_json: Option<String>,
    pub session_snippets_json: Option<String>,
    pub empty_folders_json: Option<String>,
    pub config_json: Option<String>,
    pub known_hosts_text: Option<String>,
}

impl PendingImport {
    pub fn preview(&self, schema_version: i64) -> ImportPreview {
        let session_labels = self
            .sessions_json
            .as_deref()
            .and_then(|s| serde_json::from_str::<Vec<serde_json::Value>>(s).ok())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| {
                        v.get("label")
                            .and_then(|l| l.as_str())
                            .map(|l| l.to_string())
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let session_count = session_labels.len() as i64;
        let manager_key_count = json_array_len(self.keys_json.as_deref());
        let tag_count = json_array_len(self.tags_json.as_deref());
        let snippet_count = json_array_len(self.snippets_json.as_deref());
        let empty_folder_count = json_array_len(self.empty_folders_json.as_deref());
        ImportPreview {
            schema_version,
            session_count,
            session_labels,
            manager_key_count,
            tag_count,
            snippet_count,
            empty_folder_count,
            has_config: self.config_json.as_deref().is_some_and(|s| !s.is_empty()),
            has_known_hosts: self
                .known_hosts_text
                .as_deref()
                .is_some_and(|s| !s.is_empty()),
        }
    }
}

fn json_array_len(s: Option<&str>) -> i64 {
    s.and_then(|s| serde_json::from_str::<Vec<serde_json::Value>>(s).ok())
        .map(|v| v.len() as i64)
        .unwrap_or(0)
}

/// Process-singleton import handle registry. Owned by `AppState`.
pub struct ImportRegistry {
    inner: std::sync::Mutex<std::collections::HashMap<ImportHandleId, PendingImport>>,
}

impl ImportRegistry {
    pub fn new() -> Self {
        Self {
            inner: std::sync::Mutex::new(std::collections::HashMap::new()),
        }
    }

    fn lock(
        &self,
    ) -> std::sync::MutexGuard<'_, std::collections::HashMap<ImportHandleId, PendingImport>> {
        self.inner.lock().expect("import registry mutex poisoned")
    }

    pub fn insert(&self, id: ImportHandleId, pending: PendingImport) {
        self.lock().insert(id, pending);
    }

    pub fn take(&self, id: &str) -> Option<PendingImport> {
        self.lock().remove(id)
    }

    pub fn get_clone(&self, id: &str) -> Option<PendingImport> {
        self.lock().get(id).cloned()
    }

    pub fn drop_handle(&self, id: &str) {
        self.lock().remove(id);
    }

    pub fn count(&self) -> usize {
        self.lock().len()
    }
}

impl Default for ImportRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Serialise the `known_hosts` table to the
/// `host:port keytype base64key\n` text format the apply driver
/// re-reads. `pub(super)` because both [`compose`] and [`qr_compose`]
/// embed the same payload.
pub(super) fn build_known_hosts(conn: &Connection) -> Result<String, Error> {
    let rows = known_hosts::list_all(conn)?;
    if rows.is_empty() {
        return Ok(String::new());
    }
    // Wire format mirrors `KnownHostsManager.exportToString`:
    // `host:port keytype base64key\n` per row.
    let mut out = String::new();
    for r in rows {
        out.push_str(&format!(
            "{}:{} {} {}\n",
            r.host, r.port, r.key_type, r.key_base64
        ));
    }
    Ok(out)
}

/// Build `{folder_id → "Parent/Child/Leaf"}` by walking the
/// `folders` table. Detached / cyclic chains are resolved
/// best-effort: a hop into an unknown parent_id terminates the path
/// at the last reachable node, matching the loader's tolerance.
/// `pub(super)` so both [`compose`] and [`qr_compose`] resolve
/// session folder strings against the same map.
pub(super) fn build_folder_paths(conn: &Connection) -> Result<HashMap<String, String>, Error> {
    let rows = folders::list_all(conn)?;
    let by_id: HashMap<String, &folders::FolderRow> =
        rows.iter().map(|r| (r.id.clone(), r)).collect();
    let mut out = HashMap::new();
    for r in &rows {
        let mut parts: Vec<&str> = Vec::new();
        let mut cursor = Some(r);
        let mut seen: HashSet<&str> = HashSet::new();
        while let Some(node) = cursor {
            if !seen.insert(node.id.as_str()) {
                break;
            }
            parts.push(node.name.as_str());
            cursor = node
                .parent_id
                .as_deref()
                .and_then(|pid| by_id.get(pid).copied());
        }
        parts.reverse();
        out.insert(r.id.clone(), parts.join("/"));
    }
    Ok(out)
}

/// Read every entry in the ZIP and pack the recognised JSON /
/// text payloads into a [`PendingImport`]. Unknown entries are
/// dropped — the apply driver is the source of truth for which
/// entries actually move data, the preview just reports counts.
pub fn parse_pending_import(zip_bytes: &[u8]) -> Result<(PendingImport, i64), Error> {
    let cursor = Cursor::new(zip_bytes);
    let mut zip =
        ZipArchive::new(cursor).map_err(|e| Error::Io(format!("import zip open: {e}")))?;

    let mut pending = PendingImport {
        manifest_json: None,
        sessions_json: None,
        keys_json: None,
        tags_json: None,
        session_tags_json: None,
        folder_tags_json: None,
        snippets_json: None,
        session_snippets_json: None,
        empty_folders_json: None,
        config_json: None,
        known_hosts_text: None,
    };

    for i in 0..zip.len() {
        let mut entry = zip
            .by_index(i)
            .map_err(|e| Error::Io(format!("import zip entry {i}: {e}")))?;
        let name = entry.name().to_string();
        let mut buf = String::new();
        entry
            .read_to_string(&mut buf)
            .map_err(|e| Error::Io(format!("import read {name}: {e}")))?;
        match name.as_str() {
            "manifest.json" => pending.manifest_json = Some(buf),
            "sessions.json" => pending.sessions_json = Some(buf),
            "keys.json" => pending.keys_json = Some(buf),
            "tags.json" => pending.tags_json = Some(buf),
            "session_tags.json" => pending.session_tags_json = Some(buf),
            "folder_tags.json" => pending.folder_tags_json = Some(buf),
            "snippets.json" => pending.snippets_json = Some(buf),
            "session_snippets.json" => pending.session_snippets_json = Some(buf),
            "empty_folders.json" => pending.empty_folders_json = Some(buf),
            "config.json" => pending.config_json = Some(buf),
            "known_hosts.txt" => pending.known_hosts_text = Some(buf),
            _ => {}
        }
    }

    let schema_version = pending
        .manifest_json
        .as_deref()
        .and_then(|s| serde_json::from_str::<Value>(s).ok())
        .and_then(|v| v.get("schema_version").and_then(|x| x.as_i64()))
        .unwrap_or(0);
    Ok((pending, schema_version))
}

/// Read the file at `path`, detect whether it's an LFSE envelope
/// (4-byte magic) or a raw ZIP (`PK\x03\x04`), decrypt+parse, and
/// return the preview the apply driver consumes. The decoded
/// `PendingImport` is *not* registered here — the FRB layer
/// stages it into [`crate::app::AppState::imports`] after the
/// caller approves the preview.
pub fn read_archive_to_pending(
    path: &str,
    password: &str,
) -> Result<(PendingImport, ImportPreview), Error> {
    let bytes = std::fs::read(path).map_err(|e| Error::Io(format!("import read {path}: {e}")))?;
    let zip_bytes: zeroize::Zeroizing<Vec<u8>> =
        if bytes.len() >= 4 && bytes[..4] == ENC_HEADER_MAGIC {
            decrypt_archive_with_password(&bytes, password)?
        } else if bytes.len() >= 4 && &bytes[..4] == b"PK\x03\x04" {
            // Plaintext ZIP — wrap so the buffer drops zeroized for
            // symmetry with the decrypted branch (cheap, harmless,
            // keeps the type uniform).
            zeroize::Zeroizing::new(bytes)
        } else {
            return Err(Error::Io(format!(
                "{path}: not an LFSE archive or ZIP file"
            )));
        };
    let (pending, schema_version) = parse_pending_import(&zip_bytes)?;
    let preview = pending.preview(schema_version);
    Ok((pending, preview))
}

#[cfg(test)]
mod tests {
    use std::io::Write;

    use zip::write::SimpleFileOptions;

    use super::*;

    fn pending_with_sessions(json: &str) -> PendingImport {
        PendingImport {
            manifest_json: None,
            sessions_json: Some(json.to_string()),
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        }
    }

    #[test]
    fn import_registry_round_trip() {
        let reg = ImportRegistry::new();
        let pending = pending_with_sessions(r#"[{"label":"prod"},{"label":"staging"}]"#);
        reg.insert("h1".into(), pending);
        assert_eq!(reg.count(), 1);
        assert!(reg.get_clone("h1").is_some());
        let taken = reg.take("h1").expect("take");
        assert_eq!(reg.count(), 0);
        assert_eq!(
            taken.sessions_json.as_deref(),
            Some(r#"[{"label":"prod"},{"label":"staging"}]"#)
        );
        // Take is idempotent: a second take on a missing id returns None.
        assert!(reg.take("h1").is_none());
    }

    #[test]
    fn import_registry_drop_handle_evicts_silently() {
        let reg = ImportRegistry::new();
        reg.insert("h1".into(), pending_with_sessions("[]"));
        reg.drop_handle("h1");
        reg.drop_handle("h1"); // missing id is a no-op
        assert_eq!(reg.count(), 0);
    }

    #[test]
    fn import_preview_counts_sessions_and_pulls_labels() {
        let pending = pending_with_sessions(
            r#"[{"label":"prod","host":"a"},{"label":"staging","host":"b"}]"#,
        );
        let preview = pending.preview(7);
        assert_eq!(preview.schema_version, 7);
        assert_eq!(preview.session_count, 2);
        assert_eq!(preview.session_labels, vec!["prod", "staging"]);
        assert!(!preview.has_config);
        assert!(!preview.has_known_hosts);
    }

    #[test]
    fn import_preview_handles_malformed_sessions_json() {
        let mut pending = pending_with_sessions("not-actually-json");
        // Corrupted entries decay to zero counts rather than panic —
        // the apply path surfaces the parse error elsewhere.
        let preview = pending.preview(1);
        assert_eq!(preview.session_count, 0);
        assert!(preview.session_labels.is_empty());
        // Missing optional sources also yield zero counts.
        pending.sessions_json = None;
        let preview = pending.preview(1);
        assert_eq!(preview.session_count, 0);
    }

    #[test]
    fn import_preview_flags_config_and_known_hosts() {
        let mut pending = pending_with_sessions("[]");
        pending.config_json = Some("{\"theme\":\"dark\"}".into());
        pending.known_hosts_text = Some("example.com ssh-ed25519 AAAA".into());
        let preview = pending.preview(1);
        assert!(preview.has_config);
        assert!(preview.has_known_hosts);
    }

    #[test]
    fn import_preview_empty_strings_treat_as_absent() {
        let mut pending = pending_with_sessions("[]");
        pending.config_json = Some(String::new());
        pending.known_hosts_text = Some(String::new());
        let preview = pending.preview(1);
        assert!(!preview.has_config);
        assert!(!preview.has_known_hosts);
    }

    fn build_test_zip(entries: &[(&str, &str)]) -> Vec<u8> {
        let mut buf = Cursor::new(Vec::new());
        let mut zw = zip::ZipWriter::new(&mut buf);
        let opts = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
        for (name, body) in entries {
            zw.start_file(*name, opts).unwrap();
            zw.write_all(body.as_bytes()).unwrap();
        }
        zw.finish().unwrap();
        buf.into_inner()
    }

    #[test]
    fn parse_pending_import_picks_known_entries() {
        let zip = build_test_zip(&[
            ("manifest.json", r#"{"schema_version":7}"#),
            ("sessions.json", r#"[{"label":"x"}]"#),
            ("config.json", r#"{"theme":"dark"}"#),
            ("known_hosts.txt", "host ssh-ed25519 AAAA"),
            ("ignored.bin", "garbage"),
        ]);
        let (pending, schema) = parse_pending_import(&zip).expect("parse");
        assert_eq!(schema, 7);
        assert_eq!(pending.sessions_json.as_deref(), Some(r#"[{"label":"x"}]"#));
        assert_eq!(pending.config_json.as_deref(), Some(r#"{"theme":"dark"}"#));
        assert_eq!(
            pending.known_hosts_text.as_deref(),
            Some("host ssh-ed25519 AAAA")
        );
        assert!(pending.keys_json.is_none());
    }

    #[test]
    fn parse_pending_import_zero_schema_when_manifest_missing() {
        let zip = build_test_zip(&[("sessions.json", "[]")]);
        let (_pending, schema) = parse_pending_import(&zip).expect("parse");
        assert_eq!(schema, 0);
    }

    #[test]
    fn json_array_len_handles_object_payload() {
        // The DAO writes top-level arrays today; a future migration
        // could swap to wrapped objects. The helper must not blow
        // up on a non-array — it returns 0 so the preview shows
        // "import contains no entries" rather than panicking.
        assert_eq!(json_array_len(Some(r#"{"sessions":[]}"#)), 0);
        assert_eq!(json_array_len(Some("[]")), 0);
        assert_eq!(json_array_len(Some("[1,2,3]")), 3);
        assert_eq!(json_array_len(None), 0);
    }
}
