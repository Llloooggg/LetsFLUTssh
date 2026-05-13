//! [`Provider`] impl over the WebDAV transport in
//! [`crate::webdav`]. The wrapper owns an `Arc<WebDavClient>` so
//! multiple `Provider` calls share one HTTP connection pool +
//! cached digest-auth challenge.
//!
//! Same shape as [`super::sftp::SftpProvider`]: thin delegate, no
//! per-method logic beyond translating `Entry` / `Metadata` types
//! and wiring the stream end of GET / PUT to the trait's
//! [`ByteStream`] alias.

use std::sync::Arc;

use bytes::Bytes;
use futures_util::{StreamExt, TryStreamExt};

use super::{ByteStream, Entry, EntryKind, Metadata, Provider, ProviderFuture};
use crate::error::Error;
use crate::webdav::{PropfindEntry, WebDavClient};

/// Thin wrapper that exposes a [`WebDavClient`] through the
/// backend-agnostic [`Provider`] surface. Constructed by the
/// dispatcher once per WebDAV-kind connection.
pub struct WebDavProvider {
    client: Arc<WebDavClient>,
}

impl WebDavProvider {
    pub fn new(client: Arc<WebDavClient>) -> Self {
        Self { client }
    }
}

impl Provider for WebDavProvider {
    fn list<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Vec<Entry>> {
        Box::pin(async move {
            let entries = self.client.propfind(path, 1).await?;
            // PROPFIND depth=1 includes the listed directory itself
            // as the first entry per RFC 4918; skip it so the surface
            // matches SFTP's "children only" semantics.
            let listed_href = first_href(&entries);
            let out = entries
                .into_iter()
                .filter(|e| match listed_href.as_deref() {
                    Some(root) => e.href != root,
                    None => true,
                })
                .map(entry_from_propfind)
                .collect();
            Ok(out)
        })
    }

    fn stat<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, Metadata> {
        Box::pin(async move {
            let entries = self.client.propfind(path, 0).await?;
            let entry = entries
                .into_iter()
                .next()
                .ok_or_else(|| Error::WebDav("stat: empty multistatus".into()))?;
            Ok(metadata_from_propfind(&entry))
        })
    }

    fn mkdir<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move { self.client.mkcol(path).await })
    }

    fn remove<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, ()> {
        Box::pin(async move { self.client.delete(path).await })
    }

    fn rename<'a>(&'a self, from: &'a str, to: &'a str) -> ProviderFuture<'a, ()> {
        // `overwrite=false` matches Provider's SFTP-style contract —
        // a caller that wants to overwrite removes the target first.
        Box::pin(async move { self.client.move_resource(from, to, false).await })
    }

    fn get_stream<'a>(
        &'a self,
        path: &'a str,
        range: Option<(u64, u64)>,
    ) -> ProviderFuture<'a, ByteStream> {
        Box::pin(async move {
            let response = self.client.get(path, range, None).await?;
            // `bytes_stream` yields `Result<Bytes, reqwest::Error>`;
            // map the error onto the project's typed `Error::WebDav`
            // so the trait's `ByteStream = BoxStream<Result<Bytes, Error>>`
            // shape holds.
            let stream = response
                .bytes_stream()
                .map_err(|e| Error::WebDav(format!("get stream: {e}")))
                .boxed();
            Ok(stream)
        })
    }

    fn put_stream<'a>(
        &'a self,
        path: &'a str,
        body: ByteStream,
        _len: Option<u64>,
    ) -> ProviderFuture<'a, ()> {
        Box::pin(async move {
            // Drain the stream into a single `Bytes` buffer.
            // The current `WebDavClient::put` takes an owned
            // `Bytes`; a future commit can extend it to accept a
            // `reqwest::Body::wrap_stream` for true zero-copy chunked
            // upload on large objects. For sync archives (typically
            // < 50 MiB) the buffered shape stays well inside RAM.
            let mut buf = Vec::new();
            let mut stream = body;
            while let Some(chunk) = stream.next().await {
                let chunk = chunk?;
                buf.extend_from_slice(&chunk);
            }
            self.client.put(path, Bytes::from(buf), None).await?;
            Ok(())
        })
    }

    fn dir_size<'a>(&'a self, path: &'a str) -> ProviderFuture<'a, u64> {
        Box::pin(async move { walk_dir_size(&self.client, path).await })
    }
}

/// Walks the WebDAV tree depth-first via PROPFIND depth=1 calls,
/// summing file sizes. Symlinks don't exist in WebDAV's data model
/// so every non-collection entry contributes its `getcontentlength`.
async fn walk_dir_size(client: &WebDavClient, root: &str) -> Result<u64, Error> {
    const MAX_DEPTH: u32 = 100;
    let mut total: u64 = 0;
    let mut stack: Vec<(String, u32)> = vec![(root.to_string(), 0)];
    while let Some((path, depth)) = stack.pop() {
        if depth >= MAX_DEPTH {
            return Err(Error::WebDav(format!(
                "dir_size: depth {MAX_DEPTH} exceeded at {path}"
            )));
        }
        let entries = client.propfind(&path, 1).await?;
        let listed_href = first_href(&entries);
        for entry in entries {
            if let Some(root_href) = listed_href.as_deref() {
                if entry.href == root_href {
                    continue;
                }
            }
            if entry.is_collection {
                stack.push((entry.href, depth + 1));
            } else {
                total = total.saturating_add(entry.size_bytes.unwrap_or(0));
            }
        }
    }
    Ok(total)
}

fn first_href(entries: &[PropfindEntry]) -> Option<String> {
    entries.first().map(|e| e.href.clone())
}

pub(crate) fn entry_from_propfind(p: PropfindEntry) -> Entry {
    let kind = if p.is_collection {
        EntryKind::Dir
    } else {
        EntryKind::File
    };
    let name = href_basename(&p.href, p.is_collection)
        .or(p.display_name.clone())
        .unwrap_or_default();
    Entry {
        path: p.href,
        name,
        kind,
        size_bytes: p.size_bytes.unwrap_or(0),
        modified_unix_ms: p.last_modified_unix_ms,
    }
}

pub(crate) fn metadata_from_propfind(p: &PropfindEntry) -> Metadata {
    let kind = if p.is_collection {
        EntryKind::Dir
    } else {
        EntryKind::File
    };
    Metadata {
        kind,
        size_bytes: p.size_bytes.unwrap_or(0),
        modified_unix_ms: p.last_modified_unix_ms,
    }
}

/// Strip the trailing slash (for collections) and return the last
/// path component. Returns `None` for the bare root (`/`).
fn href_basename(href: &str, is_collection: bool) -> Option<String> {
    let trimmed = if is_collection {
        href.trim_end_matches('/')
    } else {
        href
    };
    let last = trimmed.rsplit('/').next()?;
    if last.is_empty() {
        return None;
    }
    Some(last.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pe(href: &str, is_collection: bool, size: Option<u64>, mtime: Option<i64>) -> PropfindEntry {
        PropfindEntry {
            href: href.into(),
            display_name: None,
            size_bytes: size,
            last_modified_unix_ms: mtime,
            etag: None,
            content_type: None,
            is_collection,
        }
    }

    #[test]
    fn entry_from_propfind_maps_file() {
        let e = entry_from_propfind(pe("/dav/file.txt", false, Some(42), Some(1_000)));
        assert_eq!(e.kind, EntryKind::File);
        assert_eq!(e.name, "file.txt");
        assert_eq!(e.path, "/dav/file.txt");
        assert_eq!(e.size_bytes, 42);
        assert_eq!(e.modified_unix_ms, Some(1_000));
    }

    #[test]
    fn entry_from_propfind_maps_collection_and_strips_trailing_slash_in_name() {
        let e = entry_from_propfind(pe("/dav/sub/", true, None, None));
        assert_eq!(e.kind, EntryKind::Dir);
        assert_eq!(e.name, "sub");
        assert_eq!(e.path, "/dav/sub/");
        assert_eq!(e.size_bytes, 0);
        assert!(e.modified_unix_ms.is_none());
    }

    #[test]
    fn entry_from_propfind_falls_back_to_display_name_when_href_basename_empty() {
        let p = PropfindEntry {
            href: "/".into(),
            display_name: Some("root".into()),
            size_bytes: None,
            last_modified_unix_ms: None,
            etag: None,
            content_type: None,
            is_collection: true,
        };
        let e = entry_from_propfind(p);
        assert_eq!(e.name, "root");
    }

    #[test]
    fn metadata_from_propfind_round_trip_file() {
        let p = pe("/x", false, Some(10), Some(123));
        let m = metadata_from_propfind(&p);
        assert_eq!(m.kind, EntryKind::File);
        assert_eq!(m.size_bytes, 10);
        assert_eq!(m.modified_unix_ms, Some(123));
    }

    #[test]
    fn metadata_from_propfind_round_trip_dir() {
        let p = pe("/x/", true, None, None);
        let m = metadata_from_propfind(&p);
        assert_eq!(m.kind, EntryKind::Dir);
        assert_eq!(m.size_bytes, 0);
        assert!(m.modified_unix_ms.is_none());
    }

    #[test]
    fn href_basename_strips_trailing_slash_for_collection() {
        assert_eq!(href_basename("/a/b/", true).as_deref(), Some("b"));
    }

    #[test]
    fn href_basename_returns_last_component_for_file() {
        assert_eq!(href_basename("/a/b/c.txt", false).as_deref(), Some("c.txt"));
    }

    #[test]
    fn href_basename_none_for_root() {
        assert_eq!(href_basename("/", true), None);
    }
}
