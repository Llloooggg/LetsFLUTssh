//! Typed staging inputs for the in-memory import path.
//!
//! `lfs_core::archive::apply_pending_import` consumes staged JSON
//! arrays (`sessions_json`, `keys_json`, `tags_json`,
//! `snippets_json`) — the same envelope `export_archive` writes into
//! `.lfs` archive entries. The `.lfs` import side reads bytes
//! straight off disk into the envelope, but the *in-memory* import
//! path (QR import, paste-link import, OpenSSH-config import) used
//! to compose those JSON strings Dart-side.
//!
//! That left the wire-shape contract split: the parser lives in
//! `archive.rs::apply_*`, the writer lived in
//! `lib/core/import/import_service.dart::_stageFromResult`. Drift
//! risk was quiet because flutter_test never round-tripped the two
//! halves; production hit only the `.lfs` path which was internally
//! consistent.
//!
//! This module owns the typed mirror so the in-memory caller
//! marshals primitives (label, host, port, …) into typed structs and
//! gets back the JSON-string envelope the apply driver expects. One
//! source of truth for field names, default-omission, ISO-timestamp
//! formatting, and nested-object shapes.
//!
//! Each per-type helper returns `String` (a JSON-encoded array)
//! ready to drop straight into `DbStagedImport.{sessions,keys,tags,
//! snippets}_json`. Empty input collapses to `None`, mirroring the
//! Dart side's "skip the field when empty" branch.

use serde_json::{json, Value};

use crate::archive::iso8601::format_iso8601_utc;

/// Single-session staging input. Field names match the JSON shape
/// the apply driver parses (`folder` is a path string, not a
/// folder-id; timestamps come in as ms and surface as ISO strings).
#[derive(Debug, Clone, Default)]
pub struct StagedSessionImport {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub passphrase: String,
    pub key_id: Option<String>,
    /// Raw JSON object string ("" when absent). Apply driver passes
    /// the parsed object straight through to the `extras` column.
    pub extras_json: String,
    pub via_session_id: Option<String>,
    pub via_override_host: Option<String>,
    pub via_override_port: Option<i64>,
    pub via_override_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

/// Single-key staging input — mirrors `_keyToJson` exactly.
#[derive(Debug, Clone, Default)]
pub struct StagedKeyImport {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
}

/// Single-tag staging input.
#[derive(Debug, Clone, Default)]
pub struct StagedTagImport {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at_ms: i64,
}

/// Single-snippet staging input.
#[derive(Debug, Clone, Default)]
pub struct StagedSnippetImport {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

fn stage_session_to_value(s: &StagedSessionImport) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(s.id));
    obj.insert("label".into(), json!(s.label));
    obj.insert("folder".into(), json!(s.folder));
    obj.insert("host".into(), json!(s.host));
    obj.insert("port".into(), json!(s.port));
    obj.insert("user".into(), json!(s.user));
    obj.insert("auth_type".into(), json!(s.auth_type));
    obj.insert("password".into(), json!(s.password));
    obj.insert("key_path".into(), json!(s.key_path));
    obj.insert("key_data".into(), json!(s.key_data));
    obj.insert("passphrase".into(), json!(s.passphrase));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(s.created_at_ms)),
    );
    obj.insert(
        "updated_at".into(),
        json!(format_iso8601_utc(s.updated_at_ms)),
    );
    if let Some(kid) = s.key_id.as_deref() {
        if !kid.is_empty() {
            obj.insert("key_id".into(), json!(kid));
        }
    }
    if !s.extras_json.is_empty() {
        if let Ok(parsed) = serde_json::from_str::<Value>(&s.extras_json) {
            obj.insert("extras".into(), parsed);
        }
    }
    if let Some(via) = s.via_session_id.as_deref() {
        if !via.is_empty() {
            obj.insert("via_session_id".into(), json!(via));
        }
    }
    if let (Some(h), Some(p), Some(u)) = (
        s.via_override_host.as_deref(),
        s.via_override_port,
        s.via_override_user.as_deref(),
    ) {
        obj.insert(
            "via_override".into(),
            json!({"host": h, "port": p, "user": u}),
        );
    }
    Value::Object(obj)
}

fn stage_key_to_value(k: &StagedKeyImport) -> Value {
    json!({
        "id": k.id,
        "label": k.label,
        "private_key": k.private_key,
        "public_key": k.public_key,
        "key_type": k.key_type,
        "is_generated": k.is_generated,
        "created_at": format_iso8601_utc(k.created_at_ms),
    })
}

fn stage_tag_to_value(t: &StagedTagImport) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(t.id));
    obj.insert("name".into(), json!(t.name));
    if let Some(c) = t.color.as_deref() {
        obj.insert("color".into(), json!(c));
    }
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(t.created_at_ms)),
    );
    Value::Object(obj)
}

fn stage_snippet_to_value(s: &StagedSnippetImport) -> Value {
    json!({
        "id": s.id,
        "title": s.title,
        "command": s.command,
        "description": s.description,
        "created_at": format_iso8601_utc(s.created_at_ms),
        "updated_at": format_iso8601_utc(s.updated_at_ms),
    })
}

/// Serialise an array of staged sessions to the JSON-string envelope
/// the apply driver consumes. Returns `None` for an empty input so
/// the caller can pass it straight into the `Option<String>` field
/// on `DbStagedImport.sessions_json`.
#[must_use]
pub fn stage_sessions_to_json(rows: &[StagedSessionImport]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows.iter().map(stage_session_to_value).collect();
    Some(
        serde_json::to_string(&Value::Array(arr))
            .expect("serde_json on serde_json::Value cannot fail"),
    )
}

/// Same shape as [`stage_sessions_to_json`] for manager keys.
#[must_use]
pub fn stage_keys_to_json(rows: &[StagedKeyImport]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows.iter().map(stage_key_to_value).collect();
    Some(
        serde_json::to_string(&Value::Array(arr))
            .expect("serde_json on serde_json::Value cannot fail"),
    )
}

/// Same shape as [`stage_sessions_to_json`] for tags.
#[must_use]
pub fn stage_tags_to_json(rows: &[StagedTagImport]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows.iter().map(stage_tag_to_value).collect();
    Some(
        serde_json::to_string(&Value::Array(arr))
            .expect("serde_json on serde_json::Value cannot fail"),
    )
}

/// Same shape as [`stage_sessions_to_json`] for snippets.
#[must_use]
pub fn stage_snippets_to_json(rows: &[StagedSnippetImport]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows.iter().map(stage_snippet_to_value).collect();
    Some(
        serde_json::to_string(&Value::Array(arr))
            .expect("serde_json on serde_json::Value cannot fail"),
    )
}

// Junction-table link rows the apply driver consumes via the
// `session_tags_json` / `folder_tags_json` / `session_snippets_json`
// fields on `PendingImport`. Typed FRB structs encode the wire
// shape in one place — this module — and the apply driver re-parses
// the same JSON the stagers build.

/// Session ↔ tag M2M row.
#[derive(Debug, Clone)]
pub struct StagedSessionTagLink {
    pub session_id: String,
    pub tag_id: String,
}

/// Folder ↔ tag M2M row. Carries the folder *path* (not id) — the
/// Rust apply driver resolves it against the freshly-built
/// `folder_path → folder_id` map populated by `apply_folder_tree`
/// + `apply_empty_folders`.
#[derive(Debug, Clone)]
pub struct StagedFolderTagLink {
    pub folder_path: String,
    pub tag_id: String,
}

/// Session ↔ snippet M2M row.
#[derive(Debug, Clone)]
pub struct StagedSessionSnippetLink {
    pub session_id: String,
    pub snippet_id: String,
}

#[must_use]
pub fn stage_session_tags_to_json(rows: &[StagedSessionTagLink]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows
        .iter()
        .map(|r| {
            serde_json::json!({
                "session_id": r.session_id,
                "tag_id": r.tag_id,
            })
        })
        .collect();
    Some(serde_json::to_string(&Value::Array(arr)).expect("Value array serialises"))
}

#[must_use]
pub fn stage_folder_tags_to_json(rows: &[StagedFolderTagLink]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows
        .iter()
        .map(|r| {
            serde_json::json!({
                "folder_path": r.folder_path,
                "tag_id": r.tag_id,
            })
        })
        .collect();
    Some(serde_json::to_string(&Value::Array(arr)).expect("Value array serialises"))
}

#[must_use]
pub fn stage_session_snippets_to_json(rows: &[StagedSessionSnippetLink]) -> Option<String> {
    if rows.is_empty() {
        return None;
    }
    let arr: Vec<Value> = rows
        .iter()
        .map(|r| {
            serde_json::json!({
                "session_id": r.session_id,
                "snippet_id": r.snippet_id,
            })
        })
        .collect();
    Some(serde_json::to_string(&Value::Array(arr)).expect("Value array serialises"))
}

/// Bare-string list — the empty-folder paths the apply driver
/// inserts into `folders` outside the `apply_folder_tree` pass
/// (folders explicitly carried in the archive that have no
/// sessions referencing them).
#[must_use]
pub fn stage_empty_folders_to_json(paths: &[String]) -> Option<String> {
    if paths.is_empty() {
        return None;
    }
    let arr: Vec<Value> = paths.iter().map(|p| Value::String(p.clone())).collect();
    Some(serde_json::to_string(&Value::Array(arr)).expect("Value array serialises"))
}
#[cfg(test)]
#[path = "../tests/unit/archive_stage.rs"]
mod tests;
