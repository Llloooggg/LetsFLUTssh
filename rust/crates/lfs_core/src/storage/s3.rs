//! [`Provider`] impl over the S3 transport in [`crate::s3`].
//!
//! Same shape as [`super::sftp::SftpProvider`] and
//! [`super::webdav::WebDavProvider`]: thin delegate, per-method
//! mapping between the trait surface and the transport's verb
//! shape. The S3 mapping carries one extra concern that does not
//! show up on SFTP or WebDAV — every path the caller hands in
//! resolves to a `(bucket, key)` pair through [`parse_path`]
//! before the wire call goes out.

use std::sync::Arc;

use futures_util::{StreamExt, TryStreamExt};

use super::{ByteStream, Entry, EntryKind, Metadata, Provider, ProviderFuture};
use crate::error::Error;
use crate::s3::client::S3Client;
use crate::s3::multipart::put_object_smart;

/// Wraps an [`S3Client`] in the backend-agnostic
/// [`Provider`] surface. Constructed by the dispatcher once per
/// S3-kind connection.
pub struct S3Provider {
    client: Arc<S3Client>,
}

impl S3Provider {
    pub fn new(client: Arc<S3Client>) -> Self {
        Self { client }
    }

    fn resolve(&self, path: &str) -> Result<(String, String), Error> {
        parse_path(
            path,
            &self.client.config().default_bucket,
            &self.client.config().default_prefix,
        )
    }
}

impl Provider for S3Provider {
    fn list<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Vec<Entry>> {
        Box::pin(async move {
            let (bucket, prefix) = self.resolve(path)?;
            // Walk every page so the caller sees the full listing
            // at once. Per-page paging belongs on a later surface
            // when the UI grows a "load more" affordance.
            let mut out: Vec<Entry> = Vec::new();
            let mut token: Option<String> = None;
            loop {
                let page = self
                    .client
                    .list_objects_v2(&bucket, &prefix, token.as_deref())
                    .await?;
                for obj in page.objects {
                    out.push(entry_from_object(obj, &bucket, &prefix));
                }
                match page.next_continuation_token {
                    Some(t) => token = Some(t),
                    None => break,
                }
            }
            Ok(out)
        })
    }

    fn stat<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Metadata> {
        Box::pin(async move {
            let (bucket, key) = self.resolve(path)?;
            let meta = self.client.head_object(&bucket, &key).await?;
            Ok(Metadata {
                kind: EntryKind::File,
                size_bytes: meta.size,
                modified_unix_ms: meta.last_modified_unix_ms,
            })
        })
    }

    fn mkdir<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move {
            // S3 has no native directories — convention is a
            // 0-byte object whose key ends with `/`. The Provider
            // surface accepts a directory path that may or may not
            // carry the trailing slash; normalise here.
            let (bucket, mut key) = self.resolve(path)?;
            if !key.ends_with('/') {
                key.push('/');
            }
            self.client
                .put_object_single(&bucket, &key, Vec::new())
                .await
        })
    }

    fn remove<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move {
            let (bucket, key) = self.resolve(path)?;
            self.client.delete_object(&bucket, &key).await
        })
    }

    /// **Non-atomic on S3.** The S3 API has no native rename — this
    /// implementation issues `CopyObject` from `from` to `to`
    /// followed by `DeleteObject` against `from`. A concurrent
    /// reader can observe three windows: source only (before copy),
    /// both objects (after copy, before delete), destination only
    /// (after delete). The "both objects" window is also what an
    /// abort observes when the process crashes between the two
    /// requests, or when `DeleteObject` fails after `CopyObject`
    /// already succeeded — the destination is fully written, the
    /// source is still present.
    ///
    /// Crash-safety contract surfaces here: on rerun the caller
    /// re-issues `rename(from, to)`, which is safe because
    /// `CopyObject` overwrites the destination idempotently (S3
    /// PUT semantics) and `DeleteObject` is idempotent on a
    /// missing key. The worst case is one extra round-trip and a
    /// stale `from` lingering until the sync orchestrator's next
    /// pass; never a lost rename.
    ///
    /// Mainstream-S3 providers (AWS S3, R2, MinIO, Backblaze B2's
    /// S3 surface) all share the same lack of atomic rename — this
    /// is an S3 protocol limitation, not a per-provider quirk.
    fn rename<'a>(&'a self, from: &'a str, to: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move {
            let (src_bucket, src_key) = self.resolve(from)?;
            let (dst_bucket, dst_key) = self.resolve(to)?;
            self.client
                .copy_object(&src_bucket, &src_key, &dst_bucket, &dst_key)
                .await?;
            self.client.delete_object(&src_bucket, &src_key).await
        })
    }

    fn get_stream<'a>(
        &'a self,
        path: &'a str,
        range: Option<(u64, u64)>,
    ) -> ProviderFuture<'a, ByteStream> {
        Box::pin(async move {
            let (bucket, key) = self.resolve(path)?;
            let response = self.client.get_object(&bucket, &key, range).await?;
            let stream = response
                .bytes_stream()
                .map_err(|e| Error::S3(format!("get stream: {e}")))
                .boxed();
            Ok(stream)
        })
    }

    fn put_stream<'a>(
        &'a self,
        path: &'a str,
        body: ByteStream,
        len: Option<u64>,
    ) -> ProviderFuture<'a, ()> {
        Box::pin(async move {
            let (bucket, key) = self.resolve(path)?;
            put_object_smart(&self.client, &bucket, &key, body, len).await
        })
    }

    fn dir_size<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, u64> {
        Box::pin(async move {
            let (bucket, prefix) = self.resolve(path)?;
            // ListObjectsV2 with no `delimiter` returns every object
            // under the prefix, flattened — sum `Size` straight off
            // the page. AWS caps at 1000 per page; we walk the
            // continuation tokens.
            let mut total: u64 = 0;
            let mut token: Option<String> = None;
            loop {
                let page = self
                    .client
                    .list_objects_v2(&bucket, &prefix, token.as_deref())
                    .await?;
                for obj in &page.objects {
                    if !obj.is_dir {
                        total = total.saturating_add(obj.size);
                    }
                }
                match page.next_continuation_token {
                    Some(t) => token = Some(t),
                    None => break,
                }
            }
            Ok(total)
        })
    }
}

/// Translate the Provider's path syntax into an `(bucket, key)`
/// pair. Accepts two shapes:
///
/// 1. `s3://bucket/key` — explicit bucket. The `s3://` prefix is
///    purely a Dart-facing convention; this parser also accepts
///    the bare `bucket/key` form a deep-link / drag handler might
///    produce.
/// 2. `key` — relative path. Uses `default_bucket` + prepends
///    `default_prefix`. An empty `default_bucket` rejects the
///    bare-key form so a config error surfaces immediately rather
///    than as a "NoSuchBucket" at the first list.
pub fn parse_path(
    path: &str,
    default_bucket: &str,
    default_prefix: &str,
) -> Result<(String, String), Error> {
    if let Some(rest) = path.strip_prefix("s3://") {
        let mut split = rest.splitn(2, '/');
        let bucket = split.next().unwrap_or("");
        let key = split.next().unwrap_or("");
        if bucket.is_empty() {
            return Err(Error::S3("s3:// path missing bucket".into()));
        }
        return Ok((bucket.to_string(), key.to_string()));
    }
    if default_bucket.is_empty() {
        return Err(Error::S3(
            "no default bucket configured; use s3://bucket/key syntax".into(),
        ));
    }
    let mut key = String::new();
    if !default_prefix.is_empty() {
        key.push_str(default_prefix);
        if !default_prefix.ends_with('/') && !path.starts_with('/') {
            key.push('/');
        }
    }
    let trimmed = path.trim_start_matches('/');
    key.push_str(trimmed);
    Ok((default_bucket.to_string(), key))
}

/// Map one [`crate::s3::client::S3Object`] onto the provider's
/// [`Entry`]. `parent_prefix` is the prefix the listing was made
/// against — common-prefix entries name themselves with the full
/// prefix, so the entry's display name strips the parent off so
/// the file browser does not render `logs/2024/` next to `2024/`.
fn entry_from_object(obj: crate::s3::client::S3Object, bucket: &str, parent_prefix: &str) -> Entry {
    let kind = if obj.is_dir {
        EntryKind::Dir
    } else {
        EntryKind::File
    };
    let name = display_name(&obj.key, parent_prefix);
    Entry {
        path: format!("s3://{bucket}/{}", obj.key),
        name,
        kind,
        size_bytes: obj.size,
        modified_unix_ms: obj.last_modified_unix_ms,
    }
}

/// Strip the parent prefix off the key and drop any trailing `/`
/// for common-prefix entries. Empty result falls back to the raw
/// key so the browser never renders a blank row.
fn display_name(key: &str, parent_prefix: &str) -> String {
    let stripped = key.strip_prefix(parent_prefix).unwrap_or(key);
    let trimmed = stripped.trim_end_matches('/');
    if trimmed.is_empty() {
        key.to_string()
    } else {
        trimmed.to_string()
    }
}
#[cfg(test)]
#[path = "../../tests/unit/storage_s3.rs"]
mod tests;
