//! `.lfsr` playback decoder. Pure Rust counterpart of the writer
//! in [`super`] — every frame the writer emits decodes through
//! [`open_lfsr_iter`] back into the JSON-Lines record the
//! `SessionRecorder` produced.
//!
//! Single canonical format — version `0x01` of LFR1. Layout:
//!
//! ```text
//! [magic 4 "LFR1"][version 1 = 0x01][wrap_nonce 12][wrapped_recording_key 48]
//! [frame 0]…[frame N]
//! ```
//!
//! Reader contract:
//!
//! * **Header sniff.** Reads the fixed 65-byte header, verifies the
//!   magic + version, then unwraps the per-file 32-byte recording
//!   key with the caller-supplied DB key (AES-256-GCM, AAD =
//!   `KEYWRAP_AAD`). Bad magic / unsupported version / GCM tag
//!   mismatch surface as typed [`ReaderError`] variants.
//! * **Per-frame loop.** `[len(4 LE)][nonce(12)][cipher + tag(16)]`,
//!   AES-256-GCM decrypt with the unwrapped recording key (AAD =
//!   `frame_index_u64_le`), push the resulting JSON-Lines record
//!   (newline-trimmed) through the iterator.
//!
//! The DB key is the caller's responsibility — the `lfs_frb`
//! adapter pulls it from [`crate::secrets::ACTIVE_DBKEY_SECRET_ID`]
//! before invoking `open_lfsr_iter` so the bytes never cross the
//! FRB boundary back to Dart. The recording key never leaves Rust
//! memory; it lives only between the header unwrap and the final
//! frame decrypt.

use std::io::{BufRead, ErrorKind, Read, Seek, SeekFrom};
use std::path::Path;

use super::{LFR_HEADER_LEN, LFR_MAGIC, LFR_VERSION, MAX_FRAME_PLAINTEXT_BYTES, NONCE_LEN};
use crate::crypto;

/// Per-line cap for plaintext `.cast` recordings. The asciinema
/// JSON-Lines format has no length prefix, so a malformed file
/// with a missing newline could otherwise pull the entire file
/// into memory looking for one. 16 MiB matches
/// [`MAX_FRAME_PLAINTEXT_BYTES`] — same posture as the encrypted
/// path's per-frame cap.
pub(crate) const MAX_CAST_LINE_BYTES: usize = MAX_FRAME_PLAINTEXT_BYTES as usize;

/// Errors the reader can surface. Each variant maps to a
/// user-visible "this recording cannot be played back" reason —
/// the playback dialog renders the variant name (or `error()`
/// detail when present).
#[derive(Debug)]
pub enum ReaderError {
    Io(std::io::Error),
    BadMagic,
    UnsupportedVersion(u8),
    TruncatedHeader,
    TruncatedFrame,
    FrameTooLarge(u32),
    Crypto(String),
    NonUtf8Frame,
}

impl std::fmt::Display for ReaderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReaderError::Io(e) => write!(f, "io: {e}"),
            ReaderError::BadMagic => write!(f, "bad LFR1 magic"),
            ReaderError::UnsupportedVersion(v) => write!(f, "unsupported version: {v}"),
            ReaderError::TruncatedHeader => write!(f, "truncated header"),
            ReaderError::TruncatedFrame => write!(f, "truncated frame"),
            ReaderError::FrameTooLarge(n) => {
                write!(
                    f,
                    "frame plaintext {n} exceeds {MAX_FRAME_PLAINTEXT_BYTES} cap"
                )
            }
            ReaderError::Crypto(detail) => write!(f, "decrypt: {detail}"),
            ReaderError::NonUtf8Frame => write!(f, "non-utf8 plaintext frame"),
        }
    }
}

impl std::error::Error for ReaderError {}

impl From<std::io::Error> for ReaderError {
    fn from(e: std::io::Error) -> Self {
        ReaderError::Io(e)
    }
}

/// Open `path` and return an iterator yielding decoded JSON-Lines
/// records (one per encrypted frame). The iterator owns the file
/// handle until dropped; iterating to completion drives every
/// frame through AES-256-GCM decrypt.
///
/// `db_key` is the wrap key — the DB encryption key held in
/// [`crate::secrets::ACTIVE_DBKEY_SECRET_ID`]. The header's
/// wrapped recording key unwraps under it; the recording key
/// itself never crosses this function's API surface, lives only
/// between the header read and the final frame decrypt, and
/// drops with the iterator.
///
/// Errors during the magic / version sniff surface as the first
/// `Some(Err(...))` from the iterator. Per-frame decrypt failures
/// (truncated frame, GCM tag mismatch, non-utf8 plaintext) yield
/// `Some(Err(...))` and the iterator terminates on the next call.
pub fn open_lfsr_iter(path: &Path, db_key: [u8; 32]) -> Result<LfsrFrameIter, ReaderError> {
    open_lfsr_iter_at(path, db_key, None)
}

/// Single asciinema-v2 event: `[timestamp_seconds, direction,
/// data]`. Mirror of the Dart `RecordingFrame` struct the
/// playback dialog consumes one per emitted record.
#[derive(Debug, Clone, PartialEq)]
pub struct DecodedEvent {
    pub timestamp: f64,
    pub direction: String,
    pub data: String,
}

/// Parse one JSON-Lines record from a recording. Returns
/// `Some(event)` when the line is a 3-tuple event, `None` for
/// the header line (object, not array), malformed JSON, or any
/// other shape the playback dialog should silently skip.
///
/// Lives in `lfs_core::recorder::reader` (not Dart) so the
/// asciinema-v2 wire shape stays Rust-side; the encrypted-envelope
/// decode that produces this line already lives here, this is
/// just the last leaf-parse on the playback stream.
pub fn decode_event_line(line: &str) -> Option<DecodedEvent> {
    let value: serde_json::Value = serde_json::from_str(line).ok()?;
    let arr = value.as_array()?;
    if arr.len() < 3 {
        return None;
    }
    let timestamp = arr[0].as_f64()?;
    let direction = arr[1].as_str()?.to_string();
    let data = arr[2].as_str()?.to_string();
    Some(DecodedEvent {
        timestamp,
        direction,
        data,
    })
}

/// Decoded asciinema-v2 header — carries the dimensions the
/// recorded shell ran at so playback can resize the terminal to match,
/// plus the wall-clock origin and the optional `$SHELL` label the
/// recorder captured at start time. Mirror of the Dart-side
/// `RecordingHeader` value class.
#[derive(Debug, Clone, PartialEq)]
pub struct DecodedHeader {
    pub width: u32,
    pub height: u32,
    pub wall_clock_epoch_seconds: i64,
    pub shell_label: Option<String>,
}

/// Parse one JSON-Lines record as an asciinema-v2 header. Returns
/// `Some(header)` when the line is a JSON object carrying the
/// dimensions, `None` for an event tuple (array) or any malformed
/// shape. Missing fields fall back to the asciinema defaults
/// (80×24, epoch=0, no `$SHELL`) so a hand-edited cast that omits
/// `timestamp` still plays back.
///
/// Lives next to [`decode_event_line`] so the v2 wire-shape
/// grammar (header = object, event = 3-tuple array) is single-
/// source-of-truth in `lfs_core::recorder::reader`.
pub fn decode_header_line(line: &str) -> Option<DecodedHeader> {
    let value: serde_json::Value = serde_json::from_str(line).ok()?;
    let obj = value.as_object()?;
    let width = obj
        .get("width")
        .and_then(serde_json::Value::as_u64)
        .map(|w| w as u32)
        .unwrap_or(80);
    let height = obj
        .get("height")
        .and_then(serde_json::Value::as_u64)
        .map(|h| h as u32)
        .unwrap_or(24);
    let wall_clock_epoch_seconds = obj
        .get("timestamp")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0);
    let shell_label = obj
        .get("env")
        .and_then(serde_json::Value::as_object)
        .and_then(|env| env.get("SHELL").and_then(serde_json::Value::as_str))
        .map(str::to_string);
    Some(DecodedHeader {
        width,
        height,
        wall_clock_epoch_seconds,
        shell_label,
    })
}

#[cfg(test)]
mod decode_event_line_tests {
    use super::*;

    #[test]
    fn three_tuple_decodes_to_event() {
        let e = decode_event_line(r#"[1.5,"o","hello"]"#).unwrap();
        assert_eq!(e.timestamp, 1.5);
        assert_eq!(e.direction, "o");
        assert_eq!(e.data, "hello");
    }

    #[test]
    fn header_object_returns_none() {
        // The first line of an asciinema-v2 cast is the header
        // object, not an event tuple.
        assert!(decode_event_line(r#"{"version":2,"width":80}"#).is_none());
    }

    #[test]
    fn malformed_json_returns_none() {
        assert!(decode_event_line("not json").is_none());
    }

    #[test]
    fn two_tuple_returns_none() {
        assert!(decode_event_line(r#"[1.5,"o"]"#).is_none());
    }
}

#[cfg(test)]
mod decode_header_line_tests {
    use super::*;

    #[test]
    fn header_object_decodes_each_field() {
        let h = decode_header_line(
            r#"{"version":2,"width":120,"height":40,"timestamp":1700000000,"env":{"SHELL":"/bin/zsh"}}"#,
        )
        .unwrap();
        assert_eq!(h.width, 120);
        assert_eq!(h.height, 40);
        assert_eq!(h.wall_clock_epoch_seconds, 1_700_000_000);
        assert_eq!(h.shell_label.as_deref(), Some("/bin/zsh"));
    }

    #[test]
    fn missing_fields_fall_back_to_defaults() {
        let h = decode_header_line(r#"{"version":2}"#).unwrap();
        assert_eq!(h.width, 80);
        assert_eq!(h.height, 24);
        assert_eq!(h.wall_clock_epoch_seconds, 0);
        assert!(h.shell_label.is_none());
    }

    #[test]
    fn event_tuple_returns_none() {
        // Event lines are arrays — the header decoder must reject so
        // the playback loop can dispatch correctly.
        assert!(decode_header_line(r#"[1.5,"o","hello"]"#).is_none());
    }

    #[test]
    fn malformed_json_returns_none() {
        assert!(decode_header_line("not json").is_none());
    }

    #[test]
    fn env_without_shell_yields_none_shell_label() {
        let h = decode_header_line(r#"{"version":2,"env":{"TERM":"xterm"}}"#).unwrap();
        assert!(h.shell_label.is_none());
    }
}

/// `open_lfsr_iter` with an optional pre-positioned byte offset for
/// scrub-bar seek. The offset MUST land on a frame boundary the
/// sidecar `.idx` produced (otherwise the next `[len][nonce][ct]`
/// read decodes garbage and surfaces as a `TruncatedFrame` /
/// `Crypto` error). The magic + version sniff still runs against
/// the first five bytes of the file — the seek happens after.
///
/// `frame_index` is recomputed to match the sidecar's entry-position
/// → frame-index correspondence: each `.idx` entry maps to one frame,
/// so the post-seek frame_index equals the sidecar entry index that
/// matched the seek. The caller hands that value in via
/// `start_frame_index`; the reader uses it as the AAD counter for the
/// first frame past the offset.
pub fn open_lfsr_iter_at(
    path: &Path,
    db_key: [u8; 32],
    start: Option<(u64, u64)>,
) -> Result<LfsrFrameIter, ReaderError> {
    let file = std::fs::File::open(path)?;
    let mut reader = std::io::BufReader::new(file);
    let mut header = [0u8; LFR_HEADER_LEN];
    reader
        .read_exact(&mut header)
        .map_err(|_| ReaderError::TruncatedHeader)?;
    if header[..4] != LFR_MAGIC {
        return Err(ReaderError::BadMagic);
    }
    let version = header[4];
    if version != LFR_VERSION {
        return Err(ReaderError::UnsupportedVersion(version));
    }
    // Unwrap the per-file recording key with the caller's DB key.
    // Wrong DB key, tampered nonce, or a damaged wrap field all
    // surface as `ReaderError::Crypto` — the playback dialog
    // surfaces the same "this recording cannot be opened" path
    // either way.
    let recording_key = super::unwrap_lfsr_header(&header, &db_key)
        .map_err(|e| ReaderError::Crypto(e.to_string()))?;
    let mut key_bytes = [0u8; 32];
    key_bytes.copy_from_slice(&recording_key[..]);
    let frame_index = if let Some((offset, fi)) = start {
        reader.seek(SeekFrom::Start(offset))?;
        fi
    } else {
        0
    };
    Ok(LfsrFrameIter {
        reader,
        key: key_bytes,
        frame_index,
        finished: false,
    })
}

/// Iterator over the decoded JSON-Lines records of an `.lfsr`
/// playback file. Returned by [`open_lfsr_iter`] — see that
/// function for the construction invariants.
pub struct LfsrFrameIter {
    reader: std::io::BufReader<std::fs::File>,
    key: [u8; 32],
    frame_index: u64,
    finished: bool,
}

// `Debug` deliberately omits the BufReader (no Debug impl) and the
// key (zeroize-sensitive); only the cursor state is useful to log.
impl std::fmt::Debug for LfsrFrameIter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LfsrFrameIter")
            .field("frame_index", &self.frame_index)
            .field("finished", &self.finished)
            .finish_non_exhaustive()
    }
}

impl Iterator for LfsrFrameIter {
    type Item = Result<String, ReaderError>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.finished {
            return None;
        }
        let mut len_bytes = [0u8; 4];
        match self.reader.read_exact(&mut len_bytes) {
            Ok(()) => {}
            Err(e) if e.kind() == ErrorKind::UnexpectedEof => {
                self.finished = true;
                return None;
            }
            Err(e) => {
                self.finished = true;
                return Some(Err(ReaderError::Io(e)));
            }
        }
        let pt_len = u32::from_le_bytes(len_bytes);
        if pt_len > MAX_FRAME_PLAINTEXT_BYTES {
            self.finished = true;
            return Some(Err(ReaderError::FrameTooLarge(pt_len)));
        }
        let mut nonce = [0u8; NONCE_LEN];
        if self.reader.read_exact(&mut nonce).is_err() {
            self.finished = true;
            return Some(Err(ReaderError::TruncatedFrame));
        }
        // ciphertext length = plaintext length + 16-byte GCM tag.
        // The `pt_len > MAX_FRAME_PLAINTEXT_BYTES` reject above caps the
        // attacker-controlled allocation at 16 MiB + 16 bytes before any
        // I/O against the body. Without that guard `pt_len` is a `u32`
        // and could declare ~4 GiB.
        let mut ct = vec![0u8; pt_len as usize + 16];
        if self.reader.read_exact(&mut ct).is_err() {
            self.finished = true;
            return Some(Err(ReaderError::TruncatedFrame));
        }
        let aad_buf = self.frame_index.to_le_bytes();
        let pt = crypto::aes_gcm_decrypt_raw(&self.key, &nonce, &ct, &aad_buf)
            .map_err(|e| ReaderError::Crypto(e.to_string()));
        let pt = match pt {
            Ok(v) => v,
            Err(e) => {
                self.finished = true;
                return Some(Err(e));
            }
        };
        let line = std::str::from_utf8(&pt[..])
            .map(|s| s.trim_end_matches('\n').to_string())
            .map_err(|_| ReaderError::NonUtf8Frame);
        let line = match line {
            Ok(s) => s,
            Err(e) => {
                self.finished = true;
                return Some(Err(e));
            }
        };
        self.frame_index = self.frame_index.saturating_add(1);
        Some(Ok(line))
    }
}

/// Open a plaintext `.cast` recording and return an iterator
/// yielding one JSON-Lines record per call. The asciinema v2
/// format is line-delimited; the iterator trims the trailing
/// newline and skips empty lines so the surface matches
/// [`open_lfsr_iter`].
///
/// Each line is bounded by [`MAX_CAST_LINE_BYTES`] — a malformed
/// file with a runaway line (no newline before EOF) errors with
/// [`ReaderError::FrameTooLarge`] instead of pulling the whole
/// file into memory.
pub fn open_cast_iter(path: &Path) -> Result<CastFrameIter, ReaderError> {
    open_cast_iter_at(path, None)
}

/// `open_cast_iter` with an optional pre-positioned byte offset for
/// scrub-bar seek. The offset MUST land on a newline boundary the
/// sidecar `.idx` produced — otherwise the next `read_until('\n')`
/// returns a partial line. The caller pairs this with a known-good
/// offset from `index_sidecar::seek` so the next record decodes
/// cleanly.
pub fn open_cast_iter_at(path: &Path, start: Option<u64>) -> Result<CastFrameIter, ReaderError> {
    let mut file = std::fs::File::open(path)?;
    if let Some(offset) = start {
        file.seek(SeekFrom::Start(offset))?;
    }
    let reader = std::io::BufReader::new(file);
    Ok(CastFrameIter {
        reader,
        finished: false,
    })
}

/// Iterator over the JSON-Lines records of a plaintext `.cast`
/// playback file. Returned by [`open_cast_iter`].
pub struct CastFrameIter {
    reader: std::io::BufReader<std::fs::File>,
    finished: bool,
}

impl std::fmt::Debug for CastFrameIter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CastFrameIter")
            .field("finished", &self.finished)
            .finish_non_exhaustive()
    }
}

impl Iterator for CastFrameIter {
    type Item = Result<String, ReaderError>;

    fn next(&mut self) -> Option<Self::Item> {
        loop {
            if self.finished {
                return None;
            }
            let mut buf = Vec::with_capacity(256);
            // `read_until('\n')` returns 0 on EOF without an error.
            // Cap each line at MAX_CAST_LINE_BYTES — a runaway line
            // (missing newline) would otherwise stream the whole file
            // into `buf`. Take a bounded slice off the BufReader and
            // hard-stop when it overshoots.
            let mut take = (&mut self.reader).take((MAX_CAST_LINE_BYTES + 1) as u64);
            match take.read_until(b'\n', &mut buf) {
                Ok(0) => {
                    self.finished = true;
                    return None;
                }
                Ok(_) => {}
                Err(e) => {
                    self.finished = true;
                    return Some(Err(ReaderError::Io(e)));
                }
            }
            if buf.len() > MAX_CAST_LINE_BYTES {
                self.finished = true;
                return Some(Err(ReaderError::FrameTooLarge(
                    MAX_FRAME_PLAINTEXT_BYTES.saturating_add(1),
                )));
            }
            // Strip the trailing newline (and CR on Windows-line-
            // ending exports). Empty lines are skipped — the
            // asciinema spec does not allow them as records but
            // user-edited files in the wild sometimes carry them.
            while matches!(buf.last(), Some(b'\n') | Some(b'\r')) {
                buf.pop();
            }
            if buf.is_empty() {
                continue;
            }
            return Some(String::from_utf8(buf).map_err(|_| ReaderError::NonUtf8Frame));
        }
    }
}

/// Output of [`open_for_playback`]. Either a `.cast` plaintext
/// iterator or a `.lfsr` encrypted iterator — callers loop the
/// returned shape with `match` because the two iterator types
/// have the same `Item = Result<String, ReaderError>` surface
/// but distinct concrete types.
pub enum PlaybackIter {
    Cast(CastFrameIter),
    Lfsr(LfsrFrameIter),
}

impl PlaybackIter {
    /// Convenience: drive the variant under one `next()` call so
    /// the FRB adapter doesn't need to fan out the match itself.
    pub fn next_record(&mut self) -> Option<Result<String, ReaderError>> {
        match self {
            PlaybackIter::Cast(it) => it.next(),
            PlaybackIter::Lfsr(it) => it.next(),
        }
    }
}

/// Dispatch on the file's extension to pick the right decoder.
/// `.lfsr` (case-insensitive) opens through [`open_lfsr_iter`]
/// with the supplied DB key; anything else opens through
/// [`open_cast_iter`] as plaintext asciinema. The split lives
/// Rust-side so the Dart caller hands the path in once and never
/// branches on extension itself.
///
/// The DB key is required only for the encrypted path — callers
/// that know the file is plaintext can pass `[0u8; 32]` (the key
/// is only consumed by the `.lfsr` branch). The FRB adapter reads
/// the active DB key once per call and forwards it here so the
/// bytes never cross the FRB boundary back to Dart.
pub fn open_for_playback(path: &Path, db_key: [u8; 32]) -> Result<PlaybackIter, ReaderError> {
    open_for_playback_at(path, db_key, None, 0)
}

/// `open_for_playback` with an optional pre-positioned byte offset.
/// `start_offset = None` decodes the file from the start (post-header
/// for `.lfsr`); `Some(off)` jumps to a sidecar-supplied frame
/// boundary. `start_frame_index` is the AAD counter the next
/// encrypted frame is signed under — for the plaintext `.cast` path
/// the value is ignored.
pub fn open_for_playback_at(
    path: &Path,
    db_key: [u8; 32],
    start_offset: Option<u64>,
    start_frame_index: u64,
) -> Result<PlaybackIter, ReaderError> {
    let is_lfsr = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.eq_ignore_ascii_case("lfsr"))
        .unwrap_or(false);
    if is_lfsr {
        let start = start_offset.map(|o| (o, start_frame_index));
        open_lfsr_iter_at(path, db_key, start).map(PlaybackIter::Lfsr)
    } else {
        open_cast_iter_at(path, start_offset).map(PlaybackIter::Cast)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorder::{RecorderActor, RecorderRegistry};
    use std::io::Write;

    /// Test-only LFR1 v1 writer. Wraps `recording_key` under
    /// `db_key` into the 65-byte header and appends one frame per
    /// line so the reader's round-trip + decrypt path can be
    /// exercised without spinning a full `RecorderRegistry`.
    fn write_v1_recording(
        path: &Path,
        db_key: &[u8; 32],
        recording_key: &[u8; 32],
        lines: &[&str],
    ) {
        let mut f = std::fs::File::create(path).unwrap();
        let header = super::super::build_lfsr_header(db_key, recording_key).unwrap();
        f.write_all(&header).unwrap();
        for (i, line) in lines.iter().enumerate() {
            // Mirror the writer's `build_frame` shape exactly: append
            // a trailing newline to the plaintext so the round-trip
            // matches what a live recorder would emit.
            let mut payload = line.as_bytes().to_vec();
            payload.push(b'\n');
            let nonce = [0u8; NONCE_LEN]; // deterministic for tests
            let aad = (i as u64).to_le_bytes();
            let ct = crypto::aes_gcm_encrypt_raw(recording_key, &nonce, &payload, &aad).unwrap();
            f.write_all(&(payload.len() as u32).to_le_bytes()).unwrap();
            f.write_all(&nonce).unwrap();
            f.write_all(&ct).unwrap();
        }
    }

    fn _silence_unused() {
        // Keep imports cited even when no test path uses them so a
        // re-arrange doesn't strip them silently.
        let _ = std::any::type_name::<RecorderRegistry>();
        let _ = std::any::type_name::<RecorderActor>();
    }

    /// Bare-magic header builder for negative tests — emits the
    /// 65-byte v1 shape but skips the actual wrap so we can hit
    /// truncated / frame-length / nonce-only fault paths without
    /// caring about decryptability. Wrap nonce + slot are zeros;
    /// any test that calls this must NOT also try to decrypt.
    fn write_v1_header_only(path: &Path) {
        let mut bytes = LFR_MAGIC.to_vec();
        bytes.push(LFR_VERSION);
        bytes.extend_from_slice(&[0u8; NONCE_LEN]);
        bytes.extend_from_slice(&[0u8; 48]); // wrapped slot
        std::fs::write(path, &bytes).unwrap();
    }

    #[test]
    fn open_rejects_missing_file() {
        let key = [0u8; 32];
        let err = open_lfsr_iter(Path::new("/nonexistent/path-7c8f.lfsr"), key)
            .expect_err("missing file");
        assert!(matches!(err, ReaderError::Io(_)));
    }

    #[test]
    fn open_rejects_bad_magic() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        // 65 bytes so the header read succeeds — fault must come
        // from the magic compare, not the truncation guard.
        let mut bytes = vec![b'N', b'O', b'P', b'E', LFR_VERSION];
        bytes.extend_from_slice(&[0u8; LFR_HEADER_LEN - 5]);
        std::fs::write(tmp.path(), &bytes).unwrap();
        let key = [0u8; 32];
        let err = open_lfsr_iter(tmp.path(), key).expect_err("bad magic");
        assert!(matches!(err, ReaderError::BadMagic));
    }

    #[test]
    fn open_rejects_unsupported_version() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = LFR_MAGIC.to_vec();
        bytes.push(0xFE);
        bytes.extend_from_slice(&[0u8; LFR_HEADER_LEN - 5]);
        std::fs::write(tmp.path(), &bytes).unwrap();
        let key = [0u8; 32];
        let err = open_lfsr_iter(tmp.path(), key).expect_err("bad version");
        assert!(matches!(err, ReaderError::UnsupportedVersion(0xFE)));
    }

    #[test]
    fn open_rejects_truncated_header() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        // Only 2 of the 65 header bytes — the read fails before any
        // field decode.
        std::fs::write(tmp.path(), &LFR_MAGIC[..2]).unwrap();
        let key = [0u8; 32];
        let err = open_lfsr_iter(tmp.path(), key).expect_err("trunc header");
        assert!(matches!(err, ReaderError::TruncatedHeader));
    }

    #[test]
    fn round_trip_v1_yields_original_lines() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let db_key = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        let lines = vec![
            r#"{"version":2,"width":80,"height":24}"#,
            r#"[0.5,"o","hello"]"#,
            r#"[1.0,"i","q"]"#,
        ];
        write_v1_recording(tmp.path(), &db_key, &recording_key, &lines);
        let iter = open_lfsr_iter(tmp.path(), db_key).unwrap();
        let decoded: Vec<Result<String, _>> = iter.collect();
        assert_eq!(decoded.len(), 3);
        for (got, want) in decoded.iter().zip(lines.iter()) {
            let got_line = got.as_ref().expect("frame must decrypt");
            assert_eq!(got_line, want);
        }
    }

    #[test]
    fn frame_too_large_collapses_to_typed_error() {
        // Hand-build a real header (so unwrap succeeds) with a
        // bogus frame length immediately after; the iterator must
        // short-circuit with FrameTooLarge before it tries to
        // allocate the body buffer.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let db_key = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        let header = super::super::build_lfsr_header(&db_key, &recording_key).unwrap();
        let mut bytes = header;
        let bogus_len: u32 = MAX_FRAME_PLAINTEXT_BYTES.saturating_add(1);
        bytes.extend_from_slice(&bogus_len.to_le_bytes());
        std::fs::write(tmp.path(), &bytes).unwrap();
        let mut iter = open_lfsr_iter(tmp.path(), db_key).expect("header ok");
        let first = iter.next().expect("yields error");
        assert!(matches!(first, Err(ReaderError::FrameTooLarge(_))));
        assert!(iter.next().is_none());
    }

    #[test]
    fn frame_with_u32_max_length_rejects_without_allocating() {
        // Attacker handing us `pt_len = u32::MAX` (~4 GiB) — the
        // `pt_len > MAX_FRAME_PLAINTEXT_BYTES` guard fires before
        // the ciphertext allocation; the file stays at the header
        // + 4-byte length read.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let db_key = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        let header = super::super::build_lfsr_header(&db_key, &recording_key).unwrap();
        let mut bytes = header;
        bytes.extend_from_slice(&u32::MAX.to_le_bytes());
        std::fs::write(tmp.path(), &bytes).unwrap();
        let mut iter = open_lfsr_iter(tmp.path(), db_key).expect("header ok");
        let first = iter.next().expect("yields error");
        match first {
            Err(ReaderError::FrameTooLarge(reported)) => {
                assert_eq!(reported, u32::MAX);
            }
            other => panic!("expected FrameTooLarge(u32::MAX), got {other:?}"),
        }
        assert!(iter.next().is_none());
    }

    #[test]
    fn truncated_frame_after_length_collapses_to_typed_error() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let db_key = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        let header = super::super::build_lfsr_header(&db_key, &recording_key).unwrap();
        let mut bytes = header;
        // length = 4, but no nonce / ciphertext follows.
        bytes.extend_from_slice(&4u32.to_le_bytes());
        std::fs::write(tmp.path(), &bytes).unwrap();
        let mut iter = open_lfsr_iter(tmp.path(), db_key).expect("header ok");
        assert!(matches!(
            iter.next(),
            Some(Err(ReaderError::TruncatedFrame))
        ));
        assert!(iter.next().is_none());
    }

    #[test]
    fn wrong_db_key_yields_crypto_error() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let db_key_write = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        write_v1_recording(
            tmp.path(),
            &db_key_write,
            &recording_key,
            &[r#"[0,"o","x"]"#],
        );
        let db_key_read = [0x99u8; 32];
        // Wrap unwrap fails — the wrong DB key cannot decrypt the
        // recording-key slot, so the iterator never starts.
        let err = open_lfsr_iter(tmp.path(), db_key_read).expect_err("wrong db key");
        assert!(matches!(err, ReaderError::Crypto(_)));
    }

    #[test]
    fn header_only_with_zero_wrap_yields_crypto_error_on_open() {
        // A file that carries the magic + version + zeros (no real
        // wrap) must reject at open-time — the GCM tag mismatches
        // before any frame read.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        write_v1_header_only(tmp.path());
        let err = open_lfsr_iter(tmp.path(), [0u8; 32]).expect_err("zero-wrap");
        assert!(matches!(err, ReaderError::Crypto(_)));
    }

    #[test]
    fn cast_iter_yields_each_line_trimmed() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let body = "{\"version\":2,\"width\":80,\"height\":24}\n[0.5,\"o\",\"hi\"]\n";
        std::fs::write(tmp.path(), body).unwrap();
        let mut it = open_cast_iter(tmp.path()).unwrap();
        assert_eq!(
            it.next().unwrap().unwrap(),
            "{\"version\":2,\"width\":80,\"height\":24}"
        );
        assert_eq!(it.next().unwrap().unwrap(), "[0.5,\"o\",\"hi\"]");
        assert!(it.next().is_none());
    }

    #[test]
    fn cast_iter_skips_empty_lines() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        // Empty line between records — user-edited file in the
        // wild. The iterator skips them so the playback loop stays
        // straight.
        std::fs::write(tmp.path(), "a\n\nb\n").unwrap();
        let mut it = open_cast_iter(tmp.path()).unwrap();
        assert_eq!(it.next().unwrap().unwrap(), "a");
        assert_eq!(it.next().unwrap().unwrap(), "b");
        assert!(it.next().is_none());
    }

    #[test]
    fn cast_iter_strips_crlf_line_endings() {
        // Windows-line-ending exports sometimes carry `\r\n`. The
        // trailing `\r` would otherwise leak into the JSON parser
        // on the Dart side and reject every record.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(tmp.path(), "{\"version\":2}\r\n[0,\"o\",\"x\"]\r\n").unwrap();
        let mut it = open_cast_iter(tmp.path()).unwrap();
        assert_eq!(it.next().unwrap().unwrap(), "{\"version\":2}");
        assert_eq!(it.next().unwrap().unwrap(), "[0,\"o\",\"x\"]");
    }

    #[test]
    fn cast_iter_handles_no_trailing_newline() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(tmp.path(), "[0,\"o\",\"x\"]").unwrap();
        let mut it = open_cast_iter(tmp.path()).unwrap();
        assert_eq!(it.next().unwrap().unwrap(), "[0,\"o\",\"x\"]");
        assert!(it.next().is_none());
    }

    #[test]
    fn cast_iter_rejects_oversized_line() {
        // A single line beyond MAX_CAST_LINE_BYTES surfaces as
        // FrameTooLarge. The cap matches the encrypted path's
        // per-frame cap so a malformed plaintext file cannot pull
        // a multi-GiB allocation just by omitting newlines.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = vec![b'x'; MAX_CAST_LINE_BYTES + 8];
        bytes.push(b'\n');
        std::fs::write(tmp.path(), &bytes).unwrap();
        let mut it = open_cast_iter(tmp.path()).unwrap();
        assert!(matches!(
            it.next(),
            Some(Err(ReaderError::FrameTooLarge(_)))
        ));
        assert!(it.next().is_none());
    }

    #[test]
    fn cast_iter_rejects_missing_file() {
        let err = open_cast_iter(Path::new("/nonexistent/path-cast-7c8f.cast")).unwrap_err();
        assert!(matches!(err, ReaderError::Io(_)));
    }

    #[test]
    fn open_for_playback_dispatches_on_extension() {
        // .cast → CastFrameIter regardless of the supplied db key.
        let cast = tempfile::Builder::new().suffix(".cast").tempfile().unwrap();
        std::fs::write(cast.path(), "first\nsecond\n").unwrap();
        let dummy_key = [0u8; 32];
        let mut it = open_for_playback(cast.path(), dummy_key).unwrap();
        assert!(matches!(it, PlaybackIter::Cast(_)));
        assert_eq!(it.next_record().unwrap().unwrap(), "first");
        assert_eq!(it.next_record().unwrap().unwrap(), "second");
        assert!(it.next_record().is_none());

        // .lfsr → LfsrFrameIter through the header-unwrap path.
        let lfsr = tempfile::Builder::new().suffix(".lfsr").tempfile().unwrap();
        let db_key = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        write_v1_recording(lfsr.path(), &db_key, &recording_key, &[r#"[0,"o","x"]"#]);
        let it = open_for_playback(lfsr.path(), db_key).unwrap();
        assert!(matches!(it, PlaybackIter::Lfsr(_)));
    }

    #[test]
    fn open_for_playback_treats_missing_extension_as_cast() {
        // A user-renamed file without an extension falls through to
        // the plaintext branch — no LFR1 magic match to attempt.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(tmp.path(), "raw\n").unwrap();
        let mut it = open_for_playback(tmp.path(), [0u8; 32]).unwrap();
        assert!(matches!(it, PlaybackIter::Cast(_)));
        assert_eq!(it.next_record().unwrap().unwrap(), "raw");
    }

    #[test]
    fn open_for_playback_extension_check_is_case_insensitive() {
        // `.LFSR` (uppercase) routes to the encrypted path.
        let lfsr = tempfile::Builder::new().suffix(".LFSR").tempfile().unwrap();
        let db_key = [0x42u8; 32];
        let recording_key = [0x33u8; 32];
        write_v1_recording(lfsr.path(), &db_key, &recording_key, &[r#"[0,"o","x"]"#]);
        let it = open_for_playback(lfsr.path(), db_key).unwrap();
        assert!(matches!(it, PlaybackIter::Lfsr(_)));
    }
}
