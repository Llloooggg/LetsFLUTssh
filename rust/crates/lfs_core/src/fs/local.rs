//! Local filesystem operations for the file browser.
//!
//! Replaces the Dart `LocalFS` `list / mkdir / remove / removeDir
//! / dirSize / rename` methods that used to call `dart:io`'s
//! `File` / `Directory` APIs directly. The Dart side keeps only
//! `initialDir` because that path depends on Flutter plugins
//! (`path_provider` for iOS sandbox / Android scoped storage)
//! that don't have a clean Rust analog.
//!
//! All ops route through `tokio::fs` so the Dart caller awaits
//! a Future without blocking the UI isolate. Errors surface as
//! `String` for the FRB boundary — the caller maps them to
//! `FileSystemException` shapes Dart-side.
//!
//! Windows hidden / system files: a separate helper delegates the
//! `cmd /c attrib *` spawn to
//! [`lfs_os_security::path::windows_hidden_names_raw`] (the audit
//! perimeter for subprocess invocation), parses the captured stdout
//! via [`crate::path::parse_windows_attrib_output`], and returns
//! the lowercase set of basenames the caller should drop. On
//! non-Windows targets the function is a compile-time no-op so
//! callers don't need their own platform gate.

use std::time::SystemTime;

/// Single entry from a directory listing. Field-for-field with
/// the Dart `FileEntry`'s required slots; `owner` stays empty
/// because the platform-portable stat we use here doesn't carry
/// it. The Dart `FileEntry.modeString` getter still resolves it
/// via the existing `lfs_core::sftp_models::mode_string` path.
#[derive(Debug, Clone)]
pub struct LocalFileEntry {
    pub name: String,
    pub path: String,
    pub size: u64,
    /// POSIX mode bits (e.g. `0o755`). Zero on Windows targets
    /// — the file_browser hides the modeString column there
    /// anyway since Windows ACLs don't map cleanly.
    pub mode: u32,
    /// Modification time as Unix epoch milliseconds. `0` when
    /// the underlying FS doesn't expose mtime (rare).
    pub mod_time_unix_ms: i64,
    pub is_dir: bool,
}

/// Enumerate immediate sub-directories of `path`. Returns
/// absolute paths of every direct child whose `is_dir()` is
/// true; symlinks are NOT followed (matches the Dart caller's
/// `followLinks: false`). Results are sorted by lowercased
/// basename so the picker UI does not need a second pass.
///
/// Errors are pinned to fixed keys so [`crate::fs::local`]'s
/// Dart caller can localise them through `localizeError`:
/// - `"no_such_file_or_directory"` when `path` does not exist.
/// - `"permission_denied"` when the `read_dir` syscall fails
///   with `EACCES`.
/// - `"io: <kind>"` for every other I/O failure.
///
/// Per-entry stat failures inside the directory (broken
/// symlinks, individual entries we cannot type) are skipped
/// silently; only an unreadable parent surfaces.
pub async fn list_directories(path: String) -> Result<Vec<String>, String> {
    let mut rd = tokio::fs::read_dir(&path).await.map_err(map_io_error)?;
    let mut dirs: Vec<String> = Vec::new();
    while let Some(entry) = rd
        .next_entry()
        .await
        .map_err(|e| format!("io: {}", e.kind().to_string().to_lowercase()))?
    {
        // `file_type` does not follow symlinks, so a symlinked
        // directory is reported as a symlink and filtered out
        // here without recursing into it.
        let Ok(file_type) = entry.file_type().await else {
            continue;
        };
        if !file_type.is_dir() {
            continue;
        }
        dirs.push(entry.path().to_string_lossy().into_owned());
    }
    dirs.sort_by(|a, b| {
        let an = std::path::Path::new(a)
            .file_name()
            .map(|s| s.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        let bn = std::path::Path::new(b)
            .file_name()
            .map(|s| s.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        an.cmp(&bn)
    });
    Ok(dirs)
}

fn map_io_error(e: std::io::Error) -> String {
    match e.kind() {
        std::io::ErrorKind::NotFound => "no_such_file_or_directory".to_string(),
        std::io::ErrorKind::PermissionDenied => "permission_denied".to_string(),
        other => format!("io: {}", other.to_string().to_lowercase()),
    }
}

/// List `path` and return one entry per direct child. Errors on
/// missing / unreadable directories so the Dart caller surfaces
/// `FileSystemException("Directory not found", path)` instead
/// of silently returning empty.
pub async fn list(path: String) -> Result<Vec<LocalFileEntry>, String> {
    let mut rd = tokio::fs::read_dir(&path)
        .await
        .map_err(|e| format!("read_dir({path}): {e}"))?;
    let mut entries = Vec::new();
    while let Some(entry) = rd.next_entry().await.map_err(|e| e.to_string())? {
        // Skip entries whose metadata we can't stat (broken
        // symlinks, permission denied) — same forgiving behaviour
        // the Dart side had.
        let metadata = match entry.metadata().await {
            Ok(m) => m,
            Err(_) => continue,
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path().to_string_lossy().into_owned();
        entries.push(LocalFileEntry {
            name,
            path,
            size: metadata.len(),
            mode: posix_mode(&metadata),
            mod_time_unix_ms: mod_time_ms(&metadata),
            is_dir: metadata.is_dir(),
        });
    }
    Ok(entries)
}

/// Recursively create `path` (no error if it already exists).
/// Mirrors `Directory.create(recursive: true)`.
pub async fn mkdir(path: String) -> Result<(), String> {
    tokio::fs::create_dir_all(&path)
        .await
        .map_err(|e| format!("mkdir({path}): {e}"))
}

/// Remove `path`. Routes to `remove_file` or `remove_dir_all`
/// based on the entity type — same dispatch the Dart side did.
pub async fn remove(path: String) -> Result<(), String> {
    let metadata = tokio::fs::symlink_metadata(&path)
        .await
        .map_err(|e| format!("stat({path}): {e}"))?;
    if metadata.is_dir() {
        tokio::fs::remove_dir_all(&path)
            .await
            .map_err(|e| format!("remove_dir_all({path}): {e}"))
    } else {
        tokio::fs::remove_file(&path)
            .await
            .map_err(|e| format!("remove_file({path}): {e}"))
    }
}

/// Recursively delete a directory tree. The Dart caller used
/// `Directory.delete(recursive: true)` for the same effect.
pub async fn remove_dir(path: String) -> Result<(), String> {
    tokio::fs::remove_dir_all(&path)
        .await
        .map_err(|e| format!("remove_dir_all({path}): {e}"))
}

/// Atomically rename `old_path` to `new_path` (intra-filesystem;
/// cross-volume moves fall through to whatever
/// `tokio::fs::rename` does on each OS).
pub async fn rename(old_path: String, new_path: String) -> Result<(), String> {
    tokio::fs::rename(&old_path, &new_path)
        .await
        .map_err(|e| format!("rename({old_path} → {new_path}): {e}"))
}

/// Total size (bytes) of all files under `path`, recursive.
/// Files we cannot stat are skipped silently — same as the Dart
/// version, which would otherwise error out the whole walk for
/// one inaccessible file.
pub async fn dir_size(path: String) -> Result<u64, String> {
    if !tokio::fs::try_exists(&path).await.unwrap_or(false) {
        return Ok(0);
    }
    Ok(walk_size(std::path::PathBuf::from(path)).await)
}

fn walk_size(
    p: std::path::PathBuf,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = u64> + Send>> {
    Box::pin(async move {
        let mut rd = match tokio::fs::read_dir(&p).await {
            Ok(rd) => rd,
            Err(_) => return 0,
        };
        let mut total: u64 = 0;
        while let Ok(Some(entry)) = rd.next_entry().await {
            let Ok(metadata) = entry.metadata().await else {
                continue;
            };
            if metadata.is_dir() {
                total = total.saturating_add(walk_size(entry.path()).await);
            } else {
                total = total.saturating_add(metadata.len());
            }
        }
        total
    })
}

/// Lowercase basenames the file browser should hide on Windows
/// (`H` / `S` attribs). Routes through `cmd /c attrib *` because
/// `tokio::fs::Metadata` doesn't surface NTFS attrs portably.
/// Compile-time no-op on every other target.
///
/// The `cmd /c attrib *` subprocess invocation lives in
/// [`lfs_os_security::path::windows_hidden_names_raw`] because that
/// crate is the single audit perimeter for OS-API FFI + subprocess
/// spawning; this arm is a thin delegate that runs the pure parser
/// [`crate::path::parse_windows_attrib_output`] over the captured
/// stdout. Splitting along the parse / spawn seam keeps the parser
/// unit-testable in lfs_core without dragging subprocess invocation
/// across the audit-perimeter rule.
#[cfg(target_os = "windows")]
pub async fn windows_hidden_names(dir: String) -> Vec<String> {
    let stdout = lfs_os_security::path::windows_hidden_names_raw(dir).await;
    crate::path::parse_windows_attrib_output(&stdout)
        .into_iter()
        .collect()
}

#[cfg(not(target_os = "windows"))]
pub async fn windows_hidden_names(_dir: String) -> Vec<String> {
    Vec::new()
}

#[cfg(unix)]
fn posix_mode(metadata: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt;
    metadata.mode()
}

#[cfg(not(unix))]
fn posix_mode(_metadata: &std::fs::Metadata) -> u32 {
    0
}

fn mod_time_ms(metadata: &std::fs::Metadata) -> i64 {
    metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(label: &str) -> std::path::PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default();
        let pid = std::process::id();
        let dir = std::env::temp_dir().join(format!("lfs_local_fs_{label}_{pid}_{nanos}"));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    #[tokio::test]
    async fn list_returns_directory_contents() {
        let dir = temp_dir("list");
        std::fs::write(dir.join("a.txt"), b"hello").unwrap();
        std::fs::write(dir.join("b.txt"), b"world!").unwrap();
        std::fs::create_dir(dir.join("sub")).unwrap();
        let mut entries = list(dir.to_string_lossy().into_owned()).await.unwrap();
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        assert_eq!(entries.len(), 3);
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, vec!["a.txt", "b.txt", "sub"]);
        let a = &entries[0];
        assert_eq!(a.size, 5);
        assert!(!a.is_dir);
        let s = &entries[2];
        assert!(s.is_dir);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn list_missing_directory_errors() {
        let result = list("/path/that/does/not/exist/lfs_test".to_string()).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn mkdir_creates_nested_path() {
        let dir = temp_dir("mkdir");
        let nested = dir.join("a/b/c");
        mkdir(nested.to_string_lossy().into_owned()).await.unwrap();
        assert!(nested.is_dir());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn remove_handles_file_and_directory() {
        let dir = temp_dir("remove");
        let f = dir.join("file.txt");
        std::fs::write(&f, b"x").unwrap();
        let sub = dir.join("sub");
        std::fs::create_dir(&sub).unwrap();
        std::fs::write(sub.join("inner"), b"y").unwrap();

        remove(f.to_string_lossy().into_owned()).await.unwrap();
        assert!(!f.exists());

        remove(sub.to_string_lossy().into_owned()).await.unwrap();
        assert!(!sub.exists());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn rename_moves_path() {
        let dir = temp_dir("rename");
        let from = dir.join("from.txt");
        let to = dir.join("to.txt");
        std::fs::write(&from, b"x").unwrap();
        rename(
            from.to_string_lossy().into_owned(),
            to.to_string_lossy().into_owned(),
        )
        .await
        .unwrap();
        assert!(!from.exists());
        assert!(to.exists());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn dir_size_sums_recursively() {
        let dir = temp_dir("dir_size");
        std::fs::write(dir.join("top.txt"), b"12345").unwrap();
        let sub = dir.join("nested");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(sub.join("inner.bin"), b"67890ab").unwrap();
        let total = dir_size(dir.to_string_lossy().into_owned()).await.unwrap();
        assert_eq!(total, 5 + 7);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn dir_size_missing_directory_returns_zero() {
        let total = dir_size("/this/does/not/exist/lfs_test".to_string())
            .await
            .unwrap();
        assert_eq!(total, 0);
    }

    #[tokio::test]
    async fn list_directories_returns_only_dirs() {
        let dir = temp_dir("list_dirs_only");
        std::fs::create_dir(dir.join("sub")).unwrap();
        std::fs::write(dir.join("file.txt"), b"x").unwrap();
        let out = list_directories(dir.to_string_lossy().into_owned())
            .await
            .unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(
            std::path::Path::new(&out[0])
                .file_name()
                .unwrap()
                .to_string_lossy(),
            "sub"
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn list_directories_nonexistent_returns_no_such_file_or_directory() {
        let result = list_directories("/path/that/does/not/exist/lfs_test_pick".to_string()).await;
        assert_eq!(result.unwrap_err(), "no_such_file_or_directory");
    }

    #[tokio::test]
    async fn list_directories_sorts_by_basename_case_insensitive() {
        let dir = temp_dir("list_dirs_sort");
        std::fs::create_dir(dir.join("Banana")).unwrap();
        std::fs::create_dir(dir.join("apple")).unwrap();
        std::fs::create_dir(dir.join("Cherry")).unwrap();
        let out = list_directories(dir.to_string_lossy().into_owned())
            .await
            .unwrap();
        let basenames: Vec<String> = out
            .iter()
            .map(|p| {
                std::path::Path::new(p)
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .into_owned()
            })
            .collect();
        assert_eq!(basenames, vec!["apple", "Banana", "Cherry"]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[cfg(not(target_os = "windows"))]
    #[tokio::test]
    async fn windows_hidden_names_is_empty_off_windows() {
        let dir = temp_dir("hidden");
        let result = windows_hidden_names(dir.to_string_lossy().into_owned()).await;
        assert!(result.is_empty());
        std::fs::remove_dir_all(&dir).ok();
    }
}
