//! `.lfs` archive composer — turns a [`crate::db`] state plus a
//! caller-built [`ExportInput`] into the stored-mode ZIP that the
//! LFSE envelope wraps. The crypto envelope itself lives next door
//! in [`super::envelope`]; this module owns wire-shape decisions
//! (entry names, JSON field order, default-omission rules) and the
//! per-entity DB → `serde_json::Value` builders.
//!
//! # Why each entity gets its own builder
//!
//! Sessions / keys / tags / snippets / known-hosts each have their
//! own DAO, their own toggle in [`ExportOptions`], and their own
//! "skip when empty" branch — peeling them apart keeps the export
//! orchestrator readable and makes per-entity wire changes a
//! one-helper edit. The Dart importer (`lib/core/import/
//! import_service.dart`) parses the same shapes; bumping any field
//! name without updating the apply-side parser is a wire break.
//!
//! Plaintext credentials (session passwords, key PEM, passphrases)
//! are read straight from the encrypted DB into Rust-owned strings
//! and threaded through [`Value`] without ever materialising on the
//! Dart heap. The orchestrator hands the raw ZIP bytes to
//! [`super::envelope::encrypt_with_password`] when a master password
//! is set, so the file the user picks in the save dialog is either
//! a raw ZIP (no password) or an LFSE envelope wrapping it.

use std::collections::{HashMap, HashSet};
use std::io::{Cursor, Write};

use serde_json::{json, Value};
use zip::write::SimpleFileOptions;

use crate::db::{
    folders, port_forwards, s3_sessions, sessions, sftp_bookmarks, snippets, ssh_key_certificates,
    ssh_keys, tags, webdav_sessions,
};
use crate::error::Error;

use super::envelope::encrypt_with_password;
use super::iso8601::format_iso8601_utc;
use super::{build_folder_paths, build_known_hosts};

/// What sections the caller wants in the archive. Mirrors the bool
/// fields on `ExportOptions` Dart-side; the orchestrator only emits
/// an entry when its toggle is on AND the underlying source has
/// content.
#[derive(Debug, Clone, Default)]
pub struct ExportOptions {
    pub include_sessions: bool,
    pub include_known_hosts: bool,
    pub include_config: bool,
    pub include_tags: bool,
    pub include_snippets: bool,
    /// True → include every manager key. False → include only the
    /// keys referenced by `selected_session_ids` via their `keyId`.
    pub include_all_manager_keys: bool,
    /// True when the user opted into shipping any manager keys at
    /// all. When false, no `keys.json` entry is written even if the
    /// previous toggle is true.
    pub has_manager_keys: bool,
    /// True → bundle every `.cast` / `.lfsr` under the recordings
    /// tree into the archive as plaintext `.cast` files (encrypted
    /// recordings are decrypted at compose time with the current
    /// DB key — see `ExportInput.recording_db_key` — so the
    /// receiver can play them regardless of their own DB key).
    /// False → recordings section is skipped entirely.
    pub include_recordings: bool,
}

/// Inputs to [`export_archive`]. Sessions / folders / tags / snippets
/// / known-hosts come straight from `letsflutssh.db`; only `config_json`
/// is passed through from Dart because `config.json` lives on disk.
#[derive(Debug, Clone)]
pub struct ExportInput {
    pub options: ExportOptions,
    pub selected_session_ids: Vec<String>,
    pub selected_empty_folders: Vec<String>,
    /// Pre-serialised `config.json` payload (Dart calls
    /// `AppConfig.toJsonForExport()`). Embedded verbatim when
    /// `options.include_config` is true.
    pub config_json: String,
    pub schema_version: i64,
    pub app_version: Option<String>,
    /// `None` → write the raw ZIP. `Some(pw)` → outer Argon2id +
    /// AES-GCM envelope. Empty string is treated as no encryption,
    /// matching the Dart-side contract.
    pub master_password: Option<String>,
    /// Argon2id parameters when `master_password` is set. The
    /// canonical production profile lives in
    /// `lfs_core::security::master_password::KdfParams::defaults`
    /// (64 MiB / t=3 / p=1) and Dart's `KdfParams.productionDefaults`
    /// mirrors it at startup.
    pub kdf_memory_kib: u32,
    pub kdf_iterations: u32,
    pub kdf_parallelism: u32,
    /// Unix millis to stamp into `manifest.created_at`. Passed in
    /// rather than read from the system clock so callers can pin a
    /// deterministic timestamp during tests.
    pub created_at_ms: i64,
    /// Caller-supplied identity stamp written into
    /// `manifest.sync_origin`. The sync orchestrator
    /// (`crate::sync`) stamps a unique
    /// `<install-id>:<unix_ms>` token on every push; a peer
    /// device's pull recognises "this is my own push echoing
    /// back" by comparing the field against its own stamp and
    /// skips applying the archive. `None` emits no field — manual
    /// exports from the Data → Export dialog leave it absent.
    pub sync_origin: Option<String>,
    /// Root of the recordings tree to bundle when
    /// `options.include_recordings` is true. Typically
    /// `<support_dir>/recordings`. `None` skips the recordings
    /// section even if the option is on — convenient for tests
    /// that compose without touching the filesystem.
    pub recordings_root: Option<std::path::PathBuf>,
    /// DB key the writer uses to unwrap `.lfsr` headers at compose
    /// time. The archive ships plaintext `.cast` files so the
    /// receiver does not need the sender's DB key to play them
    /// back. `None` → only plain `.cast` recordings make it into
    /// the archive; any encountered `.lfsr` is skipped with a
    /// warn-level log entry.
    pub recording_db_key: Option<[u8; 32]>,
}

/// Compose and (optionally) encrypt the `.lfs` archive.
///
/// Returns the bytes the caller writes atomically to the chosen
/// path. Errors at any stage abort the archive — partial output is
/// never returned, mirroring Dart's `tmp + rename` discipline.
pub fn export_archive(
    conn: &impl crate::db::DbAccess,
    input: &ExportInput,
) -> Result<Vec<u8>, Error> {
    let zip_bytes = build_zip(conn, input)?;

    let pw = input.master_password.as_deref().unwrap_or("");
    if pw.is_empty() {
        return Ok(zip_bytes);
    }

    encrypt_with_password(
        &zip_bytes,
        pw,
        input.kdf_memory_kib,
        input.kdf_iterations,
        input.kdf_parallelism,
    )
}

/// LFSE envelope overhead added when `master_password` is set.
/// Stays a constant regardless of inner ZIP size:
/// magic (4) + version (1) + KDF params block (10 — algo byte +
/// memory u32 BE + iterations u32 BE + parallelism u8) + salt (32)
/// + IV (12) + AES-GCM tag (16) = 75 bytes.
const LFSE_ENVELOPE_OVERHEAD: u32 = 4 + 1 + 10 + 32 + 12 + 16;

/// Size of the `.lfs` archive bytes for the current selection,
/// without running the Argon2id KDF or AES-GCM encryption pass.
/// Drives the live "archive size" preview line in the Dart export
/// dialog: composes the inner ZIP exactly the way `export_archive`
/// would, then adds the LFSE envelope's fixed overhead when the
/// master password slot is set.
///
/// `master_password` is only consulted to decide whether to add
/// the envelope-overhead constant — the bytes themselves are never
/// inspected, so the caller can hand an empty `Vec<u8>` if it
/// hasn't asked the user for the password yet but wants the
/// encrypted-shape size.
pub fn export_archive_size(
    conn: &impl crate::db::DbAccess,
    input: &ExportInput,
) -> Result<u32, Error> {
    let zip_bytes = build_zip(conn, input)?;
    let inner = u32::try_from(zip_bytes.len()).unwrap_or(u32::MAX);
    let encrypted = !input.master_password.as_deref().unwrap_or("").is_empty();
    Ok(if encrypted {
        inner.saturating_add(LFSE_ENVELOPE_OVERHEAD)
    } else {
        inner
    })
}

fn build_zip(conn: &impl crate::db::DbAccess, input: &ExportInput) -> Result<Vec<u8>, Error> {
    let mut buf = Cursor::new(Vec::new());
    let mut zw = zip::ZipWriter::new(&mut buf);
    let opts = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);

    write_manifest(&mut zw, opts, input)?;

    // Tombstoned rows travel only on the sync wire, not in manual
    // `.lfs` archive exports. Sync push stamps a non-empty
    // `sync_origin` on the manifest; manual exports leave the field
    // absent. The flag is computed up-front because the sessions /
    // keys / tags / snippets composers all gate tombstone emission
    // on it, mirroring the v3 child-table composers below.
    let sync_mode = input.sync_origin.as_deref().is_some_and(|s| !s.is_empty());

    if input.options.include_sessions {
        let folder_paths = build_folder_paths(conn)?;
        let sessions_value =
            build_sessions_value(conn, &input.selected_session_ids, &folder_paths, sync_mode)?;
        write_json_entry(&mut zw, opts, "sessions.json", &sessions_value)?;
        if !input.selected_empty_folders.is_empty() {
            let value = Value::Array(
                input
                    .selected_empty_folders
                    .iter()
                    .map(|s| Value::String(s.clone()))
                    .collect(),
            );
            write_json_entry(&mut zw, opts, "empty_folders.json", &value)?;
        }
    }

    if input.options.has_manager_keys {
        let keys_value = build_manager_keys_value(
            conn,
            &input.selected_session_ids,
            input.options.include_all_manager_keys,
            sync_mode,
        )?;
        if let Some(value) = keys_value {
            write_json_entry(&mut zw, opts, "keys.json", &value)?;
        }
    }

    if input.options.include_config && !input.config_json.is_empty() {
        write_text_entry(&mut zw, opts, "config.json", &input.config_json)?;
    }

    if input.options.include_known_hosts {
        let kh = build_known_hosts(conn)?;
        if !kh.is_empty() {
            // Entry name must match `parse_pending_import`'s reader
            // (`archive/mod.rs::parse_pending_import` keys on
            // `"known_hosts.txt"`); writing the bare name silently
            // dropped every known-hosts payload at import time.
            write_text_entry(&mut zw, opts, "known_hosts.txt", &kh)?;
        }
    }

    if input.options.include_tags {
        if let Some(tags_value) = build_tags_value(conn, sync_mode)? {
            write_json_entry(&mut zw, opts, "tags.json", &tags_value)?;

            if let Some(session_tags) = build_session_tags_value(conn, &input.selected_session_ids)?
            {
                write_json_entry(&mut zw, opts, "session_tags.json", &session_tags)?;
            }

            if let Some(folder_tags) = build_folder_tags_value(conn)? {
                write_json_entry(&mut zw, opts, "folder_tags.json", &folder_tags)?;
            }
        }
    }

    if input.options.include_snippets {
        if let Some(snippets_value) = build_snippets_value(conn, sync_mode)? {
            write_json_entry(&mut zw, opts, "snippets.json", &snippets_value)?;
            if let Some(session_snippets) =
                build_session_snippets_value(conn, &input.selected_session_ids)?
            {
                write_json_entry(&mut zw, opts, "session_snippets.json", &session_snippets)?;
            }
        }
    }

    // v3 child-table entries. Each piggy-backs on an existing
    // include toggle so the user does not need a separate checkbox
    // for every newly-portable table:
    // - `ssh_key_certificates` follows `has_manager_keys` (a cert
    //   without its parent key is meaningless).
    // - `webdav_session_details`, `s3_session_details`,
    //   `sftp_bookmarks`, `port_forward_rules` follow `include_sessions`
    //   (each row is keyed by `session_id`).
    if input.options.has_manager_keys {
        if let Some(value) = build_ssh_key_certificates_value(
            conn,
            &input.selected_session_ids,
            input.options.include_all_manager_keys,
        )? {
            write_json_entry(&mut zw, opts, "ssh_key_certificates.json", &value)?;
        }
    }
    // `sync_mode` (computed above) keeps tombstone emission off the
    // archive-import applier even when the user-facing dialog reuses
    // the same composer — manual exports leave `sync_origin` absent.
    if input.options.include_sessions {
        if let Some(value) =
            build_webdav_session_details_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "webdav_session_details.json", &value)?;
        }
        if let Some(value) =
            build_s3_session_details_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "s3_session_details.json", &value)?;
        }
        if let Some(value) =
            build_sftp_bookmarks_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "sftp_bookmarks.json", &value)?;
        }
        if let Some(value) =
            build_port_forward_rules_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "port_forward_rules.json", &value)?;
        }
    }

    if input.options.include_recordings {
        if let Some(root) = input.recordings_root.as_deref() {
            write_recordings_entries(&mut zw, opts, root, input.recording_db_key.as_ref())?;
        }
    }

    zw.finish()
        .map_err(|e| Error::Archive(format!("zip finish: {e}")))?;
    Ok(buf.into_inner())
}

/// Walk `<root>/<session_id>/<file>.{cast,lfsr}` and bundle every
/// recording into the archive as a plaintext `.cast` entry under
/// `recordings/<session_id>/<base>.cast`. `.lfsr` files are
/// decrypted at compose time using `db_key` (the writer's DB
/// encryption key); a `None` `db_key` skips them since the
/// receiver could not play an encrypted recording bound to the
/// sender's DB key anyway. Sidecar `.idx` files are dropped —
/// the receiver rebuilds them on first scan if/when the scrub
/// path needs them.
///
/// Any per-file failure (truncated header, GCM tag mismatch,
/// I/O hiccup) logs at warn and continues with the next file so
/// one bad recording does not abort the whole export.
fn write_recordings_entries(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    root: &std::path::Path,
    db_key: Option<&[u8; 32]>,
) -> Result<(), Error> {
    if !root.is_dir() {
        return Ok(());
    }
    let session_entries = match std::fs::read_dir(root) {
        Ok(it) => it,
        Err(_) => return Ok(()),
    };
    for session_entry in session_entries.flatten() {
        let session_path = session_entry.path();
        let ty = match session_entry.file_type() {
            Ok(t) => t,
            Err(_) => continue,
        };
        if !ty.is_dir() {
            continue;
        }
        let Some(session_id) = session_path.file_name().and_then(|s| s.to_str()) else {
            continue;
        };
        let inner = match std::fs::read_dir(&session_path) {
            Ok(it) => it,
            Err(_) => continue,
        };
        for file_entry in inner.flatten() {
            let file_path = file_entry.path();
            let ft = match file_entry.file_type() {
                Ok(t) => t,
                Err(_) => continue,
            };
            if !ft.is_file() {
                continue;
            }
            let Some(file_name) = file_path.file_name().and_then(|s| s.to_str()) else {
                continue;
            };
            let ext = file_path
                .extension()
                .and_then(|e| e.to_str())
                .map(|s| s.to_ascii_lowercase());
            let cast_bytes: Option<Vec<u8>> = match ext.as_deref() {
                Some("cast") => std::fs::read(&file_path).ok(),
                Some("lfsr") => match db_key {
                    None => {
                        crate::app_log_warn!(
                            "ArchiveExport",
                            "skip encrypted recording {}: no DB key available",
                            file_path.display()
                        );
                        None
                    }
                    Some(k) => decrypt_lfsr_to_cast_bytes(&file_path, k).ok(),
                },
                // `.idx` sidecars + any stray extension: skip.
                _ => None,
            };
            let Some(bytes) = cast_bytes else {
                continue;
            };
            let base = file_path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or(file_name);
            let entry_name = format!("recordings/{session_id}/{base}.cast");
            // Same `Stored` compression the rest of `build_zip` uses
            // — keeps the outer LFSE envelope deterministic without
            // reaching for an extra compression feature from the
            // `zip` crate's default feature set.
            zw.start_file::<_, ()>(entry_name.clone(), opts)
                .map_err(|e| Error::Archive(format!("recording start {entry_name}: {e}")))?;
            std::io::Write::write_all(zw, &bytes)
                .map_err(|e| Error::Archive(format!("recording write {entry_name}: {e}")))?;
        }
    }
    Ok(())
}

/// Stream-decrypt a `.lfsr` file under `db_key` and reassemble the
/// plaintext asciinema events into a `.cast`-shaped byte buffer.
/// The reader's `LfsrFrameIter` yields one JSON-Lines record per
/// decoded frame, header included; we restore the trailing newline
/// the reader trims and concatenate. Returns the resulting bytes —
/// suitable for direct write into the archive zip entry.
fn decrypt_lfsr_to_cast_bytes(
    lfsr_path: &std::path::Path,
    db_key: &[u8; 32],
) -> Result<Vec<u8>, Error> {
    let iter = crate::recorder::reader::open_lfsr_iter(lfsr_path, *db_key)
        .map_err(|e| Error::Archive(format!("lfsr open {}: {e}", lfsr_path.display())))?;
    let mut out: Vec<u8> = Vec::new();
    for record in iter {
        let line = record
            .map_err(|e| Error::Archive(format!("lfsr frame {}: {e}", lfsr_path.display())))?;
        out.extend_from_slice(line.as_bytes());
        out.push(b'\n');
    }
    Ok(out)
}

fn write_manifest(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    input: &ExportInput,
) -> Result<(), Error> {
    let mut obj = serde_json::Map::new();
    obj.insert("schema_version".into(), json!(input.schema_version));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(input.created_at_ms)),
    );
    if let Some(v) = input.app_version.as_deref() {
        if !v.is_empty() {
            obj.insert("app_version".into(), json!(v));
        }
    }
    // `sync_origin` stamped only when the caller supplied a
    // non-empty token. Manual exports leave the field absent;
    // the sync orchestrator passes `<install-id>:<unix_ms>` so a
    // peer device's pull can detect its own push echoing back.
    if let Some(o) = input.sync_origin.as_deref() {
        if !o.is_empty() {
            obj.insert("sync_origin".into(), json!(o));
        }
    }
    write_json_entry(zw, opts, "manifest.json", &Value::Object(obj))
}

fn build_sessions_value(
    conn: &impl crate::db::DbAccess,
    selected_ids: &[String],
    folder_paths: &HashMap<String, String>,
    sync_mode: bool,
) -> Result<Value, Error> {
    let want: HashSet<&str> = selected_ids.iter().map(|s| s.as_str()).collect();
    let mut arr = Vec::new();
    if sync_mode {
        // Sync emits tombstoned sessions so a peer can replay the
        // deletion; `list_all` filters them out, which is why a
        // delete on one device used to silently resurrect after a
        // round-trip. `selected_ids` already includes tombstoned
        // ids in the sync path (see `sync::service::compose_archive`).
        let rows = sessions::list_all_with_tombstones(conn)?;
        for (r, _updated_at, deleted_at) in rows {
            if !want.contains(r.id.as_str()) {
                continue;
            }
            arr.push(session_row_to_json(&r, folder_paths, deleted_at)?);
        }
    } else {
        let rows = sessions::list_all(conn)?;
        for r in rows.into_iter().filter(|r| want.contains(r.id.as_str())) {
            arr.push(session_row_to_json(&r, folder_paths, None)?);
        }
    }
    Ok(Value::Array(arr))
}

fn session_row_to_json(
    r: &sessions::SessionRow,
    folder_paths: &HashMap<String, String>,
    deleted_at: Option<i64>,
) -> Result<Value, Error> {
    let folder_path = r
        .folder_id
        .as_ref()
        .and_then(|id| folder_paths.get(id))
        .cloned()
        .unwrap_or_default();

    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(r.id));
    obj.insert("label".into(), json!(r.label));
    obj.insert("folder".into(), json!(folder_path));
    // `kind` omitted from the payload for SSH-kind rows so an older
    // import (pre-v5 archives) round-trips unchanged. Only WebDAV
    // and any future non-SSH kinds emit the field; the importer
    // defaults missing values to SSH on read.
    if r.kind != sessions::SESSION_KIND_SSH && !r.kind.is_empty() {
        obj.insert("kind".into(), json!(r.kind));
    }
    obj.insert("host".into(), json!(r.host));
    obj.insert("port".into(), json!(r.port));
    obj.insert("user".into(), json!(r.user));
    obj.insert("auth_type".into(), json!(r.auth_type));
    if let Some(kid) = r.key_id.as_deref() {
        if !kid.is_empty() {
            obj.insert("key_id".into(), json!(kid));
        }
    }
    obj.insert("key_path".into(), json!(r.key_path));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(r.created_at_ms)),
    );
    obj.insert(
        "updated_at".into(),
        json!(format_iso8601_utc(r.updated_at_ms)),
    );

    // `extras` is stored as a JSON string in the DB. Emit only when
    // it parses to a non-empty object (matches Dart's
    // `if (extras.isNotEmpty)` branch).
    if !r.extras.is_empty() {
        if let Ok(parsed) = serde_json::from_str::<Value>(&r.extras) {
            if let Some(obj_extras) = parsed.as_object() {
                if !obj_extras.is_empty() {
                    obj.insert("extras".into(), parsed);
                }
            }
        }
    }

    if let Some(via) = r.via_session_id.as_deref() {
        if !via.is_empty() {
            obj.insert("via_session_id".into(), json!(via));
        }
    }
    if let (Some(h), Some(p), Some(u)) = (r.via_host.as_deref(), r.via_port, r.via_user.as_deref())
    {
        if !h.is_empty() && !u.is_empty() {
            obj.insert(
                "via_override".into(),
                json!({"host": h, "port": p, "user": u}),
            );
        }
    }

    // Credentials — always written, mirroring `toJsonWithCredentials`.
    obj.insert("password".into(), json!(r.password));
    obj.insert("key_data".into(), json!(r.key_data));
    obj.insert("passphrase".into(), json!(r.passphrase));

    // Free-form user note. The apply driver reads `notes` for archive
    // imports (`apply_sessions`), so omitting it here silently dropped
    // the field on every round-trip. Omit-when-empty keeps pre-notes
    // archives byte-identical.
    if !r.notes.is_empty() {
        obj.insert("notes".into(), json!(r.notes));
    }

    // Sync tombstone marker. Present only when the caller passed a
    // `deleted_at` (sync push of a soft-deleted session); the
    // `updated_at` field above already carries the deletion stamp
    // for the LWW gate, so the apply path keys the tombstone off
    // this flag and the timestamp.
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }

    Ok(Value::Object(obj))
}

fn build_manager_keys_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    include_all: bool,
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    // Sync emits tombstoned keys so a peer can replay a key
    // deletion (a deleted credential must not resurrect); archive /
    // QR export keeps to live keys. The key list shape is identical
    // either way — the tombstone path just pairs each row with its
    // `deleted_at` stamp and tags the dead ones.
    let keyed_rows: Vec<(ssh_keys::SshKeyRow, Option<i64>)> = if sync_mode {
        ssh_keys::list_all_with_tombstones(conn)?
    } else {
        ssh_keys::list_all(conn)?
            .into_iter()
            .map(|k| (k, None))
            .collect()
    };
    if keyed_rows.is_empty() {
        return Ok(None);
    }
    let used_ids: HashSet<String> = if include_all {
        HashSet::new()
    } else {
        let want_sessions: HashSet<&str> =
            selected_session_ids.iter().map(|s| s.as_str()).collect();
        let session_rows = sessions::list_all(conn)?;
        session_rows
            .into_iter()
            .filter(|s| want_sessions.contains(s.id.as_str()))
            .filter_map(|s| s.key_id.filter(|k| !k.is_empty()))
            .collect()
    };

    let arr: Vec<Value> = keyed_rows
        .into_iter()
        .filter(|(k, _)| include_all || used_ids.contains(&k.id))
        .map(|(k, deleted_at)| build_key_value(&k, deleted_at))
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

/// Build the per-row JSON for a single `ssh_keys` row. Always emits
/// the `backend` discriminator (`software` / `fido2` / `pkcs11` /
/// `enclave` / `hello` / `tpm` / `keystore`). Per-backend payload:
///
/// | Backend | Fields | Rationale |
/// |---|---|---|
/// | `software` | private_key, public_key, key_type, label | full export today |
/// | `fido2` | public_key, key_type, label, credential_id, application_string, has_user_verification | YubiKey portable across hosts |
/// | `pkcs11` | public_key, key_type, label, pkcs11_uri, pkcs11_token_serial, pkcs11_object_id, pkcs11_object_label | hardware token plugs into new host; module path re-discovered locally |
/// | `enclave`, `hello`, `tpm`, `keystore` | public_key, key_type, label | stub — private side is device-bound |
///
/// `pkcs11_module_path` is NEVER emitted (per-host install location);
/// re-discovered on first use via the well-known-paths scan keyed on
/// `pkcs11_token_serial`.
fn build_key_value(k: &ssh_keys::SshKeyRow, deleted_at: Option<i64>) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(k.id));
    obj.insert("label".into(), json!(k.label));
    obj.insert("public_key".into(), json!(k.public_key));
    obj.insert("key_type".into(), json!(k.key_type));
    obj.insert("is_generated".into(), json!(k.is_generated));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(k.created_at_ms)),
    );
    obj.insert("backend".into(), json!(k.backend.as_db_str()));
    match k.backend {
        ssh_keys::KeyBackend::Software => {
            obj.insert("private_key".into(), json!(k.private_key));
        }
        ssh_keys::KeyBackend::Fido2 => {
            if let Some(ref cid) = k.credential_id {
                obj.insert("credential_id".into(), json!(cid));
            }
            if let Some(ref app) = k.application_string {
                obj.insert("application_string".into(), json!(app));
            }
            obj.insert(
                "has_user_verification".into(),
                json!(k.has_user_verification),
            );
        }
        ssh_keys::KeyBackend::Pkcs11 => {
            if let Some(ref uri) = k.pkcs11_uri {
                obj.insert("pkcs11_uri".into(), json!(uri));
            }
            if let Some(ref serial) = k.pkcs11_token_serial {
                obj.insert("pkcs11_token_serial".into(), json!(serial));
            }
            if let Some(ref oid) = k.pkcs11_object_id {
                obj.insert("pkcs11_object_id".into(), json!(oid));
            }
            if let Some(ref olabel) = k.pkcs11_object_label {
                obj.insert("pkcs11_object_label".into(), json!(olabel));
            }
        }
        ssh_keys::KeyBackend::Enclave
        | ssh_keys::KeyBackend::Hello
        | ssh_keys::KeyBackend::Tpm
        | ssh_keys::KeyBackend::Keystore => {
            // Stub backends — only the label + public_key + key_type
            // + backend discriminator travel. Device-bound material
            // (enclave_tag / hello_credential_name / tpm_* /
            // keystore_*) stays on the source device's hardware.
        }
    }
    // Sync tombstone marker. Keys carry `created_at` (not
    // `updated_at`) as their LWW key; the apply path compares the
    // peer `deleted_at_ms` against the local `created_at`.
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

// ── v3 child-table composers ─────────────────────────────────────

fn build_ssh_key_certificates_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    include_all_keys: bool,
) -> Result<Option<Value>, Error> {
    let all_certs = ssh_key_certificates::list_all(conn)?;
    if all_certs.is_empty() {
        return Ok(None);
    }
    // Filter to the cert rows whose parent key actually travels
    // through this export. When `include_all_keys` is true every
    // cert ships; otherwise we keep only certs whose `key_id`
    // appears in the keys-from-selected-sessions cone.
    let allowed_keys: Option<HashSet<String>> = if include_all_keys {
        None
    } else {
        let want_sessions: HashSet<&str> =
            selected_session_ids.iter().map(|s| s.as_str()).collect();
        let session_rows = sessions::list_all(conn)?;
        Some(
            session_rows
                .into_iter()
                .filter(|s| want_sessions.contains(s.id.as_str()))
                .filter_map(|s| s.key_id.filter(|k| !k.is_empty()))
                .collect(),
        )
    };
    let arr: Vec<Value> = all_certs
        .into_iter()
        .filter(|c| {
            allowed_keys
                .as_ref()
                .is_none_or(|set| set.contains(&c.key_id))
        })
        .map(|c| {
            json!({
                "key_id": c.key_id,
                "certificate": c.certificate,
                "valid_after": c.valid_after,
                "valid_before": c.valid_before,
                "principals": c.principals,
                "critical_options": c.critical_options,
                "fingerprint": c.fingerprint,
            })
        })
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_webdav_session_details_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let mut arr: Vec<Value> = Vec::new();
    if sync_mode {
        let rows = webdav_sessions::list_all_with_tombstones(conn)?;
        for (r, updated_at, deleted_at) in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(webdav_row_to_value(&r, Some(updated_at), deleted_at));
        }
    } else {
        let rows = webdav_sessions::list_all(conn)?;
        for r in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(webdav_row_to_value(&r, None, None));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn webdav_row_to_value(
    r: &webdav_sessions::WebDavSessionRow,
    updated_at: Option<i64>,
    deleted_at: Option<i64>,
) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("session_id".into(), json!(r.session_id));
    obj.insert("base_url".into(), json!(r.base_url));
    obj.insert("username".into(), json!(r.username));
    obj.insert("auth_method".into(), json!(r.auth_method));
    if let Some(pem) = r.trusted_cert_pem.as_deref() {
        obj.insert("trusted_cert_pem".into(), json!(pem));
    }
    if r.insecure_skip_verify {
        obj.insert("insecure_skip_verify".into(), json!(true));
    }
    // Credential bytes stay on the source device. The canonical
    // SecretStore id is reconstructed by the receiving device via
    // `webdav_secret_id(session_id)`; surfacing the id pointer keeps
    // the import path explicit about "re-enter password" without
    // embedding any secret material on the wire.
    obj.insert(
        "credential_secret_id".into(),
        json!(webdav_sessions::webdav_secret_id(&r.session_id)),
    );
    if let Some(ts) = updated_at {
        obj.insert("updated_at_ms".into(), json!(ts));
    }
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

fn build_s3_session_details_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let mut arr: Vec<Value> = Vec::new();
    if sync_mode {
        let rows = s3_sessions::list_all_with_tombstones(conn)?;
        for (r, updated_at, deleted_at) in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(s3_row_to_value(&r, Some(updated_at), deleted_at));
        }
    } else {
        let rows = s3_sessions::list_all(conn)?;
        for r in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(s3_row_to_value(&r, None, None));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn s3_row_to_value(
    r: &s3_sessions::S3SessionRow,
    updated_at: Option<i64>,
    deleted_at: Option<i64>,
) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("session_id".into(), json!(r.session_id));
    obj.insert("access_key_id".into(), json!(r.access_key_id));
    obj.insert("region".into(), json!(r.region));
    obj.insert("endpoint".into(), json!(r.endpoint));
    obj.insert("path_style".into(), json!(r.path_style));
    obj.insert("default_bucket".into(), json!(r.default_bucket));
    obj.insert("default_prefix".into(), json!(r.default_prefix));
    if let Some(pem) = &r.trusted_cert_pem {
        obj.insert("trusted_cert_pem".into(), json!(pem));
    }
    if r.insecure_skip_verify {
        obj.insert("insecure_skip_verify".into(), json!(true));
    }
    // Same opaque-pointer discipline as WebDAV: the access key id is
    // the public half of the AWS credential and travels verbatim;
    // the secret access key bytes don't — the receiving device finds
    // them missing and surfaces "re-enter secret access key" on
    // first connect.
    obj.insert(
        "secret_access_key_secret_id".into(),
        json!(s3_sessions::s3_secret_id(&r.session_id)),
    );
    if let Some(ts) = updated_at {
        obj.insert("updated_at_ms".into(), json!(ts));
    }
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

fn build_sftp_bookmarks_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    // Sync emits tombstoned bookmarks so a peer can replay a
    // deletion; archive / QR export keeps to live bookmarks.
    // Bookmarks carry `created_at` as their LWW key.
    let keyed_rows: Vec<(sftp_bookmarks::SftpBookmarkRow, Option<i64>)> = if sync_mode {
        sftp_bookmarks::list_all_with_tombstones(conn)?
    } else {
        sftp_bookmarks::list_all(conn)?
            .into_iter()
            .map(|r| (r, None))
            .collect()
    };
    if keyed_rows.is_empty() {
        return Ok(None);
    }
    let arr: Vec<Value> = keyed_rows
        .into_iter()
        .filter(|(r, _)| want.contains(r.session_id.as_str()))
        .map(|(r, deleted_at)| {
            let mut obj = serde_json::Map::new();
            obj.insert("id".into(), json!(r.id));
            obj.insert("session_id".into(), json!(r.session_id));
            obj.insert("remote_path".into(), json!(r.remote_path));
            obj.insert("label".into(), json!(r.label));
            obj.insert(
                "created_at".into(),
                json!(format_iso8601_utc(r.created_at_ms)),
            );
            if let Some(ts) = deleted_at {
                obj.insert("deleted_at_ms".into(), json!(ts));
                obj.insert("tombstone".into(), json!(true));
            }
            Value::Object(obj)
        })
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_port_forward_rules_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let mut arr: Vec<Value> = Vec::new();
    if sync_mode {
        let rows = port_forwards::list_all_with_tombstones(conn)?;
        for (r, deleted_at) in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(port_forward_row_to_value(&r, true, deleted_at));
        }
    } else {
        let rows = port_forwards::list_all(conn)?;
        for r in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(port_forward_row_to_value(&r, false, None));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn port_forward_row_to_value(
    r: &port_forwards::PortForwardRuleRow,
    include_sync_stamps: bool,
    deleted_at: Option<i64>,
) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(r.id));
    obj.insert("session_id".into(), json!(r.session_id));
    obj.insert("kind".into(), json!(r.kind));
    obj.insert("bind_host".into(), json!(r.bind_host));
    obj.insert("bind_port".into(), json!(r.bind_port));
    obj.insert("remote_host".into(), json!(r.remote_host));
    obj.insert("remote_port".into(), json!(r.remote_port));
    obj.insert("description".into(), json!(r.description));
    obj.insert("enabled".into(), json!(r.enabled));
    obj.insert("sort_order".into(), json!(r.sort_order));
    obj.insert("created_at_ms".into(), json!(r.created_at_ms));
    if include_sync_stamps {
        obj.insert("updated_at_ms".into(), json!(r.updated_at_ms));
    }
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

fn build_tags_value(
    conn: &impl crate::db::DbAccess,
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    // Sync emits tombstoned tags so a peer can replay a deletion;
    // archive / QR export keeps to live tags. Tags carry `created_at`
    // as their LWW key (no `updated_at` column).
    let keyed_rows: Vec<(tags::TagRow, Option<i64>)> = if sync_mode {
        tags::list_all_with_tombstones(conn)?
    } else {
        tags::list_all(conn)?
            .into_iter()
            .map(|t| (t, None))
            .collect()
    };
    if keyed_rows.is_empty() {
        return Ok(None);
    }
    let arr: Vec<Value> = keyed_rows
        .into_iter()
        .map(|(t, deleted_at)| {
            let mut obj = serde_json::Map::new();
            obj.insert("id".into(), json!(t.id));
            obj.insert("name".into(), json!(t.name));
            obj.insert("color".into(), json!(t.color));
            obj.insert(
                "created_at".into(),
                json!(format_iso8601_utc(t.created_at_ms)),
            );
            if let Some(ts) = deleted_at {
                obj.insert("deleted_at_ms".into(), json!(ts));
                obj.insert("tombstone".into(), json!(true));
            }
            Value::Object(obj)
        })
        .collect();
    Ok(Some(Value::Array(arr)))
}

fn build_session_tags_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
) -> Result<Option<Value>, Error> {
    let mut arr = Vec::new();
    for sid in selected_session_ids {
        let tag_ids = tags::list_session_tag_ids(conn, sid)?;
        for tid in tag_ids {
            arr.push(json!({"session_id": sid, "tag_id": tid}));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_folder_tags_value(conn: &impl crate::db::DbAccess) -> Result<Option<Value>, Error> {
    let folders = folders::list_all(conn)?;
    if folders.is_empty() {
        return Ok(None);
    }
    let folder_paths = build_folder_paths(conn)?;
    let mut arr = Vec::new();
    for f in folders {
        let tag_ids = tags::list_folder_tag_ids(conn, &f.id)?;
        if tag_ids.is_empty() {
            continue;
        }
        let path = folder_paths.get(&f.id).cloned().unwrap_or_default();
        for tid in tag_ids {
            arr.push(json!({"folder_path": path, "tag_id": tid}));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_snippets_value(
    conn: &impl crate::db::DbAccess,
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    // Sync emits tombstoned snippets so a peer can replay a
    // deletion; archive / QR export keeps to live snippets. LWW key
    // is `updated_at` — the deletion stamp rides on it via the
    // tombstone's `deleted_at_ms`.
    let keyed_rows: Vec<(snippets::SnippetRow, Option<i64>)> = if sync_mode {
        snippets::list_all_with_tombstones(conn)?
            .into_iter()
            .map(|(s, _updated, deleted)| (s, deleted))
            .collect()
    } else {
        snippets::list_all(conn)?
            .into_iter()
            .map(|s| (s, None))
            .collect()
    };
    if keyed_rows.is_empty() {
        return Ok(None);
    }
    let arr: Vec<Value> = keyed_rows
        .into_iter()
        .map(|(s, deleted_at)| {
            let mut obj = serde_json::Map::new();
            obj.insert("id".into(), json!(s.id));
            obj.insert("title".into(), json!(s.title));
            obj.insert("command".into(), json!(s.command));
            obj.insert("description".into(), json!(s.description));
            obj.insert(
                "created_at".into(),
                json!(format_iso8601_utc(s.created_at_ms)),
            );
            obj.insert(
                "updated_at".into(),
                json!(format_iso8601_utc(s.updated_at_ms)),
            );
            if let Some(ts) = deleted_at {
                obj.insert("deleted_at_ms".into(), json!(ts));
                obj.insert("tombstone".into(), json!(true));
            }
            Value::Object(obj)
        })
        .collect();
    Ok(Some(Value::Array(arr)))
}

fn build_session_snippets_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
) -> Result<Option<Value>, Error> {
    let mut arr = Vec::new();
    for sid in selected_session_ids {
        let snippet_ids = snippets::list_session_snippet_ids(conn, sid)?;
        for snid in snippet_ids {
            arr.push(json!({"session_id": sid, "snippet_id": snid}));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn write_json_entry(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    name: &str,
    value: &Value,
) -> Result<(), Error> {
    let serialised = serde_json::to_vec(value)
        .map_err(|e| Error::Archive(format!("json serialise {name}: {e}")))?;
    zw.start_file(name, opts)
        .map_err(|e| Error::Archive(format!("zip start {name}: {e}")))?;
    zw.write_all(&serialised)
        .map_err(|e| Error::Archive(format!("zip write {name}: {e}")))?;
    Ok(())
}

fn write_text_entry(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    name: &str,
    text: &str,
) -> Result<(), Error> {
    zw.start_file(name, opts)
        .map_err(|e| Error::Archive(format!("zip start {name}: {e}")))?;
    zw.write_all(text.as_bytes())
        .map_err(|e| Error::Archive(format!("zip write {name}: {e}")))?;
    Ok(())
}

#[cfg(test)]
mod tests;
