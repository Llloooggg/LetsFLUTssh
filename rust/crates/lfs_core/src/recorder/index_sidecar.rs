//! Sidecar `.idx` index for recording playback seek.
//!
//! Each recording file (`.cast` or `.lfsr`) is paired with a fixed-width
//! `.idx` file written next to it. Every asciinema event the writer emits
//! contributes one index entry:
//!
//! `[event_file_offset_u64_le][event_timestamp_ms_u32_le]` — 12 bytes per
//! entry. Entries are appended in event order so the reader binary-searches
//! by timestamp without scanning the main file.
//!
//! # Wire format
//!
//! Both plaintext and encrypted variants start with a header:
//!
//! `LFI1` magic (4 bytes) + version `0x01` (1 byte).
//!
//! ## Plaintext (`.cast`)
//!
//! After the header, a stream of raw 12-byte entries:
//!
//! `[offset_u64_le (8)][timestamp_ms_u32_le (4)]`.
//!
//! ## Encrypted (`.lfsr`)
//!
//! After the header, a stream of self-framed AES-256-GCM blocks. Each
//! block encrypts exactly one 12-byte plaintext entry:
//!
//! `[len_u32_le (4)][nonce (12)][ciphertext + GCM tag (12 + 16)]`
//!
//! Per-block AAD is `entry_seq_u64_le` — a counter the reader reconstructs
//! from block position (0 for the first entry, 1 for the second, …). Same
//! AAD-binding pattern as the main `.lfsr` file (`super`) so swapping two
//! index blocks on disk breaks the GCM tag at both swapped positions.
//!
//! # Key derivation
//!
//! The index key chains off the recorder key — separate HKDF info tag
//! (`letsflutssh-recording-idx-v1`) so a leak of one key does not expose
//! the other. Derivation lives FRB-side in
//! `lfs_frb::api::recorder::recorder_seek`; this module accepts the
//! derived 32-byte key as a parameter so the same code path can be
//! exercised in unit tests without bootstrapping the secrets store.
//!
//! # Crash safety
//!
//! The main-file write happens BEFORE the index entry write. A crash
//! between the two leaves the trailing entry missing — the reader treats
//! that as "no index past the last good entry" and falls back to
//! sequential decode for any seek target past it. The pairing is
//! deliberately non-atomic: paying fsync × 2 per event would dominate
//! the writer's hot path, and the worst case (lose one scrub-target on
//! the last 10 ms of a recording before crash) is a minor degradation.
//!
//! # Why 12-byte entries + `u32` timestamp
//!
//! `u32` milliseconds tops out at ~49 days — far beyond any plausible
//! single recording. Pulling the timestamp narrower (`u32` vs `u64`)
//! halves the per-entry size on the plaintext path, which directly cuts
//! the binary-search range a typical seek walks. The offset stays `u64`
//! because `MAX_FILE_BYTES = 100 MB` per file is small relative to the
//! type but multi-file rotations could in theory chain a single playback
//! across rotation boundaries — keeping the type wide leaves room.

use std::fs::{File, OpenOptions};
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

use rand::Rng;

use super::NONCE_LEN;
use crate::crypto;
use crate::error::Error;

/// Sidecar magic — `LFI1` (LetsFLUTssh Index). Pinned so every reader
/// branches consistently on the first four bytes.
pub(crate) const LFI_MAGIC: [u8; 4] = [0x4C, 0x46, 0x49, 0x31];
/// On-disk format version byte (post-magic).
pub(crate) const LFI_VERSION: u8 = 0x01;

/// Plaintext per-entry size on disk: 8-byte offset + 4-byte timestamp.
pub(crate) const ENTRY_PLAINTEXT_LEN: usize = 12;

/// Encrypted block layout: 4-byte length prefix + 12-byte nonce +
/// 12-byte ciphertext + 16-byte GCM tag = 44 bytes. Used by the
/// unit-tests below to assert on-disk byte counts; production
/// readers walk the length prefix so they never need the constant.
#[cfg(test)]
pub(crate) const ENCRYPTED_BLOCK_LEN: usize = 4 + NONCE_LEN + ENTRY_PLAINTEXT_LEN + 16;

/// HKDF-SHA256 info string for the per-recording index key.
///
/// **Never bump.** Existing sidecar files key the per-block GCM tag
/// against this exact byte sequence; changing it orphans every
/// `<recording>.idx` already on disk.
pub const INDEX_HKDF_INFO: &[u8] = b"letsflutssh-recording-idx-v1";

/// Return the sidecar path for a given recording path: append `.idx`
/// to the full filename (so `foo.cast` → `foo.cast.idx`, `bar.lfsr`
/// → `bar.lfsr.idx`). The extra extension keeps the original file
/// extension intact so the browser walk still classifies the
/// recording correctly.
pub fn sidecar_path(recording_path: &Path) -> PathBuf {
    let mut s = recording_path.as_os_str().to_os_string();
    s.push(".idx");
    PathBuf::from(s)
}

/// One entry as it lives in plaintext form (regardless of whether the
/// on-disk variant is plaintext or encrypted).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IndexEntry {
    pub offset: u64,
    pub timestamp_ms: u32,
}

/// Encode one entry as 12 bytes.
fn encode_entry(entry: IndexEntry) -> [u8; ENTRY_PLAINTEXT_LEN] {
    let mut buf = [0u8; ENTRY_PLAINTEXT_LEN];
    buf[..8].copy_from_slice(&entry.offset.to_le_bytes());
    buf[8..].copy_from_slice(&entry.timestamp_ms.to_le_bytes());
    buf
}

/// Decode 12 bytes back into an entry.
fn decode_entry(bytes: &[u8; ENTRY_PLAINTEXT_LEN]) -> IndexEntry {
    let offset = u64::from_le_bytes(bytes[..8].try_into().unwrap());
    let timestamp_ms = u32::from_le_bytes(bytes[8..].try_into().unwrap());
    IndexEntry {
        offset,
        timestamp_ms,
    }
}

/// Owned sidecar writer. Holds an append-mode `BufWriter`, tracks the
/// running entry sequence number (for encrypted-mode AAD), and either
/// holds the recorder index key or `None` for plaintext mode.
pub struct IndexWriter {
    file: BufWriter<File>,
    key: Option<zeroize::Zeroizing<[u8; 32]>>,
    /// Running entry index. Increments on every successful append;
    /// rotation drops the writer and a fresh one starts at 0.
    next_seq: u64,
}

impl IndexWriter {
    /// Open a fresh sidecar at `path`. Writes the magic + version
    /// header immediately so a reader can distinguish empty-but-
    /// initialised from missing.
    pub fn create(path: &Path, key: Option<zeroize::Zeroizing<[u8; 32]>>) -> Result<Self, Error> {
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| Error::Recorder(format!("idx mkdir {}: {e}", parent.display())))?;
            }
        }
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(path)
            .map_err(|e| Error::Recorder(format!("idx open {}: {e}", path.display())))?;
        // chmod 0600 — same posture as the main recording file; an
        // index entry leaks the timestamp shape of the user's typing
        // burst even without the payload, and the main-file mode is
        // worth nothing if the sibling is world-readable.
        crate::path::harden_file_perms(path)
            .map_err(|msg| Error::Recorder(format!("idx harden {}: {msg}", path.display())))?;
        file.write_all(&LFI_MAGIC)
            .and_then(|_| file.write_all(&[LFI_VERSION]))
            .map_err(|e| Error::Recorder(format!("idx header write: {e}")))?;
        Ok(Self {
            file: BufWriter::new(file),
            key,
            next_seq: 0,
        })
    }

    /// Append one entry. Plaintext mode writes the 12 bytes verbatim;
    /// encrypted mode writes the 44-byte AES-GCM block. Flush after
    /// every entry so the durability story matches the main file
    /// (where `record_frame` writes via `write_all` and the OS flushes
    /// on drop).
    pub fn append(&mut self, entry: IndexEntry) -> Result<(), Error> {
        let pt = encode_entry(entry);
        let block: Vec<u8> = match self.key.as_deref() {
            None => pt.to_vec(),
            Some(key) => build_encrypted_block(&pt, key, self.next_seq)?,
        };
        self.file
            .write_all(&block)
            .map_err(|e| Error::Recorder(format!("idx append: {e}")))?;
        self.file
            .flush()
            .map_err(|e| Error::Recorder(format!("idx flush: {e}")))?;
        self.next_seq = self.next_seq.saturating_add(1);
        Ok(())
    }
}

/// Build the encrypted-block bytes for one entry. AAD is the entry
/// sequence number so a disk-side swap of two blocks invalidates the
/// GCM tag at both swapped positions.
fn build_encrypted_block(
    plaintext: &[u8; ENTRY_PLAINTEXT_LEN],
    key: &[u8; 32],
    seq: u64,
) -> Result<Vec<u8>, Error> {
    let mut nonce = [0u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut nonce);
    let aad = seq.to_le_bytes();
    let ct = crypto::aes_gcm_encrypt_raw(key, &nonce, plaintext, &aad)?;
    let mut block = Vec::with_capacity(4 + NONCE_LEN + ct.len());
    let pt_len = ENTRY_PLAINTEXT_LEN as u32;
    block.extend_from_slice(&pt_len.to_le_bytes());
    block.extend_from_slice(&nonce);
    block.extend_from_slice(&ct);
    Ok(block)
}

/// Iterate the sidecar at `path` and return every successfully-decoded
/// entry. Stops at the first truncated / malformed block — the trailing
/// dangling-entry case from a crash mid-append is handled by silently
/// dropping the partial block (an attacker-supplied tampered block
/// surfaces the same way: as "no entry past this point"). Either way
/// the caller falls back to sequential decode past the last good entry.
///
/// `key` is required for encrypted sidecars (the writer was opened with
/// a key); `None` decodes plaintext sidecars. The reader peeks at the
/// magic + version header and rejects on mismatch — a `.cast` recording
/// paired with an encrypted-shaped sidecar (or vice versa) returns
/// `Ok(vec![])` so the caller falls back to sequential decode rather
/// than spamming an error.
pub fn read_all(path: &Path, key: Option<&[u8; 32]>) -> Result<Vec<IndexEntry>, Error> {
    let file = match File::open(path) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(Error::Recorder(format!("idx open: {e}"))),
    };
    let mut reader = BufReader::new(file);
    let mut header = [0u8; 5];
    if reader.read_exact(&mut header).is_err() {
        // Truncated header (zero or partial bytes) → treat as empty.
        return Ok(Vec::new());
    }
    if header[..4] != LFI_MAGIC || header[4] != LFI_VERSION {
        // Wrong magic / version → treat as empty so the caller can
        // fall back to sequential decode rather than refuse playback.
        return Ok(Vec::new());
    }
    let mut entries = Vec::new();
    let mut seq: u64 = 0;
    loop {
        if let Some(key) = key {
            match read_encrypted_block(&mut reader, key, seq) {
                Ok(Some(entry)) => entries.push(entry),
                Ok(None) => break,
                Err(_) => break, // partial / tampered block — stop cleanly
            }
        } else {
            let mut buf = [0u8; ENTRY_PLAINTEXT_LEN];
            match reader.read_exact(&mut buf) {
                Ok(()) => entries.push(decode_entry(&buf)),
                Err(_) => break,
            }
        }
        seq = seq.saturating_add(1);
    }
    Ok(entries)
}

/// Read one encrypted block. Returns `Ok(None)` on a clean EOF
/// (no length prefix bytes left); `Err` on any partial-read /
/// AEAD-failure mid-block.
fn read_encrypted_block<R: Read>(
    reader: &mut R,
    key: &[u8; 32],
    seq: u64,
) -> Result<Option<IndexEntry>, Error> {
    let mut len_bytes = [0u8; 4];
    match reader.read_exact(&mut len_bytes) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(Error::Recorder(format!("idx block len: {e}"))),
    }
    let pt_len = u32::from_le_bytes(len_bytes) as usize;
    if pt_len != ENTRY_PLAINTEXT_LEN {
        return Err(Error::Recorder(format!(
            "idx block plaintext len {pt_len} (expected {ENTRY_PLAINTEXT_LEN})"
        )));
    }
    let mut nonce = [0u8; NONCE_LEN];
    reader
        .read_exact(&mut nonce)
        .map_err(|e| Error::Recorder(format!("idx block nonce: {e}")))?;
    let mut ct = vec![0u8; pt_len + 16];
    reader
        .read_exact(&mut ct)
        .map_err(|e| Error::Recorder(format!("idx block ct: {e}")))?;
    let aad = seq.to_le_bytes();
    let pt = crypto::aes_gcm_decrypt_raw(key, &nonce, &ct, &aad)
        .map_err(|e| Error::Recorder(format!("idx block decrypt: {e}")))?;
    let pt_arr: [u8; ENTRY_PLAINTEXT_LEN] = pt
        .as_slice()
        .try_into()
        .map_err(|_| Error::Recorder("idx block plaintext size".to_string()))?;
    Ok(Some(decode_entry(&pt_arr)))
}

/// Binary-search the entries for the largest `(offset, ts_ms)` whose
/// `timestamp_ms <= target_ms`. Returns `None` when no entry is at
/// or before `target_ms` (i.e. the target lands before the first
/// recorded event), or when `entries` is empty.
///
/// Pure-function helper used by both [`seek`] and unit tests so the
/// search behaviour is exercised without an on-disk file.
pub fn search(entries: &[IndexEntry], target_ms: u64) -> Option<IndexEntry> {
    if entries.is_empty() {
        return None;
    }
    // partition_point finds the first index where the predicate flips
    // from true to false. Entries with ts_ms <= target stay in the
    // left partition; the largest such entry is at `idx - 1`.
    let idx = entries.partition_point(|e| (e.timestamp_ms as u64) <= target_ms);
    if idx == 0 {
        None
    } else {
        Some(entries[idx - 1])
    }
}

/// Hit returned from [`seek`]: the matched entry plus its position in
/// the sidecar. The position doubles as the AAD frame-index counter
/// the next encrypted frame past `offset` is signed under — every
/// sidecar entry maps to one main-file frame, so entry[i] points at
/// frame i.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SeekHit {
    pub offset: u64,
    pub entry_index: u64,
    pub timestamp_ms: u32,
}

/// High-level seek helper: open the sidecar, walk every entry, binary-
/// search for the largest entry at or before `target_ms`. Returns the
/// matched entry's offset + sidecar entry index, or `None` if no entry
/// qualifies (sidecar missing / empty / target before first event).
pub fn seek(
    recording_path: &Path,
    target_ms: u64,
    encrypted: bool,
    key: Option<&[u8; 32]>,
) -> Result<Option<SeekHit>, Error> {
    let idx_path = sidecar_path(recording_path);
    let entries = if encrypted {
        match key {
            Some(k) => read_all(&idx_path, Some(k))?,
            None => return Ok(None),
        }
    } else {
        read_all(&idx_path, None)?
    };
    if entries.is_empty() {
        return Ok(None);
    }
    let idx = entries.partition_point(|e| (e.timestamp_ms as u64) <= target_ms);
    if idx == 0 {
        return Ok(None);
    }
    let entry = entries[idx - 1];
    Ok(Some(SeekHit {
        offset: entry.offset,
        entry_index: (idx - 1) as u64,
        timestamp_ms: entry.timestamp_ms,
    }))
}
#[cfg(test)]
#[path = "../../tests/unit/recorder_index_sidecar.rs"]
mod tests;
