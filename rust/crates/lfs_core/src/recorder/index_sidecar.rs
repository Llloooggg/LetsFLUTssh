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
mod tests {
    use super::*;
    use std::io::Write;

    fn tempfile_path(suffix: &str) -> PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir();
        dir.join(format!("lfs_idx_test_{pid}_{n}_{suffix}"))
    }

    #[test]
    fn sidecar_path_appends_dot_idx() {
        let p = Path::new("/tmp/foo.cast");
        assert_eq!(sidecar_path(p), PathBuf::from("/tmp/foo.cast.idx"));
        let p = Path::new("/tmp/foo.lfsr");
        assert_eq!(sidecar_path(p), PathBuf::from("/tmp/foo.lfsr.idx"));
    }

    #[test]
    fn writer_creates_header_then_appends_plaintext_entries() {
        let p = tempfile_path("plain");
        let mut w = IndexWriter::create(&p, None).expect("create");
        w.append(IndexEntry {
            offset: 100,
            timestamp_ms: 500,
        })
        .unwrap();
        w.append(IndexEntry {
            offset: 200,
            timestamp_ms: 1000,
        })
        .unwrap();
        drop(w);
        let on_disk = std::fs::read(&p).unwrap();
        // 5-byte header + 2 × 12-byte entries.
        assert_eq!(on_disk.len(), 5 + 2 * ENTRY_PLAINTEXT_LEN);
        assert_eq!(&on_disk[..4], &LFI_MAGIC);
        assert_eq!(on_disk[4], LFI_VERSION);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn writer_appends_one_encrypted_block_per_entry() {
        let p = tempfile_path("enc");
        let key = [9u8; 32];
        let mut w = IndexWriter::create(&p, Some(zeroize::Zeroizing::new(key))).unwrap();
        w.append(IndexEntry {
            offset: 100,
            timestamp_ms: 500,
        })
        .unwrap();
        w.append(IndexEntry {
            offset: 200,
            timestamp_ms: 1000,
        })
        .unwrap();
        drop(w);
        let on_disk = std::fs::read(&p).unwrap();
        // 5-byte header + 2 × 44-byte encrypted blocks.
        assert_eq!(on_disk.len(), 5 + 2 * ENCRYPTED_BLOCK_LEN);
        // Length prefix of first block is 12 (plaintext size).
        let first_len = u32::from_le_bytes(on_disk[5..9].try_into().unwrap());
        assert_eq!(first_len as usize, ENTRY_PLAINTEXT_LEN);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_round_trips_plaintext() {
        let p = tempfile_path("rtplain");
        let mut w = IndexWriter::create(&p, None).unwrap();
        let entries = vec![
            IndexEntry {
                offset: 0,
                timestamp_ms: 0,
            },
            IndexEntry {
                offset: 42,
                timestamp_ms: 100,
            },
            IndexEntry {
                offset: 4096,
                timestamp_ms: 5000,
            },
        ];
        for e in &entries {
            w.append(*e).unwrap();
        }
        drop(w);
        let got = read_all(&p, None).unwrap();
        assert_eq!(got, entries);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_round_trips_encrypted_with_correct_key() {
        let p = tempfile_path("rtenc");
        let key = [42u8; 32];
        let mut w = IndexWriter::create(&p, Some(zeroize::Zeroizing::new(key))).unwrap();
        let entries = vec![
            IndexEntry {
                offset: 5,
                timestamp_ms: 1,
            },
            IndexEntry {
                offset: 256,
                timestamp_ms: 250,
            },
            IndexEntry {
                offset: 999_999,
                timestamp_ms: 3600 * 1000,
            },
        ];
        for e in &entries {
            w.append(*e).unwrap();
        }
        drop(w);
        let got = read_all(&p, Some(&key)).unwrap();
        assert_eq!(got, entries);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_with_wrong_key_returns_no_entries() {
        let p = tempfile_path("wrongkey");
        let key_write = [1u8; 32];
        let key_read = [2u8; 32];
        let mut w = IndexWriter::create(&p, Some(zeroize::Zeroizing::new(key_write))).unwrap();
        w.append(IndexEntry {
            offset: 1,
            timestamp_ms: 1,
        })
        .unwrap();
        drop(w);
        // GCM tag mismatch — the reader stops at the first block and
        // returns the entries it had decoded so far (none).
        let got = read_all(&p, Some(&key_read)).unwrap();
        assert!(got.is_empty());
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_returns_empty_when_file_missing() {
        let p = tempfile_path("missing");
        let got = read_all(&p, None).unwrap();
        assert!(got.is_empty());
    }

    #[test]
    fn read_all_returns_empty_when_header_truncated() {
        let p = tempfile_path("trunc");
        std::fs::write(&p, b"LFI").unwrap(); // only 3 of 5 header bytes
        let got = read_all(&p, None).unwrap();
        assert!(got.is_empty());
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_returns_empty_when_header_magic_wrong() {
        let p = tempfile_path("badmagic");
        std::fs::write(&p, b"NOPE\x01").unwrap();
        let got = read_all(&p, None).unwrap();
        assert!(got.is_empty());
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_ignores_dangling_partial_plaintext_entry() {
        // Simulate a crash-mid-append: well-formed header + one full
        // entry + half of a second entry. Reader must yield the one
        // complete entry and stop without erroring.
        let p = tempfile_path("danglepart");
        let mut f = File::create(&p).unwrap();
        f.write_all(&LFI_MAGIC).unwrap();
        f.write_all(&[LFI_VERSION]).unwrap();
        let entry = IndexEntry {
            offset: 100,
            timestamp_ms: 50,
        };
        f.write_all(&encode_entry(entry)).unwrap();
        f.write_all(&[0xAA, 0xBB, 0xCC]).unwrap(); // 3 dangling bytes
        drop(f);
        let got = read_all(&p, None).unwrap();
        assert_eq!(got, vec![entry]);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn read_all_ignores_dangling_partial_encrypted_block() {
        let p = tempfile_path("dangleenc");
        let key = [7u8; 32];
        let mut w = IndexWriter::create(&p, Some(zeroize::Zeroizing::new(key))).unwrap();
        w.append(IndexEntry {
            offset: 100,
            timestamp_ms: 50,
        })
        .unwrap();
        drop(w);
        // Append a few stray bytes — half a length prefix.
        let mut f = OpenOptions::new().append(true).open(&p).unwrap();
        f.write_all(&[0x0C, 0x00]).unwrap();
        drop(f);
        let got = read_all(&p, Some(&key)).unwrap();
        assert_eq!(got.len(), 1);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn search_returns_largest_entry_at_or_below_target() {
        let entries = vec![
            IndexEntry {
                offset: 0,
                timestamp_ms: 0,
            },
            IndexEntry {
                offset: 100,
                timestamp_ms: 1000,
            },
            IndexEntry {
                offset: 200,
                timestamp_ms: 2000,
            },
            IndexEntry {
                offset: 300,
                timestamp_ms: 3000,
            },
        ];
        // Exact hits.
        assert_eq!(
            search(&entries, 0),
            Some(IndexEntry {
                offset: 0,
                timestamp_ms: 0
            })
        );
        assert_eq!(
            search(&entries, 2000),
            Some(IndexEntry {
                offset: 200,
                timestamp_ms: 2000
            })
        );
        // In between — must return the one BEFORE the gap.
        assert_eq!(
            search(&entries, 1500),
            Some(IndexEntry {
                offset: 100,
                timestamp_ms: 1000
            })
        );
        // After the last entry — returns the last entry.
        assert_eq!(
            search(&entries, 9999),
            Some(IndexEntry {
                offset: 300,
                timestamp_ms: 3000
            })
        );
    }

    #[test]
    fn search_returns_none_when_target_before_first_entry() {
        let entries = vec![IndexEntry {
            offset: 100,
            timestamp_ms: 500,
        }];
        assert!(search(&entries, 100).is_none());
    }

    #[test]
    fn search_returns_none_on_empty_entries() {
        assert!(search(&[], 1234).is_none());
    }

    #[test]
    fn seek_returns_offset_via_sidecar_lookup() {
        let main = tempfile_path("seekmain");
        // Touch the main file so seek doesn't reject on its absence
        // (sidecar uses `<main>.idx` — main existence is unrelated to
        // the lookup, but build the realistic pair anyway).
        std::fs::write(&main, b"").unwrap();
        let idx = sidecar_path(&main);
        let mut w = IndexWriter::create(&idx, None).unwrap();
        w.append(IndexEntry {
            offset: 0,
            timestamp_ms: 0,
        })
        .unwrap();
        w.append(IndexEntry {
            offset: 512,
            timestamp_ms: 1000,
        })
        .unwrap();
        w.append(IndexEntry {
            offset: 1024,
            timestamp_ms: 2000,
        })
        .unwrap();
        drop(w);
        let hit = seek(&main, 1500, false, None).unwrap().unwrap();
        assert_eq!(hit.offset, 512);
        assert_eq!(hit.entry_index, 1);
        assert_eq!(hit.timestamp_ms, 1000);
        let hit_late = seek(&main, 3000, false, None).unwrap().unwrap();
        assert_eq!(hit_late.offset, 1024);
        assert_eq!(hit_late.entry_index, 2);
        let _ = std::fs::remove_file(&main);
        let _ = std::fs::remove_file(&idx);
    }

    #[test]
    fn seek_returns_none_when_sidecar_missing() {
        let main = tempfile_path("seeknosidecar");
        std::fs::write(&main, b"").unwrap();
        assert!(seek(&main, 1000, false, None).unwrap().is_none());
        let _ = std::fs::remove_file(&main);
    }

    #[test]
    fn seek_returns_none_when_sidecar_header_only() {
        let main = tempfile_path("seekemptysidecar");
        std::fs::write(&main, b"").unwrap();
        let idx = sidecar_path(&main);
        // Empty sidecar (header only) → no entries.
        let w = IndexWriter::create(&idx, None).unwrap();
        drop(w);
        assert!(seek(&main, 1000, false, None).unwrap().is_none());
        let _ = std::fs::remove_file(&main);
        let _ = std::fs::remove_file(&idx);
    }

    #[test]
    fn seek_encrypted_requires_key() {
        let main = tempfile_path("seekencnokey");
        std::fs::write(&main, b"").unwrap();
        // `encrypted=true` with `key=None` short-circuits to None
        // before any disk access.
        assert!(seek(&main, 1000, true, None).unwrap().is_none());
        let _ = std::fs::remove_file(&main);
    }

    /// Encrypted-block AAD binding regression: swap two blocks on disk
    /// and verify the reader stops at the first one rather than
    /// silently yielding the swapped payload at the wrong position.
    #[test]
    fn encrypted_block_swap_invalidates_aad_chain() {
        let p = tempfile_path("encswap");
        let key = [5u8; 32];
        let mut w = IndexWriter::create(&p, Some(zeroize::Zeroizing::new(key))).unwrap();
        w.append(IndexEntry {
            offset: 100,
            timestamp_ms: 50,
        })
        .unwrap();
        w.append(IndexEntry {
            offset: 200,
            timestamp_ms: 150,
        })
        .unwrap();
        drop(w);

        // Layout: 5-byte header + two 44-byte blocks.
        let mut bytes = std::fs::read(&p).unwrap();
        let block_a = bytes[5..5 + ENCRYPTED_BLOCK_LEN].to_vec();
        let block_b = bytes[5 + ENCRYPTED_BLOCK_LEN..5 + 2 * ENCRYPTED_BLOCK_LEN].to_vec();
        bytes.truncate(5);
        bytes.extend_from_slice(&block_b);
        bytes.extend_from_slice(&block_a);
        std::fs::write(&p, &bytes).unwrap();

        // Position 0 now holds block_b's ciphertext signed under AAD=1,
        // but the reader recomputes AAD=0 → tag mismatch → reader
        // stops and yields zero entries.
        let got = read_all(&p, Some(&key)).unwrap();
        assert!(got.is_empty());
        let _ = std::fs::remove_file(&p);
    }
}
