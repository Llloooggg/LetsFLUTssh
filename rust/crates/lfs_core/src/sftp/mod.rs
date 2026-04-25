//! SFTP client surface (russh-sftp-backed, v3 protocol).
//!
//! Sub-phase 1.5a shipped the byte-level CRUD surface — list, read,
//! write, stat, rename, mkdir, remove.
//!
//! Sub-phase 1.5b adds streamed GET/PUT for large files: open
//! returns a `SftpFile` handle, callers pump chunks via `read_chunk`
//! / `write_all` and may seek for resumable transfers. Mirrors
//! dartssh2's `SftpFile.read()` / `writeBytes()` byte-stream surface
//! and feeds the existing transfer queue once the unified
//! SshTransport swap lands.
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
    /// through the streaming surface that lands at sub-phase 1.5b.
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
