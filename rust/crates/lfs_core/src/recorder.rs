//! Session recorder.
//!
//! Owns the canonical state + file IO for active recordings.
//! Per-frame AES-GCM crypto runs Rust-side
//! (`crypto::aes_gcm_encrypt_raw`); this module brings the file
//! handle + byte counter alongside so a recording's state lives
//! in one place rather than half on each side of the FRB
//! boundary.
//!
//! [`queue`] adds the per-recording write queue: each id gets a
//! dedicated tokio worker that drains an mpsc channel of
//! `QueueEntry` items in arrival order. The Dart shim is then a
//! fire-and-forget enqueue layer — the asciinema event stream
//! lands on disk in the same order the user typed / saw it even
//! when concurrent FRB calls overlap on the runtime.
//!
//! # Surfaces
//!
//! - [`RecorderRegistry::register`] — counter-only; the caller
//!   (Dart `SessionRecorder` legacy path) owns file IO.
//! - [`RecorderRegistry::register_with_io`] — registry owns the
//!   file handle + encryption key. Pair with
//!   [`RecorderRegistry::record_frame`] /
//!   [`RecorderRegistry::close_with_io`] so the consumer never
//!   sees plaintext after the registry takes over.
//!
//! # Frame format (encrypted mode)
//!
//! Each frame is `[len(4 LE)][nonce(12)][ciphertext + tag]` —
//! mirrors the existing Dart-era format so files written by
//! either driver are interoperable. The leading file marker is
//! `LFR1` + version byte `0x01`.

pub mod queue;

use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::{Arc, Mutex};

use rand::RngCore;

use crate::bus::{Event, EventBus};
use crate::error::Error;

/// File-format magic — `LFR1` (LetsFLUTssh Recorder). Pinned so
/// every reader (Rust playback path + on-disk integrity probe)
/// branches consistently on the first four bytes.
const LFR_MAGIC: [u8; 4] = [0x4C, 0x46, 0x52, 0x31];
/// On-disk format version byte (post-magic).
///
/// * `0x01` (legacy): per-frame AES-GCM with empty AAD. An attacker
///   with file-write access could swap two frames within the same
///   recording — the GCM tag matches because nothing binds frame
///   position. The Dart reader still decodes pre-upgrade files
///   through this branch, but the Rust writer never emits it.
/// * `0x02` (current): per-frame AAD = `frame_index_u64_le`. Writer
///   tracks a monotonic counter per recording (reset on
///   `rotate_to`), reader recomputes it from the position in the
///   stream — the index never lands on disk, so the counter cannot
///   be tampered without invalidating subsequent tags.
const LFR_VERSION: u8 = 2;
const NONCE_LEN: usize = 12;

/// Hard upper bound on a single recording file size before the
/// driver rolls to a new file under the same session. 100 MB is
/// large enough for a multi-hour vim-heavy editing session, small
/// enough that the asciinema export of a single recording stays
/// trivially shareable. Reads from the FRB binding (`recorder_max_file_bytes`)
/// so the Dart caller never holds a stale duplicate of the constant.
pub const MAX_FILE_BYTES: u64 = 100 * 1024 * 1024;

/// Stable identifier for an active recording. The Dart side
/// allocates this off `Uuid().v4()` so the same string flows
/// through Riverpod ownership before the Rust side has finished
/// opening the underlying file.
pub type RecorderId = String;

/// What kind of frame the recorder is writing — terminal output
/// (stdout / stderr) or terminal input (user keystrokes).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordDirection {
    Output,
    Input,
}

/// Per-recording metadata — what the FRB layer hands over to a
/// late subscriber as the initial state.
#[derive(Debug, Clone)]
pub struct RecorderSnapshot {
    pub id: RecorderId,
    pub session_id: String,
    pub path: String,
    pub bytes_written: u64,
    pub encrypted: bool,
}

pub struct RecorderActor {
    pub id: RecorderId,
    pub session_id: String,
    pub path: String,
    pub bytes_written: u64,
    pub encrypted: bool,
    /// Wall-clock timestamp captured at register time, used as the
    /// `t = 0` anchor for asciinema event deltas. `None` for
    /// counter-only actors that don't compose events here.
    started_at: Option<std::time::SystemTime>,
    /// Owned file handle when the registry drives IO. `None` for
    /// counter-only actors registered via [`RecorderRegistry::register`].
    /// Wrapped in `Arc<Mutex>` so frame writes can drop the
    /// registry mutex first and contend only on this handle.
    file: Option<Arc<Mutex<std::fs::File>>>,
    /// 32-byte AES-256 key in encrypted mode. Derived caller-side
    /// (HKDF off the DB key) and handed in once at register time.
    /// Wrapped in `Zeroizing` so the bytes wipe on `RecorderActor`
    /// drop instead of lingering in the registry's process memory
    /// after the recording closes.
    key: Option<zeroize::Zeroizing<[u8; 32]>>,
    /// Monotonic per-frame counter used as AES-GCM AAD on encrypted
    /// recordings (LFR v2). Reset to 0 on rotate. Never persisted
    /// on disk: the reader recomputes it from frame position so a
    /// disk-side swap of two frames invalidates the GCM tag.
    frame_index: u64,
}

impl RecorderActor {
    pub fn new(id: RecorderId, session_id: String, path: String, encrypted: bool) -> Self {
        Self {
            id,
            session_id,
            path,
            bytes_written: 0,
            encrypted,
            started_at: None,
            file: None,
            key: None,
            frame_index: 0,
        }
    }

    pub fn snapshot(&self) -> RecorderSnapshot {
        RecorderSnapshot {
            id: self.id.clone(),
            session_id: self.session_id.clone(),
            path: self.path.clone(),
            bytes_written: self.bytes_written,
            encrypted: self.encrypted,
        }
    }
}

impl std::fmt::Debug for RecorderActor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RecorderActor")
            .field("id", &self.id)
            .field("session_id", &self.session_id)
            .field("path", &self.path)
            .field("bytes_written", &self.bytes_written)
            .field("encrypted", &self.encrypted)
            .finish()
    }
}

/// Process-singleton registry. Owned by `AppState`. The full
/// frame-write driver loop lands in the next 5.4 commit; today
/// the registry only manages actor creation + removal so the
/// FRB surface stabilises ahead of the consumer port.
pub struct RecorderRegistry {
    inner: Mutex<RegistryInner>,
}

struct RegistryInner {
    by_id: HashMap<RecorderId, RecorderActor>,
}

impl RecorderRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryInner {
                by_id: HashMap::new(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Register a fresh recording actor. Emits `RecorderStarted`
    /// for any subscribed view. Idempotent on repeated id —
    /// later registers replace the row.
    pub fn register(
        &self,
        id: RecorderId,
        session_id: String,
        path: String,
        encrypted: bool,
        bus: &EventBus,
    ) -> RecorderSnapshot {
        let actor = RecorderActor::new(id.clone(), session_id, path, encrypted);
        let snap = actor.snapshot();
        {
            let mut g = self.lock();
            g.by_id.insert(id.clone(), actor);
        }
        bus.publish(Event::RecorderStarted {
            id,
            path: snap.path.clone(),
        });
        snap
    }

    /// Tear down a recording actor. Idempotent on a missing id.
    /// Emits `RecorderStopped` so subscribers can refresh their
    /// recording list.
    pub fn close(&self, id: &str, bus: &EventBus) {
        let removed = {
            let mut g = self.lock();
            g.by_id.remove(id)
        };
        if removed.is_some() {
            bus.publish(Event::RecorderStopped { id: id.to_string() });
        }
    }

    pub fn snapshot(&self, id: &str) -> Option<RecorderSnapshot> {
        self.lock().by_id.get(id).map(|a| a.snapshot())
    }

    pub fn count(&self) -> usize {
        self.lock().by_id.len()
    }

    /// Test escape hatch: panics while holding the registry's
    /// inner mutex so an integration-test thread can poison it.
    /// `#[doc(hidden)]` keeps it out of the rendered API surface;
    /// calling this at runtime is unconditionally a panic.
    #[doc(hidden)]
    pub fn force_poison_for_tests(&self) -> ! {
        let _g = self.inner.lock().unwrap();
        panic!("RecorderRegistry::force_poison_for_tests");
    }

    /// Bump the byte counter for an actor — used by the
    /// counter-only path where Dart still owns file IO. Pair
    /// with [`RecorderRegistry::register`] (no file handle on
    /// the actor).
    pub fn record_chunk(&self, id: &str, bytes: u64, bus: &EventBus) {
        let new_total = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return;
            };
            actor.bytes_written = actor.bytes_written.saturating_add(bytes);
            actor.bytes_written
        };
        bus.publish(Event::RecorderBytesWritten {
            id: id.to_string(),
            total_bytes: new_total,
        });
    }

    /// Register an IO-owned recording actor. Opens [`path`] in
    /// append mode, writes the LFR1 magic + version byte when
    /// [`key`] is `Some`, and emits `RecorderStarted`. Plaintext
    /// mode (`key = None`) writes nothing on open — the file is
    /// directly playable as asciinema once the caller pumps the
    /// header line through [`RecorderRegistry::record_frame`].
    pub fn register_with_io(
        &self,
        id: RecorderId,
        session_id: String,
        path: String,
        key: Option<zeroize::Zeroizing<[u8; 32]>>,
        bus: &EventBus,
    ) -> Result<RecorderSnapshot, Error> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .map_err(|e| Error::Recorder(format!("open {path}: {e}")))?;
        // Harden the file mode to 0600 immediately after open so a
        // crash mid-record does not leave plaintext terminal output
        // (or the encrypted envelope) at the umask-default mode —
        // typically 0644 on Linux, group/world-readable on multi-
        // user hosts. See ARCH §3.13 file-mode invariant.
        if let Err(msg) = crate::path::harden_file_perms(std::path::Path::new(&path)) {
            return Err(Error::Recorder(format!("harden {path}: {msg}")));
        }
        let encrypted = key.is_some();
        let mut bytes_written: u64 = 0;
        if encrypted {
            file.write_all(&LFR_MAGIC)
                .and_then(|_| file.write_all(&[LFR_VERSION]))
                .map_err(|e| Error::Recorder(format!("magic write: {e}")))?;
            bytes_written = (LFR_MAGIC.len() + 1) as u64;
        }
        let actor = RecorderActor {
            id: id.clone(),
            session_id,
            path: path.clone(),
            bytes_written,
            encrypted,
            started_at: Some(std::time::SystemTime::now()),
            file: Some(Arc::new(Mutex::new(file))),
            key,
            frame_index: 0,
        };
        let snap = actor.snapshot();
        {
            let mut g = self.lock();
            g.by_id.insert(id.clone(), actor);
        }
        bus.publish(Event::RecorderStarted { id, path });
        Ok(snap)
    }

    /// Compose the asciinema v2 header line (`{"version": 2, …}`)
    /// using the registered recording's `started_at` anchor and
    /// caller-supplied terminal dimensions, then append it as a
    /// frame. Body of the header lands as the first JSON-Lines
    /// entry of the file so any plaintext export — and the
    /// encrypted file once decrypted — starts as a valid
    /// asciinema document.
    pub fn record_header(
        &self,
        id: &str,
        width: u32,
        height: u32,
        shell_label: &str,
        bus: &EventBus,
    ) -> Result<u64, Error> {
        let started_at = {
            let g = self.lock();
            let actor = g
                .by_id
                .get(id)
                .ok_or_else(|| Error::Recorder(format!("{id} not registered")))?;
            actor
                .started_at
                .ok_or_else(|| Error::Recorder(format!("{id} has no started_at anchor")))?
        };
        let timestamp_secs = started_at
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        // Hand-build the JSON instead of pulling serde derive on a
        // single-call shape — the header is fixed, the values are
        // sanitised at the boundary, and a matching encoder is the
        // only path that produces byte-identical output to the
        // legacy Dart writer.
        let escaped_shell = json_escape(shell_label);
        let line = format!(
            "{{\"version\":2,\"width\":{width},\"height\":{height},\"timestamp\":{timestamp_secs},\"env\":{{\"TERM\":\"xterm-256color\",\"SHELL\":\"{escaped_shell}\"}}}}\n"
        );
        self.record_frame(id, line.as_bytes(), bus)
    }

    /// Compose an asciinema v2 event line `[delta_secs, "o"|"i",
    /// utf8_str]` for the given direction, then append it as a
    /// frame. `delta_secs` is the wall-clock delta from the
    /// recording's `started_at` anchor — same semantics the legacy
    /// Dart `_enqueueEvent` produced. Bytes that don't decode as
    /// UTF-8 are passed through with replacement characters so a
    /// stray binary chunk doesn't sink the whole event.
    pub fn record_event(
        &self,
        id: &str,
        kind: RecordDirection,
        bytes: &[u8],
        bus: &EventBus,
    ) -> Result<u64, Error> {
        if bytes.is_empty() {
            // Nothing to record — return the running total so
            // callers don't observe a state change.
            let g = self.lock();
            return Ok(g.by_id.get(id).map(|a| a.bytes_written).unwrap_or(0));
        }
        let started_at = {
            let g = self.lock();
            let actor = g
                .by_id
                .get(id)
                .ok_or_else(|| Error::Recorder(format!("{id} not registered")))?;
            actor
                .started_at
                .ok_or_else(|| Error::Recorder(format!("{id} has no started_at anchor")))?
        };
        let delta = std::time::SystemTime::now()
            .duration_since(started_at)
            .unwrap_or_default()
            .as_micros() as f64
            / 1_000_000.0;
        let kind_char = match kind {
            RecordDirection::Output => 'o',
            RecordDirection::Input => 'i',
        };
        let payload = String::from_utf8_lossy(bytes);
        let escaped = json_escape(&payload);
        // asciinema v2 spec: float seconds with whatever precision
        // the writer wants. Match the Dart writer's `delta.toString()`
        // shape (no fixed-width, no trailing zeros) so the output is
        // byte-identical for the same delta.
        let line = format!("[{},\"{kind_char}\",\"{escaped}\"]\n", format_delta(delta));
        self.record_frame(id, line.as_bytes(), bus)
    }

    /// Encrypt (when keyed) and append a frame to the recording's
    /// file. Plaintext mode writes the bytes verbatim. Returns
    /// the running byte total. Errors when the actor was not
    /// registered through [`RecorderRegistry::register_with_io`].
    pub fn record_frame(&self, id: &str, plaintext: &[u8], bus: &EventBus) -> Result<u64, Error> {
        // Snapshot the IO handle + key + claim the next frame index
        // under the registry lock, then drop the lock before doing
        // the (potentially blocking) write. Other registry operations
        // stay non-blocked while a frame writes out. Claiming the
        // index here (post-increment) keeps frame_index ordering
        // consistent with the file mutex order: the first thread
        // through this section gets index N, the next gets N+1, and
        // the file mutex serialises the writes so on-disk order
        // matches.
        let (file_handle, key, frame_index) = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return Err(Error::Recorder(format!("{id} not registered")));
            };
            let Some(file) = actor.file.as_ref() else {
                return Err(Error::Recorder(format!(
                    "recorder {id} has no file handle (counter-only registration)"
                )));
            };
            let idx = actor.frame_index;
            actor.frame_index = actor.frame_index.saturating_add(1);
            (file.clone(), actor.key.clone(), idx)
        };

        let frame = build_frame(plaintext, key.as_deref(), frame_index)?;
        {
            let mut handle = file_handle
                .lock()
                .map_err(|_| Error::Io("recorder file mutex poisoned".to_string()))?;
            handle
                .write_all(&frame)
                .map_err(|e| Error::Recorder(format!("frame write: {e}")))?;
        }

        let new_total = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                // Actor removed mid-write — not fatal; the frame
                // is on disk, return its size as the delta.
                return Ok(frame.len() as u64);
            };
            actor.bytes_written = actor.bytes_written.saturating_add(frame.len() as u64);
            actor.bytes_written
        };
        bus.publish(Event::RecorderBytesWritten {
            id: id.to_string(),
            total_bytes: new_total,
        });
        Ok(new_total)
    }

    /// Atomically close the current file for [`id`], open a fresh
    /// file at [`new_path`], write the magic + version byte when the
    /// recording is encrypted, and reset the per-actor byte counter.
    /// The actor's id stays stable so subscribers tracking the
    /// recording across rotations don't have to re-bind. Returns the
    /// new snapshot (with the new path + zero `bytes_written`).
    ///
    /// Errors when the actor was registered counter-only (no file
    /// handle) or has already been closed.
    pub fn rotate_to(
        &self,
        id: &str,
        new_path: String,
        bus: &EventBus,
    ) -> Result<RecorderSnapshot, Error> {
        // Hold the registry lock while we swap the file handle out
        // so a concurrent record_frame either finishes against the
        // old handle or sees the new handle — never half-rotated state.
        let snap = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return Err(Error::Recorder(format!("{id} not registered")));
            };
            let Some(old_file) = actor.file.take() else {
                return Err(Error::Recorder(format!(
                    "recorder {id} has no file handle (counter-only registration)"
                )));
            };
            // Best-effort flush before we drop the old file. The
            // append-mode write already calls write_all under the
            // mutex, so a missed flush is a logging concern — the
            // OS still flushes on drop.
            if let Ok(mut handle) = old_file.lock() {
                let _ = handle.flush();
            }
            drop(old_file);

            let mut file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&new_path)
                .map_err(|e| Error::Recorder(format!("rotate open {new_path}: {e}")))?;
            // Same chmod 0600 harden the initial-register path
            // applies — every rotation creates a fresh file at
            // umask-default mode otherwise.
            if let Err(msg) = crate::path::harden_file_perms(std::path::Path::new(&new_path)) {
                return Err(Error::Recorder(format!(
                    "recorder rotate harden {new_path}: {msg}"
                )));
            }
            let mut bytes_written: u64 = 0;
            if actor.encrypted {
                file.write_all(&LFR_MAGIC)
                    .and_then(|_| file.write_all(&[LFR_VERSION]))
                    .map_err(|e| Error::Recorder(format!("rotate magic: {e}")))?;
                bytes_written = (LFR_MAGIC.len() + 1) as u64;
            }
            actor.file = Some(Arc::new(Mutex::new(file)));
            actor.path = new_path.clone();
            actor.bytes_written = bytes_written;
            // Reset the per-frame AAD counter — every rotated file
            // starts a fresh GCM tag chain so a frame from the old
            // file cannot be replayed at the same position in the
            // new file.
            actor.frame_index = 0;
            actor.snapshot()
        };
        bus.publish(Event::RecorderStarted {
            id: id.to_string(),
            path: new_path,
        });
        Ok(snap)
    }

    /// Flush + close an IO-owned recording. Mirrors
    /// [`RecorderRegistry::close`] but ensures the file handle
    /// flushes pending writes before drop. Idempotent on a
    /// missing id.
    pub fn close_with_io(&self, id: &str, bus: &EventBus) -> Result<(), Error> {
        let removed = {
            let mut g = self.lock();
            g.by_id.remove(id)
        };
        if let Some(actor) = removed {
            if let Some(file) = actor.file {
                let mut handle = file
                    .lock()
                    .map_err(|_| Error::Io("recorder file mutex poisoned".to_string()))?;
                handle
                    .flush()
                    .map_err(|e| Error::Recorder(format!("close flush: {e}")))?;
                // File drops with the guard; OS handle closes.
            }
            bus.publish(Event::RecorderStopped { id: id.to_string() });
        }
        Ok(())
    }
}

/// JSON-escape a string for embedding inside a `"…"` JSON
/// literal. Handles the spec-mandated escapes (control chars,
/// quote, backslash); UTF-8 passes through verbatim. Used by
/// the asciinema header + event-line composers above so callers
/// don't need to pull serde_json on a single-line shape.
fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                use std::fmt::Write as _;
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out
}

/// Format the asciinema event delta `t` as a JSON-friendly
/// number. Whole seconds emit as `"N"`, fractional seconds emit
/// as `"N.frac"` with up to six digits of precision (microsecond
/// resolution — same as the Dart writer's
/// `Duration.inMicroseconds / 1e6` produced).
fn format_delta(t: f64) -> String {
    if t == 0.0 {
        return "0".to_string();
    }
    if t.fract() == 0.0 {
        return format!("{}", t as i64);
    }
    let formatted = format!("{t:.6}");
    // Trim trailing zeros + dangling `.` so `1.500000` becomes
    // `1.5` instead of carrying the noise. `f64`'s default Display
    // produces scientific notation for sub-microsecond values
    // (`1e-7`); the asciinema spec accepts any JSON number, but
    // the Dart writer never emitted scientific shapes since its
    // delta is microsecond-quantised. Stay in the same lane.
    let trimmed = formatted.trim_end_matches('0');
    let trimmed = trimmed.trim_end_matches('.');
    trimmed.to_string()
}

/// Build the on-disk frame for `plaintext`. With `Some(key)`
/// returns `[len(4 LE)][nonce(12)][ciphertext+tag]`; with
/// `None` returns `plaintext` as-is so plaintext recordings
/// remain valid asciinema documents.
///
/// LFR v2: `frame_index` is bound into the GCM AAD as
/// `frame_index.to_le_bytes()` (8 bytes). The index is NOT written
/// to disk — both writer and reader recompute it from frame
/// position so an attacker who swaps two frames can't move the
/// AAD with them. Tag mismatch on the swapped position fires
/// instead, and the reader treats it as the recording-format
/// error it is.
fn build_frame(
    plaintext: &[u8],
    key: Option<&[u8; 32]>,
    frame_index: u64,
) -> Result<Vec<u8>, Error> {
    let Some(key) = key else {
        return Ok(plaintext.to_vec());
    };
    let mut nonce = [0u8; NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce);
    let aad = frame_index.to_le_bytes();
    let ct = crate::crypto::aes_gcm_encrypt_raw(key, &nonce, plaintext, &aad)?;
    let mut frame = Vec::with_capacity(4 + NONCE_LEN + ct.len());
    let pt_len = u32::try_from(plaintext.len())
        .map_err(|_| Error::Io("recorder plaintext exceeds u32 frame length".to_string()))?;
    frame.extend_from_slice(&pt_len.to_le_bytes());
    frame.extend_from_slice(&nonce);
    frame.extend_from_slice(&ct);
    Ok(frame)
}

impl Default for RecorderRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_and_close() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
        let reg = RecorderRegistry::new();
        let snap = reg.register("r1".into(), "s1".into(), "/tmp/r.cast".into(), false, &bus);
        assert_eq!(snap.id, "r1");
        assert_eq!(reg.count(), 1);
        // Drain the bus event sent during register.
        let _ = rx.try_recv();
        reg.close("r1", &bus);
        assert_eq!(reg.count(), 0);
    }

    #[test]
    fn record_chunk_bumps_bytes() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        reg.register("r1".into(), "s1".into(), "/tmp/r.cast".into(), false, &bus);
        reg.record_chunk("r1", 42, &bus);
        assert_eq!(reg.snapshot("r1").unwrap().bytes_written, 42);
    }

    fn tempfile_path(suffix: &str) -> String {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir();
        dir.join(format!("lfs_recorder_test_{pid}_{n}_{suffix}"))
            .to_string_lossy()
            .into_owned()
    }

    #[test]
    fn register_with_io_writes_magic_when_encrypted() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("enc");
        let key = [42u8; 32];
        let snap = reg
            .register_with_io(
                "r1".into(),
                "s1".into(),
                path.clone(),
                Some(zeroize::Zeroizing::new(key)),
                &bus,
            )
            .expect("register");
        assert!(snap.encrypted);
        let on_disk = std::fs::read(&path).expect("read");
        assert_eq!(&on_disk[..4], b"LFR1");
        assert_eq!(on_disk[4], LFR_VERSION);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn register_with_io_plaintext_writes_no_magic() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("plain");
        let snap = reg
            .register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .expect("register");
        assert!(!snap.encrypted);
        let on_disk = std::fs::read(&path).expect("read");
        assert!(on_disk.is_empty());
        let _ = std::fs::remove_file(&path);
    }

    /// Regression: the recorder used to open files at the
    /// umask-default mode (0644 on most Linux
    /// installs), leaving plaintext terminal output (or its
    /// envelope) group/world-readable on multi-user hosts. ARCH
    /// §3.13 requires `chmod 0600` on every recording — the open
    /// path now hardens immediately after creating the file.
    #[cfg(unix)]
    #[test]
    fn register_with_io_hardens_file_to_owner_only_perms() {
        use std::os::unix::fs::PermissionsExt;
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("perm");
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .expect("register");
        let perms = std::fs::metadata(&path).expect("stat").permissions();
        assert_eq!(
            perms.mode() & 0o777,
            0o600,
            "recorder file mode must be 0600, got {:o}",
            perms.mode() & 0o777,
        );
        let _ = std::fs::remove_file(&path);
    }

    /// Same chmod 0600 invariant for the rotated-file path. A
    /// rotation creates a new file at umask-default mode otherwise.
    #[cfg(unix)]
    #[test]
    fn rotate_to_hardens_file_to_owner_only_perms() {
        use std::os::unix::fs::PermissionsExt;
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let initial = tempfile_path("rotpre");
        let rotated = tempfile_path("rotpost");
        reg.register_with_io("r1".into(), "s1".into(), initial.clone(), None, &bus)
            .expect("register");
        reg.rotate_to("r1", rotated.clone(), &bus).expect("rotate");
        let perms = std::fs::metadata(&rotated).expect("stat").permissions();
        assert_eq!(
            perms.mode() & 0o777,
            0o600,
            "rotated recorder file mode must be 0600, got {:o}",
            perms.mode() & 0o777,
        );
        let _ = std::fs::remove_file(&initial);
        let _ = std::fs::remove_file(&rotated);
    }

    #[test]
    fn record_frame_plaintext_appends_verbatim() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("plainwrite");
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .expect("register");
        reg.record_frame("r1", b"hello\n", &bus).expect("frame");
        reg.record_frame("r1", b"world\n", &bus).expect("frame");
        reg.close_with_io("r1", &bus).expect("close");
        let on_disk = std::fs::read(&path).expect("read");
        assert_eq!(on_disk, b"hello\nworld\n");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn record_frame_encrypted_round_trips() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("encwrite");
        let key = [7u8; 32];
        reg.register_with_io(
            "r1".into(),
            "s1".into(),
            path.clone(),
            Some(zeroize::Zeroizing::new(key)),
            &bus,
        )
        .expect("register");
        let payload = b"some recorded bytes\n";
        reg.record_frame("r1", payload, &bus).expect("frame");
        reg.close_with_io("r1", &bus).expect("close");

        let on_disk = std::fs::read(&path).expect("read");
        // Magic + version (5 bytes), then [len(4)][nonce(12)][ct+tag(payload+16)]
        assert_eq!(&on_disk[..4], b"LFR1");
        assert_eq!(on_disk[4], LFR_VERSION);
        let len = u32::from_le_bytes(on_disk[5..9].try_into().unwrap()) as usize;
        assert_eq!(len, payload.len());
        let nonce = &on_disk[9..21];
        let ct = &on_disk[21..];
        // First frame's AAD is `0u64` little-endian per the v2
        // contract — the writer claimed index 0 before incrementing.
        let aad = 0u64.to_le_bytes();
        let pt = crate::crypto::aes_gcm_decrypt_raw(&key, nonce, ct, &aad).expect("decrypt");
        assert_eq!(pt.as_slice(), payload);
        // Sanity: empty AAD must NOT decrypt — proves AAD binding.
        assert!(crate::crypto::aes_gcm_decrypt_raw(&key, nonce, ct, &[]).is_err());
        let _ = std::fs::remove_file(&path);
    }

    /// LFR v2 binds the per-frame counter into AAD. An attacker who
    /// swaps two frames byte-for-byte (positions 0 and 1) MUST break
    /// the AEAD tag at both swapped positions: the wire bytes are
    /// the ciphertext signed under AAD=N, but the reader recomputes
    /// AAD from position M, and N != M.
    #[test]
    fn frame_swap_breaks_aad_binding_at_swapped_positions() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("swap");
        let key = [11u8; 32];
        reg.register_with_io(
            "r1".into(),
            "s1".into(),
            path.clone(),
            Some(zeroize::Zeroizing::new(key)),
            &bus,
        )
        .expect("register");
        let payload_a = b"alpha\n";
        let payload_b = b"beta\n";
        reg.record_frame("r1", payload_a, &bus).expect("frame a");
        reg.record_frame("r1", payload_b, &bus).expect("frame b");
        reg.close_with_io("r1", &bus).expect("close");

        let mut on_disk = std::fs::read(&path).expect("read");
        // Layout: [magic(4)][ver(1)] [len(4)][nonce(12)][ct+tag(a+16)] [len(4)][nonce(12)][ct+tag(b+16)]
        let frame_a_off = 5;
        let frame_a_size = 4 + NONCE_LEN + payload_a.len() + 16;
        let frame_b_off = frame_a_off + frame_a_size;
        let frame_b_size = 4 + NONCE_LEN + payload_b.len() + 16;
        let mut swapped = on_disk[..frame_a_off].to_vec();
        swapped.extend_from_slice(&on_disk[frame_b_off..frame_b_off + frame_b_size]);
        swapped.extend_from_slice(&on_disk[frame_a_off..frame_a_off + frame_a_size]);
        on_disk = swapped;

        // The decoder validates AAD by frame position. Position 0 now
        // holds the ciphertext signed under AAD=1, so decrypt under
        // AAD=0 must fail. Same for position 1 ↔ AAD=1 ≠ original=0.
        let pos0_ct = &on_disk[frame_a_off + 4 + NONCE_LEN..frame_a_off + frame_a_size];
        let pos0_nonce = &on_disk[frame_a_off + 4..frame_a_off + 4 + NONCE_LEN];
        let aad_pos0 = 0u64.to_le_bytes();
        assert!(
            crate::crypto::aes_gcm_decrypt_raw(&key, pos0_nonce, pos0_ct, &aad_pos0).is_err(),
            "swapped frame must fail AAD-bound decrypt at its new position"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn record_frame_on_counter_only_actor_errors() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        reg.register("r1".into(), "s1".into(), "/tmp/x".into(), false, &bus);
        let err = reg.record_frame("r1", b"x", &bus).unwrap_err();
        assert!(err.to_string().contains("no file handle"));
    }

    #[test]
    fn record_frame_missing_actor_errors() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let err = reg.record_frame("missing", b"x", &bus).unwrap_err();
        assert!(err.to_string().contains("not registered"));
    }

    #[test]
    fn rotate_to_swaps_file_and_resets_counter() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path1 = tempfile_path("rot1");
        let path2 = tempfile_path("rot2");
        let key = [9u8; 32];
        reg.register_with_io(
            "r1".into(),
            "s1".into(),
            path1.clone(),
            Some(zeroize::Zeroizing::new(key)),
            &bus,
        )
        .expect("register");
        reg.record_frame("r1", b"first\n", &bus).expect("frame");
        let pre = reg.snapshot("r1").unwrap();
        assert!(pre.bytes_written > 0);

        let rotated = reg.rotate_to("r1", path2.clone(), &bus).expect("rotate_to");
        // After rotation the actor reports the new path and a fresh
        // counter equal to the magic + version header.
        assert_eq!(rotated.path, path2);
        assert_eq!(rotated.bytes_written, (LFR_MAGIC.len() + 1) as u64);

        reg.record_frame("r1", b"second\n", &bus).expect("frame2");
        reg.close_with_io("r1", &bus).expect("close");

        // Old file ends with the first frame; new file starts with magic.
        let old_disk = std::fs::read(&path1).expect("read old");
        assert_eq!(&old_disk[..4], b"LFR1");
        let new_disk = std::fs::read(&path2).expect("read new");
        assert_eq!(&new_disk[..4], b"LFR1");

        let _ = std::fs::remove_file(&path1);
        let _ = std::fs::remove_file(&path2);
    }

    #[test]
    fn rotate_to_missing_actor_errors() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let err = reg.rotate_to("missing", "/tmp/x".into(), &bus).unwrap_err();
        assert!(err.to_string().contains("not registered"));
    }

    #[test]
    fn rotate_to_counter_only_errors() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        reg.register("r1".into(), "s1".into(), "/tmp/x".into(), false, &bus);
        let err = reg.rotate_to("r1", "/tmp/y".into(), &bus).unwrap_err();
        assert!(err.to_string().contains("no file handle"));
    }

    #[test]
    fn record_header_emits_asciinema_v2_shape() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("header");
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .unwrap();
        reg.record_header("r1", 80, 24, "/bin/zsh", &bus).unwrap();
        let body = std::fs::read_to_string(&path).unwrap();
        assert!(body.starts_with("{\"version\":2,"));
        assert!(body.contains("\"width\":80"));
        assert!(body.contains("\"height\":24"));
        assert!(body.contains("\"SHELL\":\"/bin/zsh\""));
        assert!(body.ends_with("\n"));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn record_event_writes_jsonline_with_delta() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("event");
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .unwrap();
        reg.record_event("r1", RecordDirection::Output, b"hello", &bus)
            .unwrap();
        let body = std::fs::read_to_string(&path).unwrap();
        assert!(body.starts_with("["));
        assert!(body.contains(",\"o\",\"hello\"]\n"));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn record_event_escapes_control_chars_and_quotes() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("escapes");
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .unwrap();
        reg.record_event(
            "r1",
            RecordDirection::Input,
            b"line\nwith \"quote\" and \x07 bell",
            &bus,
        )
        .unwrap();
        let body = std::fs::read_to_string(&path).unwrap();
        assert!(body.contains("\\n"));
        assert!(body.contains("\\\""));
        assert!(body.contains("\\u0007"));
        assert!(body.contains(",\"i\","));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn record_event_empty_bytes_is_noop() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        let path = tempfile_path("empty");
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), None, &bus)
            .unwrap();
        let total = reg
            .record_event("r1", RecordDirection::Output, b"", &bus)
            .unwrap();
        assert_eq!(total, 0);
        let body = std::fs::read_to_string(&path).unwrap();
        assert!(body.is_empty());
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn format_delta_strips_trailing_zeros() {
        assert_eq!(format_delta(0.0), "0");
        assert_eq!(format_delta(1.0), "1");
        assert_eq!(format_delta(1.5), "1.5");
        assert_eq!(format_delta(0.123456), "0.123456");
        assert_eq!(format_delta(2.500000), "2.5");
    }

    #[test]
    fn json_escape_handles_spec_escapes() {
        assert_eq!(json_escape("plain"), "plain");
        assert_eq!(json_escape("with\"quote"), "with\\\"quote");
        assert_eq!(json_escape("back\\slash"), "back\\\\slash");
        assert_eq!(json_escape("new\nline"), "new\\nline");
        assert_eq!(json_escape("tab\there"), "tab\\there");
        assert_eq!(json_escape("\x01ctrl"), "\\u0001ctrl");
        assert_eq!(json_escape("emoji 🦀 ok"), "emoji 🦀 ok");
    }
}
