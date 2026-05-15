//! SFTP client surface (russh-sftp-backed, v3 protocol).
//!
//! Byte-level CRUD — list, read, write, stat, rename, mkdir,
//! remove — plus streamed GET/PUT: open returns a `SftpFile`
//! handle and callers pump chunks via `read_chunk` / `write_all`
//! (with `seek` for resumable transfers).
//!
//! `Sftp` is opened off a live `ssh::Session` via
//! `Session::open_sftp` — allocates a fresh channel, requests the
//! `sftp` subsystem, and hands the bidirectional stream to
//! `russh-sftp`'s `SftpSession::new`.

use std::io::SeekFrom;

use russh_sftp::client::SftpSession;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncSeekExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::Mutex;

use crate::error::Error;

/// Live SFTP client. Drop-safe — when the wrapping object goes
/// out of scope, russh-sftp's session signals close on the
/// underlying channel and russh tears it down.
pub struct Sftp {
    session: SftpSession,
}

impl Sftp {
    /// Wrap a bidirectional byte stream in an SFTP session. Used by
    /// `ssh::Session::open_sftp` after `request_subsystem("sftp")`.
    pub(crate) async fn from_stream<S>(stream: S) -> Result<Self, Error>
    where
        S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let session = SftpSession::new(stream)
            .await
            .map_err(|e| Error::Sftp(format!("sftp init: {e}")))?;
        Ok(Sftp { session })
    }

    /// List a directory. Returns one `DirEntry` per child — does not
    /// recurse. Symlinks surface as their own kind so the caller
    /// decides whether to follow.
    pub async fn list(&self, path: &str) -> Result<Vec<DirEntry>, Error> {
        let read_dir = self
            .session
            .read_dir(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp read_dir: {e}")))?;

        let entries = read_dir
            .into_iter()
            .map(|e| {
                let name = e.file_name();
                let meta = e.metadata();
                DirEntry {
                    name,
                    size: meta.size.unwrap_or(0),
                    is_dir: meta.is_dir(),
                    is_symlink: meta.is_symlink(),
                    modified_unix: meta.mtime.map(|m| m as i64),
                    permissions: meta.permissions.unwrap_or(0),
                }
            })
            .collect();

        Ok(entries)
    }

    /// Recursive directory-size walk over the remote tree rooted
    /// at `path`. Sums every non-directory entry's byte count,
    /// recursing through every subdirectory up to `max_depth`
    /// levels deep. Symlinks are NOT followed.
    ///
    /// `max_depth = 0` returns the immediate children's size
    /// without descending; `max_depth = 64` is the runaway-traversal
    /// guard the caller passes in.
    ///
    /// Runs the entire walk Rust-side so the SFTP `read_dir`
    /// round-trips pay one channel turnaround each — one FRB hop
    /// regardless of tree depth.
    pub async fn dir_size_recursive(&self, path: &str, max_depth: u32) -> Result<u64, Error> {
        // Async recursion in Rust requires indirection — use a
        // Box::pin'd inner future. Mirrors the pattern in
        // `lfs_core::fs::local::copy_recursive_no_symlinks`.
        fn walk<'a>(
            sftp: &'a Sftp,
            path: &'a str,
            depth: u32,
            max_depth: u32,
        ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<u64, Error>> + Send + 'a>>
        {
            Box::pin(async move {
                let entries = sftp.list(path).await?;
                let mut total: u64 = 0;
                for entry in entries {
                    if entry.is_symlink {
                        continue;
                    }
                    if entry.is_dir {
                        if depth >= max_depth {
                            continue;
                        }
                        let child = if path.ends_with('/') {
                            format!("{path}{}", entry.name)
                        } else {
                            format!("{path}/{}", entry.name)
                        };
                        total =
                            total.saturating_add(walk(sftp, &child, depth + 1, max_depth).await?);
                    } else {
                        total = total.saturating_add(entry.size);
                    }
                }
                Ok(total)
            })
        }
        walk(self, path, 0, max_depth).await
    }

    /// Read a small file fully into memory. Suitable for config /
    /// dotfile-sized reads; large files (≥ a few MB) should go
    /// through the streaming surface (`open` + `read_chunk`).
    pub async fn read_file(&self, path: &str) -> Result<Vec<u8>, Error> {
        self.session
            .read(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp read: {e}")))
    }

    /// Overwrite a small file with `data`. Same size guidance as
    /// `read_file`. Server applies the bytes atomically only if the
    /// remote filesystem supports it (most do not — the typical
    /// behaviour is truncate + append).
    pub async fn write_file(&self, path: &str, data: &[u8]) -> Result<(), Error> {
        self.session
            .write(path, data)
            .await
            .map_err(|e| Error::Sftp(format!("sftp write: {e}")))
    }

    /// Stat a path. Resolves symlinks (use [`stat_symlink`] for
    /// per-link stat without resolution).
    pub async fn stat(&self, path: &str) -> Result<FileMetadata, Error> {
        let meta = self
            .session
            .metadata(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp stat: {e}")))?;
        Ok(FileMetadata::from_russh(&meta))
    }

    /// Stat a path without dereferencing symlinks.
    pub async fn stat_symlink(&self, path: &str) -> Result<FileMetadata, Error> {
        let meta = self
            .session
            .symlink_metadata(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp lstat: {e}")))?;
        Ok(FileMetadata::from_russh(&meta))
    }

    /// Rename / move. Atomic on the same filesystem; cross-filesystem
    /// behaviour is server-dependent (OpenSSH falls back to copy +
    /// delete, which is not atomic).
    pub async fn rename(&self, old: &str, new: &str) -> Result<(), Error> {
        self.session
            .rename(old, new)
            .await
            .map_err(|e| Error::Sftp(format!("sftp rename: {e}")))
    }

    /// Create a directory. Errors if the parent does not exist —
    /// callers wanting `mkdir -p` semantics must walk the path.
    pub async fn mkdir(&self, path: &str) -> Result<(), Error> {
        self.session
            .create_dir(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp mkdir: {e}")))
    }

    /// Remove a regular file. Errors on directories — use
    /// `remove_dir` for those.
    pub async fn remove_file(&self, path: &str) -> Result<(), Error> {
        self.session
            .remove_file(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp remove_file: {e}")))
    }

    /// Remove an empty directory. Errors when non-empty.
    pub async fn remove_dir(&self, path: &str) -> Result<(), Error> {
        self.session
            .remove_dir(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp remove_dir: {e}")))
    }

    /// Recursively delete a remote directory. Walks the tree
    /// depth-first, removing files and empty directories, then
    /// drops [`path`] itself. Mirrors the Dart
    /// `RemoteSftpFs.removeDir` walker — caps depth at
    /// [`SFTP_MAX_RECURSION_DEPTH`] so a cyclic symlink or
    /// pathologically deep tree fails fast instead of blowing
    /// the stack.
    ///
    /// Cancellation: every `await` is a Tokio yield point so a
    /// caller `tokio::select!`-ing this against a cancellation
    /// signal can drop the future cleanly. The active `await`
    /// completes; the next iteration of the for-loop never
    /// starts.
    pub async fn remove_dir_recursive(&self, path: &str) -> Result<(), Error> {
        remove_dir_recursive_inner(self, path, 0).await
    }
}

/// Hard recursion cap — matches the Dart `sftpMaxRecursionDepth`
/// (100). Guards against cyclic symlinks + pathologically deep
/// trees.
pub const SFTP_MAX_RECURSION_DEPTH: usize = 100;

fn remove_dir_recursive_inner<'a>(
    sftp: &'a Sftp,
    path: &'a str,
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), Error>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return Err(Error::Sftp(format!(
                "sftp remove_dir_recursive: max depth ({SFTP_MAX_RECURSION_DEPTH}) exceeded at {path}"
            )));
        }
        let entries = sftp.list(path).await?;
        let trimmed = path.trim_end_matches('/');
        for entry in entries {
            let child = format!("{trimmed}/{}", entry.name);
            // Symlink-to-directory escape: the server may resolve a
            // symlink's target metadata into `is_dir = true`. Recursing
            // would walk the link's target — outside the intended
            // delete subtree. Unlinking the symlink itself stops at
            // the directory entry without touching the pointed-to
            // contents, which is what every POSIX rm-rf does too.
            if entry.is_symlink {
                sftp.remove_file(&child).await?;
                continue;
            }
            if entry.is_dir {
                remove_dir_recursive_inner(sftp, &child, depth + 1).await?;
            } else {
                sftp.remove_file(&child).await?;
            }
        }
        sftp.remove_dir(path).await?;
        Ok(())
    })
}

// Tail of the `impl Sftp` block re-opens here so the rest of
// the file (open / create / mkdir helpers) stays unchanged.
impl Sftp {
    /// Open a file for reading. Returns a streaming handle whose
    /// `read_chunk` pumps bytes one window at a time so multi-GB
    /// transfers stay bounded in memory.
    pub async fn open(&self, path: &str) -> Result<SftpFile, Error> {
        let file = self
            .session
            .open(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp open: {e}")))?;
        Ok(SftpFile {
            inner: Mutex::new(file),
        })
    }

    /// Open a file for writing, truncating any existing content. Same
    /// streaming handle shape as `open`. Use `open_with_flags`-style
    /// extensions later (1.5c) for append / O_EXCL semantics.
    pub async fn create(&self, path: &str) -> Result<SftpFile, Error> {
        let file = self
            .session
            .create(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp create: {e}")))?;
        Ok(SftpFile {
            inner: Mutex::new(file),
        })
    }

    /// Resolve a path against the server's notion of the current
    /// directory. Useful for expanding `~` / relative paths the
    /// remote shell would resolve.
    pub async fn canonicalize(&self, path: &str) -> Result<String, Error> {
        self.session
            .canonicalize(path)
            .await
            .map_err(|e| Error::Sftp(format!("sftp canonicalize: {e}")))
    }

    /// Recursively upload `local_dir` into `remote_dir`. Walks the
    /// local tree depth-first, mkdir-ing each remote directory
    /// (best-effort — already-existing dirs are tolerated) and
    /// streaming each file in 64 KiB chunks. Per-file completion
    /// fires through `progress`; the closure returns `false` to
    /// signal cancellation, in which case the walk aborts at the
    /// next yield point with [`Error::Cancelled`].
    ///
    /// First-pass shape: sequential file-by-file walk. The
    /// pre-Tier-2 Dart walker pumped 4 files per directory level
    /// in parallel; that optimisation lands as a follow-up once
    /// the cancellation-safe JoinSet shape is wired.
    pub async fn upload_dir(
        &self,
        local_dir: &str,
        remote_dir: &str,
        progress: &(dyn Fn(TransferProgressEvent) -> bool + Send + Sync),
    ) -> Result<(), Error> {
        let total_files = count_local_files(std::path::Path::new(local_dir)).await;
        let mut counter: u64 = 0;
        let ctx = DirWalkCtx {
            sftp: self,
            total_files,
            progress,
        };
        upload_dir_inner(&ctx, local_dir, remote_dir, &mut counter, 0).await
    }

    /// Recursively download `remote_dir` into `local_dir`. Mirror
    /// of [`upload_dir`]: lists the remote, mkdir-s each local
    /// directory (`tokio::fs::create_dir_all`), streams each file
    /// in 64 KiB chunks, fires per-file progress through the
    /// closure. Same cancellation contract.
    pub async fn download_dir(
        &self,
        remote_dir: &str,
        local_dir: &str,
        progress: &(dyn Fn(TransferProgressEvent) -> bool + Send + Sync),
    ) -> Result<(), Error> {
        let total_files = count_remote_files(self, remote_dir, 0).await;
        let mut counter: u64 = 0;
        let ctx = DirWalkCtx {
            sftp: self,
            total_files,
            progress,
        };
        download_dir_inner(&ctx, remote_dir, local_dir, &mut counter, 0).await
    }

    /// Streamed single-file upload — opens both files, copies the
    /// local body into the remote in 64 KiB chunks, fires `progress`
    /// after every chunk with `(done_bytes, total_bytes)`. The
    /// closure returning `false` requests cancellation; the loop
    /// breaks at the next yield with [`Error::Cancelled`].
    ///
    /// Single FRB hop replaces the per-chunk Dart `writeAll`
    /// loop on the SFTP transfer hot path — see
    /// ARCHITECTURE.md §3.14.
    pub async fn upload_file_streaming(
        &self,
        local_path: &str,
        remote_path: &str,
        progress: &(dyn Fn(u64, u64) -> bool + Send + Sync),
    ) -> Result<(), Error> {
        let total_bytes = tokio::fs::metadata(local_path)
            .await
            .map(|m| m.len())
            .unwrap_or(0);
        let mut local = tokio::fs::File::open(local_path)
            .await
            .map_err(|e| Error::Sftp(format!("open {local_path}: {e}")))?;
        let remote = self.create(remote_path).await?;
        let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
        let mut done: u64 = 0;
        loop {
            let n = local
                .read(&mut buf)
                .await
                .map_err(|e| Error::Sftp(format!("local read {local_path}: {e}")))?;
            if n == 0 {
                break;
            }
            remote.write_all(&buf[..n]).await?;
            done = done.saturating_add(n as u64);
            if !progress(done, total_bytes) {
                return Err(Error::Cancelled);
            }
        }
        remote.sync_all().await?;
        Ok(())
    }

    /// Streamed single-file download — mirror of
    /// [`upload_file_streaming`]. Reads the remote `stat`-reported
    /// size up front so progress carries a real total instead of a
    /// rolling estimate.
    pub async fn download_file_streaming(
        &self,
        remote_path: &str,
        local_path: &str,
        progress: &(dyn Fn(u64, u64) -> bool + Send + Sync),
    ) -> Result<(), Error> {
        let total_bytes = self.stat(remote_path).await.map(|m| m.size).unwrap_or(0);
        let remote = self.open(remote_path).await?;
        if let Some(parent) = std::path::Path::new(local_path).parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| Error::Sftp(format!("mkdir {parent:?}: {e}")))?;
        }
        let mut local = tokio::fs::File::create(local_path)
            .await
            .map_err(|e| Error::Sftp(format!("create {local_path}: {e}")))?;
        let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
        let mut done: u64 = 0;
        loop {
            let n = remote.read_into(&mut buf).await?;
            if n == 0 {
                break;
            }
            local
                .write_all(&buf[..n])
                .await
                .map_err(|e| Error::Sftp(format!("local write {local_path}: {e}")))?;
            done = done.saturating_add(n as u64);
            if !progress(done, total_bytes) {
                return Err(Error::Cancelled);
            }
        }
        local
            .flush()
            .await
            .map_err(|e| Error::Sftp(format!("local flush {local_path}: {e}")))?;
        Ok(())
    }
}

/// Per-file completion event emitted by [`Sftp::upload_dir`] /
/// [`Sftp::download_dir`]. The Dart wrapper wraps these as
/// `TransferProgress` for the existing UI surface.
#[derive(Debug, Clone)]
pub struct TransferProgressEvent {
    pub file_name: String,
    pub total_files: u64,
    pub done_files: u64,
    pub is_upload: bool,
}

/// Per-file streaming chunk size — matches russh-sftp's default
/// packet window.
const TRANSFER_CHUNK_SIZE: usize = 65536;

async fn count_local_files(dir: &std::path::Path) -> u64 {
    fn walk(
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
                    total = total.saturating_add(walk(entry.path()).await);
                } else {
                    total = total.saturating_add(1);
                }
            }
            total
        })
    }
    walk(dir.to_path_buf()).await
}

fn count_remote_files<'a>(
    sftp: &'a Sftp,
    path: &'a str,
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = u64> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return 0;
        }
        let entries = match sftp.list(path).await {
            Ok(v) => v,
            Err(_) => return 0,
        };
        let trimmed = path.trim_end_matches('/');
        let mut total: u64 = 0;
        for entry in entries {
            let child = format!("{trimmed}/{}", entry.name);
            if entry.is_dir {
                total = total.saturating_add(count_remote_files(sftp, &child, depth + 1).await);
            } else {
                total = total.saturating_add(1);
            }
        }
        total
    })
}

/// Immutable per-walk context shared across recursive
/// upload_dir / download_dir calls. Bundling the invariants
/// (sftp handle, total file count, progress callback) into one
/// struct keeps the recursive signature under clippy's
/// too-many-arguments threshold; the mutable counter and depth
/// stay as separate args because they vary per recursive frame.
struct DirWalkCtx<'a> {
    sftp: &'a Sftp,
    total_files: u64,
    progress: &'a (dyn Fn(TransferProgressEvent) -> bool + Send + Sync),
}

fn upload_dir_inner<'a>(
    ctx: &'a DirWalkCtx<'a>,
    local_dir: &'a str,
    remote_dir: &'a str,
    counter: &'a mut u64,
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), Error>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return Err(Error::Sftp(format!(
                "sftp upload_dir: max depth ({SFTP_MAX_RECURSION_DEPTH}) exceeded at {local_dir}"
            )));
        }
        // mkdir is best-effort — directory may already exist on the remote.
        let _ = ctx.sftp.mkdir(remote_dir).await;

        let mut rd = tokio::fs::read_dir(local_dir)
            .await
            .map_err(|e| Error::Sftp(format!("read_dir {local_dir}: {e}")))?;
        let mut files: Vec<(String, String)> = Vec::new();
        let mut subdirs: Vec<(String, String)> = Vec::new();
        while let Some(entry) = rd
            .next_entry()
            .await
            .map_err(|e| Error::Sftp(format!("read_dir entry: {e}")))?
        {
            let Ok(metadata) = entry.metadata().await else {
                continue;
            };
            let name = entry.file_name().to_string_lossy().into_owned();
            let local_child = entry.path().to_string_lossy().into_owned();
            let remote_child = format!("{}/{}", remote_dir.trim_end_matches('/'), name);
            if metadata.is_dir() {
                subdirs.push((local_child, remote_child));
            } else if metadata.is_file() {
                files.push((local_child, remote_child));
            }
        }

        for (local_path, remote_path) in files {
            stream_upload_file(ctx.sftp, &local_path, &remote_path).await?;
            *counter = counter.saturating_add(1);
            let name = std::path::Path::new(&local_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let cont = (ctx.progress)(TransferProgressEvent {
                file_name: name,
                total_files: ctx.total_files,
                done_files: *counter,
                is_upload: true,
            });
            if !cont {
                return Err(Error::Cancelled);
            }
        }
        for (local_child, remote_child) in subdirs {
            upload_dir_inner(ctx, &local_child, &remote_child, counter, depth + 1).await?;
        }
        Ok(())
    })
}

fn download_dir_inner<'a>(
    ctx: &'a DirWalkCtx<'a>,
    remote_dir: &'a str,
    local_dir: &'a str,
    counter: &'a mut u64,
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), Error>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return Err(Error::Sftp(format!(
                "sftp download_dir: max depth ({SFTP_MAX_RECURSION_DEPTH}) exceeded at {remote_dir}"
            )));
        }
        tokio::fs::create_dir_all(local_dir)
            .await
            .map_err(|e| Error::Sftp(format!("create_dir_all {local_dir}: {e}")))?;
        let entries = ctx.sftp.list(remote_dir).await?;
        let trimmed = remote_dir.trim_end_matches('/');
        let mut files: Vec<(String, String)> = Vec::new();
        let mut subdirs: Vec<(String, String)> = Vec::new();
        for entry in entries {
            let remote_child = format!("{trimmed}/{}", entry.name);
            let local_child = format!("{}/{}", local_dir.trim_end_matches('/'), entry.name);
            if entry.is_dir {
                subdirs.push((remote_child, local_child));
            } else {
                files.push((remote_child, local_child));
            }
        }

        for (remote_path, local_path) in files {
            stream_download_file(ctx.sftp, &remote_path, &local_path).await?;
            *counter = counter.saturating_add(1);
            let name = std::path::Path::new(&local_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let cont = (ctx.progress)(TransferProgressEvent {
                file_name: name,
                total_files: ctx.total_files,
                done_files: *counter,
                is_upload: false,
            });
            if !cont {
                return Err(Error::Cancelled);
            }
        }
        for (remote_child, local_child) in subdirs {
            download_dir_inner(ctx, &remote_child, &local_child, counter, depth + 1).await?;
        }
        Ok(())
    })
}

async fn stream_upload_file(sftp: &Sftp, local_path: &str, remote_path: &str) -> Result<(), Error> {
    let mut local = tokio::fs::File::open(local_path)
        .await
        .map_err(|e| Error::Sftp(format!("open {local_path}: {e}")))?;
    let remote = sftp.create(remote_path).await?;
    let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
    loop {
        let n = local
            .read(&mut buf)
            .await
            .map_err(|e| Error::Sftp(format!("local read {local_path}: {e}")))?;
        if n == 0 {
            break;
        }
        remote.write_all(&buf[..n]).await?;
    }
    remote.sync_all().await?;
    Ok(())
}

async fn stream_download_file(
    sftp: &Sftp,
    remote_path: &str,
    local_path: &str,
) -> Result<(), Error> {
    let remote = sftp.open(remote_path).await?;
    let mut local = tokio::fs::File::create(local_path)
        .await
        .map_err(|e| Error::Sftp(format!("create {local_path}: {e}")))?;
    // Reused scratch buffer — same rationale as the transfer
    // driver loop. One alloc per call, not per chunk.
    let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
    loop {
        let n = remote.read_into(&mut buf).await?;
        if n == 0 {
            break;
        }
        local
            .write_all(&buf[..n])
            .await
            .map_err(|e| Error::Sftp(format!("local write {local_path}: {e}")))?;
    }
    local
        .flush()
        .await
        .map_err(|e| Error::Sftp(format!("local flush {local_path}: {e}")))?;
    Ok(())
}

/// Streaming SFTP file handle. Wraps russh-sftp's `File` (which
/// implements tokio's `AsyncRead` + `AsyncWrite`) behind a `Mutex`
/// because every IO call needs `&mut self` and we want the handle
/// shareable across tasks (e.g. progress reporter + transfer task
/// holding it together).
pub struct SftpFile {
    inner: Mutex<russh_sftp::client::fs::File>,
}

impl SftpFile {
    /// Read up to `max_bytes` from the current position. Returns the
    /// bytes actually read — an empty `Vec` signals EOF.
    ///
    /// Allocates a fresh `Vec` per call. For tight loops where the
    /// caller already owns a reusable scratch buffer (transfer
    /// driver / archive-stream reader), prefer [`read_into`] to
    /// skip the per-iteration `vec![0; N]` allocation.
    pub async fn read_chunk(&self, max_bytes: usize) -> Result<Vec<u8>, Error> {
        let mut guard = self.inner.lock().await;
        let mut buf = vec![0u8; max_bytes];
        let n = guard
            .read(&mut buf)
            .await
            .map_err(|e| Error::Sftp(format!("sftp read: {e}")))?;
        buf.truncate(n);
        Ok(buf)
    }

    /// Read up to `buf.len()` bytes into the caller-provided
    /// scratch buffer. Returns the number of bytes actually read —
    /// `0` signals EOF. Reuses the caller's allocation across
    /// chunks, eliminating the `vec![0; chunk_size]` malloc the
    /// `read_chunk` path runs once per chunk; on a 100 MB/s pipe
    /// with 256 KiB chunks that's ~400 mallocs/s saved per
    /// transfer driver loop.
    pub async fn read_into(&self, buf: &mut [u8]) -> Result<usize, Error> {
        let mut guard = self.inner.lock().await;
        guard
            .read(buf)
            .await
            .map_err(|e| Error::Sftp(format!("sftp read: {e}")))
    }

    /// Write the entire `data` slice to the current position. Returns
    /// when every byte has been queued; russh-sftp pipelines internally
    /// so callers do not need to chunk further for throughput.
    pub async fn write_all(&self, data: &[u8]) -> Result<(), Error> {
        let mut guard = self.inner.lock().await;
        guard
            .write_all(data)
            .await
            .map_err(|e| Error::Sftp(format!("sftp write: {e}")))
    }

    /// Move the read / write cursor to `offset` bytes from the start
    /// of the file. Used for resumable downloads / sparse uploads.
    pub async fn seek(&self, offset: u64) -> Result<(), Error> {
        let mut guard = self.inner.lock().await;
        guard
            .seek(SeekFrom::Start(offset))
            .await
            .map(|_| ())
            .map_err(|e| Error::Sftp(format!("sftp seek: {e}")))
    }

    /// Drain any pipelined WRITE acks the russh-sftp client has queued
    /// (poll_write returns Ready(Ok) before the server acks; the ack
    /// receivers live in the file's `write_acks` deque), then ask the
    /// server to fsync the handle to disk. The fsync round-trip is
    /// best-effort — servers without `fsync@openssh.com` quietly skip
    /// it — but the flush is mandatory: without it the upload driver
    /// declares a task `Completed` while WRITE bytes are still in the
    /// SSH transport queue, racing any caller that reads the remote
    /// file immediately after the bus event.
    pub async fn sync_all(&self) -> Result<(), Error> {
        use tokio::io::AsyncWriteExt;
        let mut guard = self.inner.lock().await;
        guard
            .flush()
            .await
            .map_err(|e| Error::Sftp(format!("sftp flush: {e}")))?;
        guard
            .sync_all()
            .await
            .map_err(|e| Error::Sftp(format!("sftp sync: {e}")))
    }

    /// Read file metadata via the open handle (avoids a second
    /// round-trip when the caller already has the file open). Useful
    /// to grab `size` for download progress bars before pumping
    /// chunks.
    pub async fn metadata(&self) -> Result<FileMetadata, Error> {
        let guard = self.inner.lock().await;
        let meta = guard
            .metadata()
            .await
            .map_err(|e| Error::Sftp(format!("sftp fstat: {e}")))?;
        Ok(FileMetadata::from_russh(&meta))
    }
}

/// One directory entry returned by `Sftp::list`.
#[derive(Debug, Clone)]
pub struct DirEntry {
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
    pub is_symlink: bool,
    /// Unix epoch seconds (server-side mtime). `None` when the
    /// server omitted it or a translation failed.
    pub modified_unix: Option<i64>,
    /// POSIX mode bits (e.g. 0o755). `0` when unavailable.
    pub permissions: u32,
}

/// File metadata returned by `Sftp::stat` / `stat_symlink`.
#[derive(Debug, Clone)]
pub struct FileMetadata {
    pub size: u64,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub modified_unix: Option<i64>,
    pub permissions: u32,
}

impl FileMetadata {
    fn from_russh(meta: &russh_sftp::protocol::FileAttributes) -> Self {
        FileMetadata {
            size: meta.size.unwrap_or(0),
            is_dir: meta.is_dir(),
            is_symlink: meta.is_symlink(),
            modified_unix: meta.mtime.map(|m| m as i64),
            permissions: meta.permissions.unwrap_or(0),
        }
    }
}

#[cfg(test)]
mod tests {
    //! Unit tests for the SFTP module's pure helpers. The
    //! per-method tests against a real SFTP server live in the
    //! integration suite (`lfs_frb` / Dart `transfer_queue_test`);
    //! the tests below cover the parts that don't need a transport.
    use super::*;
    use russh_sftp::protocol::FileAttributes;

    fn touch(path: &std::path::Path) {
        std::fs::File::create(path).expect("create test file");
    }

    #[tokio::test]
    async fn count_local_files_empty_dir_returns_zero() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let n = count_local_files(tmp.path()).await;
        assert_eq!(n, 0);
    }

    #[tokio::test]
    async fn count_local_files_counts_flat_files() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        touch(&tmp.path().join("a.txt"));
        touch(&tmp.path().join("b.txt"));
        touch(&tmp.path().join("c.txt"));
        let n = count_local_files(tmp.path()).await;
        assert_eq!(n, 3);
    }

    #[tokio::test]
    async fn count_local_files_recurses_into_subdirs() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let nested = tmp.path().join("sub").join("deep");
        std::fs::create_dir_all(&nested).expect("mkdir -p");
        touch(&tmp.path().join("root.txt"));
        touch(&tmp.path().join("sub/mid.txt"));
        touch(&nested.join("leaf.txt"));
        let n = count_local_files(tmp.path()).await;
        assert_eq!(n, 3);
    }

    #[tokio::test]
    async fn count_local_files_missing_dir_returns_zero() {
        // A missing path must return 0, not panic — matches the
        // graceful-degradation contract count_remote_files honours.
        let n = count_local_files(std::path::Path::new("/nonexistent/path-7c8f")).await;
        assert_eq!(n, 0);
    }

    #[test]
    fn file_metadata_from_russh_preserves_every_field_for_dir() {
        // `FileAttributes::default()` already sets permissions to
        // `0o777 | DIR`, so this tests the directory branch by
        // augmenting the default with size + mtime.
        let attr = FileAttributes {
            size: Some(2048),
            mtime: Some(1_700_000_000),
            ..FileAttributes::default()
        };
        let m = FileMetadata::from_russh(&attr);
        assert_eq!(m.size, 2048);
        assert!(m.is_dir);
        assert!(!m.is_symlink);
        assert_eq!(m.modified_unix, Some(1_700_000_000));
        assert_ne!(m.permissions & 0o777, 0);
    }

    #[test]
    fn file_metadata_from_russh_folds_missing_optionals_to_safe_defaults() {
        // Real SFTP servers omit fields the client didn't request —
        // the converter must fold every gap into a safe default
        // rather than panic. Build a fully-empty attribute set.
        let attr = FileAttributes {
            size: None,
            uid: None,
            user: None,
            gid: None,
            group: None,
            permissions: None,
            atime: None,
            mtime: None,
        };
        let m = FileMetadata::from_russh(&attr);
        assert_eq!(m.size, 0);
        assert!(!m.is_dir);
        assert!(!m.is_symlink);
        assert_eq!(m.modified_unix, None);
        assert_eq!(m.permissions, 0);
    }

    #[test]
    fn file_metadata_from_russh_flags_regular_file() {
        // A regular file: clear the DIR bit baked into Default and
        // set the REG one. Confirms the converter returns
        // `is_dir = false` for non-directory entries. Mutating
        // setters used here (no struct-update shortcut available)
        // because each setter ORs into the permissions field.
        let mut attr = FileAttributes::default();
        attr.remove_type(russh_sftp::protocol::FileMode::DIR);
        attr.set_regular(true);
        let m = FileMetadata::from_russh(&attr);
        assert!(!m.is_dir);
        assert!(!m.is_symlink);
    }

    #[test]
    fn dir_entry_clone_round_trip() {
        // Pre-fill a DirEntry, clone it, mutate the original — the
        // clone must hold the original values. Guards against an
        // accidental shared-reference field in a future refactor.
        let entry = DirEntry {
            name: "fileA".into(),
            size: 1234,
            is_dir: false,
            is_symlink: false,
            modified_unix: Some(42),
            permissions: 0o644,
        };
        let cloned = entry.clone();
        let mut original = entry;
        original.name = "mutated".into();
        original.size = 0;
        assert_eq!(cloned.name, "fileA");
        assert_eq!(cloned.size, 1234);
        assert_eq!(cloned.permissions, 0o644);
    }

    #[test]
    fn transfer_progress_event_clone_round_trip() {
        let evt = TransferProgressEvent {
            file_name: "x.bin".into(),
            total_files: 10,
            done_files: 3,
            is_upload: true,
        };
        let cloned = evt.clone();
        assert_eq!(cloned.file_name, "x.bin");
        assert_eq!(cloned.total_files, 10);
        assert_eq!(cloned.done_files, 3);
        assert!(cloned.is_upload);
    }

    // ─── Local-fs walk edge cases ──────────────────────────────────

    #[tokio::test]
    async fn count_local_files_includes_hidden_dotfiles() {
        // The walker must not silently skip dotfiles — dotfile
        // exclusion would diverge from `cp -r` semantics and surprise
        // a user who expects a full transfer count to match
        // `find <dir> -type f | wc -l`.
        let tmp = tempfile::tempdir().expect("tmp dir");
        touch(&tmp.path().join(".hidden"));
        touch(&tmp.path().join("visible.txt"));
        std::fs::create_dir(tmp.path().join(".dot_dir")).expect("mkdir");
        touch(&tmp.path().join(".dot_dir/inside.txt"));
        let n = count_local_files(tmp.path()).await;
        assert_eq!(n, 3);
    }

    #[tokio::test]
    async fn count_local_files_does_not_count_directories_themselves() {
        // The walker counts files only — a tree of empty directories
        // returns zero so a directory-only transfer doesn't inflate
        // the progress denominator.
        let tmp = tempfile::tempdir().expect("tmp dir");
        let nested = tmp.path().join("a").join("b").join("c");
        std::fs::create_dir_all(&nested).expect("mkdir -p");
        let n = count_local_files(tmp.path()).await;
        assert_eq!(n, 0);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn count_local_files_follows_into_subdir_via_symlink_target_only() {
        // Symlinks themselves are counted by `read_dir` enumeration
        // but the walker recurses only on `is_dir()` (file_type), and
        // a symlink-to-dir is NOT classified as a directory by
        // `read_dir` metadata — verifies the walker doesn't follow a
        // symlink loop. A two-file dir + a symlink to it counts the
        // two real files plus the symlink entry itself = 3.
        let tmp = tempfile::tempdir().expect("tmp dir");
        let sub = tmp.path().join("sub");
        std::fs::create_dir(&sub).expect("mkdir");
        touch(&sub.join("a.txt"));
        touch(&sub.join("b.txt"));
        std::os::unix::fs::symlink(&sub, tmp.path().join("link")).expect("symlink");
        let n = count_local_files(tmp.path()).await;
        // Two real files inside `sub`; the symlink entry at the top
        // level is not a directory per `file_type().is_dir()` and is
        // counted as a single entry.
        assert_eq!(n, 3);
    }

    // ─── FileMetadata mode-bit edge cases ──────────────────────────

    #[test]
    fn file_metadata_size_at_u64_max_round_trips() {
        // Pin the size field's full 64-bit range — a regression that
        // truncates to u32 would silently corrupt large-file stat()
        // results (>4 GiB files come back wrong).
        let attr = FileAttributes {
            size: Some(u64::MAX),
            ..FileAttributes::default()
        };
        let m = FileMetadata::from_russh(&attr);
        assert_eq!(m.size, u64::MAX);
    }

    #[test]
    fn file_metadata_modified_unix_handles_large_mtime() {
        // mtime as u32 max (year 2106 epoch) round-trips into i64
        // without losing the high bit. Pre-2038 values stay positive.
        let attr = FileAttributes {
            mtime: Some(u32::MAX),
            ..FileAttributes::default()
        };
        let m = FileMetadata::from_russh(&attr);
        assert_eq!(m.modified_unix, Some(u32::MAX as i64));
    }

    #[test]
    fn file_metadata_permissions_preserve_setuid_and_sticky_bits() {
        // setuid (04000), setgid (02000), sticky (01000) bits live
        // above the rwx mode triplets — a regression masking with
        // 0o777 would silently strip them from the surfaced metadata.
        let attr = FileAttributes {
            permissions: Some(0o7755),
            ..FileAttributes::default()
        };
        let m = FileMetadata::from_russh(&attr);
        assert_eq!(m.permissions & 0o7000, 0o7000);
    }

    // ─── DirEntry / TransferProgressEvent invariants ───────────────

    #[test]
    fn dir_entry_default_field_values_are_safe() {
        // Construct a "minimum information" entry with empty name +
        // zeroed scalars + None mtime. Confirms the struct accepts
        // every legitimate gap a parse path might produce without
        // requiring all fields populated.
        let entry = DirEntry {
            name: String::new(),
            size: 0,
            is_dir: false,
            is_symlink: false,
            modified_unix: None,
            permissions: 0,
        };
        assert!(entry.name.is_empty());
        assert_eq!(entry.size, 0);
        assert!(!entry.is_dir);
    }

    #[test]
    fn transfer_progress_event_at_completion_marks_done_equals_total() {
        // The completed-progress shape is `done_files == total_files`.
        // Pin the equality so consumers (Dart progress bar) can rely
        // on `done == total ⇒ finished` without a separate flag.
        let evt = TransferProgressEvent {
            file_name: "final.bin".into(),
            total_files: 5,
            done_files: 5,
            is_upload: false,
        };
        assert_eq!(evt.done_files, evt.total_files);
        assert!(!evt.is_upload);
    }

    #[test]
    fn transfer_progress_event_at_zero_progress_signals_pending() {
        // Initial-state shape: total > 0, done == 0. Confirms the
        // struct accepts the legitimate "queued, nothing done yet"
        // case without requiring a non-zero done_files.
        let evt = TransferProgressEvent {
            file_name: "first.bin".into(),
            total_files: 3,
            done_files: 0,
            is_upload: true,
        };
        assert_eq!(evt.done_files, 0);
        assert_ne!(evt.total_files, 0);
    }
}
