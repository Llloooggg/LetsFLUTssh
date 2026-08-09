/// Unit tests extracted from recorder/storage_cap.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::fs;
use std::io::Write;
use std::time::{Duration, SystemTime};
use tempfile::TempDir;

/// Seed a recording file at `<root>/<session>/<name>` with the
/// given payload bytes + adjust the mtime so the eviction sort
/// has deterministic ordering. mtime is set via the std
/// `File::set_modified` (Rust 1.75+; toolchain pins 1.85).
fn seed_file(root: &Path, session: &str, name: &str, payload: &[u8], mtime: SystemTime) {
    let session_dir = root.join(session);
    fs::create_dir_all(&session_dir).unwrap();
    let path = session_dir.join(name);
    let mut f = fs::File::create(&path).unwrap();
    f.write_all(payload).unwrap();
    f.sync_all().unwrap();
    let f = fs::File::options().write(true).open(&path).unwrap();
    f.set_modified(mtime).unwrap();
}

fn anchor() -> SystemTime {
    // 2020-01-01ish — far enough above zero that earlier-test
    // seeds can subtract days without clipping into the Unix
    // epoch.
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_577_836_800)
}

#[test]
fn storage_used_sums_files_in_root_and_subdirs() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    seed_file(&root, "sess-a", "1.lfsr", &[0u8; 100], anchor());
    seed_file(&root, "sess-a", "2.cast", &[0u8; 50], anchor());
    seed_file(&root, "sess-b", "3.lfsr", &[0u8; 200], anchor());
    let used = storage_used(&root).unwrap();
    assert_eq!(used, 350);
}

#[test]
fn storage_used_is_zero_on_empty_root() {
    let dir = TempDir::new().unwrap();
    // Root does not exist — fresh-install path.
    let missing = dir.path().join("not-there");
    assert_eq!(storage_used(&missing).unwrap(), 0);
    // Root exists but empty — recorder created the dir on a
    // prior run that never produced output.
    let empty = dir.path().join("empty");
    fs::create_dir_all(&empty).unwrap();
    assert_eq!(storage_used(&empty).unwrap(), 0);
}

#[test]
fn enforce_below_cap_is_noop() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    seed_file(&root, "sess-a", "1.lfsr", &[0u8; 100], anchor());
    let out = enforce_storage_cap(&root, 1_000, &[]).unwrap();
    assert_eq!(out.files_evicted, 0);
    assert_eq!(out.bytes_reclaimed, 0);
    assert_eq!(out.used_after, 100);
    // File still on disk.
    assert!(root.join("sess-a").join("1.lfsr").exists());
}

#[test]
fn enforce_evicts_oldest_first() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    let base = anchor();
    // Three files of 100 bytes each. mtimes: t0 (oldest), t1,
    // t2 (newest). Cap at 150 — the loop must evict t0 + t1 to
    // get under the cap, leaving t2 intact.
    seed_file(&root, "sess-a", "old.lfsr", &[0u8; 100], base);
    seed_file(
        &root,
        "sess-a",
        "mid.lfsr",
        &[0u8; 100],
        base + Duration::from_secs(60),
    );
    seed_file(
        &root,
        "sess-a",
        "new.lfsr",
        &[0u8; 100],
        base + Duration::from_secs(120),
    );
    let out = enforce_storage_cap(&root, 150, &[]).unwrap();
    assert_eq!(out.files_evicted, 2);
    assert_eq!(out.bytes_reclaimed, 200);
    assert_eq!(out.used_after, 100);
    assert!(!root.join("sess-a").join("old.lfsr").exists());
    assert!(!root.join("sess-a").join("mid.lfsr").exists());
    assert!(root.join("sess-a").join("new.lfsr").exists());
}

#[test]
fn enforce_skips_active_paths_even_when_oldest() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    let base = anchor();
    // The oldest file is also the live one — the sweep must
    // skip it and evict the next-oldest instead.
    let live_path = root.join("sess-a").join("live.lfsr");
    seed_file(&root, "sess-a", "live.lfsr", &[0u8; 100], base);
    seed_file(
        &root,
        "sess-a",
        "mid.lfsr",
        &[0u8; 100],
        base + Duration::from_secs(60),
    );
    seed_file(
        &root,
        "sess-a",
        "new.lfsr",
        &[0u8; 100],
        base + Duration::from_secs(120),
    );
    let out = enforce_storage_cap(&root, 150, std::slice::from_ref(&live_path)).unwrap();
    // Strict LRU: skip the active row when it comes up as the
    // oldest candidate, keep walking. Both mid and new are
    // eligible and removable; the sweep stops once used drops
    // to or below the cap. Live survives the cap-bust because
    // it is the only file the recorder is still writing.
    assert_eq!(out.files_evicted, 2);
    assert_eq!(out.bytes_reclaimed, 200);
    assert_eq!(out.used_after, 100);
    assert!(live_path.exists());
    assert!(!root.join("sess-a").join("mid.lfsr").exists());
    assert!(!root.join("sess-a").join("new.lfsr").exists());
}

#[test]
fn enforce_stops_at_cap_does_not_overshoot() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    let base = anchor();
    // Four 100-byte files, cap 250. Must evict oldest two to
    // hit 200 (under 250); the third-oldest stays even though
    // continuing to evict would shrink the total further.
    for (i, name) in ["a", "b", "c", "d"].iter().enumerate() {
        seed_file(
            &root,
            "sess",
            &format!("{name}.lfsr"),
            &[0u8; 100],
            base + Duration::from_secs(60 * i as u64),
        );
    }
    let out = enforce_storage_cap(&root, 250, &[]).unwrap();
    assert_eq!(out.files_evicted, 2);
    assert_eq!(out.used_after, 200);
    assert!(!root.join("sess").join("a.lfsr").exists());
    assert!(!root.join("sess").join("b.lfsr").exists());
    assert!(root.join("sess").join("c.lfsr").exists());
    assert!(root.join("sess").join("d.lfsr").exists());
}

#[test]
fn clear_all_removes_every_file() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    seed_file(&root, "sess-a", "1.lfsr", &[0u8; 100], anchor());
    seed_file(&root, "sess-a", "2.cast", &[0u8; 100], anchor());
    seed_file(&root, "sess-b", "3.lfsr", &[0u8; 100], anchor());
    let removed = clear_all(&root, &[]).unwrap();
    assert_eq!(removed, 3);
    assert_eq!(storage_used(&root).unwrap(), 0);
}

#[test]
fn clear_all_respects_active_paths() {
    let dir = TempDir::new().unwrap();
    let root = dir.path().join("recordings");
    let live = root.join("sess-a").join("live.lfsr");
    seed_file(&root, "sess-a", "live.lfsr", &[0u8; 100], anchor());
    seed_file(&root, "sess-a", "old.lfsr", &[0u8; 100], anchor());
    let removed = clear_all(&root, std::slice::from_ref(&live)).unwrap();
    assert_eq!(removed, 1);
    assert!(live.exists());
    assert!(!root.join("sess-a").join("old.lfsr").exists());
}
