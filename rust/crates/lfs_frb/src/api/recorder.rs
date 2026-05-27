//! FRB adapter for `lfs_core::recorder`. Surfaces the IO-owning
//! recording driver so Dart can hand off framing + writes to
//! Rust. Plaintext credential bytes (the user's terminal output
//! / keystrokes) are still produced Dart-side — the encryption +
//! file write moves Rust-side, which means the on-disk frame
//! never crosses the FRB boundary back outwards.

use crate::api::frb_err;

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
            .map_err(|_| frb_err::wire(frb_err::kind::RECORDER, "recorder key must be 32 bytes"))?;
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
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder register task: {e}"),
        )
    })?
}

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
    recorder_open_for_playback_inner(path, None, 0, sink).await;
}

/// Variant of [`recorder_open_for_playback`] that pre-positions the
/// underlying byte cursor to `start_offset` before yielding records.
/// `start_frame_index` is the encrypted-frame AAD counter for the
/// first frame past the offset — the sidecar entry index matches it
/// 1:1 because every sidecar entry maps to one main-file frame.
///
/// Plaintext recordings ignore `start_frame_index` (no AAD chain) and
/// route `start_offset` straight into the `BufReader`. Pass
/// `start_offset = None` to behave identically to
/// `recorder_open_for_playback`.
pub async fn recorder_open_for_playback_at(
    path: String,
    start_offset: u64,
    start_frame_index: u64,
    sink: crate::frb_generated::StreamSink<DbPlaybackEvent>,
) {
    recorder_open_for_playback_inner(path, Some(start_offset), start_frame_index, sink).await;
}

async fn recorder_open_for_playback_inner(
    path: String,
    start_offset: Option<u64>,
    start_frame_index: u64,
    sink: crate::frb_generated::StreamSink<DbPlaybackEvent>,
) {
    let _ = tokio::task::spawn_blocking(move || {
        let path_buf = std::path::PathBuf::from(&path);
        let is_lfsr = path_buf
            .extension()
            .and_then(|e| e.to_str())
            .map(|s| s.eq_ignore_ascii_case("lfsr"))
            .unwrap_or(false);
        let Some(key_arr) = resolve_playback_key(is_lfsr, &sink) else {
            return;
        };
        let mut iter = match lfs_core::recorder::reader::open_for_playback_at(
            &path_buf,
            key_arr,
            start_offset,
            start_frame_index,
        ) {
            Ok(it) => it,
            Err(e) => {
                emit_playback_error(&sink, &e.to_string());
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
                    emit_playback_error(&sink, &e.to_string());
                    break;
                }
            }
        }
    })
    .await;
}

/// Resolve the 32-byte recording key for playback. Encrypted `.lfsr`
/// recordings need the active DB key (the reader unwraps the per-file
/// recording key from the v1 header internally); plaintext `.cast`
/// files skip the secret-store probe and get zeros so the
/// `open_for_playback_at` signature stays uniform — playback then
/// works even on a tier with no in-memory key. Returns None (after
/// emitting the reason to `sink`) when an encrypted recording has no
/// usable key.
fn resolve_playback_key(
    is_lfsr: bool,
    sink: &crate::frb_generated::StreamSink<DbPlaybackEvent>,
) -> Option<[u8; 32]> {
    if !is_lfsr {
        return Some([0u8; 32]);
    }
    let app = lfs_core::app::instance();
    match app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID) {
        Some(db_key) if !db_key.is_empty() => match db_key.as_slice().try_into() {
            Ok(arr) => Some(arr),
            Err(_) => {
                emit_playback_error(sink, "active db key wrong length");
                None
            }
        },
        _ => {
            emit_playback_error(
                sink,
                "no active DB key — encrypted recording cannot be opened",
            );
            None
        }
    }
}

fn emit_playback_error(sink: &crate::frb_generated::StreamSink<DbPlaybackEvent>, message: &str) {
    let _ = sink.add(DbPlaybackEvent {
        line: None,
        error: Some(message.to_string()),
    });
}

/// FRB mirror of [`lfs_core::recorder::index_sidecar::SeekHit`].
/// Carries everything the playback adapter needs to resume from a
/// scrub target: the byte offset in the main file, the sidecar entry
/// index (= AAD counter for the next encrypted frame), and the
/// matched event's timestamp (so the UI can snap the scrub thumb to
/// the actual frame boundary instead of the requested target).
#[derive(Debug, Clone)]
pub struct DbSeekHit {
    pub offset: u64,
    pub entry_index: u64,
    pub timestamp_ms: u32,
}

impl From<lfs_core::recorder::index_sidecar::SeekHit> for DbSeekHit {
    fn from(h: lfs_core::recorder::index_sidecar::SeekHit) -> Self {
        Self {
            offset: h.offset,
            entry_index: h.entry_index,
            timestamp_ms: h.timestamp_ms,
        }
    }
}

/// Resolve `<recording>.idx` next to `recording_path`, binary-search
/// for the first entry whose timestamp is at or before `target_ms`,
/// and return the matched entry's byte offset + entry index. Returns
/// `None` when no sidecar exists, the sidecar is empty, or
/// `target_ms` lands before the first event — caller falls back to
/// sequential decode in any of those branches.
///
/// `encrypted` mirrors the main file: encrypted recordings carry an
/// encrypted sidecar keyed off `HKDF-SHA256(recorder_key,
/// info = "letsflutssh-recording-idx-v1")`. The chain re-derives the
/// recorder key first (info = `letsflutssh-recording-v1`), then the
/// index key off the recorder key — same two-step HKDF the writer
/// runs, so a leak of one key does not compromise the other.
///
/// Plaintext recordings (`.cast`) pass `encrypted = false` and the
/// sidecar is read without a key. The active-DB-key probe is skipped
/// entirely so plaintext-tier sessions can seek without depending on
/// the secrets-store actor.
pub async fn recorder_seek(
    recording_path: String,
    target_ms: u64,
    encrypted: bool,
) -> Result<Option<DbSeekHit>, String> {
    tokio::task::spawn_blocking(move || {
        let path = std::path::PathBuf::from(&recording_path);
        if !encrypted {
            return lfs_core::recorder::index_sidecar::seek(&path, target_ms, false, None)
                .map(|opt| opt.map(DbSeekHit::from))
                .map_err(|e| crate::api::frb_err::from_core(&e));
        }
        let app = lfs_core::app::instance();
        let Some(db_key) = app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID) else {
            // No active DB key — sidecar is unreadable, fall back to
            // sequential decode.
            return Ok(None);
        };
        if db_key.is_empty() {
            return Ok(None);
        }
        let db_arr: [u8; 32] = db_key
            .as_slice()
            .try_into()
            .map_err(|_| frb_err::wire(frb_err::kind::CRYPTO, "active db key wrong length"))?;
        // Read the v1 header off the main file and unwrap the
        // per-file recording key under the DB key. The sidecar key
        // is HKDF-derived off that recording key (same chain the
        // recorder uses to write the sidecar), so the seek path
        // looks at the same wrapped material the playback path
        // uses — one source of truth for the per-file key.
        let mut head = [0u8; lfs_core::recorder::LFR_HEADER_LEN];
        match std::fs::File::open(&path) {
            Ok(mut f) => {
                use std::io::Read as _;
                if f.read_exact(&mut head).is_err() {
                    return Ok(None);
                }
            }
            Err(_) => return Ok(None),
        }
        let recording_key = match lfs_core::recorder::unwrap_lfsr_header(&head, &db_arr) {
            Ok(rk) => rk,
            Err(_) => {
                // Wrap mismatch / damaged header — treat as
                // "no sidecar reachable", fall back to sequential
                // decode. Playback path will surface the same
                // crypto error if/when the user retries open.
                return Ok(None);
            }
        };
        let index_key = lfs_core::crypto::hkdf_sha256(
            &recording_key[..],
            &[],
            lfs_core::recorder::index_sidecar::INDEX_HKDF_INFO,
            32,
        )
        .map_err(|e| frb_err::wire(frb_err::kind::RECORDER, &format!("recorder idx hkdf: {e}")))?;
        let index_arr: [u8; 32] = index_key
            .as_slice()
            .try_into()
            .map_err(|_| frb_err::wire(frb_err::kind::RECORDER, "recorder index key wrong size"))?;
        lfs_core::recorder::index_sidecar::seek(&path, target_ms, true, Some(&index_arr))
            .map(|opt| opt.map(DbSeekHit::from))
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("recorder seek task: {e}")))?
}

/// SecretRef variant of [`recorder_register`]. Reads the running
/// session's DB key from
/// [`lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID`] and registers the
/// recorder with that DB key as the wrap key. The recorder's
/// `register_with_io` then mints a fresh random per-file recording
/// key, wraps it under the DB key in the v1 LFR1 header, and uses
/// the recording key for every frame's GCM tag + the sidecar HKDF
/// chain. When the active slot is empty (plaintext tier) the
/// recorder registers in plaintext-asciinema mode.
///
/// `base_path` is the recording path **without an extension**. This
/// function appends `.lfsr` when the recorder ends up encrypted or
/// `.cast` when plaintext — having Rust own the extension keeps
/// the on-disk file shape in lock-step with the actual wire format
/// (the playback dispatcher routes off the extension). The earlier
/// shape, where Dart picked the extension off `secrets_has`,
/// diverged on the plaintext tier (slot present but empty bytes →
/// `secrets_has = true`, encrypted decision `false`) and produced
/// `.lfsr`-named files with asciinema-plaintext content the reader
/// could never decrypt. The returned snapshot's `path` field
/// carries the final on-disk path so the caller threads it through
/// to `recorder_queue_spawn` and the eventual `.lfsr` / `.cast`
/// listing surface.
///
/// Bytes never cross the FRB boundary on this path — both the DB
/// key and the random per-file recording key live in Rust memory
/// only.
pub async fn recorder_register_from_active(
    id: String,
    session_id: String,
    base_path: String,
) -> Result<DbRecorderSnapshot, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let key_arr = match app.secrets.get(lfs_core::secrets::ACTIVE_DBKEY_SECRET_ID) {
            Some(db_key) if !db_key.is_empty() => {
                let arr: [u8; 32] = db_key.as_slice().try_into().map_err(|_| {
                    frb_err::wire(frb_err::kind::CRYPTO, "active db key wrong length")
                })?;
                Some(zeroize::Zeroizing::new(arr))
            }
            _ => None,
        };
        let ext = if key_arr.is_some() { "lfsr" } else { "cast" };
        let final_path = format!("{base_path}.{ext}");
        lfs_core::recorder::RecorderRegistry::register_with_io(
            &app.recorders,
            id,
            session_id,
            final_path,
            key_arr,
            &app.bus,
        )
        .map(DbRecorderSnapshot::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder register from active task: {e}"),
        )
    })?
}

/// Walk the recordings tree under `recordings_root` and rename any
/// `.lfsr` file whose first bytes do not match the encrypted-frame
/// magic to `.cast`. This unsticks recordings made before the
/// extension-decision moved Rust-side: the earlier Dart-side check
/// of `secrets_has(ACTIVE_DBKEY_SECRET_ID)` returned `true` on the
/// plaintext tier (slot present but empty bytes), so the file
/// landed with a `.lfsr` extension even though the writer
/// registered plaintext-asciinema mode and skipped the
/// [`recorder::LFR_MAGIC`] header. Playback then routed by
/// extension into the encrypted reader and failed with "no active
/// DB key — encrypted recording cannot be opened".
///
/// Idempotent: a fresh-write `.lfsr` file (correct encrypted
/// magic) is left alone; a re-run after a previous rename is a
/// no-op because there are no misnamed files left to fix.
///
/// Returns the number of files renamed. Errors are logged and the
/// walk continues — one stuck entry shouldn't block the rest from
/// migrating.
pub async fn recorder_migrate_misnamed_files(recordings_root: String) -> Result<u32, String> {
    tokio::task::spawn_blocking(move || migrate_misnamed_in_tree(&recordings_root))
        .await
        .map_err(|e| {
            frb_err::wire(
                frb_err::kind::GENERIC,
                &format!("recorder migrate task: {e}"),
            )
        })
}

/// Walk [`recordings_root`] depth-first, migrating each misnamed file
/// and returning the rename count. Best-effort throughout: a stuck
/// subdirectory or entry is skipped (it's logged upstream when the
/// recordings list / playback step hits it) so one snag doesn't block
/// the rest of the tree.
fn migrate_misnamed_in_tree(recordings_root: &str) -> u32 {
    let root = std::path::PathBuf::from(recordings_root);
    if !root.is_dir() {
        return 0;
    }
    let mut renamed = 0u32;
    let mut stack = vec![root];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(ty) = entry.file_type() else {
                continue;
            };
            if ty.is_dir() {
                stack.push(path);
                continue;
            }
            renamed += migrate_recording_file(&path);
        }
    }
    renamed
}

/// Migrate a single file, returning 1 when a rename happened. Routes
/// orphan `.lfsr.idx` sidecars and misnamed `.lfsr` main files; every
/// other file is left untouched.
fn migrate_recording_file(path: &std::path::Path) -> u32 {
    let Some(file_name) = path.file_name().and_then(|s| s.to_str()) else {
        return 0;
    };
    if file_name.ends_with(".lfsr.idx") {
        return migrate_orphan_idx(path, file_name);
    }
    let is_lfsr = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.eq_ignore_ascii_case("lfsr"))
        .unwrap_or(false);
    // A fresh-write `.lfsr` file (correct encrypted magic) is left
    // alone; only an `.lfsr` that lacks the LFR magic is a plaintext
    // recording misnamed by the registration-race bug.
    if !is_lfsr || file_starts_with_lfr_magic(path) {
        return 0;
    }
    migrate_lfsr_main(path)
}

/// Orphan `.lfsr.idx` sidecar — its `.lfsr` parent was already moved
/// to `.cast` by an earlier sweep (only the main file moved before
/// this fix landed), so the playback dialog's scrub probe hits
/// `<basename>.cast.idx` (absent) and disables the slider. Rename the
/// orphan in place so the probe finds the index and re-enables
/// seeking. No-op when no migrated `.cast` parent exists.
fn migrate_orphan_idx(path: &std::path::Path, file_name: &str) -> u32 {
    let base = file_name.trim_end_matches(".lfsr.idx").to_owned();
    let cast_main = path.with_file_name(format!("{base}.cast"));
    if !cast_main.exists() {
        return 0;
    }
    let new_idx = cast_main.with_file_name(format!("{base}.cast.idx"));
    u32::from(std::fs::rename(path, &new_idx).is_ok())
}

/// Rename a misnamed plaintext `.lfsr` main file to `.cast`, carrying
/// its `.idx` sidecar alongside. The sidecar lives at
/// `<filename>.idx` (`lfs_core::recorder::index_sidecar::sidecar_path`
/// appends `.idx` to the full filename), so a misnamed `foo.lfsr`
/// ships its index as `foo.lfsr.idx`; without moving it too, the seek
/// lookup for the new `foo.cast` would hit the absent `foo.cast.idx`
/// and disable the scrub bar even though a valid plaintext index sits
/// right next to it. Best-effort: a stuck rename retries on the next
/// sweep; a missing sidecar (older recording with no index) skips.
fn migrate_lfsr_main(path: &std::path::Path) -> u32 {
    let renamed_path = path.with_extension("cast");
    if std::fs::rename(path, &renamed_path).is_err() {
        return 0;
    }
    let old_idx = append_idx_suffix(path);
    if old_idx.exists() {
        let _ = std::fs::rename(&old_idx, append_idx_suffix(&renamed_path));
    }
    1
}

/// Append a `.idx` suffix to the full filename (not replacing the
/// extension) — matches `index_sidecar::sidecar_path`.
fn append_idx_suffix(path: &std::path::Path) -> std::path::PathBuf {
    let mut s = path.to_path_buf().into_os_string();
    s.push(".idx");
    std::path::PathBuf::from(s)
}

/// Read the first 4 bytes of [`path`] and compare against the
/// recorder's encrypted-frame magic. Files shorter than 4 bytes
/// or any I/O error return `false` so the migration treats them
/// as candidates for the `.cast` rename (worst case: a broken
/// file ends up with the `.cast` extension but the playback
/// dispatcher already tolerates malformed plaintext recordings).
fn file_starts_with_lfr_magic(path: &std::path::Path) -> bool {
    use std::io::Read as _;
    let mut buf = [0u8; 4];
    let mut file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(_) => return false,
    };
    if file.read_exact(&mut buf).is_err() {
        return false;
    }
    buf == lfs_core::recorder::lfr_magic()
}

/// FRB mirror of [`lfs_core::recorder::reader::DecodedEvent`]:
/// asciinema-v2 `[timestamp, direction, data]` triple. The
/// playback dialog dispatches one of these per emitted record;
/// the wire shape is a flat struct so the Dart side gets the
/// three fields directly without an intermediate `List<dynamic>`.
#[derive(Debug, Clone)]
pub struct DbRecordingEvent {
    pub timestamp: f64,
    pub direction: String,
    pub data: String,
}

/// Parse one JSON-Lines record from a recording. Returns
/// `Some(event)` for a 3-tuple event row, `None` for the header
/// line (object, not array), malformed JSON, or any other shape
/// the caller should silently skip.
///
/// Sync because the playback dialog calls this once per frame
/// while ticking through the recording's emitted records — an
/// async hop would force a per-frame `Future.await` on the
/// rendering path. The wire shape is stable (asciinema v2) and
/// the cost is dominated by the JSON parse, which the standard
/// `serde_json` path runs in microseconds.
#[flutter_rust_bridge::frb(sync)]
pub fn recorder_decode_event_line(line: String) -> Option<DbRecordingEvent> {
    lfs_core::recorder::reader::decode_event_line(&line).map(|e| DbRecordingEvent {
        timestamp: e.timestamp,
        direction: e.direction,
        data: e.data,
    })
}

/// FRB mirror of [`lfs_core::recorder::reader::DecodedHeader`]:
/// asciinema-v2 header carrying width/height (so playback can
/// resize the terminal to match), the wall-clock origin timestamp, and
/// the optional `$SHELL` label captured at start time.
#[derive(Debug, Clone)]
pub struct DbRecordingHeader {
    pub width: u32,
    pub height: u32,
    pub wall_clock_epoch_seconds: i64,
    pub shell_label: Option<String>,
}

/// Parse one JSON-Lines record as an asciinema-v2 header. Returns
/// `Some(header)` when the line is the header object (first
/// JSON-Lines record of every cast), `None` for an event tuple or
/// any malformed shape. Missing per-field values fall back to the
/// asciinema defaults (80×24, epoch=0, no shell label).
///
/// Sync — same rationale as [`recorder_decode_event_line`]: the
/// playback dialog hits this once per stream open (or once per
/// browser-list row during the read-meta walk) and async overhead
/// on a serde parse would dwarf the work itself.
#[flutter_rust_bridge::frb(sync)]
pub fn recorder_decode_header_line(line: String) -> Option<DbRecordingHeader> {
    lfs_core::recorder::reader::decode_header_line(&line).map(|h| DbRecordingHeader {
        width: h.width,
        height: h.height,
        wall_clock_epoch_seconds: h.wall_clock_epoch_seconds,
        shell_label: h.shell_label,
    })
}

/// Tagged-union mirror of one decoded JSON-Lines record. Routes the
/// asciinema v2 dispatch (header object vs event tuple) Rust-side so
/// the Dart playback loop never re-runs `jsonDecode` to peek the
/// shape. A non-conforming line lands on the `other` variant and
/// the Dart consumer drops the record.
#[derive(Debug, Clone)]
pub enum DbRecordingLine {
    Header(DbRecordingHeader),
    Event(DbRecordingEvent),
    Other,
}

/// Decode one JSON-Lines record into either the header struct, the
/// event tuple, or `Other` for any malformed / non-conforming shape.
/// Combines the two leaf decoders so the playback dialog (and the
/// `readMeta` walk) hand one line in and pattern-match on the
/// returned enum instead of running its own JSON triage.
///
/// Sync for the same reason the underlying leaf decoders are sync:
/// per-frame cost on a microsecond serde parse.
#[flutter_rust_bridge::frb(sync)]
pub fn recorder_decode_line(line: String) -> DbRecordingLine {
    if let Some(h) = lfs_core::recorder::reader::decode_header_line(&line) {
        return DbRecordingLine::Header(DbRecordingHeader {
            width: h.width,
            height: h.height,
            wall_clock_epoch_seconds: h.wall_clock_epoch_seconds,
            shell_label: h.shell_label,
        });
    }
    if let Some(e) = lfs_core::recorder::reader::decode_event_line(&line) {
        return DbRecordingLine::Event(DbRecordingEvent {
            timestamp: e.timestamp,
            direction: e.direction,
            data: e.data,
        });
    }
    DbRecordingLine::Other
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
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder header task: {e}"),
        )
    })?
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
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("recorder event task: {e}")))?
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
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder rotate task: {e}"),
        )
    })?
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
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("recorder close task: {e}")))?
}

// =====================================================================
// Per-id write queue surface
// =====================================================================
//
// The Dart shim does not call `recorder_record_*` directly — the
// per-id worker inside `lfs_core::recorder::queue` drains a
// dedicated mpsc and serialises calls into the registry so the
// asciinema event stream lands on disk in arrival order even when
// concurrent FRB calls overlap on the runtime. Spawn the worker once
// after `recorder_register`; use the enqueue endpoints below for the
// recording's lifetime; close drains + drops the worker.

/// Spawn the per-id write worker. Pair with an existing
/// [`recorder_register`] so the actor row exists. Idempotent on a
/// re-spawn for the same id — the displaced worker exits cleanly on
/// its next mailbox `recv`.
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
// The walk + stat + delete for `<appSupport>/recordings/` live
// Rust-side under `lfs_core::recorder::browser` so the
// `Rust owns data` invariant holds for the whole recordings
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

/// Canonical `<support_dir>/recordings` path. Rust resolves the
/// pinned support directory and joins `recordings/` once so every
/// Dart caller (recordings browser, settings storage tile) reads
/// the same canonical root through one FRB sync hop instead of
/// re-running `path_provider.getApplicationSupportDirectory() +
/// path.join('recordings')` per surface. `Err` only when no pin
/// has been set yet — the cold-start ordering invariant ensures
/// `config_store_init` lands before any UI surface that needs the
/// root.
#[flutter_rust_bridge::frb(sync)]
pub fn recorder_recordings_root() -> Result<String, String> {
    let dir = lfs_core::app::instance()
        .support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(dir.join("recordings").to_string_lossy().into_owned())
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
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("recorder list task: {e}")))?
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
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder delete task: {e}"),
        )
    })?
}

// =====================================================================
// Storage-cap surface
// =====================================================================
//
// LRU eviction sweep that bounds the recordings tree against
// `AppConfig.recordings_storage_cap_bytes`. The lifecycle hooks in
// `lfs_core::recorder::RecorderRegistry::{register_with_io,
// close_with_io}` invoke `enforce_storage_cap` automatically on
// every register / close; the entry points below let the future
// Settings UI surface the running total, push a new cap, and
// trigger a manual "delete all" without waiting on a register /
// close pair.

/// FRB mirror of [`lfs_core::recorder::storage_cap::EvictionOutcome`].
/// Carries the counts the Settings UI tile renders after a
/// user-driven cap change.
#[derive(Debug, Clone)]
pub struct DbEvictionOutcome {
    pub files_evicted: u32,
    pub bytes_reclaimed: u64,
    pub used_after: u64,
}

impl From<lfs_core::recorder::storage_cap::EvictionOutcome> for DbEvictionOutcome {
    fn from(o: lfs_core::recorder::storage_cap::EvictionOutcome) -> Self {
        Self {
            files_evicted: o.files_evicted,
            bytes_reclaimed: o.bytes_reclaimed,
            used_after: o.used_after,
        }
    }
}

/// Bytes currently used under `<recordings_root>`. Walks every
/// session sub-directory and sums regular-file byte sizes. Cheap
/// enough on the typical hundreds-of-files tree but the walk runs
/// inside `spawn_blocking` because a large library on a slow
/// filesystem (network mount, spinning disk) can take real time.
pub async fn recorder_storage_used(recordings_root: String) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || {
        let root = std::path::PathBuf::from(recordings_root);
        lfs_core::recorder::storage_cap::storage_used(&root)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder storage used task: {e}"),
        )
    })?
}

/// Update the persisted `recordings_storage_cap_bytes` field on
/// the `config_store` actor and run an immediate eviction sweep
/// against the new cap. Returns the [`DbEvictionOutcome`] so the
/// caller can surface "freed N MB" feedback after a user lowers
/// the cap.
///
/// The config_store actor debounces the write to disk on its own
/// schedule; the in-memory state flips synchronously so a
/// follow-up `register_with_io` already sees the new cap.
pub async fn recorder_set_storage_cap(
    recordings_root: String,
    bytes: u64,
) -> Result<DbEvictionOutcome, String> {
    tokio::task::spawn_blocking(move || {
        // Pull the current canonical JSON, splice the new cap,
        // push it back. The store actor's `set_json` re-parses
        // through `AppConfig::from_json_value` which runs
        // `sanitized()` so a zero / absurd value lands on the
        // canonical default rather than the raw input. The sweep
        // below reads the post-sanitisation cap through the same
        // accessor the recorder hooks use.
        let store = lfs_core::config_store::instance();
        let current_json = store
            .get_json()
            .ok_or_else(|| frb_err::wire(frb_err::kind::GENERIC, "config_store not initialised"))?;
        let mut value: serde_json::Value = serde_json::from_str(&current_json).map_err(|e| {
            frb_err::wire(
                frb_err::kind::GENERIC,
                &format!("config_store snapshot parse: {e}"),
            )
        })?;
        let obj = value.as_object_mut().ok_or_else(|| {
            frb_err::wire(
                frb_err::kind::GENERIC,
                "config_store snapshot not a JSON object",
            )
        })?;
        obj.insert("recordings_storage_cap_bytes".into(), bytes.into());
        let new_json = serde_json::to_string(&value).map_err(|e| {
            frb_err::wire(
                frb_err::kind::GENERIC,
                &format!("config_store serialise: {e}"),
            )
        })?;
        store.set_json(&new_json)?;

        let root = std::path::PathBuf::from(recordings_root);
        let app = lfs_core::app::instance();
        let active = app.recorders.active_paths();
        let cap = read_cap_from_store();
        let outcome = lfs_core::recorder::storage_cap::enforce_storage_cap(&root, cap, &active)
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        Ok::<DbEvictionOutcome, String>(outcome.into())
    })
    .await
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder set cap task: {e}"),
        )
    })?
}

/// Delete every recording the user has on disk under
/// `recordings_root`. The currently-writing files (registered IO
/// actors) are skipped — closing a recording mid-clear would
/// strand the live file handle. Returns the count of files
/// actually removed.
pub async fn recorder_clear_all_recordings(recordings_root: String) -> Result<u32, String> {
    tokio::task::spawn_blocking(move || {
        let root = std::path::PathBuf::from(recordings_root);
        let app = lfs_core::app::instance();
        let active = app.recorders.active_paths();
        lfs_core::recorder::storage_cap::clear_all(&root, &active)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("recorder clear all task: {e}"),
        )
    })?
}

/// Pull the current cap value out of the config_store snapshot.
/// Falls back to
/// [`lfs_core::config::DEFAULT_RECORDINGS_STORAGE_CAP_BYTES`] when
/// the actor is unavailable or the snapshot lacks the field —
/// mirrors the same defensive read the recorder lifecycle hooks
/// run against, so the cap an FRB caller observes lines up with
/// the cap the in-process eviction sweep enforces.
fn read_cap_from_store() -> u64 {
    let default = lfs_core::config::DEFAULT_RECORDINGS_STORAGE_CAP_BYTES;
    let Some(json) = lfs_core::config_store::instance().get_json() else {
        return default;
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&json) else {
        return default;
    };
    value
        .as_object()
        .and_then(|o| o.get("recordings_storage_cap_bytes"))
        .and_then(|v| v.as_u64())
        .unwrap_or(default)
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

    #[test]
    fn seek_hit_carries_every_field() {
        let core = lfs_core::recorder::index_sidecar::SeekHit {
            offset: 4096,
            entry_index: 7,
            timestamp_ms: 12_345,
        };
        let db: DbSeekHit = core.into();
        assert_eq!(db.offset, 4096);
        assert_eq!(db.entry_index, 7);
        assert_eq!(db.timestamp_ms, 12_345);
    }

    #[test]
    fn migrate_renames_paired_sidecar_alongside_misnamed_main_file() {
        // Set up `<tmp>/sess/rec.lfsr` (plaintext content, missing
        // the encrypted-frame magic) + a matching plaintext
        // sidecar `rec.lfsr.idx`. The migration should rename both
        // so the scrub-bar probe (which looks for `rec.cast.idx`
        // next to the `.cast` recording) finds the index after
        // the sweep.
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let root = std::env::temp_dir().join(format!("lfs_mig_test_{pid}_{n}"));
        let session_dir = root.join("sess-1");
        std::fs::create_dir_all(&session_dir).unwrap();
        let main_path = session_dir.join("rec.lfsr");
        let idx_path = session_dir.join("rec.lfsr.idx");
        // Plaintext recording body — first bytes are an asciinema
        // header line, not the encrypted-frame magic, so the
        // migration treats it as a misnamed plaintext file.
        std::fs::write(&main_path, b"{\"version\":2,\"width\":80,\"height\":24}\n").unwrap();
        std::fs::write(&idx_path, b"\x00\x01\x02\x03").unwrap();

        let renamed = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(recorder_migrate_misnamed_files(
                root.to_string_lossy().into_owned(),
            ))
            .unwrap();
        assert_eq!(renamed, 1);

        let new_main = session_dir.join("rec.cast");
        let new_idx = session_dir.join("rec.cast.idx");
        assert!(new_main.exists(), "main file should be renamed to .cast");
        assert!(new_idx.exists(), "sidecar should be renamed alongside");
        assert!(!main_path.exists(), "old .lfsr file should be gone");
        assert!(!idx_path.exists(), "old .lfsr.idx sidecar should be gone");

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn migrate_renames_orphan_lfsr_sidecar_when_main_already_cast() {
        // After the original migration shipped, plaintext
        // recordings got `.lfsr → .cast` for the main file but
        // left `.lfsr.idx` behind. Re-running the sweep against
        // that state should rename the orphan in place so the
        // scrub probe finds `<basename>.cast.idx`.
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let root = std::env::temp_dir().join(format!("lfs_mig_orphan_{pid}_{n}"));
        let session_dir = root.join("sess-1");
        std::fs::create_dir_all(&session_dir).unwrap();
        let cast_main = session_dir.join("rec.cast");
        let orphan_idx = session_dir.join("rec.lfsr.idx");
        std::fs::write(&cast_main, b"{\"version\":2}\n").unwrap();
        std::fs::write(&orphan_idx, b"\x00\x01\x02\x03").unwrap();

        let renamed = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(recorder_migrate_misnamed_files(
                root.to_string_lossy().into_owned(),
            ))
            .unwrap();
        assert_eq!(renamed, 1);

        let new_idx = session_dir.join("rec.cast.idx");
        assert!(
            new_idx.exists(),
            "orphan sidecar should be renamed to .cast.idx"
        );
        assert!(!orphan_idx.exists(), "orphan .lfsr.idx should be gone");
        assert!(cast_main.exists(), "main .cast file must stay untouched");

        std::fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn eviction_outcome_carries_every_field() {
        let core = lfs_core::recorder::storage_cap::EvictionOutcome {
            files_evicted: 3,
            bytes_reclaimed: 4096,
            used_after: 16_384,
        };
        let db: DbEvictionOutcome = core.into();
        assert_eq!(db.files_evicted, 3);
        assert_eq!(db.bytes_reclaimed, 4096);
        assert_eq!(db.used_after, 16_384);
    }
}
