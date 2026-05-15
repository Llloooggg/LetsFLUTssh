//! FRB adapter for `lfs_core::webdav` + `lfs_core::storage::webdav`.
//!
//! Mirrors the SSH/SFTP pair in [`crate::api::sftp`]: an opaque
//! handle wrapping the live transport, plus per-verb methods the
//! Dart file browser calls. Connect resolves the password from
//! the process-singleton SecretStore (the Dart caller never holds
//! the plaintext), builds an `lfs_core::webdav::WebDavClient`, and
//! probes the base URL with a PROPFIND depth=0 so a bad URL /
//! credential surfaces immediately rather than at the first list.
//!
//! ## Why dedicated `webdav_*` FRB
//!
//! The `Provider` trait already abstracts the per-verb surface
//! Rust-side; exposing one shared `provider_*` FRB surface would
//! force every caller through a backend tag at the FRB boundary
//! before any compile-time check fires. The per-backend pair
//! (`webdav_connect` → `WebDavConnection.list` / `…`) keeps the
//! Dart caller polymorphic over the high-level `RemoteFileSystem`
//! facade without paying for tagged dispatch on every call.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use futures_util::StreamExt;
use zeroize::Zeroizing;

use lfs_core::storage::webdav::WebDavProvider;
use lfs_core::storage::{Entry, EntryKind, Metadata, Provider};
use lfs_core::webdav::{AuthMethod, Credentials, WebDavClient};

/// One directory entry surfaced by [`WebDavConnection::list`].
/// Field set mirrors the SFTP shape so the Dart `RemoteFileSystem`
/// facade can hand both surfaces the same `FileEntry` row.
#[derive(Debug, Clone)]
pub struct WebDavDirEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    /// Unix epoch milliseconds. `null` on the Dart side when the
    /// server omitted the modification timestamp.
    pub modified_unix_ms: Option<i64>,
}

impl From<Entry> for WebDavDirEntry {
    fn from(e: Entry) -> Self {
        Self {
            name: e.name,
            path: e.path,
            is_dir: matches!(e.kind, EntryKind::Dir),
            size: e.size_bytes,
            modified_unix_ms: e.modified_unix_ms,
        }
    }
}

/// File metadata surfaced by [`WebDavConnection::stat`].
#[derive(Debug, Clone)]
pub struct WebDavFileMetadata {
    pub is_dir: bool,
    pub size: u64,
    pub modified_unix_ms: Option<i64>,
}

impl From<Metadata> for WebDavFileMetadata {
    fn from(m: Metadata) -> Self {
        Self {
            is_dir: matches!(m.kind, EntryKind::Dir),
            size: m.size_bytes,
            modified_unix_ms: m.modified_unix_ms,
        }
    }
}

/// FRB-visible mirror of
/// [`lfs_core::webdav::ServerAddressFields`]. Flat
/// `{host, port}` projection of a base URL, used by the
/// session-edit dialog to populate the legacy `sessions.host` /
/// `.port` columns so SQL filters keyed on those keep working.
#[derive(Debug, Clone)]
pub struct DbServerAddressFields {
    pub host: String,
    pub port: u32,
}

impl From<lfs_core::webdav::ServerAddressFields> for DbServerAddressFields {
    fn from(value: lfs_core::webdav::ServerAddressFields) -> Self {
        DbServerAddressFields {
            host: value.host,
            port: value.port,
        }
    }
}

/// Parse `base_url` and return the WebDAV session's host + port
/// projection. Explicit `:port` wins; otherwise scheme default
/// (`https` → 443, `http` → 80); else `0`. Empty / malformed
/// input returns an empty host + `0` so a benign caller (live
/// preview, debug log) degrades gracefully.
#[flutter_rust_bridge::frb(sync)]
pub fn webdav_server_address_from_base_url(base_url: String) -> DbServerAddressFields {
    lfs_core::webdav::server_address_from_base_url(&base_url).into()
}

/// Live WebDAV client tied to a single session. Drop on the Dart
/// side releases the inner `Arc`; the underlying `reqwest` client
/// drops its connection pool when the last reference goes away.
#[frb(opaque)]
pub struct WebDavConnection {
    provider: Arc<WebDavProvider>,
}

impl WebDavConnection {
    /// List one directory level. The server returns the listed
    /// directory itself as the first entry per RFC 4918; the
    /// `WebDavProvider` filters it out so this matches SFTP's
    /// "children only" contract.
    pub async fn list(&self, path: String) -> Result<Vec<WebDavDirEntry>, String> {
        let entries = self
            .provider
            .list(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        Ok(entries.into_iter().map(WebDavDirEntry::from).collect())
    }

    /// PROPFIND depth=0 against `path`. Errors when the path does
    /// not exist; callers wanting "exists?" semantics catch and
    /// treat any error as `false`.
    pub async fn stat(&self, path: String) -> Result<WebDavFileMetadata, String> {
        self.provider
            .stat(&path)
            .await
            .map(WebDavFileMetadata::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// `MKCOL path`. Single level — no `mkdir -p` semantics; the
    /// Dart caller walks the path if needed.
    pub async fn mkdir(&self, path: String) -> Result<(), String> {
        self.provider
            .mkdir(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Remove a file or empty collection. Recursive collection
    /// removal is server-defined (most WebDAV servers cascade by
    /// default); the file browser drives one DELETE per entry to
    /// stay portable.
    pub async fn remove(&self, path: String) -> Result<(), String> {
        self.provider
            .remove(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// `MOVE from to` with `Overwrite: F`. Callers that want to
    /// overwrite delete the target first — same contract as the
    /// SFTP rename.
    pub async fn rename(&self, from: String, to: String) -> Result<(), String> {
        self.provider
            .rename(&from, &to)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Fetch the full body. Buffered into a `Vec<u8>` — large-file
    /// streaming through a FRB `StreamSink` is a follow-up.
    pub async fn get_full(&self, path: String) -> Result<Vec<u8>, String> {
        let mut stream = self
            .provider
            .get_stream(&path, None)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        let mut buf = Vec::new();
        while let Some(chunk) = stream.next().await {
            let bytes = chunk.map_err(|e| crate::api::frb_err::from_core(&e))?;
            buf.extend_from_slice(&bytes);
        }
        Ok(buf)
    }

    /// Upload `body` to `path`. Single buffered PUT — see
    /// [`get_full`] note on streaming.
    pub async fn put_full(&self, path: String, body: Vec<u8>) -> Result<(), String> {
        use bytes::Bytes;
        use futures_util::stream;
        let len = body.len() as u64;
        let chunk: Result<Bytes, lfs_core::error::Error> = Ok(Bytes::from(body));
        let stream = Box::pin(stream::iter(std::iter::once(chunk)));
        self.provider
            .put_stream(&path, stream, Some(len))
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Recursive size walk. Same depth cap as the SFTP equivalent
    /// (100 levels) — see the `Provider::dir_size` doc for the
    /// rationale.
    pub async fn dir_size(&self, path: String) -> Result<u64, String> {
        self.provider
            .dir_size(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }
}

/// Resolve `auth_method` (wire value from
/// `webdav_session_details.auth_method`) into the typed
/// `AuthMethod`. Unrecognised values surface as a string error so
/// the caller's localized error path can render a clear message
/// rather than panic.
fn parse_auth_method(raw: &str) -> Result<AuthMethod, String> {
    match raw {
        "basic" => Ok(AuthMethod::Basic),
        "digest" => Ok(AuthMethod::Digest),
        "bearer" => Ok(AuthMethod::Bearer),
        other => Err(format!("unknown WebDAV auth method: {other}")),
    }
}

/// Open a WebDAV session.
///
/// `password_secret_id` is the SecretStore id under which the
/// password / bearer token has been staged (typically
/// `session.webdav.<session_id>`). The connect path resolves the
/// id, builds the typed `Credentials`, constructs the
/// `WebDavClient`, and runs a PROPFIND depth=0 against the base
/// URL as a connect probe — so a bad URL or wrong credential
/// surfaces at connect time rather than at the first list.
///
/// `self_signed_fingerprint` is reserved for the future TOFU
/// pinning surface; the current `WebDavClient` constructor relies
/// on the bundled webpki-roots so a non-null value here is a
/// no-op for now. Wiring it through the FRB layer up-front lets
/// the Dart UI persist the value before the transport-side
/// hookup lands.
pub async fn webdav_connect(
    base_url: String,
    username: String,
    password_secret_id: String,
    auth_method: String,
    self_signed_fingerprint: Option<String>,
) -> Result<WebDavConnection, String> {
    let method = parse_auth_method(&auth_method)?;
    // Borrow UTF-8 via `&secret_bytes` so the `Zeroizing<Vec<u8>>`
    // scrubs on the early-return path. `String::from_utf8(_.to_vec())`
    // would shed the bytes into a `FromUtf8Error` that drops without
    // scrubbing — a plaintext leak on invalid input.
    let secret_bytes = lfs_core::app::instance()
        .secrets
        .get(&password_secret_id)
        .ok_or_else(|| format!("WebDAV secret not staged: {password_secret_id}"))?;
    let secret_str =
        std::str::from_utf8(&secret_bytes).map_err(|e| format!("WebDAV secret not UTF-8: {e}"))?;
    let secret = Zeroizing::new(secret_str.to_owned());
    let creds = Credentials {
        method,
        username: if username.is_empty() {
            None
        } else {
            Some(username)
        },
        password_or_token: secret,
    };
    let client =
        WebDavClient::new(&base_url, creds).map_err(|e| crate::api::frb_err::from_core(&e))?;
    // Connect probe — PROPFIND depth=0 against the base URL. Fails
    // fast on bad URL, expired credential, or wrong realm.
    client
        .propfind("", 0)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    // Reserved — pin the fingerprint when the TOFU surface lands.
    let _ = self_signed_fingerprint;
    let provider = WebDavProvider::new(Arc::new(client));
    Ok(WebDavConnection {
        provider: Arc::new(provider),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_auth_method_accepts_three_wire_values() {
        assert!(matches!(parse_auth_method("basic"), Ok(AuthMethod::Basic)));
        assert!(matches!(
            parse_auth_method("digest"),
            Ok(AuthMethod::Digest)
        ));
        assert!(matches!(
            parse_auth_method("bearer"),
            Ok(AuthMethod::Bearer)
        ));
    }

    #[test]
    fn parse_auth_method_rejects_unknown_value() {
        let err = parse_auth_method("oauth2").unwrap_err();
        assert!(err.contains("unknown WebDAV auth method"));
    }

    #[test]
    fn webdav_dir_entry_maps_file_and_dir_kinds() {
        let file = Entry {
            name: "notes.txt".into(),
            path: "/dav/notes.txt".into(),
            kind: EntryKind::File,
            size_bytes: 42,
            modified_unix_ms: Some(1_000),
        };
        let mapped: WebDavDirEntry = file.into();
        assert!(!mapped.is_dir);
        assert_eq!(mapped.size, 42);
        assert_eq!(mapped.name, "notes.txt");

        let dir = Entry {
            name: "sub".into(),
            path: "/dav/sub/".into(),
            kind: EntryKind::Dir,
            size_bytes: 0,
            modified_unix_ms: None,
        };
        let mapped: WebDavDirEntry = dir.into();
        assert!(mapped.is_dir);
    }

    #[test]
    fn webdav_file_metadata_maps_kind() {
        let m = Metadata {
            kind: EntryKind::Dir,
            size_bytes: 0,
            modified_unix_ms: None,
        };
        let mapped: WebDavFileMetadata = m.into();
        assert!(mapped.is_dir);
    }

    #[tokio::test]
    async fn webdav_connect_rejects_secret_with_invalid_utf8() {
        // Pin the contract: when the staged secret is not valid
        // UTF-8, the connect path returns the UTF-8 error before
        // any WebDavClient / network construction runs. This is
        // the failure branch where leaking a plaintext copy
        // through `FromUtf8Error` would matter — the test fixes
        // the shape so the regression cannot return.
        let app = lfs_core::app::init();
        let secret_id = "test.webdav.invalid-utf8";
        // 0xFF / 0xFE / 0xFD are illegal as the first byte of a
        // UTF-8 sequence, so `str::from_utf8` rejects deterministically.
        app.secrets.put(secret_id, &[0xFF, 0xFE, 0xFD]);
        let result = webdav_connect(
            "https://example.invalid/dav".into(),
            "alice".into(),
            secret_id.into(),
            "basic".into(),
            None,
        )
        .await;
        app.secrets.drop_id(secret_id);
        // `WebDavConnection` is `#[frb(opaque)]` and intentionally
        // does not implement `Debug`, so `expect_err` is unavailable
        // here.
        let err = match result {
            Ok(_) => panic!("invalid UTF-8 secret must fail"),
            Err(e) => e,
        };
        assert!(
            err.contains("WebDAV secret not UTF-8"),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn webdav_connect_rejects_missing_secret_id() {
        // Pin the sibling early-return: an unknown secret id
        // surfaces "not staged" before any network construction.
        // Together with the UTF-8 test, this pins both branches
        // of the resolve-then-validate step.
        let _app = lfs_core::app::init();
        let result = webdav_connect(
            "https://example.invalid/dav".into(),
            "alice".into(),
            "test.webdav.does-not-exist".into(),
            "basic".into(),
            None,
        )
        .await;
        let err = match result {
            Ok(_) => panic!("missing secret id must fail"),
            Err(e) => e,
        };
        assert!(
            err.contains("WebDAV secret not staged"),
            "unexpected error: {err}"
        );
    }
}
