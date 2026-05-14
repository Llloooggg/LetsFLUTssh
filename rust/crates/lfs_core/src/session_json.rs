//! Canonical Session JSON codec.
//!
//! Single source of truth for the persisted-session wire shape — the
//! field set, key order, and conditional-omit rules that ship across
//! every boundary the user-visible session payload crosses (archive
//! export, undo-snapshot blob, QR payload, dev test fixture).
//!
//! Both halves live here in pure-Rust:
//!
//! * [`encode_canonical_json`] — builds the `{...}` payload from an
//!   [`SessionJsonInput`]. The Dart side previously held a parallel
//!   `Session.toJson` / `toJsonWithCredentials` encoder; that has been
//!   retired in favour of routing through this function over FRB.
//! * [`decode_canonical_json`] — parses a payload into a typed
//!   [`SessionJsonOutput`] with the inverse field set. Replaces the
//!   Dart `Session.fromJson` / `ProxyJumpOverride.fromJson` /
//!   `_decodeExtras` triple, all of which previously walked the same
//!   shape by hand and could drift between sides.
//!
//! Wire-shape invariants — keep these in lock-step with the
//! corresponding test in `test/utils/session_json_drift_test.dart`:
//!
//! * Mandatory keys (`id`, `label`, `folder`, `host`, `port`, `user`,
//!   `auth_type`, `key_path`, `created_at`, `updated_at`) always
//!   serialise; on decode they are tolerant — missing string fields
//!   default to empty, missing `port` defaults to `22`, missing
//!   timestamps fall back to a zero ISO-8601 string the caller can
//!   substitute for `now`.
//! * Conditional keys (`kind`, `key_id`, `extras`, `via_session_id`,
//!   `via_override`, `notes`, `sort_order`, `last_connected_at_ms`)
//!   are emitted only when their value is non-default. The decoder
//!   tolerates their absence by leaving the corresponding output
//!   field at its empty / `None` / `0` default.
//! * `extras` is emitted as a raw JSON object when non-empty; the
//!   decoder converts each leaf into a [`SessionJsonValue`] tagged
//!   union so the Dart consumer no longer needs to call `jsonDecode`
//!   to read the persisted column. Nested objects / arrays carry
//!   their fully typed children (`Array(Vec<SessionJsonValue>)` /
//!   `Object(Vec<(String, SessionJsonValue)>)`) so a probe at any
//!   depth never re-parses raw JSON text.
//! * `extras` is also accepted as a JSON-encoded **string** on
//!   decode — that path appears when the column is read off the
//!   sessions table verbatim and handed back through the same
//!   codec for the row → typed-bag transform.
//! * Credential fields (`password`, `key_data`, `passphrase`) are
//!   present iff `include_credentials` was set on the encoder input.
//!   The decoder always reads them; absent values yield empty
//!   strings.

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

/// Optional saved-bastion override carried in the `via_override`
/// block. Mirrors the Dart `ProxyJumpOverride` field set.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionJsonViaOverride {
    pub host: String,
    pub port: u32,
    pub user: String,
}

/// Encoder input. Field set mirrors the union of `Session.toJson` +
/// `Session.toJsonWithCredentials`; the `include_credentials` flag
/// selects between the two by gating the credential trio.
#[derive(Debug, Clone)]
pub struct SessionJsonInput {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: u32,
    pub user: String,
    pub kind: String,
    pub auth_type: String,
    pub key_id: String,
    pub key_path: String,
    pub created_at_iso: String,
    pub updated_at_iso: String,
    pub extras_json: String,
    pub via_session_id: Option<String>,
    pub via_override: Option<SessionJsonViaOverride>,
    pub notes: String,
    pub sort_order: i32,
    pub last_connected_at_ms: Option<i64>,
    pub include_credentials: bool,
    pub password: String,
    pub key_data: String,
    pub passphrase: String,
}

/// One leaf of the typed `extras` payload. The Dart-side accessor
/// helpers (`extrasBool` / `extrasStr` / `extrasInt`) pattern-match
/// on these variants directly so a `jsonDecode` is no longer needed
/// on the persisted blob.
///
/// Nested arrays / objects carry their fully typed children so a
/// caller walking the tree never has to re-parse raw JSON. The
/// `Vec` indirection on the `Array` / `Object` arms keeps the
/// enum's stack size bounded under recursion.
#[derive(Debug, Clone, PartialEq)]
pub enum SessionJsonValue {
    /// JSON `null` or a missing key in the input.
    Null,
    /// JSON boolean.
    Bool(bool),
    /// JSON integer. Floats that fit losslessly in `i64` are
    /// represented here; non-integer numbers go through
    /// [`SessionJsonValue::Double`].
    Int(i64),
    /// JSON non-integer number.
    Double(f64),
    /// JSON string.
    Text(String),
    /// JSON array, carried as a typed list of children. Each
    /// element is heap-allocated to keep the enum's stack size
    /// bounded under recursion.
    Array(Vec<SessionJsonValue>),
    /// JSON object, carried as a key-ordered list of typed
    /// `{key, value}` pairs. Key order matches `serde_json`'s
    /// preserve-order iteration so the original document order
    /// round-trips across encode → decode.
    Object(Vec<(String, SessionJsonValue)>),
}

impl SessionJsonValue {
    /// Build a tagged-union leaf from an arbitrary
    /// [`serde_json::Value`]. Used by the decoder when walking the
    /// `extras` object and by tests that want to construct a typed
    /// expected value.
    pub fn from_value(value: &Value) -> Self {
        match value {
            Value::Null => SessionJsonValue::Null,
            Value::Bool(b) => SessionJsonValue::Bool(*b),
            Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    SessionJsonValue::Int(i)
                } else if let Some(u) = n.as_u64() {
                    // u64 that fits in i64 → Int; otherwise fall
                    // back to a lossy f64 so callers still get a
                    // numeric type rather than a parse error.
                    if u <= i64::MAX as u64 {
                        SessionJsonValue::Int(u as i64)
                    } else {
                        SessionJsonValue::Double(u as f64)
                    }
                } else if let Some(f) = n.as_f64() {
                    // Whole-number floats round-trip as Int so the
                    // Dart `extrasInt` accessor matches the
                    // `extrasBool` / `extrasStr` symmetry.
                    if f.fract() == 0.0 && f >= i64::MIN as f64 && f <= i64::MAX as f64 {
                        SessionJsonValue::Int(f as i64)
                    } else {
                        SessionJsonValue::Double(f)
                    }
                } else {
                    SessionJsonValue::Null
                }
            }
            Value::String(s) => SessionJsonValue::Text(s.clone()),
            Value::Array(items) => {
                SessionJsonValue::Array(items.iter().map(SessionJsonValue::from_value).collect())
            }
            Value::Object(map) => SessionJsonValue::Object(
                map.iter()
                    .map(|(k, v)| (k.clone(), SessionJsonValue::from_value(v)))
                    .collect(),
            ),
        }
    }
}

/// Decoder output. Field set mirrors the union of the Dart factories
/// `Session.fromJson`, `ProxyJumpOverride.fromJson`, and the helper
/// `_decodeExtras`. The Dart consumer rehydrates a `Session` instance
/// from this struct without ever calling `jsonDecode` on the
/// persisted payload.
#[derive(Debug, Clone)]
pub struct SessionJsonOutput {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: u32,
    pub user: String,
    pub kind: String,
    pub auth_type: String,
    pub key_id: String,
    pub key_path: String,
    pub created_at_iso: String,
    pub updated_at_iso: String,
    pub extras: BTreeMap<String, SessionJsonValue>,
    pub via_session_id: Option<String>,
    pub via_override: Option<SessionJsonViaOverride>,
    pub notes: String,
    pub sort_order: i32,
    pub last_connected_at_ms: Option<i64>,
    pub password: String,
    pub key_data: String,
    pub passphrase: String,
}

/// Build the canonical JSON payload for [`input`].
///
/// See module docs for the conditional-omit invariants. Sync — the
/// work is one `serde_json::Map` build + one `to_string`, so the
/// caller can run this on the UI microtask without yielding.
pub fn encode_canonical_json(input: &SessionJsonInput) -> Result<String, String> {
    let mut obj = Map::new();
    obj.insert("id".into(), json!(input.id));
    obj.insert("label".into(), json!(input.label));
    obj.insert("folder".into(), json!(input.folder));
    // `kind` defaults to "ssh"; omit so a pre-WebDAV importer reading
    // the same payload sees an unchanged shape. The decoder treats a
    // missing key as `ssh` for symmetry.
    if !input.kind.is_empty() && input.kind != "ssh" {
        obj.insert("kind".into(), json!(input.kind));
    }
    obj.insert("host".into(), json!(input.host));
    obj.insert("port".into(), json!(input.port));
    obj.insert("user".into(), json!(input.user));
    obj.insert("auth_type".into(), json!(input.auth_type));
    if !input.key_id.is_empty() {
        obj.insert("key_id".into(), json!(input.key_id));
    }
    obj.insert("key_path".into(), json!(input.key_path));
    obj.insert("created_at".into(), json!(input.created_at_iso));
    obj.insert("updated_at".into(), json!(input.updated_at_iso));
    if !input.extras_json.is_empty() {
        let parsed: Value = serde_json::from_str(&input.extras_json)
            .map_err(|e| format!("extras_json parse: {e}"))?;
        if let Some(map) = parsed.as_object() {
            if !map.is_empty() {
                obj.insert("extras".into(), parsed);
            }
        }
    }
    if let Some(via) = input.via_session_id.as_deref() {
        if !via.is_empty() {
            obj.insert("via_session_id".into(), json!(via));
        }
    }
    if let Some(over) = &input.via_override {
        obj.insert(
            "via_override".into(),
            json!({"host": over.host, "port": over.port, "user": over.user}),
        );
    }
    if !input.notes.is_empty() {
        obj.insert("notes".into(), json!(input.notes));
    }
    if input.sort_order != 0 {
        obj.insert("sort_order".into(), json!(input.sort_order));
    }
    if let Some(ms) = input.last_connected_at_ms {
        obj.insert("last_connected_at_ms".into(), json!(ms));
    }
    if input.include_credentials {
        obj.insert("password".into(), json!(input.password));
        obj.insert("key_data".into(), json!(input.key_data));
        obj.insert("passphrase".into(), json!(input.passphrase));
    }
    serde_json::to_string(&Value::Object(obj))
        .map_err(|e| format!("session_canonical_json serialise: {e}"))
}

/// Parse a canonical JSON payload into a [`SessionJsonOutput`].
///
/// Tolerant in the same way the retired Dart `fromJson` was: missing
/// optional keys land at their defaults; the legacy `group` key
/// alias for `folder` is honoured. Returns `Err` only for structural
/// problems (top-level not a JSON object, malformed JSON) — never
/// for missing keys or type mismatches inside the object, which
/// would otherwise turn a downstream import into a crash on the
/// first row.
pub fn decode_canonical_json(json: &str) -> Result<SessionJsonOutput, String> {
    let value: Value = serde_json::from_str(json).map_err(|e| format!("parse: {e}"))?;
    let obj = value
        .as_object()
        .ok_or_else(|| "top-level value is not a JSON object".to_string())?;

    let id = read_string(obj, "id");
    let label = read_string(obj, "label");
    let folder = match obj.get("folder") {
        Some(Value::String(s)) => s.clone(),
        _ => match obj.get("group") {
            Some(Value::String(s)) => s.clone(),
            _ => String::new(),
        },
    };
    let host = read_string(obj, "host");
    let port = match obj.get("port") {
        Some(Value::Number(n)) => n
            .as_u64()
            .map(|u| u as u32)
            .or_else(|| n.as_i64().and_then(|i| u32::try_from(i).ok()))
            .or_else(|| n.as_f64().map(|f| f as u32))
            .unwrap_or(22),
        _ => 22,
    };
    let user = read_string(obj, "user");
    let kind = match obj.get("kind") {
        Some(Value::String(s)) if !s.is_empty() => s.clone(),
        _ => "ssh".to_string(),
    };
    let auth_type = match obj.get("auth_type") {
        Some(Value::String(s)) if !s.is_empty() => s.clone(),
        _ => "password".to_string(),
    };
    let key_id = read_string(obj, "key_id");
    let key_path = read_string(obj, "key_path");
    let created_at_iso = read_string(obj, "created_at");
    let updated_at_iso = read_string(obj, "updated_at");

    let extras = decode_extras(obj.get("extras"));

    let via_session_id = match obj.get("via_session_id") {
        Some(Value::String(s)) => Some(s.clone()),
        _ => None,
    };

    let via_override = match obj.get("via_override") {
        Some(Value::Object(via)) => {
            let host = via
                .get("host")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_default();
            // Default 22 mirrors the retired
            // `ProxyJumpOverride.fromJson` grammar (port omitted →
            // 22). The constructor enforces `1..=65535` at use time;
            // we keep parse tolerant.
            let port = via
                .get("port")
                .and_then(|v| match v {
                    Value::Number(n) => n
                        .as_u64()
                        .map(|u| u as u32)
                        .or_else(|| n.as_i64().and_then(|i| u32::try_from(i).ok())),
                    _ => None,
                })
                .unwrap_or(22);
            let user = via
                .get("user")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_default();
            Some(SessionJsonViaOverride { host, port, user })
        }
        _ => None,
    };

    let notes = read_string(obj, "notes");
    let sort_order = obj
        .get("sort_order")
        .and_then(Value::as_i64)
        .map(|i| i as i32)
        .unwrap_or(0);
    let last_connected_at_ms = obj.get("last_connected_at_ms").and_then(Value::as_i64);

    let password = read_string(obj, "password");
    let key_data = read_string(obj, "key_data");
    let passphrase = read_string(obj, "passphrase");

    Ok(SessionJsonOutput {
        id,
        label,
        folder,
        host,
        port,
        user,
        kind,
        auth_type,
        key_id,
        key_path,
        created_at_iso,
        updated_at_iso,
        extras,
        via_session_id,
        via_override,
        notes,
        sort_order,
        last_connected_at_ms,
        password,
        key_data,
        passphrase,
    })
}

/// Decode the `extras` payload tolerantly. Accepts an inline JSON
/// object, a JSON-encoded string (DB column read path), or `null` /
/// missing / malformed — anything that does not parse to an object
/// falls through to an empty map so a corrupt blob can never block
/// a session from loading.
fn decode_extras(raw: Option<&Value>) -> BTreeMap<String, SessionJsonValue> {
    let mut out = BTreeMap::new();
    let Some(raw) = raw else { return out };
    let parsed: Option<Value> = match raw {
        Value::Object(_) => Some(raw.clone()),
        Value::String(s) => {
            if s.is_empty() {
                None
            } else {
                serde_json::from_str(s).ok()
            }
        }
        _ => None,
    };
    if let Some(Value::Object(map)) = parsed {
        for (k, v) in map {
            out.insert(k, SessionJsonValue::from_value(&v));
        }
    }
    out
}

/// Decode a JSON-encoded extras blob (the DB column shape) into the
/// typed leaf map. Convenience wrapper around [`decode_extras`] —
/// the mapper layer calls this directly so a row read does not need
/// to round-trip through [`decode_canonical_json`].
#[must_use]
pub fn decode_extras_string(json: &str) -> BTreeMap<String, SessionJsonValue> {
    if json.is_empty() {
        return BTreeMap::new();
    }
    decode_extras(Some(&Value::String(json.to_string())))
}

/// Pure helper — read a string field or fall back to empty.
fn read_string(obj: &Map<String, Value>, key: &str) -> String {
    obj.get(key)
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_default()
}

/// Encode a list of canonical-JSON session payloads as a JSON array
/// for the undo-history snapshot blob. Wraps [`encode_canonical_json`]
/// in a single `Vec<Value>` build so the on-disk byte shape matches
/// the retired Dart `_encode` exactly.
pub fn encode_session_array(items: &[SessionJsonInput]) -> Result<String, String> {
    let mut arr: Vec<Value> = Vec::with_capacity(items.len());
    for item in items {
        let s = encode_canonical_json(item)?;
        let v: Value = serde_json::from_str(&s).map_err(|e| format!("re-parse: {e}"))?;
        arr.push(v);
    }
    serde_json::to_string(&Value::Array(arr)).map_err(|e| format!("serialise: {e}"))
}

/// Decode a JSON array of canonical-JSON session payloads emitted by
/// [`encode_session_array`]. Each element passes through
/// [`decode_canonical_json`]; a malformed element aborts the whole
/// parse (the snapshot is treated as one atomic unit — partial
/// restore would leave the undo stack in a confusing state).
pub fn decode_session_array(json: &str) -> Result<Vec<SessionJsonOutput>, String> {
    let value: Value = serde_json::from_str(json).map_err(|e| format!("parse: {e}"))?;
    let arr = value
        .as_array()
        .ok_or_else(|| "top-level value is not a JSON array".to_string())?;
    arr.iter()
        .map(|v| {
            let s = serde_json::to_string(v).map_err(|e| format!("re-serialise: {e}"))?;
            decode_canonical_json(&s)
        })
        .collect()
}

/// Decoded snapshot envelope yielded by [`decode_snapshot_envelope`].
/// Mirrors the Dart `SessionSnapshot` field set (sessions /
/// `emptyFolders` / description) — the description rides through
/// the envelope so a single byte-buffer hands the Rust-side undo
/// actor everything it needs to label menu entries.
#[derive(Debug, Clone)]
pub struct SnapshotEnvelope {
    pub sessions: Vec<SessionJsonOutput>,
    pub empty_folders: Vec<String>,
    pub description: String,
}

/// Encode an undo-history snapshot envelope: a JSON object wrapping
/// the per-session array, the `emptyFolders` list, and the
/// description label. The Dart side hands typed inputs in and
/// receives a single byte buffer to push through the registry —
/// no `jsonEncode` / `jsonDecode` round-trip stays Dart-side.
///
/// Wire shape — pinned by `test/utils/session_json_drift_test.dart`:
/// `{"sessions": [<canonical session>...], "emptyFolders": [...],
/// "description": "..."}`.
pub fn encode_snapshot_envelope(
    sessions: &[SessionJsonInput],
    empty_folders: &[String],
    description: &str,
) -> Result<String, String> {
    let array_str = encode_session_array(sessions)?;
    let array: Value =
        serde_json::from_str(&array_str).map_err(|e| format!("re-parse sessions array: {e}"))?;
    let mut obj = Map::new();
    obj.insert("sessions".into(), array);
    obj.insert(
        "emptyFolders".into(),
        Value::Array(empty_folders.iter().cloned().map(Value::String).collect()),
    );
    obj.insert("description".into(), Value::String(description.to_owned()));
    serde_json::to_string(&Value::Object(obj))
        .map_err(|e| format!("snapshot envelope serialise: {e}"))
}

/// Decode an undo-history snapshot envelope produced by
/// [`encode_snapshot_envelope`]. Tolerant on missing keys —
/// `sessions` falls back to empty, `emptyFolders` to empty, the
/// `description` to the empty string (the wrapper caller carries
/// the live description in `current_description` for the registry
/// API so the inner blob's value is informational only).
pub fn decode_snapshot_envelope(json: &str) -> Result<SnapshotEnvelope, String> {
    let value: Value = serde_json::from_str(json).map_err(|e| format!("parse: {e}"))?;
    let obj = value
        .as_object()
        .ok_or_else(|| "top-level value is not a JSON object".to_string())?;
    let sessions = match obj.get("sessions") {
        Some(v) => {
            let s = serde_json::to_string(v).map_err(|e| format!("re-serialise sessions: {e}"))?;
            decode_session_array(&s)?
        }
        None => Vec::new(),
    };
    let empty_folders = obj
        .get("emptyFolders")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    let description = obj
        .get("description")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_default();
    Ok(SnapshotEnvelope {
        sessions,
        empty_folders,
        description,
    })
}

/// Encode an `extras` map (DB column shape) into the JSON-text wire
/// form. Symmetric counterpart of [`decode_extras_string`] so the
/// mapper layer can drop its Dart-side `jsonEncode` and stage the
/// row through one Rust-owned grammar instead. Empty input yields
/// an empty string (the DB column default), matching the decode
/// side's tolerance.
pub fn encode_extras_string(extras: &[(String, SessionJsonValue)]) -> Result<String, String> {
    if extras.is_empty() {
        return Ok(String::new());
    }
    let map: Map<String, Value> = extras
        .iter()
        .map(|(k, v)| (k.clone(), session_json_value_to_value(v)))
        .collect();
    serde_json::to_string(&Value::Object(map)).map_err(|e| format!("encode_extras_string: {e}"))
}

/// Convert a typed [`SessionJsonValue`] tree back into a raw
/// [`serde_json::Value`] for re-serialisation. Inverse of
/// [`SessionJsonValue::from_value`].
fn session_json_value_to_value(v: &SessionJsonValue) -> Value {
    match v {
        SessionJsonValue::Null => Value::Null,
        SessionJsonValue::Bool(b) => Value::Bool(*b),
        SessionJsonValue::Int(i) => Value::Number((*i).into()),
        SessionJsonValue::Double(f) => serde_json::Number::from_f64(*f)
            .map(Value::Number)
            .unwrap_or(Value::Null),
        SessionJsonValue::Text(s) => Value::String(s.clone()),
        SessionJsonValue::Array(items) => {
            Value::Array(items.iter().map(session_json_value_to_value).collect())
        }
        SessionJsonValue::Object(pairs) => Value::Object(
            pairs
                .iter()
                .map(|(k, val)| (k.clone(), session_json_value_to_value(val)))
                .collect(),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn populated_input() -> SessionJsonInput {
        SessionJsonInput {
            id: "sess-1".into(),
            label: "Edge prod".into(),
            folder: "production/web".into(),
            host: "edge.example.com".into(),
            port: 2222,
            user: "deploy".into(),
            kind: "ssh".into(),
            auth_type: "key".into(),
            key_id: "key-7c8f".into(),
            key_path: "/home/deploy/.ssh/id_ed25519".into(),
            created_at_iso: "2026-05-09T12:00:00.000Z".into(),
            updated_at_iso: "2026-05-09T13:30:00.000Z".into(),
            extras_json: r#"{"tags":"web,prod","priority":1}"#.into(),
            via_session_id: Some("bastion-id".into()),
            via_override: Some(SessionJsonViaOverride {
                host: "bastion.example.com".into(),
                port: 2200,
                user: "jump".into(),
            }),
            notes: "maintenance 03:00 UTC".into(),
            sort_order: 5,
            last_connected_at_ms: Some(1_715_000_000_000),
            include_credentials: false,
            password: "pwd".into(),
            key_data: "PEM".into(),
            passphrase: "phrase".into(),
        }
    }

    #[test]
    fn encode_then_decode_round_trips_every_field() {
        let input = populated_input();
        let json = encode_canonical_json(&input).unwrap();
        let out = decode_canonical_json(&json).unwrap();

        assert_eq!(out.id, input.id);
        assert_eq!(out.label, input.label);
        assert_eq!(out.folder, input.folder);
        assert_eq!(out.host, input.host);
        assert_eq!(out.port, input.port);
        assert_eq!(out.user, input.user);
        // Default 'ssh' kind is omitted on emit; the decoder must
        // fold a missing key back to 'ssh'.
        assert_eq!(out.kind, "ssh");
        assert_eq!(out.auth_type, input.auth_type);
        assert_eq!(out.key_id, input.key_id);
        assert_eq!(out.key_path, input.key_path);
        assert_eq!(out.created_at_iso, input.created_at_iso);
        assert_eq!(out.updated_at_iso, input.updated_at_iso);
        assert_eq!(out.extras.get("priority"), Some(&SessionJsonValue::Int(1)));
        assert_eq!(
            out.extras.get("tags"),
            Some(&SessionJsonValue::Text("web,prod".into()))
        );
        assert_eq!(out.via_session_id.as_deref(), Some("bastion-id"));
        assert_eq!(
            out.via_override,
            Some(SessionJsonViaOverride {
                host: "bastion.example.com".into(),
                port: 2200,
                user: "jump".into(),
            })
        );
        assert_eq!(out.notes, input.notes);
        assert_eq!(out.sort_order, input.sort_order);
        assert_eq!(out.last_connected_at_ms, Some(1_715_000_000_000));
        // Credentials were not included in the encoded payload, so
        // the decoder leaves them empty even though the input
        // carried values.
        assert!(out.password.is_empty());
        assert!(out.key_data.is_empty());
        assert!(out.passphrase.is_empty());
    }

    #[test]
    fn encode_with_credentials_emits_secret_trio_and_decode_reads_back() {
        let mut input = populated_input();
        input.include_credentials = true;
        let json = encode_canonical_json(&input).unwrap();
        assert!(json.contains("\"password\""));
        assert!(json.contains("\"key_data\""));
        assert!(json.contains("\"passphrase\""));
        let out = decode_canonical_json(&json).unwrap();
        assert_eq!(out.password, "pwd");
        assert_eq!(out.key_data, "PEM");
        assert_eq!(out.passphrase, "phrase");
    }

    #[test]
    fn encode_omits_empty_extras_and_decode_handles_missing_key() {
        let mut input = populated_input();
        input.extras_json = String::new();
        let json = encode_canonical_json(&input).unwrap();
        assert!(!json.contains("\"extras\""));
        let out = decode_canonical_json(&json).unwrap();
        assert!(out.extras.is_empty());
    }

    #[test]
    fn encode_omits_empty_extras_object() {
        let mut input = populated_input();
        input.extras_json = "{}".into();
        let json = encode_canonical_json(&input).unwrap();
        assert!(!json.contains("\"extras\""));
    }

    #[test]
    fn decode_tolerates_json_encoded_extras_string() {
        // Older payloads sometimes embedded `"extras":"{\"k\":42}"` —
        // the column shape on the wire mirrors the row column. Make
        // sure the decoder handles both inline-object and string
        // shapes the same way.
        let payload = r#"{
            "id":"x","label":"l","folder":"","host":"h","port":22,"user":"u",
            "auth_type":"password","key_path":"","created_at":"","updated_at":"",
            "extras":"{\"k\":42}"
        }"#;
        let out = decode_canonical_json(payload).unwrap();
        assert_eq!(out.extras.get("k"), Some(&SessionJsonValue::Int(42)));
    }

    #[test]
    fn decode_tolerates_corrupt_extras_string_with_empty_map() {
        let payload = r#"{
            "id":"x","label":"l","folder":"","host":"h","port":22,"user":"u",
            "auth_type":"password","key_path":"","created_at":"","updated_at":"",
            "extras":"{not-json"
        }"#;
        let out = decode_canonical_json(payload).unwrap();
        assert!(out.extras.is_empty());
    }

    #[test]
    fn decode_legacy_group_key_aliases_folder() {
        let payload = r#"{
            "id":"x","label":"l","host":"h","user":"u","group":"Production/EU",
            "auth_type":"password","key_path":"","created_at":"","updated_at":""
        }"#;
        let out = decode_canonical_json(payload).unwrap();
        assert_eq!(out.folder, "Production/EU");
    }

    #[test]
    fn decode_missing_optional_fields_lands_on_defaults() {
        let payload = r#"{"id":"x","host":"h","user":"u"}"#;
        let out = decode_canonical_json(payload).unwrap();
        assert_eq!(out.id, "x");
        assert_eq!(out.host, "h");
        assert_eq!(out.user, "u");
        assert_eq!(out.label, "");
        assert_eq!(out.folder, "");
        assert_eq!(out.port, 22);
        assert_eq!(out.kind, "ssh");
        assert_eq!(out.auth_type, "password");
        assert_eq!(out.key_id, "");
        assert_eq!(out.notes, "");
        assert_eq!(out.sort_order, 0);
        assert!(out.last_connected_at_ms.is_none());
        assert!(out.via_session_id.is_none());
        assert!(out.via_override.is_none());
    }

    #[test]
    fn decode_via_override_with_missing_port_defaults_22() {
        let payload = r#"{
            "id":"x","host":"h","user":"u",
            "auth_type":"password","key_path":"","created_at":"","updated_at":"",
            "via_override":{"host":"b.example","user":"j"}
        }"#;
        let out = decode_canonical_json(payload).unwrap();
        let over = out.via_override.unwrap();
        assert_eq!(over.host, "b.example");
        assert_eq!(over.port, 22);
        assert_eq!(over.user, "j");
    }

    #[test]
    fn decode_rejects_top_level_array() {
        let err = decode_canonical_json("[]").unwrap_err();
        assert!(err.contains("not a JSON object"), "got: {err}");
    }

    #[test]
    fn decode_rejects_malformed_json() {
        let err = decode_canonical_json("{not-json").unwrap_err();
        assert!(err.contains("parse"), "got: {err}");
    }

    #[test]
    fn extras_value_promotes_whole_floats_to_int() {
        // The Dart `extrasInt('count')` accessor used to accept
        // `5` and `5.0` indifferently because `jsonDecode` produced
        // a `num` either way. Keep that contract via the promote.
        let v = SessionJsonValue::from_value(&Value::from(5.0_f64));
        assert_eq!(v, SessionJsonValue::Int(5));
    }

    #[test]
    fn extras_value_preserves_non_integer_floats() {
        let v = SessionJsonValue::from_value(&Value::from(1.5_f64));
        assert_eq!(v, SessionJsonValue::Double(1.5));
    }

    #[test]
    fn extras_value_arrays_and_objects_carry_typed_children() {
        let array = serde_json::from_str::<Value>(r#"[1,"two",false]"#).unwrap();
        match SessionJsonValue::from_value(&array) {
            SessionJsonValue::Array(items) => {
                assert_eq!(items.len(), 3);
                assert_eq!(items[0], SessionJsonValue::Int(1));
                assert_eq!(items[1], SessionJsonValue::Text("two".into()));
                assert_eq!(items[2], SessionJsonValue::Bool(false));
            }
            other => panic!("expected Array, got {other:?}"),
        }
        let object = serde_json::from_str::<Value>(r#"{"nested":true}"#).unwrap();
        match SessionJsonValue::from_value(&object) {
            SessionJsonValue::Object(pairs) => {
                assert_eq!(pairs.len(), 1);
                assert_eq!(pairs[0].0, "nested");
                assert_eq!(pairs[0].1, SessionJsonValue::Bool(true));
            }
            other => panic!("expected Object, got {other:?}"),
        }
    }

    #[test]
    fn extras_value_recurses_through_nested_arrays_and_objects() {
        let value =
            serde_json::from_str::<Value>(r#"{"layers":[{"name":"web","flags":[true,false]},42]}"#)
                .unwrap();
        let typed = SessionJsonValue::from_value(&value);
        let SessionJsonValue::Object(top) = typed else {
            panic!("expected top-level Object");
        };
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].0, "layers");
        let SessionJsonValue::Array(layers) = &top[0].1 else {
            panic!("expected layers Array");
        };
        assert_eq!(layers.len(), 2);
        let SessionJsonValue::Object(first) = &layers[0] else {
            panic!("expected first layer Object");
        };
        // `serde_json::Map` uses a BTreeMap by default, so the inner
        // object's keys land sorted alphabetically ("flags" before
        // "name"). The Dart consumer does its own re-keying into a
        // `Map<String, Object?>` so the order is not load-bearing for
        // call sites — the test asserts on it to pin the contract.
        let first_keys: Vec<&str> = first.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(first_keys, vec!["flags", "name"]);
        let flags_pair = first.iter().find(|(k, _)| k == "flags").unwrap();
        let SessionJsonValue::Array(flags) = &flags_pair.1 else {
            panic!("expected flags Array");
        };
        assert_eq!(
            flags,
            &vec![SessionJsonValue::Bool(true), SessionJsonValue::Bool(false)]
        );
        let name_pair = first.iter().find(|(k, _)| k == "name").unwrap();
        assert_eq!(name_pair.1, SessionJsonValue::Text("web".into()));
        assert_eq!(layers[1], SessionJsonValue::Int(42));
    }

    #[test]
    fn session_array_round_trips_through_encode_decode() {
        let a = populated_input();
        let mut b = populated_input();
        b.id = "sess-2".into();
        b.label = "another".into();
        let encoded = encode_session_array(&[a.clone(), b.clone()]).unwrap();
        let decoded = decode_session_array(&encoded).unwrap();
        assert_eq!(decoded.len(), 2);
        assert_eq!(decoded[0].id, "sess-1");
        assert_eq!(decoded[0].label, "Edge prod");
        assert_eq!(decoded[1].id, "sess-2");
        assert_eq!(decoded[1].label, "another");
    }

    #[test]
    fn session_array_decode_rejects_non_array_top_level() {
        let err = decode_session_array("{}").unwrap_err();
        assert!(err.contains("not a JSON array"), "got: {err}");
    }

    #[test]
    fn decode_extras_string_handles_empty_blob() {
        assert!(decode_extras_string("").is_empty());
    }

    #[test]
    fn decode_extras_string_yields_typed_leaves() {
        let m = decode_extras_string(r#"{"flag":true,"name":"r","count":7}"#);
        assert_eq!(m.get("flag"), Some(&SessionJsonValue::Bool(true)));
        assert_eq!(m.get("name"), Some(&SessionJsonValue::Text("r".into())));
        assert_eq!(m.get("count"), Some(&SessionJsonValue::Int(7)));
    }

    #[test]
    fn encode_extras_string_empty_yields_empty_string() {
        // Mirrors the DB column default — the upsert path inserts
        // `''` for sessions with no extras and the decode side
        // tolerates an empty blob.
        assert_eq!(encode_extras_string(&[]).unwrap(), "");
    }

    #[test]
    fn encode_extras_string_round_trips_through_decode() {
        let extras = vec![
            ("flag".to_string(), SessionJsonValue::Bool(true)),
            ("count".to_string(), SessionJsonValue::Int(7)),
            ("name".to_string(), SessionJsonValue::Text("edge".into())),
            (
                "nested".to_string(),
                SessionJsonValue::Object(vec![(
                    "k".to_string(),
                    SessionJsonValue::Text("v".into()),
                )]),
            ),
        ];
        let encoded = encode_extras_string(&extras).unwrap();
        let decoded = decode_extras_string(&encoded);
        assert_eq!(decoded.get("flag"), Some(&SessionJsonValue::Bool(true)));
        assert_eq!(decoded.get("count"), Some(&SessionJsonValue::Int(7)));
        assert_eq!(
            decoded.get("name"),
            Some(&SessionJsonValue::Text("edge".into()))
        );
        // Nested object round-trips intact.
        let SessionJsonValue::Object(pairs) = decoded.get("nested").cloned().unwrap() else {
            panic!("expected nested object");
        };
        assert_eq!(pairs.len(), 1);
        assert_eq!(pairs[0].0, "k");
        assert_eq!(pairs[0].1, SessionJsonValue::Text("v".into()));
    }

    #[test]
    fn snapshot_envelope_round_trips_sessions_folders_description() {
        let a = populated_input();
        let envelope = encode_snapshot_envelope(
            std::slice::from_ref(&a),
            &["empty/folder".to_string()],
            "delete session",
        )
        .unwrap();
        let decoded = decode_snapshot_envelope(&envelope).unwrap();
        assert_eq!(decoded.sessions.len(), 1);
        assert_eq!(decoded.sessions[0].id, "sess-1");
        assert_eq!(decoded.empty_folders, vec!["empty/folder".to_string()]);
        assert_eq!(decoded.description, "delete session");
    }

    #[test]
    fn snapshot_envelope_decode_tolerates_missing_fields() {
        // Mirrors the prior Dart `_decode` shape — a malformed
        // envelope with a missing `emptyFolders` or `description`
        // still round-trips so a partial blob from a future build
        // doesn't poison the undo stack.
        let envelope = decode_snapshot_envelope(r#"{"sessions":[]}"#).unwrap();
        assert!(envelope.sessions.is_empty());
        assert!(envelope.empty_folders.is_empty());
        assert_eq!(envelope.description, "");
    }

    #[test]
    fn snapshot_envelope_decode_rejects_non_object_root() {
        let err = decode_snapshot_envelope("[]").unwrap_err();
        assert!(err.contains("not a JSON object"), "got: {err}");
    }
}
