//! FRB adapter for `lfs_core::sftp`. Long-lived `SftpSession`-style
//! client opened off an `SshSession`; methods exposed as Dart calls
//! returning futures / typed Dart exceptions on error.
//!
//! Sub-phase 1.5a — byte-level CRUD only. Streaming GET/PUT for
//! large files (progress-reporting) lands at sub-phase 1.5b.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::ssh::SshSession;

/// Live SFTP client tied to a single `SshSession`. Drop on the Dart
/// side closes the underlying channel; russh tears it down even
/// without an explicit `close`.
#[frb(opaque)]
pub struct SshSftp {
    inner: Arc<lfs_core::sftp::Sftp>,
}

/// One directory entry surfaced by `SshSftp::list`.
#[derive(Debug, Clone)]
pub struct SftpDirEntry {
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
    pub is_symlink: bool,
    /// Unix epoch seconds, `null` on the Dart side when the server
    /// omitted mtime or a translation failed.
    pub modified_unix: Option<i64>,
    /// POSIX mode bits (e.g. 0o755). `0` when unavailable.
    pub permissions: u32,
}

impl From<lfs_core::sftp::DirEntry> for SftpDirEntry {
    fn from(e: lfs_core::sftp::DirEntry) -> Self {
        SftpDirEntry {
            name: e.name,
            size: e.size,
            is_dir: e.is_dir,
            is_symlink: e.is_symlink,
            modified_unix: e.modified_unix,
            permissions: e.permissions,
        }
    }
}

/// File metadata surfaced by `SshSftp::stat` / `stat_symlink`.
#[derive(Debug, Clone)]
pub struct SftpFileMetadata {
    pub size: u64,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub modified_unix: Option<i64>,
    pub permissions: u32,
}

impl From<lfs_core::sftp::FileMetadata> for SftpFileMetadata {
    fn from(m: lfs_core::sftp::FileMetadata) -> Self {
        SftpFileMetadata {
            size: m.size,
            is_dir: m.is_dir,
            is_symlink: m.is_symlink,
            modified_unix: m.modified_unix,
            permissions: m.permissions,
        }
    }
}

impl SshSftp {
    /// List a directory.
    pub async fn list(&self, path: String) -> Result<Vec<SftpDirEntry>, String> {
        let entries = self.inner.list(&path).await.map_err(|e| e.to_string())?;
        Ok(entries.into_iter().map(SftpDirEntry::from).collect())
    }

    /// Read a small file fully into memory. Use the streaming surface
    /// (sub-phase 1.5b) for files larger than a few MB.
    pub async fn read_file(&self, path: String) -> Result<Vec<u8>, String> {
        self.inner.read_file(&path).await.map_err(|e| e.to_string())
    }

    /// Overwrite a small file with `data`.
    pub async fn write_file(&self, path: String, data: Vec<u8>) -> Result<(), String> {
        self.inner
            .write_file(&path, &data)
            .await
            .map_err(|e| e.to_string())
    }

    /// Stat a path (resolves symlinks).
    pub async fn stat(&self, path: String) -> Result<SftpFileMetadata, String> {
        self.inner
            .stat(&path)
            .await
            .map(SftpFileMetadata::from)
            .map_err(|e| e.to_string())
    }

    /// Stat a path without resolving symlinks.
    pub async fn stat_symlink(&self, path: String) -> Result<SftpFileMetadata, String> {
        self.inner
            .stat_symlink(&path)
            .await
            .map(SftpFileMetadata::from)
            .map_err(|e| e.to_string())
    }

    /// Rename / move.
    pub async fn rename(&self, old_path: String, new_path: String) -> Result<(), String> {
        self.inner
            .rename(&old_path, &new_path)
            .await
            .map_err(|e| e.to_string())
    }

    /// Create a directory (single level — caller walks for `mkdir -p`).
    pub async fn mkdir(&self, path: String) -> Result<(), String> {
        self.inner.mkdir(&path).await.map_err(|e| e.to_string())
    }

    /// Remove a regular file.
    pub async fn remove_file(&self, path: String) -> Result<(), String> {
        self.inner
            .remove_file(&path)
            .await
            .map_err(|e| e.to_string())
    }

    /// Remove an empty directory.
    pub async fn remove_dir(&self, path: String) -> Result<(), String> {
        self.inner
            .remove_dir(&path)
            .await
            .map_err(|e| e.to_string())
    }

    /// Resolve a path against the server's working directory.
    /// Expands `~` / relative paths the remote shell would resolve.
    pub async fn canonicalize(&self, path: String) -> Result<String, String> {
        self.inner
            .canonicalize(&path)
            .await
            .map_err(|e| e.to_string())
    }
}

/// Open an SFTP subsystem on a fresh channel of the given session.
/// Multiple SFTP clients can coexist on one SSH session — each call
/// allocates a new channel.
pub async fn ssh_open_sftp(session: &SshSession) -> Result<SshSftp, String> {
    let sftp = session.open_sftp_inner().await?;
    Ok(SshSftp {
        inner: Arc::new(sftp),
    })
}

// ---- Streaming file handle (1.5b) ------------------------------------

/// Open SFTP file. Used for streamed GET / PUT of large files. Drop
/// closes the handle.
#[frb(opaque)]
pub struct SshSftpFile {
    inner: Arc<lfs_core::sftp::SftpFile>,
}

impl SshSftpFile {
    /// Read up to `max_bytes` starting at the current cursor. Empty
    /// `Vec` signals EOF.
    pub async fn read_chunk(&self, max_bytes: u32) -> Result<Vec<u8>, String> {
        self.inner
            .read_chunk(max_bytes as usize)
            .await
            .map_err(|e| e.to_string())
    }

    /// Write the entire `data` slice at the current cursor.
    pub async fn write_all(&self, data: Vec<u8>) -> Result<(), String> {
        self.inner.write_all(&data).await.map_err(|e| e.to_string())
    }

    /// Move the cursor to `offset` bytes from the start of the file.
    pub async fn seek(&self, offset: u64) -> Result<(), String> {
        self.inner.seek(offset).await.map_err(|e| e.to_string())
    }

    /// Flush + fsync (best-effort — server may ignore).
    pub async fn sync_all(&self) -> Result<(), String> {
        self.inner.sync_all().await.map_err(|e| e.to_string())
    }

    /// Stat the open handle (no extra round-trip).
    pub async fn metadata(&self) -> Result<SftpFileMetadata, String> {
        self.inner
            .metadata()
            .await
            .map(SftpFileMetadata::from)
            .map_err(|e| e.to_string())
    }
}

/// Open a remote file for reading. Use `SshSftpFile::read_chunk`
/// to pump bytes, or `metadata` first to grab `size` for progress
/// reporting.
pub async fn ssh_sftp_open(sftp: &SshSftp, path: String) -> Result<SshSftpFile, String> {
    let file = sftp.inner.open(&path).await.map_err(|e| e.to_string())?;
    Ok(SshSftpFile {
        inner: Arc::new(file),
    })
}

/// Open a remote file for writing, truncating any existing content.
pub async fn ssh_sftp_create(sftp: &SshSftp, path: String) -> Result<SshSftpFile, String> {
    let file = sftp.inner.create(&path).await.map_err(|e| e.to_string())?;
    Ok(SshSftpFile {
        inner: Arc::new(file),
    })
}
