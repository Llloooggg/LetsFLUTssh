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

/// Append a frame to an open recording. Encrypted recordings
/// produce the `[len(4 LE)][nonce(12)][ct+tag]` framing
/// internally; plaintext recordings write `plaintext` verbatim.
/// Returns the running byte total.
pub async fn recorder_record_frame(id: String, plaintext: Vec<u8>) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        app.recorders
            .record_frame(&id, &plaintext, &app.bus)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("recorder write task: {e}"))?
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
