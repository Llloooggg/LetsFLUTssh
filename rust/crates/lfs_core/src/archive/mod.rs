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
//!   (`0x03` = Argon2id with header-bound AAD; new exports emit
//!   this) + KdfParams (algorithm id + memory KiB + iters +
//!   parallelism, 10 bytes for Argon2id) + 32-byte salt + 12-byte
//!   IV + AES-256-GCM ciphertext. Legacy `0x02` envelopes (empty
//!   AAD) are still accepted on read for backwards compatibility;
//!   see [`envelope`] for the version-dispatch contract.
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

use serde_json::Value;
use zip::ZipArchive;

use crate::db::{folders, known_hosts};
use crate::error::Error;

pub mod apply;
pub mod compose;
pub mod envelope;
pub mod iso8601;

/// Hard upper bound on the on-disk `.lfs` size accepted by
/// [`read_archive_to_pending`]. 256 MiB covers a session library
/// of thousands of entries with key PEM bodies; anything larger
/// is either user error (wrong file picked) or a DoS attempt
/// against the import pipeline. Surfaces as [`Error::Archive`]
/// so the import dialog renders the typed envelope.
pub const MAX_ARCHIVE_BYTES: u64 = 256 * 1024 * 1024;

/// Hard upper bound on the inflated ZIP payload (sum of all
/// uncompressed entry sizes). Defends the import path against a
/// zip-bomb that deflates to many gigabytes; 1 GiB caps the
/// in-RAM materialisation that follows the read.
pub const MAX_DECOMPRESSED_BYTES: u64 = 1024 * 1024 * 1024;
pub mod probe;
pub mod qr_compose;

pub use apply::{
    apply_pending_import, apply_pending_import_merge, apply_pending_to_db,
    apply_recordings_to_filesystem, ApplyMode, ApplyOptions, ApplyOutcome, ApplyResult, ImportMode,
    RecordingApplyOutcome,
};
pub use compose::{export_archive, export_archive_size, ExportInput, ExportOptions};
pub use envelope::decrypt_archive_with_password;
pub use qr_compose::{qr_export_payload, qr_export_payload_size, QrExportInput, QrExportOptions};

/// Compute the set of "relevant" empty-folder paths for an
/// archive export selection. The export dialog gates which
/// folders ride along with a partial selection so the receiving
/// side can rebuild the same hierarchy without leaking unrelated
/// branches of the user's folder tree.
///
/// The caller passes the selected sessions' folder paths
/// (deduplicated by the caller is fine but not required), the
/// source set of currently-empty folders from the live tree, and
/// an `all_selected` flag set when every session is in the
/// selection.
///
/// Result is the union of:
///   1. every ancestor path of each selected session's folder
///      (`a/b/c` -> `a`, `a/b`),
///   2. every entry in `source_empty_folders` that is the
///      selected folder itself, an ancestor of a selected
///      folder, or a descendant of a selected folder,
///   3. every entry in `source_empty_folders` unconditionally
///      when `all_selected` is true (export the full structure).
///
/// Returned vector is deduplicated and sorted lexicographically
/// so callers comparing two results don't have to re-sort.
pub fn resolve_relevant_empty_folders(
    selected_session_folders: &[String],
    source_empty_folders: &[String],
    all_selected: bool,
) -> Vec<String> {
    let mut result: HashSet<String> = HashSet::new();

    // Ancestor expansion: every prefix of every selected folder.
    // Keeps the export payload self-describing for receivers that
    // rely on the emptyFolders set to reconstruct hierarchy.
    for folder in selected_session_folders {
        if folder.is_empty() {
            continue;
        }
        let parts: Vec<&str> = folder.split('/').collect();
        for i in 1..parts.len() {
            result.insert(parts[..i].join("/"));
        }
    }

    let selected: Vec<&str> = selected_session_folders
        .iter()
        .map(String::as_str)
        .collect();
    for folder in source_empty_folders {
        if all_selected {
            result.insert(folder.clone());
            continue;
        }
        let related = selected.iter().any(|sel| {
            *sel == folder.as_str()
                || sel.starts_with(&format!("{folder}/"))
                || folder.starts_with(&format!("{sel}/"))
        });
        if related {
            result.insert(folder.clone());
        }
    }
    let mut out: Vec<String> = result.into_iter().collect();
    out.sort();
    out
}

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
    /// Number of `.cast` recordings the archive carried. The preview
    /// dialog renders this as a "X recordings" line so the user
    /// sees the upcoming write into `<support>/recordings/imported/`
    /// before approving the apply.
    pub recording_count: i64,
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
    /// Paired OpenSSH certificate rows (`ssh_key_certificates`).
    pub ssh_key_certificates_json: Option<String>,
    /// WebDAV per-session config (`webdav_session_details`). The
    /// credential bytes stay in the source device's SecretStore;
    /// only the opaque secret-id pointer travels.
    pub webdav_session_details_json: Option<String>,
    /// S3 per-session config (`s3_session_details`). Same
    /// opaque-secret-id discipline as WebDAV — access key id
    /// travels, secret access key bytes don't.
    pub s3_session_details_json: Option<String>,
    /// Per-session SFTP bookmarks (`sftp_bookmarks`). Tombstone-aware.
    pub sftp_bookmarks_json: Option<String>,
    /// Local / Remote / Dynamic port-forward rules
    /// (`port_forward_rules`).
    pub port_forward_rules_json: Option<String>,
    /// Plaintext `.cast` recordings the archive shipped. Bundled
    /// when the sender ticked the "Recordings" checkbox in the
    /// export dialog. Apply step writes each entry to
    /// `<support>/recordings/imported/<session_id>/<file_name>`
    /// and (when the receiver has an active DB key) re-encrypts
    /// them via [`crate::recorder::migrate::convert_all_cast_to_lfsr`]
    /// so the local tier discipline matches every other file
    /// under the recordings root. Empty `Vec` when the archive
    /// did not ship recordings.
    pub recordings: Vec<PendingRecording>,
}

/// One recording carried by an `.lfs` archive. The `bytes` payload
/// is asciinema-v2 plaintext (`.cast`); encrypted senders decrypt
/// at compose time so the receiver can play / re-encrypt without
/// needing the sender's DB key.
#[derive(Debug, Clone)]
pub struct PendingRecording {
    pub session_id: String,
    pub file_name: String,
    pub bytes: Vec<u8>,
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
            recording_count: self.recordings.len() as i64,
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
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
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

/// Decoded `recordings/<session_id>/<file_name>` zip entry path.
/// Returned by [`parse_recording_entry_path`] when the entry sits
/// under the recordings prefix; the caller binds the two segments
/// straight into [`PendingRecording`].
struct RecordingEntryPath {
    session_id: String,
    file_name: String,
}

/// Parse an `recordings/<session_id>/<file_name>` zip entry path.
/// Returns `Some(...)` only when the path has exactly three
/// forward-slash-separated segments starting with the `recordings`
/// prefix and the session_id / file_name are safe (no `..`, no
/// nested separators, non-empty). Anything else — sub-sub paths,
/// embedded `..`, empty components — returns `None` and the caller
/// drops the entry as unrecognised.
///
/// Path traversal defence: the apply step writes
/// `<recordings_root>/imported/<session_id>/<file_name>`. Without
/// the `..` reject, a hostile archive entry like
/// `recordings/..%2F..%2Fetc%2Fpasswd/foo.cast` could escape the
/// recordings tree. The `==` equality checks below collapse every
/// such shape into `None`.
fn parse_recording_entry_path(raw: &str) -> Option<RecordingEntryPath> {
    let stripped = raw.strip_prefix("recordings/")?;
    let parts: Vec<&str> = stripped.split('/').collect();
    if parts.len() != 2 {
        return None;
    }
    let session_id = parts[0];
    let file_name = parts[1];
    if session_id.is_empty() || file_name.is_empty() {
        return None;
    }
    if session_id == "." || session_id == ".." || session_id.contains('\\') {
        return None;
    }
    if file_name == "." || file_name == ".." || file_name.contains('\\') {
        return None;
    }
    // `.cast` only — encrypted senders decrypt at compose time so
    // every recording inside the archive is plaintext asciinema.
    // A stray `.lfsr` entry is a forward-compat shape we do not
    // know how to handle yet; reject so the importer drops it via
    // the unknown-entry log path.
    if !file_name.to_ascii_lowercase().ends_with(".cast") {
        return None;
    }
    Some(RecordingEntryPath {
        session_id: session_id.to_string(),
        file_name: file_name.to_string(),
    })
}

/// Serialise the `known_hosts` table to the
/// `host:port keytype base64key\n` text format the apply driver
/// re-reads. `pub(super)` because both [`compose`] and [`qr_compose`]
/// embed the same payload.
pub(super) fn build_known_hosts(conn: &impl crate::db::DbAccess) -> Result<String, Error> {
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
pub(super) fn build_folder_paths(
    conn: &impl crate::db::DbAccess,
) -> Result<HashMap<String, String>, Error> {
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
        ZipArchive::new(cursor).map_err(|e| Error::Archive(format!("import zip open: {e}")))?;
    // Sum the uncompressed sizes of every entry before reading any —
    // a zip-bomb that deflates to many gigabytes lands on the cap
    // here instead of OOMing the parse loop.
    let mut total_uncompressed: u64 = 0;
    for i in 0..zip.len() {
        let entry = zip
            .by_index(i)
            .map_err(|e| Error::Archive(format!("import zip entry {i}: {e}")))?;
        total_uncompressed = total_uncompressed.saturating_add(entry.size());
        if total_uncompressed > MAX_DECOMPRESSED_BYTES {
            return Err(Error::Archive(format!(
                "import zip uncompressed {total_uncompressed} bytes exceeds {MAX_DECOMPRESSED_BYTES}-byte cap"
            )));
        }
    }

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
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
    };

    for i in 0..zip.len() {
        let mut entry = zip
            .by_index(i)
            .map_err(|e| Error::Archive(format!("import zip entry {i}: {e}")))?;
        let name = entry.name().to_string();
        // Bound the read on the actual decompressed bytes — the
        // pre-loop above sums declared `entry.size()` against
        // MAX_DECOMPRESSED_BYTES, but a hostile archive can lie
        // about its size header and explode at extract time.
        // `take(cap+1)` lets us catch the over-cap case as a
        // post-read length check without pre-allocating cap bytes.
        let cap = MAX_DECOMPRESSED_BYTES;
        // Recording payloads use the `read_to_end` binary path so
        // the entry's bytes survive UTF-8 sniffing intact — even
        // though `.cast` files are valid UTF-8 by spec, going
        // through `read_to_string` for every entry path adds an
        // invariant the format does not enforce.
        if let Some(rec) = parse_recording_entry_path(&name) {
            let mut bytes: Vec<u8> = Vec::new();
            std::io::Read::take(&mut entry, cap.saturating_add(1))
                .read_to_end(&mut bytes)
                .map_err(|e| Error::Archive(format!("import read {name}: {e}")))?;
            if bytes.len() as u64 > cap {
                return Err(Error::Archive(format!(
                    "import zip entry {name}: decompressed size exceeds {cap}-byte cap (zip bomb?)"
                )));
            }
            pending.recordings.push(PendingRecording {
                session_id: rec.session_id,
                file_name: rec.file_name,
                bytes,
            });
            continue;
        }
        let mut buf = String::new();
        std::io::Read::take(&mut entry, cap.saturating_add(1))
            .read_to_string(&mut buf)
            .map_err(|e| Error::Archive(format!("import read {name}: {e}")))?;
        if buf.len() as u64 > cap {
            return Err(Error::Archive(format!(
                "import zip entry {name}: decompressed size exceeds {cap}-byte cap (zip bomb?)"
            )));
        }
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
            "ssh_key_certificates.json" => pending.ssh_key_certificates_json = Some(buf),
            "webdav_session_details.json" => pending.webdav_session_details_json = Some(buf),
            "s3_session_details.json" => pending.s3_session_details_json = Some(buf),
            "sftp_bookmarks.json" => pending.sftp_bookmarks_json = Some(buf),
            "port_forward_rules.json" => pending.port_forward_rules_json = Some(buf),
            other => {
                // Unknown entry — log so a forward-compat archive
                // (a future build that ships an extra payload like
                // `recordings_index.json`) is greppable in support
                // traces, then drop. The schema-version check at
                // the caller catches the "future build" case
                // explicitly; logging here means a malformed v1
                // archive with stray content also leaves a trail
                // rather than silently disappearing into the void.
                crate::app_log_warn!(
                    "ArchiveImport",
                    "unknown archive entry '{}' (size={}): dropped",
                    other,
                    buf.len()
                );
            }
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

/// Extract the optional `sync_origin` field from a parsed
/// [`PendingImport`]. Returns `None` when the manifest is absent,
/// the field is missing (legacy v1 archives), or the value is not
/// a string. The sync orchestrator
/// ([`crate::sync::pull`]) uses this to detect "this is my own
/// push echoing back" without re-parsing the manifest in two
/// places.
pub fn parse_sync_origin(pending: &PendingImport) -> Option<String> {
    let manifest = pending.manifest_json.as_deref()?;
    let value: Value = serde_json::from_str(manifest).ok()?;
    value
        .get("sync_origin")
        .and_then(|x| x.as_str())
        .filter(|s| !s.is_empty())
        .map(String::from)
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
    // Pre-check the on-disk size before reading into RAM so a
    // user picking a 50 GiB file by accident (or hostile drop)
    // surfaces as a typed Archive error instead of consuming
    // memory until the import pipeline OOMs.
    let meta =
        std::fs::metadata(path).map_err(|e| Error::Archive(format!("import stat {path}: {e}")))?;
    if meta.len() > MAX_ARCHIVE_BYTES {
        return Err(Error::Archive(format!(
            "{path}: archive {} bytes exceeds {MAX_ARCHIVE_BYTES}-byte cap",
            meta.len()
        )));
    }
    let bytes =
        std::fs::read(path).map_err(|e| Error::Archive(format!("import read {path}: {e}")))?;
    let zip_bytes: zeroize::Zeroizing<Vec<u8>> =
        if bytes.len() >= 4 && bytes[..4] == ENC_HEADER_MAGIC {
            decrypt_archive_with_password(&bytes, password)?
        } else if bytes.len() >= 4 && &bytes[..4] == b"PK\x03\x04" {
            // Plaintext ZIP — wrap so the buffer drops zeroized for
            // symmetry with the decrypted branch (cheap, harmless,
            // keeps the type uniform).
            zeroize::Zeroizing::new(bytes)
        } else {
            return Err(Error::Archive(format!(
                "{path}: not an LFSE archive or ZIP file"
            )));
        };
    let (pending, schema_version) = parse_pending_import(&zip_bytes)?;
    let supported = i64::from(crate::migration::SchemaVersions::ARCHIVE);
    // Reject out-of-range values explicitly. Negative or zero
    // can only come from a malformed manifest (a sentinel); the
    // pre-check posture rejects future-version too. The error
    // variant carries the raw `i64` so a 64-bit value lands on
    // the wire / log trace verbatim.
    if !(1..=supported).contains(&schema_version) {
        return Err(Error::ArchiveFutureVersion {
            found: schema_version,
            supported: crate::migration::SchemaVersions::ARCHIVE,
        });
    }
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
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
            recordings: Vec::new(),
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
    fn read_archive_to_pending_rejects_future_version() {
        // Future-version manifest stamped by a hypothetical newer
        // build. Current build supports SchemaVersions::ARCHIVE = 1
        // and must refuse rather than silently apply whatever subset
        // of fields it understands.
        let zip = build_test_zip(&[
            ("manifest.json", r#"{"schema_version":99}"#),
            ("sessions.json", "[]"),
        ]);
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("future.lfs");
        std::fs::write(&path, &zip).unwrap();
        let err = read_archive_to_pending(path.to_str().unwrap(), "")
            .expect_err("future-version archive must error");
        match err {
            Error::ArchiveFutureVersion { found, supported } => {
                assert_eq!(found, 99);
                assert_eq!(supported, crate::migration::SchemaVersions::ARCHIVE);
            }
            other => panic!("expected ArchiveFutureVersion, got {other:?}"),
        }
    }

    #[test]
    fn read_archive_to_pending_accepts_current_version() {
        let zip = build_test_zip(&[
            (
                "manifest.json",
                &format!(
                    "{{\"schema_version\":{}}}",
                    crate::migration::SchemaVersions::ARCHIVE
                ),
            ),
            ("sessions.json", "[]"),
        ]);
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("current.lfs");
        std::fs::write(&path, &zip).unwrap();
        let (_pending, preview) =
            read_archive_to_pending(path.to_str().unwrap(), "").expect("current version");
        assert_eq!(
            preview.schema_version,
            i64::from(crate::migration::SchemaVersions::ARCHIVE),
        );
    }

    #[test]
    fn read_archive_to_pending_accepts_legacy_v1_manifest() {
        // v1 archives written before the sync_origin field existed
        // must still import — `1..=ARCHIVE` is the supported range
        // and the v3 manifest is a superset of the v1 wire shape.
        let zip = build_test_zip(&[
            ("manifest.json", r#"{"schema_version":1}"#),
            ("sessions.json", "[]"),
        ]);
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("v1.lfs");
        std::fs::write(&path, &zip).unwrap();
        let (_pending, preview) =
            read_archive_to_pending(path.to_str().unwrap(), "").expect("legacy v1");
        assert_eq!(preview.schema_version, 1);
    }

    /// v1 archive carrying every typed slot the reader knows about —
    /// manifest, sessions, child tables, `sync_origin`. Pins that
    /// the slim `read_archive_to_pending` accepts the current shape
    /// end-to-end without surfacing unknown-entry warnings. The
    /// forward-version gate is covered by the
    /// `rejects_future_version` test above.
    #[test]
    fn read_archive_to_pending_v1_with_all_typed_slots_parses() {
        let zip = build_test_zip(&[
            (
                "manifest.json",
                r#"{"schema_version":1,"sync_origin":"install-x:42"}"#,
            ),
            ("sessions.json", "[]"),
            ("ssh_key_certificates.json", "[]"),
            ("webdav_session_details.json", "[]"),
            ("s3_session_details.json", "[]"),
            ("sftp_bookmarks.json", "[]"),
            ("port_forward_rules.json", "[]"),
        ]);
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("v1-full.lfs");
        std::fs::write(&path, &zip).unwrap();
        let (pending, preview) =
            read_archive_to_pending(path.to_str().unwrap(), "").expect("v1 parse");
        assert_eq!(preview.schema_version, 1);
        assert!(pending.ssh_key_certificates_json.is_some());
        assert!(pending.webdav_session_details_json.is_some());
        assert!(pending.s3_session_details_json.is_some());
        assert!(pending.sftp_bookmarks_json.is_some());
        assert!(pending.port_forward_rules_json.is_some());
    }

    #[test]
    fn parse_sync_origin_extracts_field_from_manifest() {
        let pending = PendingImport {
            manifest_json: Some(r#"{"schema_version":2,"sync_origin":"inst-1:42"}"#.into()),
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
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
            recordings: Vec::new(),
        };
        assert_eq!(parse_sync_origin(&pending).as_deref(), Some("inst-1:42"));
    }

    #[test]
    fn parse_sync_origin_returns_none_when_field_absent_or_empty() {
        let mut pending = PendingImport {
            manifest_json: Some(r#"{"schema_version":2}"#.into()),
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
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
            recordings: Vec::new(),
        };
        assert!(parse_sync_origin(&pending).is_none());
        pending.manifest_json = Some(r#"{"schema_version":2,"sync_origin":""}"#.into());
        assert!(parse_sync_origin(&pending).is_none());
        pending.manifest_json = None;
        assert!(parse_sync_origin(&pending).is_none());
    }

    #[test]
    fn resolve_relevant_empty_folders_empty_selection_returns_empty() {
        let out = resolve_relevant_empty_folders(&[], &[], false);
        assert!(out.is_empty());
    }

    #[test]
    fn resolve_relevant_empty_folders_pulls_in_ancestors_of_selected_folders() {
        let selected = vec!["a/b/c".to_string()];
        let source: Vec<String> = vec![];
        let out = resolve_relevant_empty_folders(&selected, &source, false);
        assert_eq!(out, vec!["a".to_string(), "a/b".to_string()]);
    }

    #[test]
    fn resolve_relevant_empty_folders_includes_descendants_skips_unrelated() {
        let selected = vec!["a".to_string()];
        let source = vec!["a/x".to_string(), "b".to_string(), "root".to_string()];
        let out = resolve_relevant_empty_folders(&selected, &source, false);
        assert!(out.contains(&"a/x".to_string()));
        assert!(!out.contains(&"b".to_string()));
        assert!(!out.contains(&"root".to_string()));
    }

    #[test]
    fn resolve_relevant_empty_folders_all_selected_includes_every_source_folder() {
        let selected = vec!["prod/web".to_string()];
        let source = vec!["prod".to_string(), "stg".to_string(), "archive".to_string()];
        let out = resolve_relevant_empty_folders(&selected, &source, true);
        assert!(out.contains(&"prod".to_string()));
        assert!(out.contains(&"stg".to_string()));
        assert!(out.contains(&"archive".to_string()));
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
