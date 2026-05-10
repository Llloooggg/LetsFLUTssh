//! FRB adapter for `lfs_core::recorder`. Surfaces the IO-owning
//! recording driver so Dart can hand off framing + writes to
//! Rust. Plaintext credential bytes (the user's terminal output
//! / keystrokes) are still produced Dart-side — the encryption +
//! file write moves Rust-side, which means the on-disk frame
//! never crosses the FRB boundary back outwards.

/// Public mirror of `RecorderSnapshot`. Same shape — kept here
/// rather than reused so FRB can derive its own marshalling.
#[derive(Debug, Clone)]
pub struct DbRecorderSnapshot {
    pub id: String,
    pub session_id: String,
    pub path: String,
    pub bytes_written: u64,
    pub encrypted: bool,
}

impl From<lfs_core::recorder::RecorderSnapshot> for DbRecorderSnapshot {
    fn from(s: lfs_core::recorder::RecorderSnapshot) -> Self {
        Self {
            id: s.id,
            session_id: s.session_id,
            path: s.path,
            bytes_written: s.bytes_written,
            encrypted: s.encrypted,
        }
    }
}

/// Open a fresh recording. `key` is either a 32-byte AES-256
/// key (encrypted mode) or empty bytes (plaintext mode — writes
/// raw asciinema). Returns the registered snapshot.
pub async fn recorder_register(
    id: String,
    session_id: String,
    path: String,
    key: Vec<u8>,
) -> Result<DbRecorderSnapshot, String> {
    let key_arr = if key.is_empty() {
        None
    } else {
        let arr: [u8; 32] = key
            .as_slice()
            .try_into()
            .map_err(|_| "recorder key must be 32 bytes".to_string())?;
        Some(zeroize::Zeroizing::new(arr))
    };
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        lfs_core::recorder::RecorderRegistry::register_with_io(
            &app.recorders,
            id,
            session_id,
            path,
            key_arr,
            &app.bus,
        )
        .map(DbRecorderSnapshot::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("recorder register task: {e}"))?
}

/// HKDF-SHA256 info string for the per-recording AES-256 key
/// derivation. Pinned to this exact byte sequence — bumping it
/// makes every existing on-disk `.lfsr` recording undecryptable
/// because the reader recomputes the same HKDF chain off the
/// active DB key.
const RECORDER_HKDF_INFO: &[u8] = b"letsflutssh-recording-v1";

/// One playback event. `line` carries a decoded JSON-Lines record;
/// `error` (when set) carries a typed reason the playback aborted.
/// Exactly one field is non-null per event. The tagged shape lets
/// errors surface IN the stream rather than through the
/// `Result<(), String>` return — FRB's generated Dart wrapper
/// drops the return-channel future via `unawaited(...)`, so a
/// `return Err(...)` would leak as an uncaught zone error rather
/// than reach the `await for` consumer.
#[derive(Debug, Clone)]
pub struct DbPlaybackEvent {
    pub line: Option<String>,
    pub error: Option<String>,
}

/// Open a recording for playback and stream every decoded
/// JSON-Lines record to `sink` as a [`DbPlaybackEvent`]. Routes
/// by extension Rust-side: `.lfsr` (case-insensitive) opens
/// through the encrypted iterator with the recording key derived
/// from `secrets::ACTIVE_DBKEY_SECRET_ID` via the pinned
/// `letsflutssh-recording-v1` HKDF chain; any other extension
/// (or none) opens through the plaintext `.cast` iterator.
///
/// The Dart caller hands the path in once and never branches on
/// extension itself. The DB key + the derived recording key
/// never cross the FRB boundary back to Dart.
///
/// Errors during the magic / version sniff + per-frame decrypt
/// (encrypted path) and per-line read (plaintext path) surface
/// as a final `DbPlaybackEvent { error: Some(detail) }` before
/// the stream closes. Stream cancellation (Dart subscription
/// cancelled) closes the sink → next `add` fails → the
/// spawn_blocking task drops out of the iteration loop.
pub async fn recorder_open_for_playback(
    path: String,
    sink: crate::frb_generated::StreamSink<DbPlaybackEvent>,
) {
    let _ = tokio::task::spawn_blocking(move || {
        let path_buf = std::path::PathBuf::from(&path);
        let is_lfsr = path_buf
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.eq_ignore_ascii_case("lfsr"))
            .unwrap_or(false);
        // Encrypted recordings need the active DB key derivation;
        // plaintext .cast files skip the secret-store probe entirely
        // so playback works even on a tier with no in-memory key
        // (e.g. plaintext-tier recordings).
        let key_arr: [u8; 32] = if is_lfsr {
            let app = lfs_core::app::instance();
            match app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID) {
                None => {
                    let _ = sink.add(DbPlaybackEvent {
                        line: None,
                        error: Some(
                            "no active DB key — encrypted recording cannot be opened".to_string(),
                        ),
                    });
                    return;
                }
                Some(db_key) if db_key.is_empty() => {
                    let _ = sink.add(DbPlaybackEvent {
                        line: None,
                        error: Some(
                            "no active DB key — encrypted recording cannot be opened".to_string(),
                        ),
                    });
                    return;
                }
                Some(db_key) => {
                    match lfs_core::crypto::hkdf_sha256(&db_key, &[], RECORDER_HKDF_INFO, 32) {
                        Ok(rk) => match rk[..].try_into() {
                            Ok(arr) => arr,
                            Err(_) => {
                                let _ = sink.add(DbPlaybackEvent {
                                    line: None,
                                    error: Some("recording key wrong size".to_string()),
                                });
                                return;
                            }
                        },
                        Err(e) => {
                            let _ = sink.add(DbPlaybackEvent {
                                line: None,
                                error: Some(format!("recorder hkdf: {e}")),
                            });
                            return;
                        }
                    }
                }
            }
        } else {
            // Plaintext path ignores the key — passing zeros keeps
            // the open_for_playback signature uniform.
            [0u8; 32]
        };
        let mut iter = match lfs_core::recorder::reader::open_for_playback(&path_buf, key_arr) {
            Ok(it) => it,
            Err(e) => {
                let _ = sink.add(DbPlaybackEvent {
                    line: None,
                    error: Some(e.to_string()),
                });
                return;
            }
        };
        while let Some(frame) = iter.next_record() {
            match frame {
                Ok(line) => {
                    if sink
                        .add(DbPlaybackEvent {
                            line: Some(line),
                            error: None,
                        })
                        .is_err()
                    {
                        // Cancelled Dart-side.
                        break;
                    }
                }
                Err(e) => {
                    let _ = sink.add(DbPlaybackEvent {
                        line: None,
                        error: Some(e.to_string()),
                    });
                    break;
                }
            }
        }
    })
    .await;
}

/// Derive the per-recording AES-256 key from the active DB key
/// in [`lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`] using the same
/// HKDF-SHA256 chain [`recorder_register_from_active`] uses for
/// the writer. Returns the 32-byte recorder key for callers that
/// drive AES-GCM decryption Dart-side (today: `RecordingReader`
/// playback streamer); future migration moves the iter Rust-side
/// and this entry point retires.
///
/// Returns an empty `Vec` when the active slot is empty
/// (plaintext tier) — caller treats empty as "no encrypted
/// recordings can be opened from this session".
pub async fn recorder_derive_key_from_active() -> Result<Vec<u8>, String> {
    tokio::task::spawn_blocking(|| {
        let app = lfs_core::app::instance();
        let Some(db_key) = app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID) else {
            return Ok(Vec::new());
        };
        if db_key.is_empty() {
            return Ok(Vec::new());
        }
        lfs_core::crypto::hkdf_sha256(&db_key, &[], RECORDER_HKDF_INFO, 32)
            .map(|z| z.to_vec())
            .map_err(|e| format!("recorder hkdf: {e}"))
    })
    .await
    .map_err(|e| format!("recorder derive task: {e}"))?
}

/// SecretRef variant of [`recorder_register`]. Reads the running
/// session's DB key from
/// [`lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`], runs the
/// `letsflutssh-recording-v1` HKDF-SHA256 derivation entirely
/// Rust-side, and registers the recorder under the derived key.
/// When the active slot is empty (plaintext tier) the recorder
/// registers in plaintext-asciinema mode.
///
/// Bytes never cross the FRB boundary on this path — both the DB
/// key and the derived recorder key live in Rust memory only.
pub async fn recorder_register_from_active(
    id: String,
    session_id: String,
    path: String,
) -> Result<DbRecorderSnapshot, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let key_arr = match app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID) {
            Some(db_key) if !db_key.is_empty() => {
                let derived = lfs_core::crypto::hkdf_sha256(&db_key, &[], RECORDER_HKDF_INFO, 32)
                    .map_err(|e| format!("recorder hkdf: {e}"))?;
                let arr: [u8; 32] = derived
                    .as_slice()
                    .try_into()
                    .map_err(|_| "recorder derived key length".to_string())?;
                Some(zeroize::Zeroizing::new(arr))
            }
            _ => None,
        };
        lfs_core::recorder::RecorderRegistry::register_with_io(
            &app.recorders,
            id,
            session_id,
            path,
            key_arr,
            &app.bus,
        )
        .map(DbRecorderSnapshot::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("recorder register from active task: {e}"))?
}

/// FRB mirror of [`lfs_core::recorder::RecordDirection`].
pub enum DbRecordDirection {
    Output,
    Input,
}

impl From<DbRecordDirection> for lfs_core::recorder::RecordDirection {
    fn from(d: DbRecordDirection) -> Self {
        match d {
            DbRecordDirection::Output => lfs_core::recorder::RecordDirection::Output,
            DbRecordDirection::Input => lfs_core::recorder::RecordDirection::Input,
        }
    }
}

/// Compose the asciinema v2 header line for the registered
/// recording (`{"version": 2, "width": …, "height": …,
/// "timestamp": …, "env": {…}}`) and append it as a frame. The
/// timestamp anchor matches the recording's `started_at` (set at
/// `recorder_register` time). `shell_label` is JSON-escaped
/// inside the helper.
pub async fn recorder_record_header(
    id: String,
    width: u32,
    height: u32,
    shell_label: String,
) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        app.recorders
            .record_header(&id, width, height, &shell_label, &app.bus)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("recorder header task: {e}"))?
}

/// Compose an asciinema v2 event line `[delta_secs, "o"|"i",
/// utf8_str]` and append it as a frame. The delta is computed
/// against the recording's `started_at` anchor — playback tools
/// that consume the v2 spec (asciinema CLI, our in-app player)
/// expect this anchoring. Empty `bytes` is a no-op.
pub async fn recorder_record_event(
    id: String,
    direction: DbRecordDirection,
    bytes: Vec<u8>,
) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        app.recorders
            .record_event(&id, direction.into(), &bytes, &app.bus)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("recorder event task: {e}"))?
}

/// Atomically rotate a recording to a fresh file under the same
/// id. Closes the current file, opens [`new_path`] in append
/// mode, writes the LFR1 magic + version when the recording is
/// encrypted, and resets the per-actor byte counter. Returns the
/// updated snapshot. Idempotent error on a missing / counter-only
/// actor.
pub async fn recorder_rotate_to(
    id: String,
    new_path: String,
) -> Result<DbRecorderSnapshot, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        app.recorders
            .rotate_to(&id, new_path, &app.bus)
            .map(DbRecorderSnapshot::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("recorder rotate task: {e}"))?
}

/// The hard upper bound, in bytes, on a single recording file
/// before the driver rolls to a new file. Mirrored from
/// `lfs_core::recorder::MAX_FILE_BYTES` so the Dart caller never
/// keeps a stale duplicate.
pub fn recorder_max_file_bytes() -> u64 {
    lfs_core::recorder::MAX_FILE_BYTES
}

/// Flush + close an open recording. Idempotent on a missing id.
pub async fn recorder_close(id: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        app.recorders
            .close_with_io(&id, &app.bus)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("recorder close task: {e}"))?
}

// =====================================================================
// Per-id write queue surface
// =====================================================================
//
// The Dart shim does not call `recorder_record_*` directly any more —
// the per-id worker inside `lfs_core::recorder::queue` drains a
// dedicated mpsc and serialises calls into the registry so the
// asciinema event stream lands on disk in arrival order even when
// concurrent FRB calls overlap on the runtime. Spawn the worker once
// after `recorder_register`; use the enqueue endpoints below for the
// recording's lifetime; close drains + drops the worker.

/// Spawn the per-id write worker. Pair with a prior
/// [`recorder_register`] so the actor row exists. Idempotent on a
/// re-spawn for the same id (the prior worker exits cleanly on its
/// next mailbox `recv`).
pub async fn recorder_queue_spawn(id: String) {
    let app = lfs_core::app::instance();
    app.recorder_queue.spawn(id).await;
}

/// Enqueue an asciinema header line. Fire-and-forget — returns once
/// the entry is in the worker's mailbox; the actual write happens
/// out of band and emits the usual `RecorderBytesWritten` bus event.
/// Uses `enqueue_blocking` so any pending chunk-buffer bytes drain
/// before the header (in practice the buffer is empty pre-header,
/// but the call shape stays uniform with rotate / close).
pub async fn recorder_queue_enqueue_header(
    id: String,
    width: u32,
    height: u32,
    shell_label: String,
) -> Result<(), String> {
    let app = lfs_core::app::instance();
    app.recorder_queue
        .enqueue_blocking(
            &id,
            lfs_core::recorder::queue::QueueEntry::Header {
                width,
                height,
                shell_label,
            },
        )
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Enqueue a terminal event chunk. Same fire-and-forget shape as
/// [`recorder_queue_enqueue_header`]. `bytes` is the raw chunk
/// (output or input); the Rust-side accumulator coalesces
/// high-frequency russh `Data` packets into one mailbox entry per
/// flush window (size + deadline) so the worker isn't woken on
/// every PTY chunk. Dart callers fire this once per arriving russh
/// `Data` packet without paying a worker wake-up per call.
pub async fn recorder_queue_enqueue_event(
    id: String,
    direction: DbRecordDirection,
    bytes: Vec<u8>,
) -> Result<(), String> {
    let app = lfs_core::app::instance();
    app.recorder_queue
        .enqueue_event_chunk(&id, direction.into(), bytes)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Enqueue an atomic rotation to a fresh file. The Dart side owns
/// path allocation (the platform `getApplicationSupportDirectory`
/// plus `hardenFilePerms` sweeps); this enqueue just hands the
/// worker the new destination. `enqueue_blocking` drains any
/// in-flight chunk buffer first so trailing bytes from the old
/// recording land in the *old* file, not the new one.
pub async fn recorder_queue_enqueue_rotate(id: String, new_path: String) -> Result<(), String> {
    let app = lfs_core::app::instance();
    app.recorder_queue
        .enqueue_blocking(
            &id,
            lfs_core::recorder::queue::QueueEntry::Rotate { new_path },
        )
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Enqueue a close. The worker drains any in-flight entries, calls
/// `close_with_io`, drops itself from the queue map, and exits.
/// `enqueue_blocking` drains the chunk buffer first so the trailing
/// bytes that arrived in the last 10 ms make it onto disk before
/// the file is sealed.
pub async fn recorder_queue_enqueue_close(id: String) -> Result<(), String> {
    let app = lfs_core::app::instance();
    app.recorder_queue
        .enqueue_blocking(&id, lfs_core::recorder::queue::QueueEntry::Close)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

// =====================================================================
// Recordings browser surface
// =====================================================================
//
// The Dart `RecordingsPanel` used to walk `<appSupport>/recordings/`
// via `Directory.list()` + `File.stat()` + `File.delete()`. The walk
// + stat + delete now live Rust-side under `lfs_core::recorder::browser`
// so the `Rust owns data` invariant holds for the whole recordings
// lifecycle (write → list → playback → delete).

/// Per-recording metadata yielded by [`recorder_list_recordings`].
/// Mirrors `lfs_core::recorder::browser::RecordingEntry` — kept in
/// the FRB crate so the codegen owns the marshalled shape.
#[derive(Debug, Clone)]
pub struct DbRecordingEntry {
    pub session_id: String,
    pub file_name: String,
    pub extension: String,
    pub size_bytes: u64,
    /// Modification time as Unix epoch seconds. The Dart side
    /// converts to `DateTime` once at the surface.
    pub mtime_unix_secs: i64,
    pub encrypted: bool,
}

impl From<lfs_core::recorder::browser::RecordingEntry> for DbRecordingEntry {
    fn from(e: lfs_core::recorder::browser::RecordingEntry) -> Self {
        Self {
            session_id: e.session_id,
            file_name: e.file_name,
            extension: e.extension,
            size_bytes: e.size_bytes,
            mtime_unix_secs: e.mtime_unix_secs,
            encrypted: e.encrypted,
        }
    }
}

/// List every recording under `<recordings_root>/<sessionId>/`.
/// `recordings_root` is the platform-specific
/// `getApplicationSupportDirectory() + "/recordings"` resolved
/// Dart-side — `path_provider` is the only piece of the chain
/// that has to live in Dart.
///
/// Filters to `.cast` + `.lfsr` regular files; skips directories,
/// symlinks, and unrelated extensions. A missing root returns an
/// empty list (fresh-install case where the recorder never ran).
pub async fn recorder_list_recordings(
    recordings_root: String,
) -> Result<Vec<DbRecordingEntry>, String> {
    tokio::task::spawn_blocking(move || {
        let root = std::path::PathBuf::from(recordings_root);
        lfs_core::recorder::browser::list_recordings(&root)
            .map(|v| v.into_iter().map(DbRecordingEntry::from).collect())
            .map_err(|e| crate::api::frb_err::wire(crate::api::frb_err::kind::IO, &e.to_string()))
    })
    .await
    .map_err(|e| format!("recorder list task: {e}"))?
}

/// Delete `<recordings_root>/<session_id>/<file_name>`. Both
/// `session_id` and `file_name` MUST be the bare components the
/// `recorder_list_recordings` walk returned — neither may contain
/// `..` or a path separator. The helper rejects tainted input
/// before issuing any filesystem call.
///
/// Idempotent on a missing target — a stale Dart-side cache that
/// requests an already-deleted row returns `Ok(())` so the UI
/// can refresh without surfacing a spurious error.
pub async fn recorder_delete_recording(
    recordings_root: String,
    session_id: String,
    file_name: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let root = std::path::PathBuf::from(recordings_root);
        lfs_core::recorder::browser::delete_recording(&root, &session_id, &file_name).map_err(|e| {
            match e {
                lfs_core::recorder::browser::BrowserError::Io(io) => {
                    crate::api::frb_err::wire(crate::api::frb_err::kind::IO, &io.to_string())
                }
                lfs_core::recorder::browser::BrowserError::InvalidComponent => {
                    crate::api::frb_err::wire(
                        crate::api::frb_err::kind::GENERIC,
                        "invalid recording path component",
                    )
                }
            }
        })
    })
    .await
    .map_err(|e| format!("recorder delete task: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    // The register / queue / playback endpoints route through
    // `app::instance().recorders` + tokio + filesystem; covered by
    // the `recording_reader_test.dart` integration suite + the
    // `lfs_frb/tests/poison_recovery.rs` cargo integration binary.
    // The standalone tests below pin the wire-shape mappings + the
    // exposed-const contract that crosses the FRB boundary.

    #[test]
    fn recorder_snapshot_carries_every_field() {
        let core = lfs_core::recorder::RecorderSnapshot {
            id: "rec-x".into(),
            session_id: "sess-y".into(),
            path: "/tmp/x.lfsr".into(),
            bytes_written: 4096,
            encrypted: true,
        };
        let db: DbRecorderSnapshot = core.into();
        assert_eq!(db.id, "rec-x");
        assert_eq!(db.session_id, "sess-y");
        assert_eq!(db.path, "/tmp/x.lfsr");
        assert_eq!(db.bytes_written, 4096);
        assert!(db.encrypted);
    }

    #[test]
    fn record_direction_round_trips_both_variants() {
        let o: lfs_core::recorder::RecordDirection = DbRecordDirection::Output.into();
        let i: lfs_core::recorder::RecordDirection = DbRecordDirection::Input.into();
        assert_eq!(o, lfs_core::recorder::RecordDirection::Output);
        assert_eq!(i, lfs_core::recorder::RecordDirection::Input);
    }

    #[test]
    fn max_file_bytes_matches_lfs_core_const() {
        // Pin the constant so a Rust-side bump can't silently
        // diverge from the documented 100 MiB cap the Dart shim
        // depends on for the rotate trigger.
        assert_eq!(
            recorder_max_file_bytes(),
            lfs_core::recorder::MAX_FILE_BYTES
        );
        assert_eq!(recorder_max_file_bytes(), 100 * 1024 * 1024);
    }

    #[test]
    fn recording_entry_carries_every_field() {
        let core = lfs_core::recorder::browser::RecordingEntry {
            session_id: "sess".into(),
            file_name: "rec.cast".into(),
            extension: "cast".into(),
            size_bytes: 1024,
            mtime_unix_secs: 1_700_000_000,
            encrypted: false,
        };
        let db: DbRecordingEntry = core.into();
        assert_eq!(db.session_id, "sess");
        assert_eq!(db.file_name, "rec.cast");
        assert_eq!(db.extension, "cast");
        assert_eq!(db.size_bytes, 1024);
        assert_eq!(db.mtime_unix_secs, 1_700_000_000);
        assert!(!db.encrypted);
    }
}
