//! Session recorder.
//!
//! Owns the canonical state + file IO for active recordings.
//! Per-frame AES-GCM crypto runs Rust-side
//! (`crypto::aes_gcm_encrypt_raw`); this module brings the file
//! handle + byte counter alongside so a recording's state lives
//! in one place rather than half on each side of the FRB
//! boundary.
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

use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::{Arc, Mutex};

use rand::RngCore;

use crate::bus::{Event, EventBus};
use crate::error::Error;

/// File-format magic — `LFR1` (LetsFLUTssh Recorder v1). Mirrors
/// the Dart-era `SessionRecorder._lfrMagic` byte-for-byte so
/// recordings remain forward-compatible.
const LFR_MAGIC: [u8; 4] = [0x4C, 0x46, 0x52, 0x31];
const LFR_VERSION: u8 = 1;
const NONCE_LEN: usize = 12;

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
    /// Owned file handle when the registry drives IO. `None` for
    /// counter-only actors registered via [`RecorderRegistry::register`].
    /// Wrapped in `Arc<Mutex>` so frame writes can drop the
    /// registry mutex first and contend only on this handle.
    file: Option<Arc<Mutex<std::fs::File>>>,
    /// 32-byte AES-256 key in encrypted mode. Derived caller-side
    /// (HKDF off the DB key) and handed in once at register time.
    key: Option<[u8; 32]>,
}

impl RecorderActor {
    pub fn new(id: RecorderId, session_id: String, path: String, encrypted: bool) -> Self {
        Self {
            id,
            session_id,
            path,
            bytes_written: 0,
            encrypted,
            file: None,
            key: None,
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
        self.inner.lock().expect("recorder registry mutex poisoned")
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
        key: Option<[u8; 32]>,
        bus: &EventBus,
    ) -> Result<RecorderSnapshot, Error> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .map_err(|e| Error::Io(format!("recorder open {path}: {e}")))?;
        let encrypted = key.is_some();
        let mut bytes_written: u64 = 0;
        if encrypted {
            file.write_all(&LFR_MAGIC)
                .and_then(|_| file.write_all(&[LFR_VERSION]))
                .map_err(|e| Error::Io(format!("recorder magic write: {e}")))?;
            bytes_written = (LFR_MAGIC.len() + 1) as u64;
        }
        let actor = RecorderActor {
            id: id.clone(),
            session_id,
            path: path.clone(),
            bytes_written,
            encrypted,
            file: Some(Arc::new(Mutex::new(file))),
            key,
        };
        let snap = actor.snapshot();
        {
            let mut g = self.lock();
            g.by_id.insert(id.clone(), actor);
        }
        bus.publish(Event::RecorderStarted { id, path });
        Ok(snap)
    }

    /// Encrypt (when keyed) and append a frame to the recording's
    /// file. Plaintext mode writes the bytes verbatim. Returns
    /// the running byte total. Errors when the actor was not
    /// registered through [`RecorderRegistry::register_with_io`].
    pub fn record_frame(&self, id: &str, plaintext: &[u8], bus: &EventBus) -> Result<u64, Error> {
        // Snapshot the IO handle + key under the registry lock,
        // then drop the lock before doing the (potentially
        // blocking) write. Other registry operations stay
        // non-blocked while a frame writes out.
        let (file_handle, key) = {
            let g = self.lock();
            let Some(actor) = g.by_id.get(id) else {
                return Err(Error::Io(format!("recorder {id} not registered")));
            };
            let Some(file) = actor.file.as_ref() else {
                return Err(Error::Io(format!(
                    "recorder {id} has no file handle (counter-only registration)"
                )));
            };
            (file.clone(), actor.key)
        };

        let frame = build_frame(plaintext, key.as_ref())?;
        {
            let mut handle = file_handle
                .lock()
                .map_err(|_| Error::Io("recorder file mutex poisoned".to_string()))?;
            handle
                .write_all(&frame)
                .map_err(|e| Error::Io(format!("recorder frame write: {e}")))?;
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
                    .map_err(|e| Error::Io(format!("recorder close flush: {e}")))?;
                // File drops with the guard; OS handle closes.
            }
            bus.publish(Event::RecorderStopped { id: id.to_string() });
        }
        Ok(())
    }
}

/// Build the on-disk frame for `plaintext`. With `Some(key)`
/// returns `[len(4 LE)][nonce(12)][ciphertext+tag]`; with
/// `None` returns `plaintext` as-is so plaintext recordings
/// remain valid asciinema documents.
fn build_frame(plaintext: &[u8], key: Option<&[u8; 32]>) -> Result<Vec<u8>, Error> {
    let Some(key) = key else {
        return Ok(plaintext.to_vec());
    };
    let mut nonce = [0u8; NONCE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut nonce);
    let ct = crate::crypto::aes_gcm_encrypt_raw(key, &nonce, plaintext, &[])?;
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
            .register_with_io("r1".into(), "s1".into(), path.clone(), Some(key), &bus)
            .expect("register");
        assert!(snap.encrypted);
        let on_disk = std::fs::read(&path).expect("read");
        assert_eq!(&on_disk[..4], b"LFR1");
        assert_eq!(on_disk[4], 0x01);
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
        reg.register_with_io("r1".into(), "s1".into(), path.clone(), Some(key), &bus)
            .expect("register");
        let payload = b"some recorded bytes\n";
        reg.record_frame("r1", payload, &bus).expect("frame");
        reg.close_with_io("r1", &bus).expect("close");

        let on_disk = std::fs::read(&path).expect("read");
        // Magic + version (5 bytes), then [len(4)][nonce(12)][ct+tag(payload+16)]
        assert_eq!(&on_disk[..4], b"LFR1");
        assert_eq!(on_disk[4], 0x01);
        let len = u32::from_le_bytes(on_disk[5..9].try_into().unwrap()) as usize;
        assert_eq!(len, payload.len());
        let nonce = &on_disk[9..21];
        let ct = &on_disk[21..];
        let pt = crate::crypto::aes_gcm_decrypt_raw(&key, nonce, ct, &[]).expect("decrypt");
        assert_eq!(pt, payload);
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
}
