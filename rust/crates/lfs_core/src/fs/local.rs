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

/// List `path` for the file-browser *view*: same as [`list`] but
/// with Windows Hidden / System files dropped so the pane matches
/// what Explorer would show. On every non-Windows target this is
/// identical to [`list`] — the filter set is empty.
///
/// The hidden-name decision lives here rather than in the Dart
/// caller: the caller used to `list`, separately fetch the hidden
/// set, then loop-and-drop. Folding the filter into one Rust call
/// keeps the "what does the browser hide?" rule Rust-owned and saves
/// the second FRB hop. The transfer-upload walker deliberately keeps
/// the raw [`list`] — an upload of a directory should carry hidden
/// files too, so the view filter must not leak into the walk.
pub async fn list_visible(path: String) -> Result<Vec<LocalFileEntry>, String> {
    let entries = list(path.clone()).await?;
    let hidden = windows_hidden_names(path).await;
    if hidden.is_empty() {
        return Ok(entries);
    }
    let hidden_lower: std::collections::HashSet<String> =
        hidden.into_iter().map(|n| n.to_lowercase()).collect();
    Ok(entries
        .into_iter()
        .filter(|e| !hidden_lower.contains(&e.name.to_lowercase()))
        .collect())
}

/// One leaf file from a recursive directory walk. `rel_path` is the
/// path relative to the walk root, joined with `/` regardless of
/// platform so the caller can re-join it onto either a local or a
/// remote (SFTP, always `/`) destination. Every segment of
/// `rel_path` has passed [`crate::path::is_safe_transfer_entry_name`].
#[derive(Debug, Clone)]
pub struct FlatFileEntry {
    /// `/`-joined path relative to the walk root.
    pub rel_path: String,
    pub size: u64,
}

/// Recursively walk `root` and return every leaf (non-directory)
/// file as a [`FlatFileEntry`]. Symlinks are skipped (never
/// followed into arbitrary targets), and every path segment is
/// validated through [`crate::path::is_safe_transfer_entry_name`]
/// so a hostile name can never escape the destination when the
/// caller re-joins `rel_path`. Recursion is bounded by `max_depth`
/// to cap a pathological directory cycle (junction loop / bind
/// mount); the walk silently stops descending past the budget
/// rather than erroring, matching the size-walk posture.
///
/// One FRB call replaces the Dart recursion that issued a `list`
/// per directory level — the enqueue loop stays Dart-side (it
/// resolves per-file conflicts through the UI) but the tree
/// enumeration is Rust-owned.
pub async fn flat_walk_files(root: String, max_depth: u32) -> Result<Vec<FlatFileEntry>, String> {
    let mut out = Vec::new();
    walk_flat(
        std::path::PathBuf::from(&root),
        String::new(),
        0,
        max_depth,
        &mut out,
    )
    .await?;
    Ok(out)
}

fn walk_flat<'a>(
    dir: std::path::PathBuf,
    rel_prefix: String,
    depth: u32,
    max_depth: u32,
    out: &'a mut Vec<FlatFileEntry>,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), String>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= max_depth {
            return Ok(());
        }
        let mut rd = tokio::fs::read_dir(&dir).await.map_err(map_io_error)?;
        while let Some(entry) = rd.next_entry().await.map_err(map_io_error)? {
            // `DirEntry::file_type` does not follow symlinks on Unix
            // — a symlink (file or dir) is identified before we ever
            // touch its target, so it is skipped without recursion.
            let Ok(file_type) = entry.file_type().await else {
                continue;
            };
            if file_type.is_symlink() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            // Reject any name that could escape the destination when
            // the caller re-joins `rel_path` — same guard the SFTP
            // walk applies to peer-supplied names.
            if !crate::path::is_safe_transfer_entry_name(&name) {
                continue;
            }
            let child_rel = if rel_prefix.is_empty() {
                name.clone()
            } else {
                format!("{rel_prefix}/{name}")
            };
            if file_type.is_dir() {
                walk_flat(entry.path(), child_rel, depth + 1, max_depth, out).await?;
            } else if file_type.is_file() {
                let size = entry.metadata().await.map(|m| m.len()).unwrap_or(0);
                out.push(FlatFileEntry {
                    rel_path: child_rel,
                    size,
                });
            }
        }
        Ok(())
    })
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
#[path = "../../tests/unit/fs_local.rs"]
mod tests;
