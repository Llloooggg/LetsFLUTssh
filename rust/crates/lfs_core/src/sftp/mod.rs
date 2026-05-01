//! SFTP client surface (russh-sftp-backed, v3 protocol).
//!
//! Byte-level CRUD surface — list, read, write, stat, rename,
//! mkdir, remove — plus streamed GET/PUT for large files: open
//! returns a `SftpFile` handle, callers pump chunks via
//! `read_chunk` / `write_all` and may seek for resumable
//! transfers. Mirrors dartssh2's `SftpFile.read()` /
//! `writeBytes()` byte-stream surface and feeds the existing
//! transfer queue once the unified SshTransport swap lands.
//!
//! `Sftp` is opened off a live `ssh::Session` via
//! `Session::open_sftp` — internally it allocates a fresh channel,
//! requests the `sftp` subsystem, and hands the resulting bidirectional
//! stream to `russh-sftp`'s `SftpSession::new`.

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
            .map_err(|e| Error::Io(format!("sftp init: {e}")))?;
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
            .map_err(|e| Error::Io(format!("sftp read_dir: {e}")))?;

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

    /// Read a small file fully into memory. Suitable for config /
    /// dotfile-sized reads; large files (≥ a few MB) should go
    /// through the streaming surface (`open` + `read_chunk`).
    pub async fn read_file(&self, path: &str) -> Result<Vec<u8>, Error> {
        self.session
            .read(path)
            .await
            .map_err(|e| Error::Io(format!("sftp read: {e}")))
    }

    /// Overwrite a small file with `data`. Same size guidance as
    /// `read_file`. Server applies the bytes atomically only if the
    /// remote filesystem supports it (most do not — the typical
    /// behaviour is truncate + append).
    pub async fn write_file(&self, path: &str, data: &[u8]) -> Result<(), Error> {
        self.session
            .write(path, data)
            .await
            .map_err(|e| Error::Io(format!("sftp write: {e}")))
    }

    /// Stat a path. Resolves symlinks (use [`stat_symlink`] for
    /// per-link stat without resolution).
    pub async fn stat(&self, path: &str) -> Result<FileMetadata, Error> {
        let meta = self
            .session
            .metadata(path)
            .await
            .map_err(|e| Error::Io(format!("sftp stat: {e}")))?;
        Ok(FileMetadata::from_russh(&meta))
    }

    /// Stat a path without dereferencing symlinks.
    pub async fn stat_symlink(&self, path: &str) -> Result<FileMetadata, Error> {
        let meta = self
            .session
            .symlink_metadata(path)
            .await
            .map_err(|e| Error::Io(format!("sftp lstat: {e}")))?;
        Ok(FileMetadata::from_russh(&meta))
    }

    /// Rename / move. Atomic on the same filesystem; cross-filesystem
    /// behaviour is server-dependent (OpenSSH falls back to copy +
    /// delete, which is not atomic).
    pub async fn rename(&self, old: &str, new: &str) -> Result<(), Error> {
        self.session
            .rename(old, new)
            .await
            .map_err(|e| Error::Io(format!("sftp rename: {e}")))
    }

    /// Create a directory. Errors if the parent does not exist —
    /// callers wanting `mkdir -p` semantics must walk the path.
    pub async fn mkdir(&self, path: &str) -> Result<(), Error> {
        self.session
            .create_dir(path)
            .await
            .map_err(|e| Error::Io(format!("sftp mkdir: {e}")))
    }

    /// Remove a regular file. Errors on directories — use
    /// `remove_dir` for those.
    pub async fn remove_file(&self, path: &str) -> Result<(), Error> {
        self.session
            .remove_file(path)
            .await
            .map_err(|e| Error::Io(format!("sftp remove_file: {e}")))
    }

    /// Remove an empty directory. Errors when non-empty.
    pub async fn remove_dir(&self, path: &str) -> Result<(), Error> {
        self.session
            .remove_dir(path)
            .await
            .map_err(|e| Error::Io(format!("sftp remove_dir: {e}")))
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
            return Err(Error::Io(format!(
                "sftp remove_dir_recursive: max depth ({SFTP_MAX_RECURSION_DEPTH}) exceeded at {path}"
            )));
        }
        let entries = sftp.list(path).await?;
        let trimmed = path.trim_end_matches('/');
        for entry in entries {
            let child = format!("{trimmed}/{}", entry.name);
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
            .map_err(|e| Error::Io(format!("sftp open: {e}")))?;
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
            .map_err(|e| Error::Io(format!("sftp create: {e}")))?;
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
            .map_err(|e| Error::Io(format!("sftp canonicalize: {e}")))
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
        upload_dir_inner(self, local_dir, remote_dir, total_files, &mut counter, progress, 0).await
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
        download_dir_inner(self, remote_dir, local_dir, total_files, &mut counter, progress, 0)
            .await
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
/// packet window. Same constant the prior Dart walker used.
const TRANSFER_CHUNK_SIZE: usize = 65536;

async fn count_local_files(dir: &std::path::Path) -> u64 {
    fn walk(p: std::path::PathBuf) -> std::pin::Pin<Box<dyn std::future::Future<Output = u64> + Send>> {
        Box::pin(async move {
            let mut rd = match tokio::fs::read_dir(&p).await {
                Ok(rd) => rd,
                Err(_) => return 0,
            };
            let mut total: u64 = 0;
            while let Ok(Some(entry)) = rd.next_entry().await {
                let Ok(metadata) = entry.metadata().await else { continue };
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

#[allow(clippy::too_many_arguments)]
fn upload_dir_inner<'a>(
    sftp: &'a Sftp,
    local_dir: &'a str,
    remote_dir: &'a str,
    total_files: u64,
    counter: &'a mut u64,
    progress: &'a (dyn Fn(TransferProgressEvent) -> bool + Send + Sync),
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), Error>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return Err(Error::Io(format!(
                "sftp upload_dir: max depth ({SFTP_MAX_RECURSION_DEPTH}) exceeded at {local_dir}"
            )));
        }
        // mkdir is best-effort — directory may already exist on the remote.
        let _ = sftp.mkdir(remote_dir).await;

        let mut rd = tokio::fs::read_dir(local_dir)
            .await
            .map_err(|e| Error::Io(format!("read_dir {local_dir}: {e}")))?;
        let mut files: Vec<(String, String)> = Vec::new();
        let mut subdirs: Vec<(String, String)> = Vec::new();
        while let Some(entry) = rd
            .next_entry()
            .await
            .map_err(|e| Error::Io(format!("read_dir entry: {e}")))?
        {
            let Ok(metadata) = entry.metadata().await else { continue };
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
            stream_upload_file(sftp, &local_path, &remote_path).await?;
            *counter = counter.saturating_add(1);
            let name = std::path::Path::new(&local_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let cont = progress(TransferProgressEvent {
                file_name: name,
                total_files,
                done_files: *counter,
                is_upload: true,
            });
            if !cont {
                return Err(Error::Cancelled);
            }
        }
        for (local_child, remote_child) in subdirs {
            upload_dir_inner(
                sftp,
                &local_child,
                &remote_child,
                total_files,
                counter,
                progress,
                depth + 1,
            )
            .await?;
        }
        Ok(())
    })
}

#[allow(clippy::too_many_arguments)]
fn download_dir_inner<'a>(
    sftp: &'a Sftp,
    remote_dir: &'a str,
    local_dir: &'a str,
    total_files: u64,
    counter: &'a mut u64,
    progress: &'a (dyn Fn(TransferProgressEvent) -> bool + Send + Sync),
    depth: usize,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), Error>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return Err(Error::Io(format!(
                "sftp download_dir: max depth ({SFTP_MAX_RECURSION_DEPTH}) exceeded at {remote_dir}"
            )));
        }
        tokio::fs::create_dir_all(local_dir)
            .await
            .map_err(|e| Error::Io(format!("create_dir_all {local_dir}: {e}")))?;
        let entries = sftp.list(remote_dir).await?;
        let trimmed = remote_dir.trim_end_matches('/');
        let mut files: Vec<(String, String)> = Vec::new();
        let mut subdirs: Vec<(String, String)> = Vec::new();
        for entry in entries {
            let remote_child = format!("{trimmed}/{}", entry.name);
            let local_child = format!(
                "{}/{}",
                local_dir.trim_end_matches('/'),
                entry.name
            );
            if entry.is_dir {
                subdirs.push((remote_child, local_child));
            } else {
                files.push((remote_child, local_child));
            }
        }

        for (remote_path, local_path) in files {
            stream_download_file(sftp, &remote_path, &local_path).await?;
            *counter = counter.saturating_add(1);
            let name = std::path::Path::new(&local_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let cont = progress(TransferProgressEvent {
                file_name: name,
                total_files,
                done_files: *counter,
                is_upload: false,
            });
            if !cont {
                return Err(Error::Cancelled);
            }
        }
        for (remote_child, local_child) in subdirs {
            download_dir_inner(
                sftp,
                &remote_child,
                &local_child,
                total_files,
                counter,
                progress,
                depth + 1,
            )
            .await?;
        }
        Ok(())
    })
}

async fn stream_upload_file(sftp: &Sftp, local_path: &str, remote_path: &str) -> Result<(), Error> {
    let mut local = tokio::fs::File::open(local_path)
        .await
        .map_err(|e| Error::Io(format!("open {local_path}: {e}")))?;
    let remote = sftp.create(remote_path).await?;
    let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
    loop {
        let n = local
            .read(&mut buf)
            .await
            .map_err(|e| Error::Io(format!("local read {local_path}: {e}")))?;
        if n == 0 {
            break;
        }
        remote.write_all(&buf[..n]).await?;
    }
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
        .map_err(|e| Error::Io(format!("create {local_path}: {e}")))?;
    loop {
        let chunk = remote.read_chunk(TRANSFER_CHUNK_SIZE).await?;
        if chunk.is_empty() {
            break;
        }
        local
            .write_all(&chunk)
            .await
            .map_err(|e| Error::Io(format!("local write {local_path}: {e}")))?;
    }
    local
        .flush()
        .await
        .map_err(|e| Error::Io(format!("local flush {local_path}: {e}")))?;
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
    pub async fn read_chunk(&self, max_bytes: usize) -> Result<Vec<u8>, Error> {
        let mut guard = self.inner.lock().await;
        let mut buf = vec![0u8; max_bytes];
        let n = guard
            .read(&mut buf)
            .await
            .map_err(|e| Error::Io(format!("sftp read: {e}")))?;
        buf.truncate(n);
        Ok(buf)
    }

    /// Write the entire `data` slice to the current position. Returns
    /// when every byte has been queued; russh-sftp pipelines internally
    /// so callers do not need to chunk further for throughput.
    pub async fn write_all(&self, data: &[u8]) -> Result<(), Error> {
        let mut guard = self.inner.lock().await;
        guard
            .write_all(data)
            .await
            .map_err(|e| Error::Io(format!("sftp write: {e}")))
    }

    /// Move the read / write cursor to `offset` bytes from the start
    /// of the file. Used for resumable downloads / sparse uploads.
    pub async fn seek(&self, offset: u64) -> Result<(), Error> {
        let mut guard = self.inner.lock().await;
        guard
            .seek(SeekFrom::Start(offset))
            .await
            .map(|_| ())
            .map_err(|e| Error::Io(format!("sftp seek: {e}")))
    }

    /// Flush buffered writes and instruct the server to fsync to
    /// disk. Best-effort — the server may quietly ignore on
    /// filesystems that do not support sync.
    pub async fn sync_all(&self) -> Result<(), Error> {
        let guard = self.inner.lock().await;
        guard
            .sync_all()
            .await
            .map_err(|e| Error::Io(format!("sftp sync: {e}")))
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
            .map_err(|e| Error::Io(format!("sftp fstat: {e}")))?;
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
