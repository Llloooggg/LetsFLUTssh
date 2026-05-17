//! Local filesystem operations for the file browser.
//!
//! Owns `list / mkdir / remove / removeDir / dirSize / rename` for
//! the Dart `LocalFS` caller. The Dart side keeps only
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
    /// `true` when the entry is a symbolic link itself (only
    /// populated by [`symlink_stat`]; [`list`] and [`stat`]
    /// follow links and report `false` here even when the
    /// underlying path resolves through a symlink). Matches
    /// the Dart caller's `FileSystemEntityType.link` discriminator.
    pub is_symlink: bool,
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
        // Probe the entry's own type without following symlinks
        // first so the `is_symlink` discriminator is set even
        // when the link target is missing or unreadable.
        // `DirEntry::file_type` does not traverse on Unix; the
        // resolved-target metadata comes from the follow path
        // below.
        let link_type = entry.file_type().await.ok();
        let is_symlink = link_type.map(|ft| ft.is_symlink()).unwrap_or(false);
        // Follow symlinks for the resolved metadata so `size`,
        // `mod_time_unix_ms`, and `is_dir` match what the
        // Dart-side `FileStat.statSync(path)` surfaced
        // (followLinks defaults to true). `DirEntry::metadata`
        // does NOT follow on Unix; `tokio::fs::metadata(path)`
        // does. The upload walker relies on the target's size
        // to size each transfer task.
        let metadata = match tokio::fs::metadata(entry.path()).await {
            Ok(m) => Some(m),
            Err(_) if is_symlink => None,
            Err(_) => continue,
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path().to_string_lossy().into_owned();
        let (size, mode, mod_time_unix_ms, is_dir) = match metadata.as_ref() {
            Some(m) => (m.len(), posix_mode(m), mod_time_ms(m), m.is_dir()),
            None => (0, 0, 0, false),
        };
        entries.push(LocalFileEntry {
            name,
            path,
            size,
            mode,
            mod_time_unix_ms,
            is_dir,
            is_symlink,
        });
    }
    Ok(entries)
}

/// Stat `path`, following symlinks. Returns `Ok(Some(entry))`
/// when the path resolves, `Ok(None)` when it does not exist,
/// and `Err(...)` for every other I/O failure (permission
/// denied on the parent, broken disk, etc.). The returned
/// `is_symlink` is always `false` — callers that need to
/// discriminate "is this a symlink itself?" use [`symlink_stat`]
/// instead.
///
/// Mirrors `FileStat.statSync(path)` + "does it exist?" in one
/// trip so the Dart caller can probe and read metadata together
/// without paying for two FRB hops.
pub async fn stat(path: String) -> Result<Option<LocalFileEntry>, String> {
    let metadata = match tokio::fs::metadata(&path).await {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(map_io_error(e)),
    };
    Ok(Some(LocalFileEntry {
        name: basename(&path),
        path: path.clone(),
        size: metadata.len(),
        mode: posix_mode(&metadata),
        mod_time_unix_ms: mod_time_ms(&metadata),
        is_dir: metadata.is_dir(),
        is_symlink: false,
    }))
}

/// Stat `path` without following symlinks. Returns `Ok(None)`
/// when the path is missing. The returned entry's `is_symlink`
/// is `true` when `path` itself is a symbolic link (regardless
/// of whether the target is a file or directory); `is_dir` then
/// reports the link entry's type (always `false` for a symlink
/// because `symlink_metadata` does not chase the target).
///
/// Mirrors `FileSystemEntity.typeSync(path, followLinks: false)`
/// — the Dart caller used this discrimination to refuse
/// overwriting an existing symlink on download.
pub async fn symlink_stat(path: String) -> Result<Option<LocalFileEntry>, String> {
    let metadata = match tokio::fs::symlink_metadata(&path).await {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(map_io_error(e)),
    };
    let file_type = metadata.file_type();
    Ok(Some(LocalFileEntry {
        name: basename(&path),
        path: path.clone(),
        size: metadata.len(),
        mode: posix_mode(&metadata),
        mod_time_unix_ms: mod_time_ms(&metadata),
        is_dir: file_type.is_dir(),
        is_symlink: file_type.is_symlink(),
    }))
}

fn basename(path: &str) -> String {
    // Use std::path::Path so the split respects whichever native
    // separator(s) the caller passed (`/` on Unix, `/` or `\` on
    // Windows). Falls back to the original string when the path
    // has no separator (a bare filename).
    std::path::Path::new(path)
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string())
}

/// Recursively create `path` (no error if it already exists).
/// Mirrors `Directory.create(recursive: true)`.
pub async fn mkdir(path: String) -> Result<(), String> {
    tokio::fs::create_dir_all(&path)
        .await
        .map_err(|e| format!("mkdir({path}): {e}"))
}

/// Android shared-storage initial-dir probe.
///
/// Scoped storage on Android 11+ lets apps see folder names at
/// the `/storage/emulated/0` root without actually granting
/// read access to the contents — a bare `metadata` call on the
/// root succeeds even when a subsequent list of any child
/// raises `EACCES`. Real-world MANAGE_EXTERNAL_STORAGE detection
/// therefore needs a deeper probe: stat the `Download` child,
/// then attempt to read its first directory entry.
///
/// `home_dir` is the canonical shared root (`/storage/emulated/0`
/// resolved Dart-side from `Platform.environment['EXTERNAL_STORAGE']`).
/// Returns `Some(home_dir)` when the deep probe succeeds, `None`
/// when any step fails. The Dart caller pivots to
/// `getExternalStorageDirectory()` (Flutter plugin) on `None`.
pub async fn android_initial_dir_probe(home_dir: String) -> Option<String> {
    let home_path = std::path::PathBuf::from(&home_dir);
    if tokio::fs::metadata(&home_path).await.is_err() {
        return None;
    }
    let download = home_path.join("Download");
    if tokio::fs::metadata(&download).await.is_ok() {
        // Read one entry — the listing succeeds on root even
        // without read access, but the entry pull surfaces
        // EACCES on a scoped-storage host.
        let mut rd = match tokio::fs::read_dir(&download).await {
            Ok(rd) => rd,
            Err(_) => return None,
        };
        if rd.next_entry().await.is_err() {
            return None;
        }
    }
    Some(home_dir)
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

/// Copy a single file from `src` to `dst`, replacing `dst` if
/// it already exists. Mirrors `tokio::fs::copy` 1-to-1; exists as
/// its own FRB entry point so the file-browser drop path goes
/// through `lfs_core` for the file branch as well as the
/// directory branch (kept symmetric with
/// [`copy_recursive_no_symlinks`]).
///
/// `Err` carries the unwrapped `tokio::fs::copy` error message so
/// the Dart caller can surface it through `FileSystemException`.
pub async fn copy_file(src: String, dst: String) -> Result<(), String> {
    tokio::fs::copy(&src, &dst)
        .await
        .map(|_| ())
        .map_err(|e| format!("copy({src} → {dst}): {e}"))
}

/// Recursively copy `src` to `dst`, refusing to traverse symlinks.
///
/// Hard fails with `Err("symlink_in_source")` when the entry at
/// `src` is itself a symlink so the caller does not accidentally
/// follow an attacker-supplied link out of the user's chosen
/// destination. Symlinks encountered inside the tree are silently
/// skipped (matches the Dart caller's `if (entity is Link) continue;`).
///
/// `max_depth` caps recursion so a pathological directory cycle
/// (e.g. a same-device bind-mount or a junction loop on Windows)
/// cannot drive the walker to unbounded stack growth. Returns
/// `Err("max_depth_exceeded")` when the budget is exhausted.
///
/// `dst` is created via `create_dir_all` so an intermediate
/// missing path is fine; an existing `dst` that is a regular file
/// returns `Err("destination_not_a_directory")`.
pub async fn copy_recursive_no_symlinks(
    src: String,
    dst: String,
    max_depth: u32,
) -> Result<(), String> {
    let src_meta = tokio::fs::symlink_metadata(&src)
        .await
        .map_err(map_io_error)?;
    if src_meta.file_type().is_symlink() {
        return Err("symlink_in_source".to_string());
    }
    if !src_meta.is_dir() {
        return Err("source_not_a_directory".to_string());
    }
    if let Ok(dst_meta) = tokio::fs::symlink_metadata(&dst).await {
        if !dst_meta.is_dir() {
            return Err("destination_not_a_directory".to_string());
        }
    }
    copy_dir_recursive_inner(
        std::path::PathBuf::from(src),
        std::path::PathBuf::from(dst),
        0,
        max_depth,
    )
    .await
}

fn copy_dir_recursive_inner(
    src: std::path::PathBuf,
    dst: std::path::PathBuf,
    depth: u32,
    max_depth: u32,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), String>> + Send>> {
    Box::pin(async move {
        if depth >= max_depth {
            return Err("max_depth_exceeded".to_string());
        }
        tokio::fs::create_dir_all(&dst)
            .await
            .map_err(map_io_error)?;
        let mut rd = tokio::fs::read_dir(&src).await.map_err(map_io_error)?;
        while let Some(entry) = rd.next_entry().await.map_err(map_io_error)? {
            // `DirEntry::file_type` does not follow symlinks on
            // Unix, so a link target's directory-ness cannot trick
            // the walker into recursing into a linked tree.
            let Ok(file_type) = entry.file_type().await else {
                continue;
            };
            if file_type.is_symlink() {
                continue;
            }
            let name = entry.file_name();
            let child_src = entry.path();
            let child_dst = dst.join(&name);
            if file_type.is_dir() {
                copy_dir_recursive_inner(child_src, child_dst, depth + 1, max_depth).await?;
            } else if file_type.is_file() {
                tokio::fs::copy(&child_src, &child_dst)
                    .await
                    .map(|_| ())
                    .map_err(map_io_error)?;
            }
        }
        Ok(())
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

    #[tokio::test]
    async fn stat_returns_some_for_existing_file() {
        let dir = temp_dir("stat_file");
        let f = dir.join("hello.txt");
        std::fs::write(&f, b"hello").unwrap();
        let entry = stat(f.to_string_lossy().into_owned())
            .await
            .unwrap()
            .expect("entry");
        assert_eq!(entry.size, 5);
        assert!(!entry.is_dir);
        assert!(!entry.is_symlink);
        assert_eq!(entry.name, "hello.txt");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn stat_returns_some_for_existing_directory() {
        let dir = temp_dir("stat_dir");
        let entry = stat(dir.to_string_lossy().into_owned())
            .await
            .unwrap()
            .expect("entry");
        assert!(entry.is_dir);
        assert!(!entry.is_symlink);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn stat_returns_none_for_missing_path() {
        let result = stat("/path/that/does/not/exist/lfs_stat_test".to_string())
            .await
            .unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn symlink_stat_returns_none_for_missing_path() {
        let result = symlink_stat("/path/that/does/not/exist/lfs_symlink_test".to_string())
            .await
            .unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn symlink_stat_reports_plain_file_not_symlink() {
        let dir = temp_dir("symlink_stat_plain");
        let f = dir.join("plain.txt");
        std::fs::write(&f, b"x").unwrap();
        let entry = symlink_stat(f.to_string_lossy().into_owned())
            .await
            .unwrap()
            .expect("entry");
        assert!(!entry.is_symlink);
        assert!(!entry.is_dir);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn list_marks_symlink_entries() {
        use std::os::unix::fs::symlink;
        let dir = temp_dir("list_symlink");
        std::fs::write(dir.join("plain.txt"), b"x").unwrap();
        let target = dir.join("target.txt");
        std::fs::write(&target, b"hello").unwrap();
        symlink(&target, dir.join("link.txt")).unwrap();

        let mut entries = list(dir.to_string_lossy().into_owned()).await.unwrap();
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        let by_name = |n: &str| entries.iter().find(|e| e.name == n).expect("present");

        assert!(!by_name("plain.txt").is_symlink);
        assert!(by_name("link.txt").is_symlink);
        // The link still resolves (target exists), so the
        // resolved metadata is populated.
        assert_eq!(by_name("link.txt").size, 5);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn symlink_stat_reports_symlink_separately() {
        use std::os::unix::fs::symlink;
        let dir = temp_dir("symlink_stat_link");
        let target = dir.join("target_dir");
        std::fs::create_dir(&target).unwrap();
        let link = dir.join("link_to_dir");
        symlink(&target, &link).unwrap();

        let entry = symlink_stat(link.to_string_lossy().into_owned())
            .await
            .unwrap()
            .expect("entry");
        assert!(entry.is_symlink);
        // `symlink_metadata` does not chase the target, so the link
        // entry's own type (not the directory it points at) is what
        // `is_dir` reports — `false`.
        assert!(!entry.is_dir);

        // `stat` follows the symlink and reports the underlying
        // directory's metadata, with `is_symlink: false`.
        let resolved = stat(link.to_string_lossy().into_owned())
            .await
            .unwrap()
            .expect("resolved");
        assert!(resolved.is_dir);
        assert!(!resolved.is_symlink);

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

    #[tokio::test]
    async fn copy_recursive_creates_target_tree() {
        let root = temp_dir("copy_recursive_tree");
        let src = root.join("src");
        let dst = root.join("dst");
        std::fs::create_dir_all(src.join("nested/inner")).unwrap();
        std::fs::write(src.join("top.txt"), b"hello").unwrap();
        std::fs::write(src.join("nested/mid.txt"), b"middle").unwrap();
        std::fs::write(src.join("nested/inner/deep.bin"), b"\x01\x02\x03").unwrap();

        copy_recursive_no_symlinks(
            src.to_string_lossy().into_owned(),
            dst.to_string_lossy().into_owned(),
            100,
        )
        .await
        .unwrap();

        assert_eq!(std::fs::read(dst.join("top.txt")).unwrap(), b"hello");
        assert_eq!(
            std::fs::read(dst.join("nested/mid.txt")).unwrap(),
            b"middle"
        );
        assert_eq!(
            std::fs::read(dst.join("nested/inner/deep.bin")).unwrap(),
            b"\x01\x02\x03"
        );
        std::fs::remove_dir_all(&root).ok();
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn copy_recursive_skips_symlinks_inside_tree() {
        use std::os::unix::fs::symlink;
        let root = temp_dir("copy_recursive_skip_link");
        let src = root.join("src");
        let dst = root.join("dst");
        std::fs::create_dir_all(&src).unwrap();
        let real = src.join("real.txt");
        std::fs::write(&real, b"real").unwrap();
        // Both file and directory links land inside the tree —
        // neither should appear at dst.
        let target_dir = root.join("link_target_dir");
        std::fs::create_dir(&target_dir).unwrap();
        std::fs::write(target_dir.join("inside.txt"), b"x").unwrap();
        symlink(&real, src.join("link_to_file")).unwrap();
        symlink(&target_dir, src.join("link_to_dir")).unwrap();

        copy_recursive_no_symlinks(
            src.to_string_lossy().into_owned(),
            dst.to_string_lossy().into_owned(),
            100,
        )
        .await
        .unwrap();

        assert!(dst.join("real.txt").is_file());
        assert!(!dst.join("link_to_file").exists());
        assert!(!dst.join("link_to_dir").exists());
        std::fs::remove_dir_all(&root).ok();
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn copy_recursive_refuses_symlink_at_root() {
        use std::os::unix::fs::symlink;
        let root = temp_dir("copy_recursive_refuse_root_link");
        let real_dir = root.join("real_dir");
        std::fs::create_dir(&real_dir).unwrap();
        let link = root.join("link_to_dir");
        symlink(&real_dir, &link).unwrap();
        let dst = root.join("dst");

        let err = copy_recursive_no_symlinks(
            link.to_string_lossy().into_owned(),
            dst.to_string_lossy().into_owned(),
            100,
        )
        .await
        .unwrap_err();
        assert_eq!(err, "symlink_in_source");
        std::fs::remove_dir_all(&root).ok();
    }

    #[tokio::test]
    async fn copy_recursive_errors_on_depth_overflow() {
        let root = temp_dir("copy_recursive_depth");
        let src = root.join("src");
        // Three levels deep: src / a / b / c (plus a leaf file).
        std::fs::create_dir_all(src.join("a/b/c")).unwrap();
        std::fs::write(src.join("a/b/c/leaf.txt"), b"x").unwrap();
        let dst = root.join("dst");

        let err = copy_recursive_no_symlinks(
            src.to_string_lossy().into_owned(),
            dst.to_string_lossy().into_owned(),
            1,
        )
        .await
        .unwrap_err();
        assert_eq!(err, "max_depth_exceeded");
        std::fs::remove_dir_all(&root).ok();
    }
}
