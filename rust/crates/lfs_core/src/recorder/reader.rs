//! `.lfsr` playback decoder. Pure Rust counterpart of the writer
//! in [`super`] — every frame the writer emits decodes through
//! [`open_lfsr_iter`] back into the JSON-Lines record the
//! `SessionRecorder` produced.
//!
//! The reader's contract mirrors the encrypted writer:
//!
//! * Magic + version sniff. `LFR1` first four bytes; rejects on
//!   miss with [`ReaderError::BadMagic`]. Version `0x01` (legacy
//!   no-AAD) and `0x02` (per-frame AAD = `frame_index_u64_le`)
//!   both decode through this path; the writer never emits
//!   `0x01` since the AAD upgrade landed but pre-upgrade files
//!   still play back.
//! * Per-frame loop: `[len(4 LE)][nonce(12)][cipher + tag(16)]`,
//!   AES-256-GCM decrypt with the recording key, push the
//!   resulting JSON-Lines record (newline-trimmed) through the
//!   iterator.
//!
//! The recording key is the caller's responsibility — the
//! `lfs_frb` adapter HKDF-derives it from the active DB key
//! (`secrets::ACTIVE_DBKEY_SECRET_ID` + the
//! `letsflutssh-recording-v1` info string) so the bytes never
//! cross the FRB boundary back to Dart.

use std::io::{ErrorKind, Read};
use std::path::Path;

use super::{LFR_MAGIC, MAX_FRAME_PLAINTEXT_BYTES, NONCE_LEN};
use crate::crypto;

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
/// frame through AES-256-GCM decrypt with `key` as the
/// 32-byte recording key.
///
/// Errors during the magic / version sniff surface as the first
/// `Some(Err(...))` from the iterator. Per-frame decrypt failures
/// (truncated frame, GCM tag mismatch, non-utf8 plaintext) yield
/// `Some(Err(...))` and the iterator terminates on the next call.
pub fn open_lfsr_iter(path: &Path, key: [u8; 32]) -> Result<LfsrFrameIter, ReaderError> {
    let file = std::fs::File::open(path)?;
    let mut reader = std::io::BufReader::new(file);
    let mut head = [0u8; 5];
    reader
        .read_exact(&mut head)
        .map_err(|_| ReaderError::TruncatedHeader)?;
    if head[..4] != LFR_MAGIC {
        return Err(ReaderError::BadMagic);
    }
    let version = head[4];
    if version != 0x01 && version != 0x02 {
        return Err(ReaderError::UnsupportedVersion(version));
    }
    Ok(LfsrFrameIter {
        reader,
        key,
        version,
        frame_index: 0,
        finished: false,
    })
}

/// Iterator over the decoded JSON-Lines records of an `.lfsr`
/// playback file. Returned by [`open_lfsr_iter`] — see that
/// function for the construction invariants.
pub struct LfsrFrameIter {
    reader: std::io::BufReader<std::fs::File>,
    key: [u8; 32],
    version: u8,
    frame_index: u64,
    finished: bool,
}

// `Debug` deliberately omits the BufReader (no Debug impl) and the
// key (zeroize-sensitive); only the cursor state is useful to log.
impl std::fmt::Debug for LfsrFrameIter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LfsrFrameIter")
            .field("version", &self.version)
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
        let mut ct = vec![0u8; pt_len as usize + 16];
        if self.reader.read_exact(&mut ct).is_err() {
            self.finished = true;
            return Some(Err(ReaderError::TruncatedFrame));
        }
        let aad_buf = self.frame_index.to_le_bytes();
        let aad: &[u8] = if self.version == 0x02 { &aad_buf } else { &[] };
        let pt = crypto::aes_gcm_decrypt_raw(&self.key, &nonce, &ct, aad)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorder::{RecorderActor, RecorderRegistry};
    use std::io::Write;

    fn write_v2_recording(path: &Path, key: &[u8; 32], lines: &[&str]) {
        // Build the file the same way `RecorderRegistry::register_with_io`
        // does: 4-byte magic + 1-byte version + per-line frame.
        let mut f = std::fs::File::create(path).unwrap();
        f.write_all(&LFR_MAGIC).unwrap();
        f.write_all(&[0x02]).unwrap();
        for (i, line) in lines.iter().enumerate() {
            // Mirror the writer's `build_frame` shape exactly: append
            // a trailing newline to the plaintext so the round-trip
            // matches what a live recorder would emit.
            let mut payload = line.as_bytes().to_vec();
            payload.push(b'\n');
            let nonce = [0u8; NONCE_LEN]; // deterministic for tests
            let aad = (i as u64).to_le_bytes();
            let ct = crypto::aes_gcm_encrypt_raw(key, &nonce, &payload, &aad).unwrap();
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
        std::fs::write(tmp.path(), b"NOPE\x02").unwrap();
        let key = [0u8; 32];
        let err = open_lfsr_iter(tmp.path(), key).expect_err("bad magic");
        assert!(matches!(err, ReaderError::BadMagic));
    }

    #[test]
    fn open_rejects_unsupported_version() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = LFR_MAGIC.to_vec();
        bytes.push(0xFE);
        std::fs::write(tmp.path(), &bytes).unwrap();
        let key = [0u8; 32];
        let err = open_lfsr_iter(tmp.path(), key).expect_err("bad version");
        assert!(matches!(err, ReaderError::UnsupportedVersion(0xFE)));
    }

    #[test]
    fn open_rejects_truncated_header() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        // Only 2 of the 5 header bytes; the read fails before we
        // can branch on the magic.
        std::fs::write(tmp.path(), &LFR_MAGIC[..2]).unwrap();
        let key = [0u8; 32];
        let err = open_lfsr_iter(tmp.path(), key).expect_err("trunc header");
        assert!(matches!(err, ReaderError::TruncatedHeader));
    }

    #[test]
    fn round_trip_v2_yields_original_lines() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let key = [0x42u8; 32];
        let lines = vec![
            r#"{"version":2,"width":80,"height":24}"#,
            r#"[0.5,"o","hello"]"#,
            r#"[1.0,"i","q"]"#,
        ];
        write_v2_recording(tmp.path(), &key, &lines);
        let iter = open_lfsr_iter(tmp.path(), key).unwrap();
        let decoded: Vec<Result<String, _>> = iter.collect();
        assert_eq!(decoded.len(), 3);
        for (got, want) in decoded.iter().zip(lines.iter()) {
            let got_line = got.as_ref().expect("frame must decrypt");
            assert_eq!(got_line, want);
        }
    }

    #[test]
    fn frame_too_large_collapses_to_typed_error() {
        // Hand-build a frame with a length prefix above the cap;
        // the iterator must short-circuit with FrameTooLarge before
        // it tries to allocate the buffer.
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = LFR_MAGIC.to_vec();
        bytes.push(0x02);
        let bogus_len: u32 = MAX_FRAME_PLAINTEXT_BYTES.saturating_add(1);
        bytes.extend_from_slice(&bogus_len.to_le_bytes());
        std::fs::write(tmp.path(), &bytes).unwrap();
        let key = [0u8; 32];
        let mut iter = open_lfsr_iter(tmp.path(), key).expect("magic ok");
        let first = iter.next().expect("yields error");
        assert!(matches!(first, Err(ReaderError::FrameTooLarge(_))));
        // Subsequent next() returns None — the iterator is
        // self-terminating after a fatal frame error.
        assert!(iter.next().is_none());
    }

    #[test]
    fn truncated_frame_after_length_collapses_to_typed_error() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = LFR_MAGIC.to_vec();
        bytes.push(0x02);
        // length = 4, but no nonce / ciphertext follows.
        bytes.extend_from_slice(&4u32.to_le_bytes());
        std::fs::write(tmp.path(), &bytes).unwrap();
        let key = [0u8; 32];
        let mut iter = open_lfsr_iter(tmp.path(), key).expect("magic ok");
        assert!(matches!(
            iter.next(),
            Some(Err(ReaderError::TruncatedFrame))
        ));
        assert!(iter.next().is_none());
    }

    #[test]
    fn wrong_key_yields_crypto_error() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let key_write = [0x42u8; 32];
        write_v2_recording(tmp.path(), &key_write, &[r#"[0,"o","x"]"#]);
        let key_read = [0x99u8; 32];
        let mut iter = open_lfsr_iter(tmp.path(), key_read).expect("magic ok");
        assert!(matches!(iter.next(), Some(Err(ReaderError::Crypto(_)))));
    }
}
