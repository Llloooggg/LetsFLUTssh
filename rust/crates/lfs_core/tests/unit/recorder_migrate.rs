//! Unit tests extracted from recorder/migrate.rs
//!
//! Declared via `#[path] mod tests;` in the source file.

use super::*;

use crate::bus::EventBus;
use crate::recorder::{RecordDirection, RecorderRegistry};
use std::sync::atomic::{AtomicU64, Ordering};

fn fresh_recordings_root(tag: &str) -> PathBuf {
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let pid = std::process::id();
    let dir = std::env::temp_dir().join(format!("lfs_mig_test_{tag}_{pid}_{n}"));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Build one real .lfsr + sidecar under `<root>/<session>/<id>.lfsr`
/// driven through the live writer so the header, frame layout, and
/// sidecar chain match a production recording byte-for-byte.
fn record_one(root: &Path, session: &str, db_key: &[u8; 32], events: &[(&str, &str)]) -> PathBuf {
    let session_dir = root.join(session);
    std::fs::create_dir_all(&session_dir).unwrap();
    let file_path = session_dir.join(format!("rec-{}.lfsr", session));
    let bus = EventBus::new();
    let reg = RecorderRegistry::new();
    let id = format!("r-{session}");
    reg.register_with_io(
        id.clone(),
        session.to_string(),
        file_path.to_string_lossy().into_owned(),
        Some(zeroize::Zeroizing::new(*db_key)),
        &bus,
    )
    .unwrap();
    // Asciinema header is required for the lfsr → cast helper's
    // smoke checks (line 0 starts with `{"version":2`), and the
    // rewrap round-trip test counts records including the
    // header — emit it here so both call sites match real
    // recordings byte-for-byte.
    reg.record_header(&id, 80, 24, "/bin/bash", &bus).unwrap();
    for (dir, payload) in events {
        let direction = match *dir {
            "o" => RecordDirection::Output,
            "i" => RecordDirection::Input,
            _ => unreachable!(),
        };
        reg.record_event(&id, direction, payload.as_bytes(), &bus)
            .unwrap();
    }
    reg.close_with_io(&id, &bus).unwrap();
    file_path
}

#[test]
fn rewrap_all_headers_round_trips_under_new_key() {
    let root = fresh_recordings_root("rewrap");
    let old_db = [0x11u8; 32];
    let new_db = [0x22u8; 32];
    let p = record_one(&root, "s1", &old_db, &[("o", "hello"), ("i", "q")]);

    // Before rewrap the file unwraps under the OLD key, not new.
    let before = std::fs::read(&p).unwrap();
    assert!(super::super::unwrap_lfsr_header(&before[..LFR_HEADER_LEN], &old_db).is_ok());
    assert!(super::super::unwrap_lfsr_header(&before[..LFR_HEADER_LEN], &new_db).is_err());

    let outcome = rewrap_all_headers(&root, &old_db, &new_db).unwrap();
    assert_eq!(outcome.headers_rewrapped, 1);
    assert_eq!(outcome.skipped, 0);

    // After rewrap the file unwraps under the NEW key, not old.
    let after = std::fs::read(&p).unwrap();
    assert!(super::super::unwrap_lfsr_header(&after[..LFR_HEADER_LEN], &new_db).is_ok());
    assert!(super::super::unwrap_lfsr_header(&after[..LFR_HEADER_LEN], &old_db).is_err());

    // Frame bodies are byte-identical past the 65-byte header.
    assert_eq!(after.len(), before.len());
    assert_eq!(&after[LFR_HEADER_LEN..], &before[LFR_HEADER_LEN..]);

    // Re-running the rewrap with the same pair is a no-op —
    // headers already on the new key. Idempotency.
    let outcome2 = rewrap_all_headers(&root, &old_db, &new_db).unwrap();
    assert_eq!(outcome2.headers_rewrapped, 0);
    assert_eq!(outcome2.skipped, 1);

    // Playback still works under the new key.
    let iter = super::super::reader::open_lfsr_iter(&p, new_db).unwrap();
    let lines: Vec<_> = iter.map(|r| r.unwrap()).collect();
    // asciinema header + 2 events.
    assert_eq!(lines.len(), 3);

    std::fs::remove_dir_all(&root).ok();
}

#[test]
fn rewrap_skips_files_under_wrong_old_key() {
    let root = fresh_recordings_root("skip-wrong");
    let real_db = [0x77u8; 32];
    let wrong_db = [0x88u8; 32];
    let new_db = [0x99u8; 32];
    record_one(&root, "s1", &real_db, &[("o", "ping")]);
    // Walking with the wrong "old" key: every unwrap fails, so
    // every file should be skipped — not corrupted, not
    // rewrapped under a key the user did not authorize.
    let outcome = rewrap_all_headers(&root, &wrong_db, &new_db).unwrap();
    assert_eq!(outcome.headers_rewrapped, 0);
    assert_eq!(outcome.skipped, 1);
    std::fs::remove_dir_all(&root).ok();
}

#[test]
fn convert_cast_to_lfsr_round_trips_under_new_key() {
    let root = fresh_recordings_root("c2l");
    let new_db = [0x44u8; 32];
    let session_dir = root.join("s1");
    std::fs::create_dir_all(&session_dir).unwrap();
    let cast_path = session_dir.join("rec.cast");
    let body =
        "{\"version\":2,\"width\":80,\"height\":24}\n[0.1,\"o\",\"hi\"]\n[0.5,\"i\",\"q\"]\n";
    std::fs::write(&cast_path, body).unwrap();

    let outcome = convert_all_cast_to_lfsr(&root, &new_db).unwrap();
    assert_eq!(outcome.cast_to_lfsr, 1);
    let lfsr_path = session_dir.join("rec.lfsr");
    assert!(lfsr_path.exists());
    assert!(!cast_path.exists());

    // Playback yields the original lines under the new DB key.
    let iter = super::super::reader::open_lfsr_iter(&lfsr_path, new_db).unwrap();
    let lines: Vec<_> = iter.map(|r| r.unwrap()).collect();
    assert_eq!(
        lines,
        vec![
            "{\"version\":2,\"width\":80,\"height\":24}".to_string(),
            "[0.1,\"o\",\"hi\"]".to_string(),
            "[0.5,\"i\",\"q\"]".to_string(),
        ]
    );

    std::fs::remove_dir_all(&root).ok();
}

#[test]
fn convert_lfsr_to_cast_round_trips_to_plaintext() {
    let root = fresh_recordings_root("l2c");
    let db = [0x55u8; 32];
    let lfsr_path = record_one(&root, "s1", &db, &[("o", "alpha"), ("o", "beta")]);

    let outcome = convert_all_lfsr_to_cast(&root, &db).unwrap();
    assert_eq!(outcome.lfsr_to_cast, 1);
    let cast_path = lfsr_path.with_extension("cast");
    assert!(cast_path.exists());
    assert!(!lfsr_path.exists());

    // .cast is plain asciinema JSON-Lines.
    let cast_body = std::fs::read_to_string(&cast_path).unwrap();
    let lines: Vec<_> = cast_body.lines().collect();
    // Header object + 2 event tuples.
    assert!(lines[0].starts_with("{\"version\":2"));
    assert!(lines[1].contains("\"o\""));
    assert!(lines[1].contains("alpha"));
    assert!(lines[2].contains("beta"));

    std::fs::remove_dir_all(&root).ok();
}

#[test]
fn round_trip_cast_lfsr_cast_preserves_event_payloads() {
    // T0 → T1 → T0: starts plaintext, encrypted under DB key,
    // back to plaintext. The frame payloads must match across
    // the two cast files byte-for-byte (modulo header which
    // the recorder produces fresh).
    let root = fresh_recordings_root("round");
    let db = [0x66u8; 32];
    let session_dir = root.join("s1");
    std::fs::create_dir_all(&session_dir).unwrap();
    let cast_path = session_dir.join("rec.cast");
    let original_body =
        "{\"version\":2,\"width\":80,\"height\":24}\n[0.1,\"o\",\"hi\"]\n[0.5,\"i\",\"q\"]\n";
    std::fs::write(&cast_path, original_body).unwrap();

    convert_all_cast_to_lfsr(&root, &db).unwrap();
    assert!(session_dir.join("rec.lfsr").exists());
    convert_all_lfsr_to_cast(&root, &db).unwrap();
    let final_body = std::fs::read_to_string(&cast_path).unwrap();

    // The asciinema events round-trip exactly; the header line
    // might differ in numeric precision so just smoke-check the
    // event tuples.
    let final_lines: Vec<&str> = final_body.lines().collect();
    assert!(final_lines[1].contains("\"o\""));
    assert!(final_lines[1].contains("hi"));
    assert!(final_lines[2].contains("\"i\""));
    assert!(final_lines[2].contains("q"));

    std::fs::remove_dir_all(&root).ok();
}

#[test]
fn rewrap_missing_root_returns_empty_outcome() {
    let root = std::env::temp_dir().join(format!("lfs_mig_missing_{}", std::process::id()));
    let outcome = rewrap_all_headers(&root, &[0u8; 32], &[1u8; 32]).unwrap();
    assert_eq!(outcome, MigrateOutcome::default());
}
