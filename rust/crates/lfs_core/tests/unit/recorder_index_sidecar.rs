/// Unit tests extracted from recorder/index_sidecar.rs
/// Declared via `#[path] mod tests;` in the source file.
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
