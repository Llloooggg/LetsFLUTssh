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
//!   - `st`       — session-tag links `[{si, ti}]`
//!   - `ft`       — folder-tag links `[{fi, ti}]`
//!   - `sn`       — snippets array `[{i, t, cm, d?}]`
//!   - `ss`       — session-snippet links `[{si, ni}]`
//!
//! Per-session compact shape (`s` array):
//!   - `l, h, u`  — label, host, user
//!   - `p`        — port (omitted when 22)
//!   - `g`        — folder path (omitted when empty)
//!   - `a`        — auth type (`password` default omitted)
//!   - `ki`       — short key id reference (lookup in `km` / `mk`)
//!   - `mg`       — `1` if `ki` references a manager key
//!   - `pw`       — password (only when exporter opted in)

use std::io::Write;

use base64::engine::{general_purpose::URL_SAFE_NO_PAD, Engine as _};
use flate2::write::DeflateDecoder;
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
        Err(InflateError::TooLarge { size, limit }) => {
            return Err(Error::Crypto(format!(
                "payload too large: {size} bytes > limit {limit}"
            )));
        }
        Err(InflateError::Inflate) => {
            return Err(Error::Crypto("payload inflate failed".into()));
        }
    };
    String::from_utf8(bytes).map_err(|e| Error::Crypto(format!("payload utf-8: {e}")))
}

enum InflateError {
    Inflate,
    TooLarge { size: usize, limit: usize },
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
    // `flate2`'s `DeflateDecoder` walks the deflate stream and
    // writes inflated bytes into the inner `Vec`. We catch oversize
    // before the user materialises it as a `String`.
    let mut out = Vec::with_capacity(compressed.len().min(64 * 1024));
    {
        let mut dec = DeflateDecoder::new(&mut out);
        dec.write_all(compressed)?;
        dec.finish()?;
    }
    if out.len() > MAX_INFLATED_PAYLOAD_BYTES {
        return Err(InflateError::TooLarge {
            size: out.len(),
            limit: MAX_INFLATED_PAYLOAD_BYTES,
        });
    }
    Ok(out)
}

fn parse_payload(json: &Value) -> Result<DecodedQrPayload, Error> {
    let obj = json
        .as_object()
        .ok_or_else(|| Error::Crypto("payload root must be object".into()))?;

    let version = obj.get("v").and_then(|v| v.as_i64()).unwrap_or(1);
    if version > CURRENT_FORMAT_VERSION {
        return Err(Error::Crypto(format!(
            "payload version too new: v{version} > supported v{CURRENT_FORMAT_VERSION}"
        )));
    }

    if !obj.contains_key("s")
        && !obj.contains_key("km")
        && !obj.contains_key("c")
        && !obj.contains_key("kh")
    {
        // No useful payload at all — empty pending. The Dart caller
        // collapses this to "invalid QR" upstream; mirror that
        // signal by returning an Err so the caller does not hand a
        // useless handle to the apply driver.
        return Err(Error::Crypto("payload empty".into()));
    }

    let key_map = obj
        .get("km")
        .and_then(|v| v.as_object())
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                .collect::<std::collections::HashMap<String, String>>()
        })
        .unwrap_or_default();

    // ---- Sessions + empty folders -----------------------------
    let mut sessions_out: Vec<Value> = Vec::new();
    if let Some(arr) = obj.get("s").and_then(|v| v.as_array()) {
        for entry in arr {
            if let Some(obj_session) = entry.as_object() {
                sessions_out.push(decode_session(obj_session, &key_map));
            }
        }
    }
    let sessions_json = if sessions_out.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&sessions_out).unwrap_or_default())
    };

    let empty_folders_json = obj
        .get("eg")
        .and_then(|v| v.as_array())
        .map(|arr| {
            let only_strings: Vec<&str> = arr.iter().filter_map(|x| x.as_str()).collect();
            serde_json::to_string(&only_strings).unwrap_or_default()
        })
        .filter(|s| !s.is_empty() && s != "[]");

    // ---- Manager keys -----------------------------------------
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
    let keys_json = if keys_out.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&keys_out).unwrap_or_default())
    };

    // ---- Tags + session-tag links -----------------------------
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
    let tags_json = if tags_out.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&tags_out).unwrap_or_default())
    };

    let session_tags_json = obj
        .get("st")
        .and_then(|v| v.as_array())
        .map(|arr| {
            let pairs: Vec<Value> = arr
                .iter()
                .filter_map(|l| {
                    let o = l.as_object()?;
                    let si = o.get("si").and_then(|v| v.as_str()).unwrap_or("");
                    let ti = o.get("ti").and_then(|v| v.as_str()).unwrap_or("");
                    Some(json!({"session_id": si, "tag_id": ti}))
                })
                .collect();
            serde_json::to_string(&pairs).unwrap_or_default()
        })
        .filter(|s| !s.is_empty() && s != "[]");

    let folder_tags_json = obj
        .get("ft")
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
        .filter(|s| !s.is_empty() && s != "[]");

    // ---- Snippets + session-snippet links ---------------------
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
    let snippets_json = if snippets_out.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&snippets_out).unwrap_or_default())
    };

    let session_snippets_json = obj
        .get("ss")
        .and_then(|v| v.as_array())
        .map(|arr| {
            let pairs: Vec<Value> = arr
                .iter()
                .filter_map(|l| {
                    let o = l.as_object()?;
                    let si = o.get("si").and_then(|v| v.as_str()).unwrap_or("");
                    let ni = o.get("ni").and_then(|v| v.as_str()).unwrap_or("");
                    Some(json!({"session_id": si, "snippet_id": ni}))
                })
                .collect();
            serde_json::to_string(&pairs).unwrap_or_default()
        })
        .filter(|s| !s.is_empty() && s != "[]");

    // ---- Config + known_hosts ---------------------------------
    let config_json = obj
        .get("c")
        .map(|v| serde_json::to_string(v).unwrap_or_default())
        .filter(|s| !s.is_empty() && s != "null");

    let known_hosts_text = obj
        .get("kh")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .filter(|s| !s.is_empty());

    Ok(DecodedQrPayload {
        pending: PendingImport {
            manifest_json: None,
            sessions_json,
            keys_json,
            tags_json,
            session_tags_json,
            folder_tags_json,
            snippets_json,
            session_snippets_json,
            empty_folders_json,
            config_json,
            known_hosts_text,
            // QR / paste-link payloads are bandwidth-bound and ship
            // only the core subset; the child tables below do not
            // travel through the QR envelope.
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
            // Recordings travel only inside the `.lfs` archive
            // pipeline (binary payloads, MB-scale per recording);
            // QR / paste-link envelopes are bandwidth-bound and
            // skip them entirely.
            recordings: Vec::new(),
        },
        schema_version: version,
    })
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

    // Manager key reference: keep short id in `key_id`. Apply
    // driver remaps to the manager-key row that lands alongside.
    // Embedded key: pull the PEM from the dedup map, write
    // inline as `key_data`.
    let (key_id, key_data) = if is_manager {
        (short_key.unwrap_or("").to_string(), String::new())
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
mod tests {
    use super::*;

    fn encode_payload_test(json_str: &str) -> String {
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
        enc.write_all(json_str.as_bytes()).unwrap();
        let deflated = enc.finish().unwrap();
        URL_SAFE_NO_PAD.encode(&deflated)
    }

    #[test]
    fn empty_payload_errors() {
        let payload = encode_payload_test(r#"{"v": 1}"#);
        let err = decode_payload(&payload).unwrap_err();
        assert!(err.to_string().contains("empty"));
    }

    #[test]
    fn future_version_rejected() {
        let payload = encode_payload_test(r#"{"v": 99, "s": []}"#);
        let err = decode_payload(&payload).unwrap_err();
        assert!(err.to_string().contains("version too new"));
    }

    #[test]
    fn current_wire_version_is_accepted() {
        // The composer stamps `SchemaVersions::QR_PAYLOAD` as `v`; the
        // decoder's ceiling derives from the same constant. A payload at
        // exactly that version must decode — a regression where the two
        // drifted (composer at 4, ceiling at 1) rejected every export as
        // "version too new". Build the version literal from the registry
        // so this stays a same-source check, not a copy of `4`.
        let v = CURRENT_FORMAT_VERSION;
        let payload = encode_payload_test(&format!(
            r#"{{"v": {v}, "s": [{{"l": "x", "h": "h", "u": "u"}}]}}"#
        ));
        assert!(
            decode_payload(&payload).is_ok(),
            "payload at the current wire version v{v} must decode"
        );
    }

    #[test]
    fn decodes_session_array_with_minted_ids() {
        let json_str = r#"{
            "v": 1,
            "s": [
                {"l": "host-a", "h": "a.com", "u": "alice", "p": 2222},
                {"l": "host-b", "h": "b.com", "u": "bob"}
            ]
        }"#;
        let result = decode_payload(&encode_payload_test(json_str)).unwrap();
        let sessions: Vec<Value> =
            serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
        assert_eq!(sessions.len(), 2);
        let s0 = sessions[0].as_object().unwrap();
        assert_eq!(s0.get("label").unwrap().as_str(), Some("host-a"));
        assert_eq!(s0.get("host").unwrap().as_str(), Some("a.com"));
        assert_eq!(s0.get("port").unwrap().as_i64(), Some(2222));
        assert!(!s0.get("id").unwrap().as_str().unwrap().is_empty());
        let s1 = sessions[1].as_object().unwrap();
        assert_eq!(s1.get("port").unwrap().as_i64(), Some(22));
    }

    #[test]
    fn decodes_manager_key_with_short_ref() {
        let json_str = r#"{
            "v": 1,
            "s": [{"l": "x", "h": "h", "u": "u", "ki": "k0", "mg": 1}],
            "km": {"k0": "PEM_BYTES"},
            "mk": {"k0": {"l": "MyKey", "t": "ssh-ed25519", "p": "ssh-ed25519 BBBB"}}
        }"#;
        let result = decode_payload(&encode_payload_test(json_str)).unwrap();
        let sessions: Vec<Value> =
            serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
        let s0 = sessions[0].as_object().unwrap();
        assert_eq!(s0.get("key_id").unwrap().as_str(), Some("k0"));
        assert_eq!(s0.get("key_data").unwrap().as_str(), Some(""));

        let keys: Vec<Value> =
            serde_json::from_str(result.pending.keys_json.as_deref().unwrap()).unwrap();
        let k0 = keys[0].as_object().unwrap();
        assert_eq!(k0.get("id").unwrap().as_str(), Some("k0"));
        assert_eq!(k0.get("label").unwrap().as_str(), Some("MyKey"));
        assert_eq!(k0.get("private_key").unwrap().as_str(), Some("PEM_BYTES"));
        assert_eq!(k0.get("key_type").unwrap().as_str(), Some("ssh-ed25519"));
    }

    #[test]
    fn decodes_embedded_key_inline() {
        let json_str = r#"{
            "v": 1,
            "s": [{"l": "x", "h": "h", "u": "u", "ki": "k0"}],
            "km": {"k0": "INLINE_PEM"}
        }"#;
        let result = decode_payload(&encode_payload_test(json_str)).unwrap();
        let sessions: Vec<Value> =
            serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
        let s0 = sessions[0].as_object().unwrap();
        assert!(s0.get("key_id").is_none() || s0.get("key_id").unwrap() == &json!(""));
        assert_eq!(s0.get("key_data").unwrap().as_str(), Some("INLINE_PEM"));
    }

    #[test]
    fn decodes_tags_and_links() {
        let json_str = r##"{
            "v": 1,
            "s": [{"l": "x", "h": "h", "u": "u"}],
            "tg": [{"i": "tag1", "n": "Production", "cl": "#ff0000"}],
            "st": [{"si": "sess1", "ti": "tag1"}],
            "ft": [{"fi": "/folder", "ti": "tag1"}]
        }"##;
        let result = decode_payload(&encode_payload_test(json_str)).unwrap();
        let tags: Vec<Value> =
            serde_json::from_str(result.pending.tags_json.as_deref().unwrap()).unwrap();
        assert_eq!(
            tags[0].as_object().unwrap().get("name").unwrap().as_str(),
            Some("Production")
        );
        assert_eq!(
            tags[0].as_object().unwrap().get("color").unwrap().as_str(),
            Some("#ff0000")
        );
        assert!(result.pending.session_tags_json.is_some());
        assert!(result.pending.folder_tags_json.is_some());
    }

    #[test]
    fn decodes_snippets() {
        let json_str = r#"{
            "v": 1,
            "s": [{"l": "x", "h": "h", "u": "u"}],
            "sn": [{"i": "s1", "t": "Title", "cm": "echo hi", "d": "desc"}]
        }"#;
        let result = decode_payload(&encode_payload_test(json_str)).unwrap();
        let snips: Vec<Value> =
            serde_json::from_str(result.pending.snippets_json.as_deref().unwrap()).unwrap();
        let s = snips[0].as_object().unwrap();
        assert_eq!(s.get("title").unwrap().as_str(), Some("Title"));
        assert_eq!(s.get("command").unwrap().as_str(), Some("echo hi"));
        assert_eq!(s.get("description").unwrap().as_str(), Some("desc"));
    }

    #[test]
    fn decodes_config_and_known_hosts() {
        let json_str = r#"{
            "v": 1,
            "s": [{"l": "x", "h": "h", "u": "u"}],
            "c": {"theme": "dark"},
            "kh": "host:22 ssh-rsa AAAA"
        }"#;
        let result = decode_payload(&encode_payload_test(json_str)).unwrap();
        assert_eq!(
            result.pending.config_json.as_deref(),
            Some(r#"{"theme":"dark"}"#)
        );
        assert_eq!(
            result.pending.known_hosts_text.as_deref(),
            Some("host:22 ssh-rsa AAAA")
        );
    }

    #[test]
    fn non_deflate_payload_is_rejected() {
        // v1 is strictly deflate — raw base64url(JSON) with no deflate
        // envelope is below the floor and must not decode.
        let json_str = r#"{"v": 1, "s": [{"l": "x", "h": "h", "u": "u"}]}"#;
        let payload = URL_SAFE_NO_PAD.encode(json_str.as_bytes());
        let err = decode_payload(&payload).unwrap_err();
        assert!(err.to_string().contains("inflate"));
    }

    #[test]
    fn extract_payload_from_uri_returns_d_value() {
        let uri = "letsflutssh://import?d=ABCD";
        assert_eq!(extract_payload_from_uri(uri), Some("ABCD".into()));
    }

    #[test]
    fn extract_payload_rejects_other_schemes() {
        assert_eq!(extract_payload_from_uri("https://example.com"), None);
        assert_eq!(
            extract_payload_from_uri("letsflutssh://connect?host=h"),
            None
        );
    }

    #[test]
    fn malformed_base64_errors() {
        let err = decode_payload("!!!not-base64!!!").unwrap_err();
        assert!(err.to_string().contains("base64"));
    }
}
