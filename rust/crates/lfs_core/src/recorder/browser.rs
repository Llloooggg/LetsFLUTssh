//! Filesystem-side recordings browser. Owns the disk walk +
//! delete the Dart `RecordingsPanel` drives over FRB.
//!
//! Tree shape: `<recordings_root>/<sessionId>/<isoTimestamp>.<lfsr|cast>`.
//! The walk lists every immediate child of every session dir,
//! filters to the two recording extensions, and skips anything
//! that is not a regular file (directories, symlinks, sockets,
//! …) — `symlink_metadata` is used so a symlink planted under
//! the recordings tree never resolves to a target outside it.
//!
//! Delete is path-component-checked: the caller hands in
//! `session_id` + `file_name` and the helper rejects either
//! containing `..` or a path separator. Defence-in-depth — the
//! UI only ever passes basenames it read out of [`list_recordings`],
//! but a future caller threading a tainted string through the
//! FRB boundary cannot escape the recordings tree.

use std::path::Path;
use std::time::SystemTime;

/// Per-recording metadata yielded by [`list_recordings`]: filename,
/// owning session, byte size, mtime, encryption flag, extension.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecordingEntry {
    pub session_id: String,
    pub file_name: String,
    pub extension: String,
    pub size_bytes: u64,
    pub mtime_unix_secs: i64,
    pub encrypted: bool,
}

/// Errors the delete path can surface. List walks return
/// `std::io::Error` directly — a missing recordings root is not
/// an error (see [`list_recordings`]); other IO faults bubble up
/// as `Io`.
#[derive(Debug)]
pub enum BrowserError {
    Io(std::io::Error),
    /// `session_id` or `file_name` contained `..` or a path
    /// separator. The component is rejected before any
    /// filesystem call, so a tainted input never touches disk.
    InvalidComponent,
}

impl std::fmt::Display for BrowserError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BrowserError::Io(e) => write!(f, "io: {e}"),
            BrowserError::InvalidComponent => {
                write!(f, "invalid recording path component")
            }
        }
    }
}

impl std::error::Error for BrowserError {}

impl From<std::io::Error> for BrowserError {
    fn from(e: std::io::Error) -> Self {
        BrowserError::Io(e)
    }
}

/// Walk `<recordings_root>/<sessionId>/<file>` and return one
/// [`RecordingEntry`] per `.cast` / `.lfsr` regular file.
///
/// A missing root is not an error — `Ok(vec![])` so a fresh
/// install with the recorder never used can still render the
/// (empty) browser. Per-entry errors during the walk are
/// swallowed with a best-effort posture: a single corrupt
/// session dir does not sink the whole list.
///
/// Order: filesystem-iteration order. The Dart caller sorts by
/// mtime descending after receiving the vec so the ordering
/// contract stays visible at the surface the user sees.
pub fn list_recordings(recordings_root: &Path) -> std::io::Result<Vec<RecordingEntry>> {
    let mut out = Vec::new();
    let session_iter = match std::fs::read_dir(recordings_root) {
        Ok(it) => it,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(out),
        Err(e) => return Err(e),
    };
    for session_entry in session_iter.flatten() {
        let session_path = session_entry.path();
        // Use symlink_metadata — a symlink at <root>/<dir> would
        // otherwise route through to whatever it points at. We
        // want session dirs only, real ones.
        let Ok(session_meta) = std::fs::symlink_metadata(&session_path) else {
            continue;
        };
        if !session_meta.file_type().is_dir() {
            continue;
        }
        let Some(session_id) = session_path.file_name().and_then(|s| s.to_str()) else {
            continue;
        };
        let session_id = session_id.to_string();
        let Ok(inner_iter) = std::fs::read_dir(&session_path) else {
            continue;
        };
        for file_entry in inner_iter.flatten() {
            let file_path = file_entry.path();
            let Ok(file_meta) = std::fs::symlink_metadata(&file_path) else {
                continue;
            };
            // Real regular files only — symlinks (which
            // symlink_metadata reports as Symlink, not File) and
            // directories are skipped.
            if !file_meta.file_type().is_file() {
                continue;
            }
            let Some(file_name) = file_path.file_name().and_then(|s| s.to_str()) else {
                continue;
            };
            let ext_lower = file_path
                .extension()
                .and_then(|e| e.to_str())
                .map(|s| s.to_ascii_lowercase())
                .unwrap_or_default();
            if ext_lower != "cast" && ext_lower != "lfsr" {
                continue;
            }
            let mtime_unix_secs = file_meta
                .modified()
                .ok()
                .and_then(systime_to_unix_secs)
                .unwrap_or(0);
            out.push(RecordingEntry {
                session_id: session_id.clone(),
                file_name: file_name.to_string(),
                extension: ext_lower.clone(),
                size_bytes: file_meta.len(),
                mtime_unix_secs,
                encrypted: ext_lower == "lfsr",
            });
        }
    }
    Ok(out)
}

/// Delete `<recordings_root>/<session_id>/<file_name>`.
///
/// Path-component invariant: neither component may contain `..`
/// or a path separator (`/` or `\`). The helper rejects with
/// [`BrowserError::InvalidComponent`] before issuing any
/// filesystem call — a hostile or tainted value can never escape
/// the recordings tree.
///
/// Idempotent on a missing target — `NotFound` returns `Ok(())`
/// so a stale Dart-side cache that requests an already-deleted
/// row does not surface a confusing error to the user. Other IO
/// errors (permission denied, IO timeout) propagate as
/// [`BrowserError::Io`].
pub fn delete_recording(
    recordings_root: &Path,
    session_id: &str,
    file_name: &str,
) -> Result<(), BrowserError> {
    if !is_safe_component(session_id) || !is_safe_component(file_name) {
        return Err(BrowserError::InvalidComponent);
    }
    let path = recordings_root.join(session_id).join(file_name);
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(BrowserError::Io(e)),
    }
}

/// Component check shared by [`delete_recording`]. A safe
/// component is non-empty, contains no `/` or `\`, and is not
/// equal to `.` or `..`. Rejects anything that could escape the
/// joined parent or sidestep a nested-directory invariant.
fn is_safe_component(s: &str) -> bool {
    !s.is_empty() && s != "." && s != ".." && !s.contains('/') && !s.contains('\\')
}

fn systime_to_unix_secs(t: SystemTime) -> Option<i64> {
    match t.duration_since(SystemTime::UNIX_EPOCH) {
        Ok(d) => i64::try_from(d.as_secs()).ok(),
        // Pre-1970 mtimes are vanishingly rare in practice; treat
        // them as "0" so the surface stays sortable.
        Err(_) => Some(0),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;

    fn temp_root(suffix: &str) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("lfs_browser_test_{pid}_{n}_{suffix}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn list_returns_empty_when_root_missing() {
        let nonexistent = std::env::temp_dir().join("lfs_browser_test_does_not_exist_xyz");
        let _ = fs::remove_dir_all(&nonexistent);
        let out = list_recordings(&nonexistent).expect("missing root is not an error");
        assert!(out.is_empty());
    }

    #[test]
    fn list_returns_empty_for_empty_root() {
        let root = temp_root("empty");
        let out = list_recordings(&root).unwrap();
        assert!(out.is_empty());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn list_filters_to_cast_and_lfsr_extensions() {
        let root = temp_root("filter");
        let session = root.join("sess-1");
        fs::create_dir_all(&session).unwrap();
        fs::File::create(session.join("a.cast"))
            .unwrap()
            .write_all(b"hello")
            .unwrap();
        fs::File::create(session.join("b.lfsr"))
            .unwrap()
            .write_all(b"world")
            .unwrap();
        // .txt is the unrelated-extension case the spec rejects.
        fs::File::create(session.join("c.txt"))
            .unwrap()
            .write_all(b"skip")
            .unwrap();
        // A nested directory inside the session dir must be skipped
        // (recordings are flat under their session).
        fs::create_dir_all(session.join("nested")).unwrap();

        let mut out = list_recordings(&root).unwrap();
        out.sort_by(|a, b| a.file_name.cmp(&b.file_name));
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].file_name, "a.cast");
        assert_eq!(out[0].extension, "cast");
        assert!(!out[0].encrypted);
        assert_eq!(out[0].session_id, "sess-1");
        assert_eq!(out[0].size_bytes, 5);
        assert_eq!(out[1].file_name, "b.lfsr");
        assert_eq!(out[1].extension, "lfsr");
        assert!(out[1].encrypted);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn list_skips_files_directly_under_root() {
        // `<root>/orphan.cast` (no session subdir) is invalid layout
        // — every recording must live under its session id. The
        // walk skips bare files at the root level.
        let root = temp_root("rootfile");
        fs::File::create(root.join("orphan.cast"))
            .unwrap()
            .write_all(b"x")
            .unwrap();
        let out = list_recordings(&root).unwrap();
        assert!(out.is_empty());
        let _ = fs::remove_dir_all(&root);
    }

    #[cfg(unix)]
    #[test]
    fn list_skips_symlinked_session_dir() {
        // A symlink at <root>/<dir> pointing outside the
        // recordings tree must NOT be traversed. The walk uses
        // symlink_metadata to detect the link and skip it without
        // dereferencing.
        use std::os::unix::fs::symlink;
        let root = temp_root("symlink-dir");
        let real = temp_root("symlink-target");
        fs::File::create(real.join("decoy.cast"))
            .unwrap()
            .write_all(b"x")
            .unwrap();
        symlink(&real, root.join("sess-link")).unwrap();
        let out = list_recordings(&root).unwrap();
        assert!(out.is_empty());
        let _ = fs::remove_dir_all(&root);
        let _ = fs::remove_dir_all(&real);
    }

    #[cfg(unix)]
    #[test]
    fn list_skips_symlinked_file_inside_session_dir() {
        use std::os::unix::fs::symlink;
        let root = temp_root("symlink-file");
        let session = root.join("sess-1");
        fs::create_dir_all(&session).unwrap();
        let real_file = root.join("outside.cast");
        fs::File::create(&real_file)
            .unwrap()
            .write_all(b"x")
            .unwrap();
        symlink(&real_file, session.join("decoy.cast")).unwrap();
        let out = list_recordings(&root).unwrap();
        assert!(out.is_empty());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn list_includes_uppercase_extensions_via_lowercase_match() {
        // macOS / Windows can produce mixed-case extensions on
        // user-renamed files; the filter compares lowercased ext
        // so `.LFSR` is still recognised as encrypted.
        let root = temp_root("upper");
        let session = root.join("sess-1");
        fs::create_dir_all(&session).unwrap();
        fs::File::create(session.join("a.LFSR"))
            .unwrap()
            .write_all(b"x")
            .unwrap();
        let out = list_recordings(&root).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].extension, "lfsr");
        assert!(out[0].encrypted);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_removes_existing_file() {
        let root = temp_root("del");
        let session = root.join("sess-1");
        fs::create_dir_all(&session).unwrap();
        let target = session.join("a.cast");
        fs::File::create(&target).unwrap().write_all(b"x").unwrap();
        delete_recording(&root, "sess-1", "a.cast").expect("delete ok");
        assert!(!target.exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_missing_target_is_idempotent() {
        let root = temp_root("del-missing");
        // Session dir does not exist either — the delete still
        // collapses to Ok rather than surfacing NotFound.
        delete_recording(&root, "sess-x", "ghost.cast").expect("idempotent on missing");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_rejects_dotdot_in_session_id() {
        let root = temp_root("del-traversal-sid");
        let err = delete_recording(&root, "..", "a.cast").unwrap_err();
        assert!(matches!(err, BrowserError::InvalidComponent));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_rejects_dotdot_in_file_name() {
        let root = temp_root("del-traversal-fn");
        let err = delete_recording(&root, "sess-1", "..").unwrap_err();
        assert!(matches!(err, BrowserError::InvalidComponent));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_rejects_path_separator_in_session_id() {
        let root = temp_root("del-sep-sid");
        let err = delete_recording(&root, "sess/../etc", "a.cast").unwrap_err();
        assert!(matches!(err, BrowserError::InvalidComponent));
        let err = delete_recording(&root, r"sess\..\etc", "a.cast").unwrap_err();
        assert!(matches!(err, BrowserError::InvalidComponent));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_rejects_path_separator_in_file_name() {
        let root = temp_root("del-sep-fn");
        let err = delete_recording(&root, "sess-1", "../foo.cast").unwrap_err();
        assert!(matches!(err, BrowserError::InvalidComponent));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_rejects_empty_components() {
        let root = temp_root("del-empty");
        assert!(matches!(
            delete_recording(&root, "", "a.cast").unwrap_err(),
            BrowserError::InvalidComponent
        ));
        assert!(matches!(
            delete_recording(&root, "sess", "").unwrap_err(),
            BrowserError::InvalidComponent
        ));
        let _ = fs::remove_dir_all(&root);
    }
}
