//! Decode the deflated + base64url-encoded QR / paste-link
//! payload into a [`PendingImport`] shape ready for the apply
//! driver. Mirrors `lib/core/session/qr_codec.dart` decode side
//! field-for-field.
//!
//! # Wire format
//!
//! Outer: `base64url-no-pad(deflate(JSON))`. Inflated payload caps
//! at 4 MiB to defuse zip-bomb-shaped input — deflate's ~1000×
//! ratio means a small QR could otherwise expand into the multi-
//! hundred-MB range.
//!
//! `v: 1` is the floor — there is no version below it, so the format
//! is always deflate-compressed. A payload that fails to inflate is
//! rejected, not read raw.
//!
//! # Field map
//!
//! Top-level JSON:
//!   - `v`        — schema version (`1`; see `SchemaVersions::QR_PAYLOAD`)
//!   - `s`        — sessions array, compact shape (see below)
//!   - `eg`       — empty folder paths (string array)
//!   - `km`       — `{shortId: PEM}` dedup map
//!   - `mk`       — `{shortId: {l, t, p}}` manager key metadata
//!   - `c`        — config object (verbatim)
//!   - `kh`       — known_hosts blob (string)
//!   - `tg`       — tags array `[{i, n, cl?}]`
//!   - `st`       — session-tag links `[{si, ti}]` (`si` = short session id)
//!   - `ft`       — folder-tag links `[{fi, ti}]`
//!   - `sn`       — snippets array `[{i, t, cm, d?}]`
//!   - `ss`       — session-snippet links `[{si, ni}]` (`si` = short session id)
//!
//! Per-session compact shape (`s` array):
//!   - `l, h, u`  — label, host, user
//!   - `p`        — port (omitted when 22)
//!   - `g`        — folder path (omitted when empty)
//!   - `a`        — auth type (`password` default omitted)
//!   - `ki`       — short key id reference (lookup in `km` / `mk`)
//!   - `mg`       — `1` if `ki` references a manager key
//!   - `pw`       — password (only when exporter opted in)
//!   - `i`        — short session id (`s0`, `s1`, …)
//!
//! The compact `s` shape carries no DB UUID (camera bandwidth), so
//! the `st` / `ss` link tables reference the short `i` instead. The
//! decoder mints a fresh UUID per session and remaps the short onto
//! it; a link whose `si` no shipped session carries (truncated, or a
//! pre-`i` payload) is dropped rather than left dangling.

use std::io::Read;

use base64::engine::{general_purpose::URL_SAFE_NO_PAD, Engine as _};
use flate2::read::DeflateDecoder;
use serde_json::{json, Value};

use crate::archive::PendingImport;
use crate::error::Error;

const MAX_INFLATED_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;
/// Wire version the decoder accepts. Derived from
/// [`crate::migration::SchemaVersions::QR_PAYLOAD`] so the framework's
/// canonical version registry is the single source of truth — a
/// payload-shape bump flows through here without a parallel constant
/// edit.
const CURRENT_FORMAT_VERSION: i64 = crate::migration::SchemaVersions::QR_PAYLOAD as i64;

/// Result of a successful decode plus any out-of-band signals
/// the caller surfaces to the user.
#[derive(Debug)]
pub struct DecodedQrPayload {
    pub pending: PendingImport,
    pub schema_version: i64,
}

/// Outcome of [`try_decode_payload`]. Splits the version-too-new
/// case out of [`Error`] so callers (notably the deeplink
/// dispatcher) can surface a typed "this build can't read v{found}"
/// signal to the UI without parsing error strings.
#[derive(Debug)]
pub enum QrDecodeResult {
    /// Decode succeeded — `pending` ready for staging via
    /// `ImportRegistry::insert`. Boxed because `DecodedQrPayload`
    /// carries an inline `PendingImport` whose JSON-string fields
    /// dwarf the other variants; clippy flags the size delta and
    /// boxing keeps the enum stack footprint at a single pointer.
    Ok(Box<DecodedQrPayload>),
    /// Payload's `v` field exceeded the version this build understands.
    /// `supported` is [`CURRENT_FORMAT_VERSION`].
    VersionTooNew { found: i64, supported: i64 },
    /// Any other decode error (base64 / inflate / utf-8 / JSON shape).
    Err(Error),
}

/// Typed decode entry point — splits version-too-new out of the
/// generic `Error::Crypto` so dispatchers can branch on it cheaply.
pub fn try_decode_payload(payload: &str) -> QrDecodeResult {
    let json_text = match decode_to_json_text(payload) {
        Ok(t) => t,
        Err(e) => return QrDecodeResult::Err(e),
    };
    let json: Value = match serde_json::from_str(&json_text) {
        Ok(v) => v,
        Err(e) => return QrDecodeResult::Err(Error::Crypto(format!("payload malformed: {e}"))),
    };
    let obj = match json.as_object() {
        Some(o) => o,
        None => return QrDecodeResult::Err(Error::Crypto("payload root must be object".into())),
    };
    let version = obj.get("v").and_then(|v| v.as_i64()).unwrap_or(1);
    if version > CURRENT_FORMAT_VERSION {
        return QrDecodeResult::VersionTooNew {
            found: version,
            supported: CURRENT_FORMAT_VERSION,
        };
    }
    match parse_payload(&json) {
        Ok(p) => QrDecodeResult::Ok(Box::new(p)),
        Err(e) => QrDecodeResult::Err(e),
    }
}

/// Decode the QR / paste-link payload.
///
/// Errors:
///   - `Error::Crypto("payload too large")` — inflated > 4 MiB cap
///   - `Error::Crypto("payload version too new")` — `v` exceeds
///     [`CURRENT_FORMAT_VERSION`]
///   - `Error::Crypto("payload malformed")` — unrecoverable parse
pub fn decode_payload(payload: &str) -> Result<DecodedQrPayload, Error> {
    let json_text = decode_to_json_text(payload)?;
    let json: Value = serde_json::from_str(&json_text)
        .map_err(|e| Error::Crypto(format!("payload malformed: {e}")))?;
    parse_payload(&json)
}

/// Strip a `letsflutssh://import?d=...` deeplink wrapper down to
/// the raw `d=` value before handing it to [`decode_payload`].
/// Returns `None` for any non-import URI shape.
pub fn extract_payload_from_uri(uri: &str) -> Option<String> {
    let rest = uri.strip_prefix("letsflutssh://import")?;
    let query = rest.strip_prefix('?')?;
    for pair in query.split('&') {
        let (k, v) = pair.split_once('=')?;
        if k == "d" {
            return Some(v.to_string());
        }
    }
    None
}

fn decode_to_json_text(payload: &str) -> Result<String, Error> {
    // v1 is strictly `base64url-no-pad(deflate(JSON))`. There is no
    // version below v1, so a non-deflate payload is rejected outright
    // rather than read raw — `SchemaVersions::QR_PAYLOAD` is the floor.
    let raw = URL_SAFE_NO_PAD
        .decode(payload.as_bytes())
        .map_err(|e| Error::Crypto(format!("payload base64 decode: {e}")))?;
    let bytes = match inflate_capped(&raw) {
        Ok(bytes) => bytes,
        Err(InflateError::TooLarge { limit }) => {
            return Err(Error::Crypto(format!(
                "payload exceeds {limit}-byte inflate cap (zip bomb?)"
            )));
        }
        Err(InflateError::Inflate) => {
            return Err(Error::Crypto("payload inflate failed".into()));
        }
    };
    String::from_utf8(bytes).map_err(|e| Error::Crypto(format!("payload utf-8: {e}")))
}

#[derive(Debug)]
enum InflateError {
    Inflate,
    TooLarge { limit: usize },
}

impl From<std::io::Error> for InflateError {
    fn from(_: std::io::Error) -> Self {
        // Stream parse failures all collapse to the same signal — the
        // caller rejects the payload on any inflate failure. Capturing
        // the underlying io::Error would never be inspected.
        InflateError::Inflate
    }
}

fn inflate_capped(compressed: &[u8]) -> Result<Vec<u8>, InflateError> {
    // Bound materialisation to `cap + 1` bytes so a deflate bomb
    // cannot balloon the heap before the size check. The read-based
    // decoder lets us wrap the inflate stream in `Read::take`, so at
    // most `cap + 1` inflated bytes are ever pulled into memory —
    // mirroring the ZIP-import streaming cap in `archive::mod`. The
    // earlier write-based decoder inflated the whole stream first
    // and only then compared lengths.
    let cap = MAX_INFLATED_PAYLOAD_BYTES;
    let mut out = Vec::new();
    DeflateDecoder::new(compressed)
        .take((cap as u64).saturating_add(1))
        .read_to_end(&mut out)?;
    if out.len() > cap {
        return Err(InflateError::TooLarge { limit: cap });
    }
    Ok(out)
}

fn parse_payload(json: &Value) -> Result<DecodedQrPayload, Error> {
    let obj = json
        .as_object()
        .ok_or_else(|| Error::Crypto("payload root must be object".into()))?;

    let version = validate_version(obj)?;
    ensure_non_empty(obj)?;

    let key_map = parse_key_map(obj);
    let (sessions_json, session_id_remap) = parse_sessions(obj, &key_map);

    Ok(DecodedQrPayload {
        pending: PendingImport {
            manifest_json: None,
            sessions_json,
            keys_json: parse_manager_keys(obj, &key_map),
            tags_json: parse_tags(obj),
            session_tags_json: parse_remapped_session_links(
                obj,
                "st",
                "ti",
                "tag_id",
                &session_id_remap,
            ),
            folder_tags_json: parse_folder_tags(obj),
            snippets_json: parse_snippets(obj),
            session_snippets_json: parse_remapped_session_links(
                obj,
                "ss",
                "ni",
                "snippet_id",
                &session_id_remap,
            ),
            empty_folders_json: parse_empty_folders(obj),
            config_json: obj
                .get("c")
                .map(|v| serde_json::to_string(v).unwrap_or_default())
                .filter(|s| !s.is_empty() && s != "null"),
            known_hosts_text: obj
                .get("kh")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .filter(|s| !s.is_empty()),
            // QR / paste-link payloads are bandwidth-bound and ship
            // only the core subset; the child tables below do not
            // travel through the QR envelope. Recordings (binary,
            // MB-scale per recording) travel only inside the `.lfs`
            // archive pipeline.
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
            recordings: Vec::new(),
        },
        schema_version: version,
    })
}

fn validate_version(obj: &serde_json::Map<String, Value>) -> Result<i64, Error> {
    let version = obj.get("v").and_then(|v| v.as_i64()).unwrap_or(1);
    if version > CURRENT_FORMAT_VERSION {
        return Err(Error::Crypto(format!(
            "payload version too new: v{version} > supported v{CURRENT_FORMAT_VERSION}"
        )));
    }
    Ok(version)
}

fn ensure_non_empty(obj: &serde_json::Map<String, Value>) -> Result<(), Error> {
    if !obj.contains_key("s")
        && !obj.contains_key("km")
        && !obj.contains_key("c")
        && !obj.contains_key("kh")
    {
        // No useful payload at all — empty pending. The Dart caller
        // collapses this to "invalid QR" upstream; mirror that signal
        // by returning an Err so the caller does not hand a useless
        // handle to the apply driver.
        return Err(Error::Crypto("payload empty".into()));
    }
    Ok(())
}

fn parse_key_map(
    obj: &serde_json::Map<String, Value>,
) -> std::collections::HashMap<String, String> {
    obj.get("km")
        .and_then(|v| v.as_object())
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                .collect::<std::collections::HashMap<String, String>>()
        })
        .unwrap_or_default()
}

/// Decode the sessions array and the short-id → fresh-UUID remap. The
/// session→tag and session→snippet link tables reference the payload's
/// short session id (`s0`, `s1`, … under `i`), so without this remap
/// the links would point at an id no imported session carries and
/// every association would be dropped (FK failure).
fn parse_sessions(
    obj: &serde_json::Map<String, Value>,
    key_map: &std::collections::HashMap<String, String>,
) -> (Option<String>, std::collections::HashMap<String, String>) {
    let mut session_id_remap: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    let mut sessions_out: Vec<Value> = Vec::new();
    if let Some(arr) = obj.get("s").and_then(|v| v.as_array()) {
        for entry in arr {
            if let Some(obj_session) = entry.as_object() {
                let decoded = decode_session(obj_session, key_map);
                if let (Some(short), Some(new_id)) = (
                    obj_session.get("i").and_then(|v| v.as_str()),
                    decoded.get("id").and_then(|v| v.as_str()),
                ) {
                    session_id_remap.insert(short.to_string(), new_id.to_string());
                }
                sessions_out.push(decoded);
            }
        }
    }
    (vec_to_json(sessions_out), session_id_remap)
}

fn parse_empty_folders(obj: &serde_json::Map<String, Value>) -> Option<String> {
    obj.get("eg")
        .and_then(|v| v.as_array())
        .map(|arr| {
            let only_strings: Vec<&str> = arr.iter().filter_map(|x| x.as_str()).collect();
            serde_json::to_string(&only_strings).unwrap_or_default()
        })
        .filter(|s| !s.is_empty() && s != "[]")
}

fn parse_manager_keys(
    obj: &serde_json::Map<String, Value>,
    key_map: &std::collections::HashMap<String, String>,
) -> Option<String> {
    let mut keys_out: Vec<Value> = Vec::new();
    if let Some(mk) = obj.get("mk").and_then(|v| v.as_object()) {
        for (short_id, meta) in mk {
            let private_key = match key_map.get(short_id) {
                Some(pem) => pem.clone(),
                None => continue,
            };
            let meta_obj = match meta.as_object() {
                Some(m) => m,
                None => continue,
            };
            let label = meta_obj.get("l").and_then(|v| v.as_str()).unwrap_or("");
            let key_type = meta_obj.get("t").and_then(|v| v.as_str()).unwrap_or("");
            let public_key = meta_obj.get("p").and_then(|v| v.as_str()).unwrap_or("");
            keys_out.push(json!({
                "id": short_id,
                "label": label,
                "private_key": private_key,
                "public_key": public_key,
                "key_type": key_type,
                "is_generated": false,
                "created_at": "",
            }));
        }
    }
    vec_to_json(keys_out)
}

fn parse_tags(obj: &serde_json::Map<String, Value>) -> Option<String> {
    let mut tags_out: Vec<Value> = Vec::new();
    if let Some(arr) = obj.get("tg").and_then(|v| v.as_array()) {
        for t in arr {
            if let Some(t_obj) = t.as_object() {
                let id = t_obj.get("i").and_then(|v| v.as_str()).unwrap_or("");
                let name = t_obj.get("n").and_then(|v| v.as_str()).unwrap_or("");
                let mut row = serde_json::Map::new();
                row.insert("id".into(), json!(id));
                row.insert("name".into(), json!(name));
                if let Some(c) = t_obj.get("cl").and_then(|v| v.as_str()) {
                    row.insert("color".into(), json!(c));
                }
                row.insert("created_at".into(), json!(""));
                tags_out.push(Value::Object(row));
            }
        }
    }
    vec_to_json(tags_out)
}

fn parse_folder_tags(obj: &serde_json::Map<String, Value>) -> Option<String> {
    obj.get("ft")
        .and_then(|v| v.as_array())
        .map(|arr| {
            let pairs: Vec<Value> = arr
                .iter()
                .filter_map(|l| {
                    let o = l.as_object()?;
                    let fi = o.get("fi").and_then(|v| v.as_str()).unwrap_or("");
                    let ti = o.get("ti").and_then(|v| v.as_str()).unwrap_or("");
                    Some(json!({"folder_path": fi, "tag_id": ti}))
                })
                .collect();
            serde_json::to_string(&pairs).unwrap_or_default()
        })
        .filter(|s| !s.is_empty() && s != "[]")
}

fn parse_snippets(obj: &serde_json::Map<String, Value>) -> Option<String> {
    let mut snippets_out: Vec<Value> = Vec::new();
    if let Some(arr) = obj.get("sn").and_then(|v| v.as_array()) {
        for s in arr {
            if let Some(s_obj) = s.as_object() {
                let id = s_obj.get("i").and_then(|v| v.as_str()).unwrap_or("");
                let title = s_obj.get("t").and_then(|v| v.as_str()).unwrap_or("");
                let cmd = s_obj.get("cm").and_then(|v| v.as_str()).unwrap_or("");
                let desc = s_obj.get("d").and_then(|v| v.as_str()).unwrap_or("");
                snippets_out.push(json!({
                    "id": id,
                    "title": title,
                    "command": cmd,
                    "description": desc,
                    "created_at": "",
                    "updated_at": "",
                }));
            }
        }
    }
    vec_to_json(snippets_out)
}

/// Decode a session-link table (`st` / `ss`) whose `si` field is the
/// payload's short session id, remapping it onto the freshly-minted
/// UUID and dropping links to a session that did not ship (or an
/// older payload whose sessions carried no short id). `other_in` is
/// the link's second field in the payload; `other_out` is its name in
/// the decoded row.
fn parse_remapped_session_links(
    obj: &serde_json::Map<String, Value>,
    key: &str,
    other_in: &str,
    other_out: &str,
    remap: &std::collections::HashMap<String, String>,
) -> Option<String> {
    obj.get(key)
        .and_then(|v| v.as_array())
        .map(|arr| {
            let pairs: Vec<Value> = arr
                .iter()
                .filter_map(|l| {
                    let o = l.as_object()?;
                    let si = o.get("si").and_then(|v| v.as_str())?;
                    let mapped = remap.get(si)?;
                    let other = o.get(other_in).and_then(|v| v.as_str())?;
                    let mut row = serde_json::Map::new();
                    row.insert("session_id".into(), json!(mapped));
                    row.insert(other_out.to_string(), json!(other));
                    Some(Value::Object(row))
                })
                .collect();
            serde_json::to_string(&pairs).unwrap_or_default()
        })
        .filter(|s| !s.is_empty() && s != "[]")
}

/// Serialise a row vector to JSON, or None when empty — the shape
/// every section emits for the `*_json` pending fields.
fn vec_to_json(items: Vec<Value>) -> Option<String> {
    if items.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&items).unwrap_or_default())
    }
}

fn decode_session(
    m: &serde_json::Map<String, Value>,
    key_map: &std::collections::HashMap<String, String>,
) -> Value {
    let label = m.get("l").and_then(|v| v.as_str()).unwrap_or("");
    let host = m.get("h").and_then(|v| v.as_str()).unwrap_or("");
    let user = m.get("u").and_then(|v| v.as_str()).unwrap_or("");
    let port = m.get("p").and_then(|v| v.as_i64()).unwrap_or(22);
    let folder = m.get("g").and_then(|v| v.as_str()).unwrap_or("");
    let auth_type = m.get("a").and_then(|v| v.as_str()).unwrap_or("password");
    let password = m.get("pw").and_then(|v| v.as_str()).unwrap_or("");
    let short_key = m.get("ki").and_then(|v| v.as_str());
    let is_manager = m.get("mg").and_then(|v| v.as_i64()) == Some(1);

    // Manager key reference: keep the short id in `key_id` only when
    // the key's PEM is actually present in the dedup map. The
    // manager-key row is emitted exclusively for short ids found in
    // `km` (see the `mk` loop above), so a reference to a missing
    // entry — a truncated or adversarial payload — would dangle and
    // fail the FK on apply (lost in a merge, whole-import rollback in
    // replace). Drop the reference and import the session keyless.
    // Embedded key: pull the PEM from the dedup map, write inline as
    // `key_data`.
    let (key_id, key_data) = if is_manager {
        match short_key {
            Some(short) if key_map.contains_key(short) => (short.to_string(), String::new()),
            _ => (String::new(), String::new()),
        }
    } else if let Some(short) = short_key {
        (
            "".to_string(),
            key_map.get(short).cloned().unwrap_or_default(),
        )
    } else {
        (String::new(), String::new())
    };

    let mut out = serde_json::Map::new();
    // Mint a fresh stable id Rust-side. Apply driver re-mints on
    // collision in merge mode; replace mode wipes existing rows.
    out.insert("id".into(), json!(generate_uuid_v4()));
    out.insert("label".into(), json!(label));
    out.insert("folder".into(), json!(folder));
    out.insert("host".into(), json!(host));
    out.insert("port".into(), json!(port));
    out.insert("user".into(), json!(user));
    out.insert("auth_type".into(), json!(auth_type));
    out.insert("password".into(), json!(password));
    out.insert("key_path".into(), json!(""));
    out.insert("key_data".into(), json!(key_data));
    out.insert("passphrase".into(), json!(""));
    out.insert("created_at".into(), json!(""));
    out.insert("updated_at".into(), json!(""));
    if !key_id.is_empty() {
        out.insert("key_id".into(), json!(key_id));
    }
    Value::Object(out)
}

/// Generate a v4 UUID. We have `rand::OsRng` in the crate already
/// (used by the recorder + session id mints); reuse it here so QR
/// imports get the same RNG quality.
fn generate_uuid_v4() -> String {
    use rand::Rng;
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
    )
}
#[cfg(test)]
#[path = "../tests/unit/qr_codec_decode.rs"]
mod tests;
