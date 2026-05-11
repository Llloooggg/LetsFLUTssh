//! Disk-cap enforcement for the recordings tree.
//!
//! The recorder writes to `<app_support>/recordings/<sessionId>/...`
//! without any global byte ceiling — long-running installs would
//! grow the tree without bound until the user noticed via the OS
//! "low disk space" warning. This module owns the LRU eviction
//! sweep that keeps the tree at or below
//! [`crate::config::AppConfig::recordings_storage_cap_bytes`].
//!
//! Tree shape is one nested level deep:
//! `<recordings_root>/<sessionId>/<isoTimestamp>.<lfsr|cast>`. The
//! walk lists every file under `<recordings_root>/<sessionId>/`
//! and ignores anything else (symlinks, sub-sub-directories,
//! unrelated files dropped under root by hand).
//!
//! **Eviction order — oldest mtime first.** A file whose
//! `metadata.modified()` errors sorts as the oldest (treat unknown
//! mtime as "delete first"); that way a filesystem with broken
//! timestamps still converges instead of refusing to evict any
//! entry. Files whose path matches an `active_paths` entry are
//! always skipped — the currently-writing recording must not
//! disappear from under the registry actor's file handle.
//!
//! Total size sums regular-file bytes only — directory entries
//! themselves do not count, and a per-entry stat failure during
//! the walk is swallowed best-effort so a single broken row
//! doesn't sink the whole sweep.
//!
//! Defence-in-depth pairs with the per-file cap in
//! [`super::MAX_FILE_BYTES`]: the per-file cap stops a single
//! pathological recording from ballooning past 100 MiB, this
//! module bounds the aggregate across every recording the user
//! kept.

use std::path::{Path, PathBuf};
use std::time::SystemTime;

use crate::error::Error;

/// Outcome of one [`enforce_storage_cap`] call. `used_after` is the
/// bytes-on-disk total after eviction completes; callers compare
/// against the cap to decide whether to log a "could not reach cap"
/// warning (would only happen when every remaining candidate is in
/// `active_paths`, i.e. the live recordings alone exceed the cap).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EvictionOutcome {
    pub files_evicted: u32,
    pub bytes_reclaimed: u64,
    pub used_after: u64,
}

/// Walk `<recordings_root>/<sessionId>/*` and sum the byte total
/// of every regular file (any extension). A missing root is not an
/// error — `Ok(0)` so a fresh install (recorder never used) still
/// reports a coherent figure for the Settings tile and the sweep
/// itself.
///
/// Per-entry stat failures during the walk are swallowed
/// best-effort — a single broken row does not sink the whole
/// total. The same invariant applies to [`enforce_storage_cap`],
/// where eviction also stays best-effort on per-file faults.
pub fn storage_used(recordings_root: &Path) -> Result<u64, Error> {
    let entries = collect_entries(recordings_root)?;
    Ok(entries.iter().map(|e| e.size_bytes).sum())
}

/// Enforce `cap_bytes` against the recordings tree by deleting
/// files in oldest-mtime order until the running total drops at
/// or below the cap. Files whose paths match an `active_paths`
/// entry are skipped — the registry's live recording handles must
/// never have their backing file unlinked. The loop bails when
/// either the total is back under the cap or no eligible
/// candidate remains; in the latter case `used_after` may still
/// exceed `cap_bytes` (the live recordings alone are over budget).
///
/// Per-file `remove_file` errors are logged but do not abort the
/// sweep — a perm-denied unlink moves on to the next candidate so
/// one stuck row doesn't peg the cap forever.
pub fn enforce_storage_cap(
    recordings_root: &Path,
    cap_bytes: u64,
    active_paths: &[PathBuf],
) -> Result<EvictionOutcome, Error> {
    let mut entries = collect_entries(recordings_root)?;
    let mut used: u64 = entries.iter().map(|e| e.size_bytes).sum();
    let mut files_evicted: u32 = 0;
    let mut bytes_reclaimed: u64 = 0;

    if used <= cap_bytes {
        return Ok(EvictionOutcome {
            files_evicted,
            bytes_reclaimed,
            used_after: used,
        });
    }

    // Oldest-first: unknown mtime sorts ahead of every known
    // timestamp so a row with a stat-broken modified() goes out
    // before a row with a valid 1970 mtime. Same direction either
    // way — keep the rule explicit so the comparator stays
    // greppable.
    entries.sort_by(|a, b| match (a.mtime, b.mtime) {
        (None, None) => std::cmp::Ordering::Equal,
        (None, Some(_)) => std::cmp::Ordering::Less,
        (Some(_), None) => std::cmp::Ordering::Greater,
        (Some(x), Some(y)) => x.cmp(&y),
    });

    for entry in entries {
        if used <= cap_bytes {
            break;
        }
        if active_paths.iter().any(|p| paths_equal(p, &entry.path)) {
            continue;
        }
        match std::fs::remove_file(&entry.path) {
            Ok(()) => {
                used = used.saturating_sub(entry.size_bytes);
                bytes_reclaimed = bytes_reclaimed.saturating_add(entry.size_bytes);
                files_evicted = files_evicted.saturating_add(1);
            }
            Err(e) => {
                crate::app_log_warn!(
                    "RecorderStorageCap",
                    "evict {} failed, skipping: {e}",
                    entry.path.display()
                );
            }
        }
    }

    Ok(EvictionOutcome {
        files_evicted,
        bytes_reclaimed,
        used_after: used,
    })
}

/// Delete every recording file under `recordings_root` (current
/// plus every per-session sub-directory). Files whose paths
/// match an `active_paths` entry are skipped — the registry's
/// live recording handles must keep their backing file on disk
/// until the actor closes. Returns the count of files actually
/// removed.
///
/// Per-file `remove_file` errors are logged but do not abort the
/// sweep, mirroring [`enforce_storage_cap`].
pub fn clear_all(recordings_root: &Path, active_paths: &[PathBuf]) -> Result<u32, Error> {
    let entries = collect_entries(recordings_root)?;
    let mut removed: u32 = 0;
    for entry in entries {
        if active_paths.iter().any(|p| paths_equal(p, &entry.path)) {
            continue;
        }
        match std::fs::remove_file(&entry.path) {
            Ok(()) => removed = removed.saturating_add(1),
            Err(e) => {
                crate::app_log_warn!(
                    "RecorderStorageCap",
                    "clear {} failed, skipping: {e}",
                    entry.path.display()
                );
            }
        }
    }
    Ok(removed)
}

#[derive(Debug)]
struct WalkedEntry {
    path: PathBuf,
    size_bytes: u64,
    /// `None` when the entry's `metadata.modified()` returned an
    /// error. Sort routine treats unknown as "delete first" so a
    /// filesystem with broken timestamps still converges.
    mtime: Option<SystemTime>,
}

/// Walk `<recordings_root>/<sessionId>/*` and return one
/// [`WalkedEntry`] per regular file. Missing root collapses to
/// `Ok(vec![])` for the fresh-install case. Per-entry stat
/// failures are swallowed.
fn collect_entries(recordings_root: &Path) -> Result<Vec<WalkedEntry>, Error> {
    let mut out = Vec::new();
    let session_iter = match std::fs::read_dir(recordings_root) {
        Ok(it) => it,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(out),
        Err(e) => {
            return Err(Error::Io(format!(
                "read_dir {}: {e}",
                recordings_root.display()
            )))
        }
    };
    for session_entry in session_iter.flatten() {
        let session_path = session_entry.path();
        // symlink_metadata: a symlink at <root>/<dir> pointing
        // outside the recordings tree must NOT be traversed.
        // Matches the browser's defence-in-depth posture.
        let Ok(session_meta) = std::fs::symlink_metadata(&session_path) else {
            continue;
        };
        if !session_meta.file_type().is_dir() {
            continue;
        }
        let Ok(inner_iter) = std::fs::read_dir(&session_path) else {
            continue;
        };
        for file_entry in inner_iter.flatten() {
            let file_path = file_entry.path();
            let Ok(file_meta) = std::fs::symlink_metadata(&file_path) else {
                continue;
            };
            if !file_meta.file_type().is_file() {
                continue;
            }
            out.push(WalkedEntry {
                path: file_path,
                size_bytes: file_meta.len(),
                mtime: file_meta.modified().ok(),
            });
        }
    }
    Ok(out)
}

/// Cross-platform path equality. `Path::eq` already does the right
/// thing on Unix; on Windows a symbolic equal-by-canonical check
/// would matter, but the only callers compare paths the recorder
/// itself produced (registry-owned for `active_paths`, walk-owned
/// for entries) and both are built off the same `recordings_root`
/// — no canonicalisation drift. Pinning the comparator into one
/// helper lets a future canonical-path upgrade land in one place.
fn paths_equal(a: &Path, b: &Path) -> bool {
    a == b
}

#[cfg(test)]
mod tests {
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
}
