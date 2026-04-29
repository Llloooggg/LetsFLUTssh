//! Pure typed composer for the v4 QR export payload.
//!
//! Splits the existing `lfs_core::archive::qr_export_payload`
//! into two halves:
//!
//! 1. **Production path** — pulls every section from sqlite
//!    (`qr_export_payload` keeps owning that), builds a
//!    [`QrPayloadInput`], and calls [`compose_qr_payload`].
//! 2. **Estimator path** — Dart `unified_export_controller`
//!    composes a [`QrPayloadInput`] from in-memory selections via
//!    FRB DTOs and calls a sync FRB shim that wraps
//!    [`compose_qr_payload`] + `compress_to_payload_size`.
//!
//! Both halves go through the **same composer** so the v4 wire
//! shape (key dedup grammar, manager-key metadata block,
//! per-section keys + abbreviations) lives one place. Closes the
//! recurring drift the F-arc caught once for `encodeSessionCompact`
//! — every section is now contract-tied.
//!
//! The composer is pure: no I/O, no DB, no FRB. Caller is
//! responsible for resolving folder paths, listing manager-key
//! metadata, pulling tag / snippet rows, etc. — anything that
//! requires a sqlite handle stays in `qr_export_payload`.

use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

use crate::archive::QrExportOptions;
use crate::qr_codec_encode::encode_session_compact;

/// Wire-format version every fresh payload writes. Mirrors the
/// `archive::QR_FORMAT_VERSION` const — duplicated here to keep the
/// composer self-contained without making the `archive` const
/// pub.
const QR_FORMAT_VERSION: i64 = 4;

/// Per-session input for [`compose_qr_payload`]. Folder paths,
/// passwords, key bytes, and key-id refs are all pre-resolved by
/// the caller — the composer doesn't know about sqlite.
#[derive(Debug, Clone, Default)]
pub struct QrSessionInput {
    pub id: String,
    pub label: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    /// Empty / `None` = embedded key (PEM in [`key_data`]).
    /// `Some(non-empty)` = manager-key reference; the manager-key
    /// PEM is resolved by the caller into the matching
    /// [`QrManagerKeyEntry`] under the same `id`.
    pub key_id: Option<String>,
    pub key_data: String,
    /// Pre-resolved folder path (e.g. `infra/prod`); empty for
    /// root-level sessions.
    pub folder_path: String,
}

/// Per-tag input. Mirrors the v4 `tg` block fields (`i`/`n`/`cl`).
#[derive(Debug, Clone, Default)]
pub struct QrTagInput {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
}

/// Per-snippet input. Mirrors the v4 `sn` block fields
/// (`i`/`t`/`cm`/`d`).
#[derive(Debug, Clone, Default)]
pub struct QrSnippetInput {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
}

/// Manager-key metadata + the PEM bytes the dedup logic dedupes
/// against. The `id` field corresponds to the manager-key DB
/// `id`; `private_key` is the same PEM the
/// [`QrSessionInput::key_id`] reference resolves into.
#[derive(Debug, Clone, Default)]
pub struct QrManagerKeyEntry {
    pub id: String,
    pub label: String,
    pub key_type: String,
    pub public_key: String,
    pub private_key: String,
}

/// `(session_id, tag_id)` link for the `st` block. Caller filters
/// to selected sessions only — the composer takes the list
/// verbatim.
#[derive(Debug, Clone, Default)]
pub struct QrSessionTagLink {
    pub session_id: String,
    pub tag_id: String,
}

/// `(folder_path, tag_id)` link for the `ft` block. Folder paths
/// (not ids) cross the wire because the importing side mints
/// fresh folder rows on apply.
#[derive(Debug, Clone, Default)]
pub struct QrFolderTagLink {
    pub folder_path: String,
    pub tag_id: String,
}

/// `(session_id, snippet_id)` link for the `ss` block.
#[derive(Debug, Clone, Default)]
pub struct QrSessionSnippetLink {
    pub session_id: String,
    pub snippet_id: String,
}

/// Complete typed input for the v4 composer. Caller pre-resolves
/// every section; the composer is pure.
#[derive(Debug, Clone, Default)]
pub struct QrPayloadInput {
    pub options: QrExportOptions,
    pub sessions: Vec<QrSessionInput>,
    pub empty_folders: Vec<String>,
    /// Pre-serialised `config.json` payload, optional. Empty
    /// string is treated as absent (matches the existing
    /// `qr_export_payload` branch).
    pub config_json: Option<String>,
    /// Pre-built `known_hosts` text. Empty = absent.
    pub known_hosts: String,
    pub tags: Vec<QrTagInput>,
    pub session_tags: Vec<QrSessionTagLink>,
    pub folder_tags: Vec<QrFolderTagLink>,
    pub snippets: Vec<QrSnippetInput>,
    pub session_snippets: Vec<QrSessionSnippetLink>,
    /// Manager-key entries the caller resolved from the DB. The
    /// composer dedupes PEMs by content across embedded +
    /// manager forms; `id` here matches
    /// [`QrSessionInput::key_id`] for the reference lookup, and
    /// the metadata fields drive the `mk` block.
    pub manager_key_entries: Vec<QrManagerKeyEntry>,
}

/// Build the v4 QR JSON payload from a typed input. Pure — no
/// I/O, no DB. Mirrors `qr_export_payload`'s composition step
/// byte-for-byte; the production path will swap to this helper
/// in a follow-up commit, the estimator path uses it from day
/// one via the FRB shim.
#[must_use]
pub fn compose_qr_payload(input: &QrPayloadInput) -> Value {
    let mut payload = serde_json::Map::new();
    payload.insert("v".into(), json!(QR_FORMAT_VERSION));

    // ── Key dedup ────────────────────────────────────────────
    // Resolve every selected session's key bytes into a
    // (session_id → (pem, from_manager)) map.
    let mut session_pem: HashMap<String, (String, bool)> = HashMap::new();
    let manager_by_id: HashMap<String, &QrManagerKeyEntry> = input
        .manager_key_entries
        .iter()
        .map(|e| (e.id.clone(), e))
        .collect();

    let pull_pems = input.options.include_embedded_keys
        || input.options.include_manager_keys
        || input.options.include_all_manager_keys;
    if pull_pems {
        for s in &input.sessions {
            let from_manager = s.key_id.as_deref().is_some_and(|k| !k.is_empty());
            if from_manager
                && !(input.options.include_manager_keys || input.options.include_all_manager_keys)
            {
                continue;
            }
            if !from_manager && !input.options.include_embedded_keys {
                continue;
            }
            let pem = if from_manager {
                manager_by_id
                    .get(s.key_id.as_ref().unwrap())
                    .map(|e| e.private_key.clone())
                    .unwrap_or_default()
            } else {
                s.key_data.clone()
            };
            if !pem.is_empty() {
                session_pem.insert(s.id.clone(), (pem, from_manager));
            }
        }
    }

    // PEM bytes → kN short id map (content-keyed). Identical PEM
    // across embedded + manager + multiple sessions collapses
    // into one `km` entry.
    let mut key_to_short: HashMap<String, String> = HashMap::new();
    let mut session_short: HashMap<String, String> = HashMap::new();
    let mut manager_shorts: HashSet<String> = HashSet::new();
    let mut counter: usize = 0;
    for s in &input.sessions {
        if let Some((pem, from_manager)) = session_pem.get(&s.id) {
            let short = key_to_short
                .entry(pem.clone())
                .or_insert_with(|| {
                    let id = format!("k{counter}");
                    counter += 1;
                    id
                })
                .clone();
            session_short.insert(s.id.clone(), short.clone());
            if *from_manager {
                manager_shorts.insert(short);
            }
        }
    }

    // ── Manager-key metadata (mk block) ──────────────────────
    let mut manager_meta: HashMap<String, (String, String, String)> = HashMap::new();
    if input.options.include_all_manager_keys {
        for k in &input.manager_key_entries {
            if k.private_key.is_empty() {
                continue;
            }
            let short = key_to_short
                .entry(k.private_key.clone())
                .or_insert_with(|| {
                    let id = format!("k{counter}");
                    counter += 1;
                    id
                })
                .clone();
            manager_shorts.insert(short.clone());
            manager_meta.insert(
                short,
                (k.label.clone(), k.key_type.clone(), k.public_key.clone()),
            );
        }
    } else if input.options.include_manager_keys {
        // Fill metadata only for keys actually referenced by the
        // selected sessions.
        let by_pem: HashMap<&str, &QrManagerKeyEntry> = input
            .manager_key_entries
            .iter()
            .map(|k| (k.private_key.as_str(), k))
            .collect();
        for short in &manager_shorts {
            if let Some((pem, _)) = key_to_short.iter().find(|(_, v)| *v == short) {
                if let Some(k) = by_pem.get(pem.as_str()) {
                    manager_meta.insert(
                        short.clone(),
                        (k.label.clone(), k.key_type.clone(), k.public_key.clone()),
                    );
                }
            }
        }
    }

    if !key_to_short.is_empty() {
        let mut km = serde_json::Map::new();
        for (pem, short) in &key_to_short {
            km.insert(short.clone(), Value::String(pem.clone()));
        }
        payload.insert("km".into(), Value::Object(km));
    }
    if !manager_meta.is_empty() {
        let mut mk = serde_json::Map::new();
        for (short, (label, kt, pk)) in &manager_meta {
            mk.insert(short.clone(), json!({"l": label, "t": kt, "p": pk}));
        }
        payload.insert("mk".into(), Value::Object(mk));
    }

    // ── Sessions + empty folders ─────────────────────────────
    if input.options.include_sessions {
        let arr: Vec<Value> = input
            .sessions
            .iter()
            .map(|s| {
                let key_short = session_short.get(&s.id);
                let is_manager = key_short
                    .map(|k| manager_shorts.contains(k))
                    .unwrap_or(false);
                encode_session_compact(
                    &s.label,
                    &s.host,
                    &s.user,
                    u16::try_from(s.port.max(0)).unwrap_or(u16::MAX),
                    &s.folder_path,
                    &s.auth_type,
                    key_short.map(String::as_str),
                    is_manager,
                    input.options.include_passwords,
                    &s.password,
                )
            })
            .collect();
        payload.insert("s".into(), Value::Array(arr));
        if !input.empty_folders.is_empty() {
            payload.insert(
                "eg".into(),
                Value::Array(
                    input
                        .empty_folders
                        .iter()
                        .map(|f| Value::String(f.clone()))
                        .collect(),
                ),
            );
        }
    }

    // ── Config + known_hosts ─────────────────────────────────
    if input.options.include_config {
        if let Some(cj) = input.config_json.as_deref() {
            if !cj.is_empty() {
                if let Ok(v) = serde_json::from_str::<Value>(cj) {
                    payload.insert("c".into(), v);
                }
            }
        }
    }
    if input.options.include_known_hosts && !input.known_hosts.is_empty() {
        payload.insert("kh".into(), Value::String(input.known_hosts.clone()));
    }

    // ── Tags + session/folder tag links ──────────────────────
    if input.options.include_tags && !input.tags.is_empty() {
        let arr: Vec<Value> = input
            .tags
            .iter()
            .map(|t| {
                let mut m = serde_json::Map::new();
                m.insert("i".into(), json!(t.id));
                m.insert("n".into(), json!(t.name));
                if let Some(c) = t.color.as_deref() {
                    m.insert("cl".into(), json!(c));
                }
                Value::Object(m)
            })
            .collect();
        payload.insert("tg".into(), Value::Array(arr));
        if !input.session_tags.is_empty() {
            let arr: Vec<Value> = input
                .session_tags
                .iter()
                .map(|l| json!({"si": l.session_id, "ti": l.tag_id}))
                .collect();
            payload.insert("st".into(), Value::Array(arr));
        }
        if !input.folder_tags.is_empty() {
            let arr: Vec<Value> = input
                .folder_tags
                .iter()
                .map(|l| json!({"fi": l.folder_path, "ti": l.tag_id}))
                .collect();
            payload.insert("ft".into(), Value::Array(arr));
        }
    }

    // ── Snippets + session/snippet links ─────────────────────
    if input.options.include_snippets && !input.snippets.is_empty() {
        let arr: Vec<Value> = input
            .snippets
            .iter()
            .map(|s| {
                let mut m = serde_json::Map::new();
                m.insert("i".into(), json!(s.id));
                m.insert("t".into(), json!(s.title));
                m.insert("cm".into(), json!(s.command));
                if !s.description.is_empty() {
                    m.insert("d".into(), json!(s.description));
                }
                Value::Object(m)
            })
            .collect();
        payload.insert("sn".into(), Value::Array(arr));
        if !input.session_snippets.is_empty() {
            let arr: Vec<Value> = input
                .session_snippets
                .iter()
                .map(|l| json!({"si": l.session_id, "ni": l.snippet_id}))
                .collect();
            payload.insert("ss".into(), Value::Array(arr));
        }
    }

    Value::Object(payload)
}

/// Compose + deflate + base64url — convenience wrapper for the
/// estimator path that only needs the size. Same wire shape +
/// alphabet as `archive::qr_export_payload`.
#[must_use]
pub fn compose_and_size(input: &QrPayloadInput) -> u32 {
    let value = compose_qr_payload(input);
    let json = serde_json::to_string(&value).expect("composed v4 payload always serialises");
    crate::qr_codec_encode::compress_to_payload_size(&json)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts_sessions_only() -> QrExportOptions {
        QrExportOptions {
            include_sessions: true,
            ..QrExportOptions::default()
        }
    }

    fn session(id: &str, label: &str) -> QrSessionInput {
        QrSessionInput {
            id: id.into(),
            label: label.into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            ..QrSessionInput::default()
        }
    }

    #[test]
    fn empty_input_emits_only_version() {
        let v = compose_qr_payload(&QrPayloadInput::default());
        let obj = v.as_object().unwrap();
        // Default options have every include_* off — only `v`.
        assert_eq!(obj.len(), 1);
        assert_eq!(obj.get("v").and_then(Value::as_i64), Some(4));
    }

    #[test]
    fn sessions_block_collapses_when_empty_with_include_on() {
        // include_sessions on but no sessions selected — `s` is
        // still emitted as an empty array (mirrors the production
        // path, which always lands the key when the toggle is on).
        let v = compose_qr_payload(&QrPayloadInput {
            options: opts_sessions_only(),
            ..QrPayloadInput::default()
        });
        let obj = v.as_object().unwrap();
        assert!(obj.contains_key("s"));
        assert!(obj.get("s").unwrap().as_array().unwrap().is_empty());
    }

    #[test]
    fn sessions_block_emits_compact_per_session_shape() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: opts_sessions_only(),
            sessions: vec![session("s1", "lab")],
            ..QrPayloadInput::default()
        });
        let s = &v.as_object().unwrap()["s"].as_array().unwrap()[0];
        assert_eq!(s.get("l").and_then(Value::as_str), Some("lab"));
        assert_eq!(s.get("h").and_then(Value::as_str), Some("h"));
        assert_eq!(s.get("u").and_then(Value::as_str), Some("u"));
    }

    #[test]
    fn empty_folders_landed_under_eg_key() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: opts_sessions_only(),
            sessions: vec![session("s1", "lab")],
            empty_folders: vec!["a/b".into(), "c".into()],
            ..QrPayloadInput::default()
        });
        let eg = v
            .as_object()
            .unwrap()
            .get("eg")
            .unwrap()
            .as_array()
            .unwrap();
        assert_eq!(eg.len(), 2);
        assert_eq!(eg[0].as_str(), Some("a/b"));
    }

    #[test]
    fn embedded_key_dedup_collapses_identical_pems() {
        // Two sessions sharing the same embedded PEM produce one
        // `km` entry under k0 and both sessions reference k0
        // through `ki`.
        let s1 = QrSessionInput {
            id: "s1".into(),
            label: "a".into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "key".into(),
            key_data: "PEM-AAA".into(),
            ..QrSessionInput::default()
        };
        let s2 = QrSessionInput {
            id: "s2".into(),
            label: "b".into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "key".into(),
            key_data: "PEM-AAA".into(),
            ..QrSessionInput::default()
        };
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_sessions: true,
                include_embedded_keys: true,
                ..QrExportOptions::default()
            },
            sessions: vec![s1, s2],
            ..QrPayloadInput::default()
        });
        let obj = v.as_object().unwrap();
        let km = obj.get("km").unwrap().as_object().unwrap();
        assert_eq!(km.len(), 1, "two identical PEMs collapse to one km entry");
        let s_arr = obj["s"].as_array().unwrap();
        assert_eq!(s_arr[0].get("ki").and_then(Value::as_str), Some("k0"));
        assert_eq!(s_arr[1].get("ki").and_then(Value::as_str), Some("k0"));
    }

    #[test]
    fn manager_key_metadata_only_emitted_for_referenced_keys() {
        // Two manager keys exist; one session references one of
        // them. With include_manager_keys (not include_all),
        // only the referenced key lands in mk.
        let s = QrSessionInput {
            id: "s1".into(),
            label: "a".into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "key".into(),
            key_id: Some("mgr1".into()),
            ..QrSessionInput::default()
        };
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_sessions: true,
                include_manager_keys: true,
                ..QrExportOptions::default()
            },
            sessions: vec![s],
            manager_key_entries: vec![
                QrManagerKeyEntry {
                    id: "mgr1".into(),
                    label: "Used".into(),
                    key_type: "ed25519".into(),
                    public_key: "PUB-MGR1".into(),
                    private_key: "PEM-MGR1".into(),
                },
                QrManagerKeyEntry {
                    id: "mgr2".into(),
                    label: "Unused".into(),
                    key_type: "ed25519".into(),
                    public_key: "PUB-MGR2".into(),
                    private_key: "PEM-MGR2".into(),
                },
            ],
            ..QrPayloadInput::default()
        });
        let mk = v
            .as_object()
            .unwrap()
            .get("mk")
            .unwrap()
            .as_object()
            .unwrap();
        assert_eq!(mk.len(), 1);
        let entry = mk.values().next().unwrap();
        assert_eq!(entry.get("l").and_then(Value::as_str), Some("Used"));
    }

    #[test]
    fn include_all_manager_keys_folds_unreferenced_keys_in() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_sessions: true,
                include_all_manager_keys: true,
                ..QrExportOptions::default()
            },
            sessions: vec![session("s1", "lab")],
            manager_key_entries: vec![
                QrManagerKeyEntry {
                    id: "mgr1".into(),
                    label: "A".into(),
                    key_type: "ed25519".into(),
                    public_key: "PUB-A".into(),
                    private_key: "PEM-A".into(),
                },
                QrManagerKeyEntry {
                    id: "mgr2".into(),
                    label: "B".into(),
                    key_type: "ed25519".into(),
                    public_key: "PUB-B".into(),
                    private_key: "PEM-B".into(),
                },
            ],
            ..QrPayloadInput::default()
        });
        let obj = v.as_object().unwrap();
        let km = obj.get("km").unwrap().as_object().unwrap();
        assert_eq!(km.len(), 2, "include_all_manager_keys folds every key in");
        let mk = obj.get("mk").unwrap().as_object().unwrap();
        assert_eq!(mk.len(), 2);
    }

    #[test]
    fn config_block_lands_under_c_key_when_provided() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_config: true,
                ..QrExportOptions::default()
            },
            config_json: Some(r#"{"foo":"bar"}"#.into()),
            ..QrPayloadInput::default()
        });
        let c = v.as_object().unwrap().get("c").unwrap();
        assert_eq!(c.get("foo").and_then(Value::as_str), Some("bar"));
    }

    #[test]
    fn config_block_omitted_when_payload_empty_or_invalid() {
        // Empty config_json string → c absent.
        let v1 = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_config: true,
                ..QrExportOptions::default()
            },
            config_json: Some(String::new()),
            ..QrPayloadInput::default()
        });
        assert!(!v1.as_object().unwrap().contains_key("c"));
        // Malformed JSON → c absent (matches production behaviour).
        let v2 = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_config: true,
                ..QrExportOptions::default()
            },
            config_json: Some("not-json".into()),
            ..QrPayloadInput::default()
        });
        assert!(!v2.as_object().unwrap().contains_key("c"));
    }

    #[test]
    fn known_hosts_block_omitted_when_empty() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_known_hosts: true,
                ..QrExportOptions::default()
            },
            known_hosts: String::new(),
            ..QrPayloadInput::default()
        });
        assert!(!v.as_object().unwrap().contains_key("kh"));
    }

    #[test]
    fn tags_block_emits_per_tag_shape() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_tags: true,
                ..QrExportOptions::default()
            },
            tags: vec![QrTagInput {
                id: "t1".into(),
                name: "prod".into(),
                color: Some("#ff0000".into()),
            }],
            session_tags: vec![QrSessionTagLink {
                session_id: "s1".into(),
                tag_id: "t1".into(),
            }],
            folder_tags: vec![QrFolderTagLink {
                folder_path: "infra".into(),
                tag_id: "t1".into(),
            }],
            ..QrPayloadInput::default()
        });
        let obj = v.as_object().unwrap();
        let tg = obj["tg"].as_array().unwrap();
        assert_eq!(tg[0].get("i").and_then(Value::as_str), Some("t1"));
        assert_eq!(tg[0].get("n").and_then(Value::as_str), Some("prod"));
        assert_eq!(tg[0].get("cl").and_then(Value::as_str), Some("#ff0000"));
        let st = obj["st"].as_array().unwrap();
        assert_eq!(st[0].get("si").and_then(Value::as_str), Some("s1"));
        let ft = obj["ft"].as_array().unwrap();
        assert_eq!(ft[0].get("fi").and_then(Value::as_str), Some("infra"));
    }

    #[test]
    fn snippets_block_drops_empty_description() {
        let v = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_snippets: true,
                ..QrExportOptions::default()
            },
            snippets: vec![QrSnippetInput {
                id: "n1".into(),
                title: "ls".into(),
                command: "ls -la".into(),
                description: String::new(),
            }],
            ..QrPayloadInput::default()
        });
        let sn = &v.as_object().unwrap()["sn"].as_array().unwrap()[0];
        assert!(!sn.as_object().unwrap().contains_key("d"));
    }

    #[test]
    fn password_only_in_payload_when_include_passwords_on() {
        let s = QrSessionInput {
            id: "s1".into(),
            label: "lab".into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            password: "secret".into(),
            ..QrSessionInput::default()
        };
        let off = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_sessions: true,
                ..QrExportOptions::default()
            },
            sessions: vec![s.clone()],
            ..QrPayloadInput::default()
        });
        assert!(!off.as_object().unwrap()["s"].as_array().unwrap()[0]
            .as_object()
            .unwrap()
            .contains_key("pw"));

        let on = compose_qr_payload(&QrPayloadInput {
            options: QrExportOptions {
                include_sessions: true,
                include_passwords: true,
                ..QrExportOptions::default()
            },
            sessions: vec![s],
            ..QrPayloadInput::default()
        });
        assert_eq!(
            on.as_object().unwrap()["s"].as_array().unwrap()[0]
                .get("pw")
                .and_then(Value::as_str),
            Some("secret"),
        );
    }

    #[test]
    fn compose_and_size_returns_non_zero_for_real_payload() {
        let size = compose_and_size(&QrPayloadInput {
            options: opts_sessions_only(),
            sessions: vec![session("s1", "lab"), session("s2", "lab2")],
            ..QrPayloadInput::default()
        });
        assert!(size > 0);
        assert!(size < 1024, "small input should compress to << 1KB");
    }
}
