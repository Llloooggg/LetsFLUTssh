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
        Some(arr)
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
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("recorder register task: {e}"))?
}

/// HKDF-SHA256 info string the Dart-era recorder used. Pinned
/// here so the byte-for-byte derivation matches whatever the old
/// recorder wrote — recordings produced before the SecretRef
/// migration must remain decryptable.
const RECORDER_HKDF_INFO: &[u8] = b"letsflutssh-recording-v1";

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
                Some(arr)
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
        .map_err(|e| e.to_string())
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
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("recorder header task: {e}"))?
}

/// Compose an asciinema v2 event line `[delta_secs, "o"|"i",
/// utf8_str]` and append it as a frame. The delta is computed
/// against the recording's `started_at` anchor — same semantics
/// the legacy Dart `_enqueueEvent` produced. Empty `bytes` is a
/// no-op.
pub async fn recorder_record_event(
    id: String,
    direction: DbRecordDirection,
    bytes: Vec<u8>,
) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        app.recorders
            .record_event(&id, direction.into(), &bytes, &app.bus)
            .map_err(|e| e.to_string())
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
            .map_err(|e| e.to_string())
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
            .map_err(|e| e.to_string())
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
        .map_err(|e| e.to_string())
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
        .map_err(|e| e.to_string())
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
        .map_err(|e| e.to_string())
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
        .map_err(|e| e.to_string())
}
