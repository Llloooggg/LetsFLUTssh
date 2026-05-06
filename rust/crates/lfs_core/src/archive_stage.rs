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
// fields on `PendingImport`. Typed FRB structs replace the prior
// Dart-side `jsonEncode([...])` envelopes — the wire shape lives
// one place, in this module, and the apply driver re-parses the
// same JSON it would have built.

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
mod tests {
    use super::*;

    fn parse(json: &str) -> Value {
        serde_json::from_str(json).expect("staged JSON must round-trip")
    }

    #[test]
    fn sessions_empty_collapses_to_none() {
        assert!(stage_sessions_to_json(&[]).is_none());
    }

    #[test]
    fn sessions_emit_required_fields_in_canonical_shape() {
        let row = StagedSessionImport {
            id: "s1".into(),
            label: "lab".into(),
            folder: "infra/prod".into(),
            host: "h.example".into(),
            port: 2222,
            user: "alice".into(),
            auth_type: "password".into(),
            password: "pw".into(),
            key_path: "/keys/id".into(),
            key_data: "data".into(),
            passphrase: "phrase".into(),
            key_id: Some("k0".into()),
            extras_json: r#"{"hello":"world"}"#.into(),
            via_session_id: Some("sx".into()),
            via_override_host: Some("bastion".into()),
            via_override_port: Some(2200),
            via_override_user: Some("jump".into()),
            created_at_ms: 1_777_161_600_000,
            updated_at_ms: 1_777_161_600_123,
        };
        let json = stage_sessions_to_json(&[row]).unwrap();
        let v = parse(&json);
        let s = &v.as_array().unwrap()[0];
        assert_eq!(s.get("id").and_then(Value::as_str), Some("s1"));
        assert_eq!(
            s.get("folder").and_then(Value::as_str),
            Some("infra/prod"),
            "folder is the path string, not folder_id",
        );
        assert_eq!(s.get("port").and_then(Value::as_i64), Some(2222));
        assert_eq!(
            s.get("created_at").and_then(Value::as_str),
            Some("2026-04-26T00:00:00.000Z"),
        );
        assert_eq!(
            s.get("updated_at").and_then(Value::as_str),
            Some("2026-04-26T00:00:00.123Z"),
        );
        assert_eq!(s.get("key_id").and_then(Value::as_str), Some("k0"));
        let extras = s.get("extras").unwrap();
        assert_eq!(
            extras.get("hello").and_then(Value::as_str),
            Some("world"),
            "extras must round-trip as a parsed object, not a JSON string",
        );
        assert_eq!(s.get("via_session_id").and_then(Value::as_str), Some("sx"),);
        let ov = s.get("via_override").unwrap();
        assert_eq!(ov.get("host").and_then(Value::as_str), Some("bastion"));
        assert_eq!(ov.get("port").and_then(Value::as_i64), Some(2200));
        assert_eq!(ov.get("user").and_then(Value::as_str), Some("jump"));
    }

    #[test]
    fn sessions_omit_empty_optionals() {
        // Mirrors Dart's `if (s.keyId.isNotEmpty)` etc. branches —
        // the apply driver treats absent / empty consistently but
        // staging an empty `key_id: ""` would surface as a non-empty
        // override on the DB row, masking a never-set state. Belt
        // and braces.
        let row = StagedSessionImport {
            id: "s1".into(),
            label: "lab".into(),
            host: "h".into(),
            user: "u".into(),
            port: 22,
            auth_type: "password".into(),
            ..Default::default()
        };
        let json = stage_sessions_to_json(&[row]).unwrap();
        let v = parse(&json);
        let s = v.as_array().unwrap()[0].as_object().unwrap();
        assert!(!s.contains_key("key_id"));
        assert!(!s.contains_key("extras"));
        assert!(!s.contains_key("via_session_id"));
        assert!(!s.contains_key("via_override"));
    }

    #[test]
    fn sessions_partial_via_override_collapses() {
        // Mirrors the Dart `if (ov != null)` guard — the override
        // surfaces only when host + port + user are all present. A
        // missing port (the fail-open case) drops the entire
        // override object, matching the existing apply-driver shape.
        let row = StagedSessionImport {
            id: "s1".into(),
            label: "lab".into(),
            host: "h".into(),
            user: "u".into(),
            port: 22,
            auth_type: "password".into(),
            via_override_host: Some("bastion".into()),
            via_override_port: None,
            via_override_user: Some("jump".into()),
            ..Default::default()
        };
        let json = stage_sessions_to_json(&[row]).unwrap();
        let v = parse(&json);
        assert!(!v.as_array().unwrap()[0]
            .as_object()
            .unwrap()
            .contains_key("via_override"));
    }

    #[test]
    fn keys_round_trip_with_iso_created_at() {
        let row = StagedKeyImport {
            id: "k1".into(),
            label: "lab".into(),
            private_key: "PRIV".into(),
            public_key: "PUB".into(),
            key_type: "ed25519".into(),
            is_generated: true,
            created_at_ms: 1_777_161_600_000,
        };
        let json = stage_keys_to_json(&[row]).unwrap();
        let v = parse(&json);
        let k = &v.as_array().unwrap()[0];
        assert_eq!(k.get("id").and_then(Value::as_str), Some("k1"));
        assert_eq!(k.get("private_key").and_then(Value::as_str), Some("PRIV"));
        assert_eq!(k.get("is_generated").and_then(Value::as_bool), Some(true));
        assert_eq!(
            k.get("created_at").and_then(Value::as_str),
            Some("2026-04-26T00:00:00.000Z"),
        );
    }

    #[test]
    fn tags_omit_color_when_unset() {
        let with_color = StagedTagImport {
            id: "t1".into(),
            name: "prod".into(),
            color: Some("#ff0000".into()),
            created_at_ms: 0,
        };
        let without_color = StagedTagImport {
            id: "t2".into(),
            name: "dev".into(),
            color: None,
            created_at_ms: 0,
        };
        let json = stage_tags_to_json(&[with_color, without_color]).unwrap();
        let v = parse(&json);
        let arr = v.as_array().unwrap();
        assert_eq!(arr[0].get("color").and_then(Value::as_str), Some("#ff0000"));
        assert!(!arr[1].as_object().unwrap().contains_key("color"));
    }

    #[test]
    fn snippets_round_trip_with_iso_timestamps() {
        let row = StagedSnippetImport {
            id: "n1".into(),
            title: "t".into(),
            command: "ls".into(),
            description: "list".into(),
            created_at_ms: 1_777_161_600_000,
            updated_at_ms: 1_777_161_600_456,
        };
        let json = stage_snippets_to_json(&[row]).unwrap();
        let v = parse(&json);
        let s = &v.as_array().unwrap()[0];
        assert_eq!(
            s.get("created_at").and_then(Value::as_str),
            Some("2026-04-26T00:00:00.000Z"),
        );
        assert_eq!(
            s.get("updated_at").and_then(Value::as_str),
            Some("2026-04-26T00:00:00.456Z"),
        );
    }

    #[test]
    fn extras_invalid_json_is_silently_dropped() {
        // Belt-and-braces — a malformed `extras` shouldn't poison
        // the entire session entry; the apply driver would otherwise
        // see a malformed JSON value and reject the whole row.
        let row = StagedSessionImport {
            id: "s1".into(),
            label: "lab".into(),
            host: "h".into(),
            user: "u".into(),
            port: 22,
            auth_type: "password".into(),
            extras_json: "not-json".into(),
            ..Default::default()
        };
        let json = stage_sessions_to_json(&[row]).unwrap();
        let v = parse(&json);
        assert!(!v.as_array().unwrap()[0]
            .as_object()
            .unwrap()
            .contains_key("extras"));
    }
}
