//! [`Provider`] implementation backed by `lfs_core::sftp::Sftp`.
//!
//! `SftpProvider` is a thin wrapper: every trait method delegates
//! to the equivalent on `Sftp`, with type mapping at the
//! boundary (russh-sftp's `DirEntry` / `FileMetadata` ↔ the
//! provider's [`Entry`] / [`Metadata`]) and a small amount of
//! glue where the trait surface is uniform but SFTP's isn't —
//! [`SftpProvider::remove`] stats first so it can dispatch
//! between `Sftp::remove_file` and `Sftp::remove_dir`.
//!
//! The engine code in `lfs_core::sftp` stays the FRB surface's
//! single source of truth for SFTP today. Provider polymorphism
//! becomes visible at the FRB / Dart layer when the second
//! backend (S3, WebDAV) lands and the dispatcher routes by
//! `(connection_id, kind)`.

use std::pin::Pin;
use std::sync::Arc;

use bytes::Bytes;
use futures_util::stream::{self, BoxStream, StreamExt};

use crate::error::Error;
use crate::sftp::{DirEntry, FileMetadata, Sftp, SftpFile, SFTP_MAX_RECURSION_DEPTH};
use crate::storage::{ByteStream, Entry, EntryKind, Metadata, Provider, ProviderFuture};

/// Chunk size for streamed GET / PUT. Matches `lfs_core::sftp`'s
/// internal `TRANSFER_CHUNK_SIZE` (64 KiB) — the existing
/// transfer driver settled on that value so single-stream SFTP
/// reads saturate the SSH channel window without per-chunk
/// round-trips. Re-using the constant size keeps the streaming
/// provider behaviour identical to the per-file transfer path.
const STREAM_CHUNK_BYTES: usize = 65536;

/// [`Provider`] backed by a live `Sftp` engine. Holds the engine
/// behind `Arc` so streams returned by [`SftpProvider::get_stream`]
/// can outlive the trait method call and keep the engine alive
/// for as long as the caller pumps chunks.
pub struct SftpProvider {
    sftp: Arc<Sftp>,
}

impl SftpProvider {
    /// Wrap an existing `Sftp` engine. The caller already opened
    /// the SFTP session off a live `ssh::Session`; the provider
    /// borrows that engine through `Arc` rather than owning the
    /// SSH transport itself.
    pub fn new(sftp: Arc<Sftp>) -> Self {
        Self { sftp }
    }
}

impl Provider for SftpProvider {
    fn list<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Vec<Entry>> {
        Box::pin(async move {
            let entries = self.sftp.list(path).await?;
            let trimmed = path.trim_end_matches('/');
            let mapped = entries
                .into_iter()
                .map(|e| entry_from_dir_entry(&e, trimmed))
                .collect();
            Ok(mapped)
        })
    }

    fn stat<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Metadata> {
        Box::pin(async move {
            let meta = self.sftp.stat(path).await?;
            Ok(metadata_from_file_metadata(&meta))
        })
    }

    fn mkdir<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move { self.sftp.mkdir(path).await })
    }

    fn remove<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()> {
        // SFTP splits the remove surface into `remove_file` / `remove_dir`;
        // the provider trait does not. One stat round-trip per remove is
        // the cost of preserving the uniform surface — callers that need
        // to skip it can drop down to `lfs_core::sftp::Sftp` directly.
        Box::pin(async move {
            let meta = self.sftp.stat(path).await?;
            if meta.is_dir {
                self.sftp.remove_dir(path).await
            } else {
                self.sftp.remove_file(path).await
            }
        })
    }

    fn rename<'a>(&'a self, from: &'a str, to: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move { self.sftp.rename(from, to).await })
    }

    fn get_stream<'a>(
        &'a self,
        path: &'a str,
        range: Option<(u64, u64)>,
    ) -> ProviderFuture<'a, ByteStream> {
        let sftp = Arc::clone(&self.sftp);
        Box::pin(async move {
            let file = sftp.open(path).await?;
            let limit = match range {
                Some((start, end)) => {
                    if end < start {
                        return Err(Error::Sftp(format!(
                            "sftp get_stream: invalid range start={start} end={end}"
                        )));
                    }
                    file.seek(start).await?;
                    // Range is inclusive on both ends — matches HTTP
                    // `Range: bytes=start-end` semantics so a future
                    // S3 / WebDAV provider can forward the same tuple
                    // unchanged.
                    Some(end.saturating_sub(start).saturating_add(1))
                }
                None => None,
            };
            let state = ReadState {
                file,
                remaining: limit,
            };
            let stream = stream::try_unfold(state, |mut s| async move {
                let max = match s.remaining {
                    Some(0) => return Ok(None),
                    // Cap by chunk size first (always fits in `usize`),
                    // then narrow — `rem` is `u64` so a 32-bit `usize`
                    // would truncate without the chunk-size floor.
                    Some(rem) => std::cmp::min(rem, STREAM_CHUNK_BYTES as u64) as usize,
                    None => STREAM_CHUNK_BYTES,
                };
                let mut buf = vec![0u8; max];
                let n = s.file.read_into(&mut buf).await?;
                if n == 0 {
                    return Ok(None);
                }
                buf.truncate(n);
                if let Some(rem) = s.remaining.as_mut() {
                    *rem = rem.saturating_sub(n as u64);
                }
                Ok(Some((Bytes::from(buf), s)))
            });
            let boxed: BoxStream<'static, Result<Bytes, Error>> = Box::pin(stream);
            Ok(boxed)
        })
    }

    fn put_stream<'a>(
        &'a self,
        path: &'a str,
        mut body: ByteStream,
        _len: Option<u64>,
    ) -> ProviderFuture<'a, ()> {
        // `_len` is a hint only — SFTP writes are length-agnostic.
        // S3's single-shot PUT uses it to pick between single-part
        // and multipart; SFTP forwards every chunk into the open
        // handle and fsyncs at the end.
        Box::pin(async move {
            let file = self.sftp.create(path).await?;
            while let Some(chunk) = body.next().await {
                let bytes = chunk?;
                if !bytes.is_empty() {
                    file.write_all(&bytes).await?;
                }
            }
            file.sync_all().await?;
            Ok(())
        })
    }

    fn dir_size<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, u64> {
        Box::pin(async move { dir_size_inner(self.sftp.as_ref(), path, 0).await })
    }
}

/// Streaming state for [`SftpProvider::get_stream`]. `remaining`
/// is `Some(n)` when a byte range bounded the read and `None` for
/// a full-file pump.
struct ReadState {
    file: SftpFile,
    remaining: Option<u64>,
}

/// Map russh-sftp's `DirEntry` onto a provider [`Entry`].
///
/// Path-joining stays here because the provider trait gives back
/// absolute paths; the engine's `DirEntry` only carries the
/// child name. `parent_trimmed` already had its trailing `/`
/// stripped by the caller so the join is a single `/` insert.
pub(crate) fn entry_from_dir_entry(entry: &DirEntry, parent_trimmed: &str) -> Entry {
    Entry {
        name: entry.name.clone(),
        path: format!("{parent_trimmed}/{}", entry.name),
        kind: kind_from_flags(entry.is_dir, entry.is_symlink),
        size_bytes: entry.size,
        modified_unix_ms: entry.modified_unix.map(unix_seconds_to_ms),
    }
}

/// Map russh-sftp's `FileMetadata` onto a provider [`Metadata`].
pub(crate) fn metadata_from_file_metadata(meta: &FileMetadata) -> Metadata {
    Metadata {
        kind: kind_from_flags(meta.is_dir, meta.is_symlink),
        size_bytes: meta.size,
        modified_unix_ms: meta.modified_unix.map(unix_seconds_to_ms),
    }
}

/// Collapse the `(is_dir, is_symlink)` tuple SFTP carries into
/// the provider's tri-state [`EntryKind`].
///
/// Symlink wins over dir: a server that resolves a symlink's
/// target as a directory still sets `is_symlink = true`, and
/// callers need to know "this is a link" so they can either
/// follow or treat it specially (the SFTP remove walker
/// unlinks the symlink itself rather than recursing into the
/// pointed-to subtree).
fn kind_from_flags(is_dir: bool, is_symlink: bool) -> EntryKind {
    if is_symlink {
        EntryKind::Symlink
    } else if is_dir {
        EntryKind::Dir
    } else {
        EntryKind::File
    }
}

/// SFTP mtime is unix epoch seconds; the provider surface
/// exchanges milliseconds so HTTP-backed backends (S3
/// `Last-Modified`, WebDAV `getlastmodified`) match without
/// truncation.
fn unix_seconds_to_ms(secs: i64) -> i64 {
    secs.saturating_mul(1_000)
}

/// Recursive directory size walker. DFS — call `list` on the
/// current path, sum file sizes inline, recurse into each
/// subdirectory. Stops at the same depth cap as the SFTP
/// `remove_dir_recursive` walker (100 levels) so a cyclic symlink
/// tree fails fast instead of blowing the stack.
///
/// O(N) cost where N is the entry count under `path`. Backends
/// with a native aggregate (S3 `ListObjectsV2` summing `Size`
/// over a prefix) override [`Provider::dir_size`] instead.
fn dir_size_inner<'a>(
    sftp: &'a Sftp,
    path: &'a str,
    depth: usize,
) -> Pin<Box<dyn std::future::Future<Output = Result<u64, Error>> + Send + 'a>> {
    Box::pin(async move {
        if depth >= SFTP_MAX_RECURSION_DEPTH {
            return Ok(0);
        }
        let entries = sftp.list(path).await?;
        let trimmed = path.trim_end_matches('/');
        let mut total: u64 = 0;
        for entry in entries {
            // Symlinks aren't followed — same rationale as
            // `Sftp::remove_dir_recursive`. A symlink-to-dir
            // would otherwise inflate the count by the target
            // subtree, which is outside the directory the
            // caller asked about.
            if entry.is_symlink {
                continue;
            }
            if entry.is_dir {
                let child = format!("{trimmed}/{}", entry.name);
                total = total.saturating_add(dir_size_inner(sftp, &child, depth + 1).await?);
            } else {
                total = total.saturating_add(entry.size);
            }
        }
        Ok(total)
    })
}
#[cfg(test)]
#[path = "../../tests/unit/storage_sftp.rs"]
mod tests;
