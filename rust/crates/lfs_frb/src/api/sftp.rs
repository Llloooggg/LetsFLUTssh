//! FRB adapter for `lfs_core::sftp`. Long-lived `SftpSession`-style
//! client opened off an `SshSession`; methods exposed as Dart calls
//! returning futures / typed Dart exceptions on error.
//!
//! Byte-level CRUD only. Streaming GET/PUT for large files
//! (progress-reporting) lands in a follow-up.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::ssh::SshSession;

/// Per-file progress event emitted by [`SshSftp::upload_dir`] /
/// [`SshSftp::download_dir`]. The Dart caller wraps each event
/// into the existing `TransferProgress` Flutter-side model.
#[derive(Debug, Clone)]
pub struct DbTransferProgress {
    pub file_name: String,
    pub total_files: u64,
    pub done_files: u64,
    pub is_upload: bool,
}

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

#[cfg(test)]
mod tests {
    use super::*;

    // The opaque `SshSftp` channel methods (list / read / write /
    // mkdir / rename / unlink / streaming up/down) need a live
    // `lfs_core::ssh::Session` against the russh test fixture; the
    // Dart `connection_lifecycle_test.dart` integration suite drives
    // them end-to-end. The standalone tests below pin the wire-shape
    // `From` mappings that cross the FRB boundary on every list /
    // stat call regardless of transport state.

    #[test]
    fn dir_entry_carries_every_field_through() {
        let core = lfs_core::sftp::DirEntry {
            name: "config.json".into(),
            size: 4096,
            is_dir: false,
            is_symlink: false,
            modified_unix: Some(1_700_000_000),
            permissions: 0o644,
        };
        let db: SftpDirEntry = core.into();
        assert_eq!(db.name, "config.json");
        assert_eq!(db.size, 4096);
        assert!(!db.is_dir);
        assert!(!db.is_symlink);
        assert_eq!(db.modified_unix, Some(1_700_000_000));
        assert_eq!(db.permissions, 0o644);
    }

    #[test]
    fn dir_entry_handles_dir_and_symlink_combinations() {
        for (is_dir, is_symlink) in [(false, false), (true, false), (false, true), (true, true)] {
            let core = lfs_core::sftp::DirEntry {
                name: "x".into(),
                size: 0,
                is_dir,
                is_symlink,
                modified_unix: None,
                permissions: 0,
            };
            let db: SftpDirEntry = core.into();
            assert_eq!(db.is_dir, is_dir);
            assert_eq!(db.is_symlink, is_symlink);
        }
    }

    #[test]
    fn file_metadata_round_trips_unset_mtime_as_none() {
        // Servers that omit mtime in stat replies surface as `None`;
        // pin the contract so a future refactor doesn't accidentally
        // collapse to `Some(0)` (which means "1970-01-01 boot").
        let core = lfs_core::sftp::FileMetadata {
            size: 0,
            is_dir: true,
            is_symlink: false,
            modified_unix: None,
            permissions: 0o755,
        };
        let db: SftpFileMetadata = core.into();
        assert!(db.modified_unix.is_none());
        assert!(db.is_dir);
        assert_eq!(db.permissions, 0o755);
    }

    #[test]
    fn file_metadata_carries_every_field_through() {
        let core = lfs_core::sftp::FileMetadata {
            size: 1024 * 1024 * 100, // 100 MiB
            is_dir: false,
            is_symlink: true,
            modified_unix: Some(1_700_000_000),
            permissions: 0o600,
        };
        let db: SftpFileMetadata = core.into();
        assert_eq!(db.size, 100 * 1024 * 1024);
        assert!(!db.is_dir);
        assert!(db.is_symlink);
        assert_eq!(db.modified_unix, Some(1_700_000_000));
        assert_eq!(db.permissions, 0o600);
    }
}

impl SshSftp {
    /// List a directory.
    pub async fn list(&self, path: String) -> Result<Vec<SftpDirEntry>, String> {
        let entries = self
            .inner
            .list(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        Ok(entries.into_iter().map(SftpDirEntry::from).collect())
    }

    /// Read a small file fully into memory. Use the streaming
    /// surface for files larger than a few MB.
    pub async fn read_file(&self, path: String) -> Result<Vec<u8>, String> {
        self.inner
            .read_file(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Overwrite a small file with `data`.
    pub async fn write_file(&self, path: String, data: Vec<u8>) -> Result<(), String> {
        self.inner
            .write_file(&path, &data)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Stat a path (resolves symlinks).
    pub async fn stat(&self, path: String) -> Result<SftpFileMetadata, String> {
        self.inner
            .stat(&path)
            .await
            .map(SftpFileMetadata::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Stat a path without resolving symlinks.
    pub async fn stat_symlink(&self, path: String) -> Result<SftpFileMetadata, String> {
        self.inner
            .stat_symlink(&path)
            .await
            .map(SftpFileMetadata::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Rename / move.
    pub async fn rename(&self, old_path: String, new_path: String) -> Result<(), String> {
        self.inner
            .rename(&old_path, &new_path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Create a directory (single level — caller walks for `mkdir -p`).
    pub async fn mkdir(&self, path: String) -> Result<(), String> {
        self.inner
            .mkdir(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Remove a regular file.
    pub async fn remove_file(&self, path: String) -> Result<(), String> {
        self.inner
            .remove_file(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Remove an empty directory.
    pub async fn remove_dir(&self, path: String) -> Result<(), String> {
        self.inner
            .remove_dir(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Recursively delete a remote directory tree. The walk is
    /// owned by `lfs_core::sftp::Sftp::remove_dir_recursive` so
    /// the Dart caller pays one FRB roundtrip instead of N
    /// (one per file + one per directory). Hard depth cap of
    /// 100 mirrors the prior Dart `sftpMaxRecursionDepth`.
    pub async fn remove_dir_recursive(&self, path: String) -> Result<(), String> {
        self.inner
            .remove_dir_recursive(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Recursively upload a local directory tree into a remote
    /// path. The walker (in `lfs_core::sftp`) handles mkdir +
    /// per-file streaming + depth cap; this shim forwards the
    /// per-file completion event to `sink`. Dart cancellation
    /// (subscription cancelled) closes the sink → the next
    /// progress emission fails → the walker returns
    /// `Error::Cancelled`.
    pub async fn upload_dir(
        &self,
        local_dir: String,
        remote_dir: String,
        sink: crate::frb_generated::StreamSink<DbTransferProgress>,
    ) -> Result<(), String> {
        let cancelled = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let cancelled_cb = cancelled.clone();
        let result = self
            .inner
            .upload_dir(&local_dir, &remote_dir, &move |evt| {
                if cancelled_cb.load(std::sync::atomic::Ordering::SeqCst) {
                    return false;
                }
                let ok = sink
                    .add(DbTransferProgress {
                        file_name: evt.file_name,
                        total_files: evt.total_files,
                        done_files: evt.done_files,
                        is_upload: evt.is_upload,
                    })
                    .is_ok();
                if !ok {
                    cancelled_cb.store(true, std::sync::atomic::Ordering::SeqCst);
                }
                ok
            })
            .await;
        result.map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Recursively download a remote directory tree into a local
    /// path. Mirror of [`upload_dir`] — same cancellation +
    /// progress contract.
    pub async fn download_dir(
        &self,
        remote_dir: String,
        local_dir: String,
        sink: crate::frb_generated::StreamSink<DbTransferProgress>,
    ) -> Result<(), String> {
        let cancelled = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let cancelled_cb = cancelled.clone();
        let result = self
            .inner
            .download_dir(&remote_dir, &local_dir, &move |evt| {
                if cancelled_cb.load(std::sync::atomic::Ordering::SeqCst) {
                    return false;
                }
                let ok = sink
                    .add(DbTransferProgress {
                        file_name: evt.file_name,
                        total_files: evt.total_files,
                        done_files: evt.done_files,
                        is_upload: evt.is_upload,
                    })
                    .is_ok();
                if !ok {
                    cancelled_cb.store(true, std::sync::atomic::Ordering::SeqCst);
                }
                ok
            })
            .await;
        result.map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Resolve a path against the server's working directory.
    /// Expands `~` / relative paths the remote shell would resolve.
    pub async fn canonicalize(&self, path: String) -> Result<String, String> {
        self.inner
            .canonicalize(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Streamed single-file upload. Replaces the per-chunk Dart
    /// `writeAll` loop on the SFTP transfer hot path — the entire
    /// 64 KiB-chunked copy now lives Rust-side; the Dart side
    /// receives a single FRB call's worth of stream events instead
    /// of N round-trips per file. `sink` receives one
    /// [`DbTransferProgressBytes`] per chunk written; subscription
    /// cancellation closes the sink → next `add` fails →
    /// `lfs_core` translates to `Error::Cancelled`.
    pub async fn stream_upload_file(
        &self,
        local_path: String,
        remote_path: String,
        sink: crate::frb_generated::StreamSink<DbTransferProgressBytes>,
    ) -> Result<(), String> {
        let cancelled = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let cancelled_cb = cancelled.clone();
        let result = self
            .inner
            .upload_file_streaming(&local_path, &remote_path, &move |done, total| {
                if cancelled_cb.load(std::sync::atomic::Ordering::SeqCst) {
                    return false;
                }
                let ok = sink
                    .add(DbTransferProgressBytes {
                        done_bytes: done,
                        total_bytes: total,
                        is_upload: true,
                    })
                    .is_ok();
                if !ok {
                    cancelled_cb.store(true, std::sync::atomic::Ordering::SeqCst);
                }
                ok
            })
            .await;
        result.map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Streamed single-file download — mirror of
    /// [`stream_upload_file`].
    pub async fn stream_download_file(
        &self,
        remote_path: String,
        local_path: String,
        sink: crate::frb_generated::StreamSink<DbTransferProgressBytes>,
    ) -> Result<(), String> {
        let cancelled = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let cancelled_cb = cancelled.clone();
        let result = self
            .inner
            .download_file_streaming(&remote_path, &local_path, &move |done, total| {
                if cancelled_cb.load(std::sync::atomic::Ordering::SeqCst) {
                    return false;
                }
                let ok = sink
                    .add(DbTransferProgressBytes {
                        done_bytes: done,
                        total_bytes: total,
                        is_upload: false,
                    })
                    .is_ok();
                if !ok {
                    cancelled_cb.store(true, std::sync::atomic::Ordering::SeqCst);
                }
                ok
            })
            .await;
        result.map_err(|e| crate::api::frb_err::from_core(&e))
    }
}

/// Per-byte transfer progress event emitted by
/// [`SshSftp::stream_upload_file`] / [`SshSftp::stream_download_file`].
/// `total_bytes` is the file size known up front (local stat for
/// upload, remote stat for download); `done_bytes` is the running
/// sum across chunks.
#[derive(Debug, Clone)]
pub struct DbTransferProgressBytes {
    pub done_bytes: u64,
    pub total_bytes: u64,
    pub is_upload: bool,
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
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Write the entire `data` slice at the current cursor.
    pub async fn write_all(&self, data: Vec<u8>) -> Result<(), String> {
        self.inner
            .write_all(&data)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Move the cursor to `offset` bytes from the start of the file.
    pub async fn seek(&self, offset: u64) -> Result<(), String> {
        self.inner
            .seek(offset)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Flush + fsync (best-effort — server may ignore).
    pub async fn sync_all(&self) -> Result<(), String> {
        self.inner
            .sync_all()
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Stat the open handle (no extra round-trip).
    pub async fn metadata(&self) -> Result<SftpFileMetadata, String> {
        self.inner
            .metadata()
            .await
            .map(SftpFileMetadata::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }
}

/// Open a remote file for reading. Use `SshSftpFile::read_chunk`
/// to pump bytes, or `metadata` first to grab `size` for progress
/// reporting.
pub async fn ssh_sftp_open(sftp: &SshSftp, path: String) -> Result<SshSftpFile, String> {
    let file = sftp
        .inner
        .open(&path)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSftpFile {
        inner: Arc::new(file),
    })
}

/// Open a remote file for writing, truncating any existing content.
pub async fn ssh_sftp_create(sftp: &SshSftp, path: String) -> Result<SshSftpFile, String> {
    let file = sftp
        .inner
        .create(&path)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSftpFile {
        inner: Arc::new(file),
    })
}
