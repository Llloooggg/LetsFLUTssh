//! FRB adapter for `lfs_core::s3` + `lfs_core::storage::s3`.
//!
//! Mirrors the SSH/SFTP pair in [`crate::api::sftp`] and the
//! WebDAV pair in [`crate::api::webdav`]: one opaque handle
//! wrapping the live transport, plus per-verb async methods the
//! Dart file browser calls. Connect resolves the secret access
//! key from the process-singleton SecretStore (the Dart caller
//! never holds the plaintext), builds an `S3Client`, and probes
//! the configured bucket with a one-page `ListObjectsV2` so a bad
//! credential / wrong region / missing bucket surfaces at connect
//! time rather than at the first list.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use futures_util::StreamExt;
use zeroize::Zeroizing;

use lfs_core::s3::{S3Client, S3Config};
use lfs_core::storage::s3::S3Provider;
use lfs_core::storage::{Entry, EntryKind, Metadata, Provider};

/// One directory entry surfaced by [`S3Connection::list`]. Field
/// set mirrors the SFTP / WebDAV shape so the Dart `RemoteFileSystem`
/// facade hands every transport the same `FileEntry` row.
#[derive(Debug, Clone)]
pub struct S3DirEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    /// Unix epoch milliseconds. `null` on the Dart side when the
    /// server omitted the modification timestamp.
    pub modified_unix_ms: Option<i64>,
}

impl From<Entry> for S3DirEntry {
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

/// File metadata surfaced by [`S3Connection::stat`].
#[derive(Debug, Clone)]
pub struct S3FileMetadata {
    pub is_dir: bool,
    pub size: u64,
    pub modified_unix_ms: Option<i64>,
}

impl From<Metadata> for S3FileMetadata {
    fn from(m: Metadata) -> Self {
        Self {
            is_dir: matches!(m.kind, EntryKind::Dir),
            size: m.size_bytes,
            modified_unix_ms: m.modified_unix_ms,
        }
    }
}

/// Parse `endpoint` + `region` and return the S3 session's host
/// + port projection. Empty `endpoint` falls back to
/// `s3.<region>.amazonaws.com` (canonical AWS endpoint;
/// `us-east-1` default when `region` empty). Explicit `:port`
/// wins; `http://` no-port defaults to 80; everything else to
/// 443. Used by the session-edit dialog to populate the legacy
/// `sessions.host` / `.port` columns.
#[flutter_rust_bridge::frb(sync)]
pub fn s3_server_address_from_endpoint(
    endpoint: String,
    region: String,
) -> crate::api::webdav::DbServerAddressFields {
    lfs_core::s3::server_address_from_s3_endpoint(&endpoint, &region).into()
}

/// Live S3 client tied to a single session. Drop on the Dart side
/// releases the inner `Arc`; the underlying `reqwest::Client` drops
/// its connection pool when the last reference goes away.
///
/// Holds an optional [`ProviderRegistration`] guard that unregisters
/// this connection's id from [`crate::app::AppState::providers`]
/// on `Drop`. Same role as the equivalent guard on `WebDavConnection`
/// — without it the transfer worker can't reach the S3 provider.
#[frb(opaque)]
pub struct S3Connection {
    provider: Arc<S3Provider>,
    client: Arc<S3Client>,
    // Drop order: this field runs before `provider`, so the
    // unregister sees the live `Arc` still in the registry.
    _registration: Option<lfs_core::storage::ProviderRegistration>,
}

impl S3Connection {
    /// List one directory level. Common prefixes surface as
    /// directories (matching SFTP's `is_dir` flag) so the Dart
    /// browser renders them identically to a real directory.
    pub async fn list(&self, path: String) -> Result<Vec<S3DirEntry>, String> {
        let entries = self
            .provider
            .list(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        Ok(entries.into_iter().map(S3DirEntry::from).collect())
    }

    /// HEAD the object. Errors when the key does not exist.
    pub async fn stat(&self, path: String) -> Result<S3FileMetadata, String> {
        self.provider
            .stat(&path)
            .await
            .map(S3FileMetadata::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Synthesise a directory marker — `PUT` a 0-byte object whose
    /// key ends with `/`. S3 has no native directories; the file
    /// browser's mkdir contract maps to this convention.
    pub async fn mkdir(&self, path: String) -> Result<(), String> {
        self.provider
            .mkdir(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// DELETE one object.
    pub async fn remove(&self, path: String) -> Result<(), String> {
        self.provider
            .remove(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Server-side copy + delete. Not atomic — a reader between the
    /// two calls observes both the source and target object.
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

    /// Upload `body` to `path`. Routes through the multipart
    /// orchestrator when the body is above the 8 MiB threshold;
    /// otherwise single-shot `PUT`.
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

    /// Recursive prefix size. Walks `ListObjectsV2` continuation
    /// tokens server-side; one FRB call regardless of prefix depth.
    pub async fn dir_size(&self, path: String) -> Result<u64, String> {
        self.provider
            .dir_size(&path)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Generate a time-limited presigned `GET` URL for `key` under
    /// `bucket`. `expires_seconds` clamps to AWS's 7-day maximum.
    pub fn generate_presigned_url(
        &self,
        bucket: String,
        key: String,
        expires_seconds: u32,
    ) -> Result<String, String> {
        self.client
            .generate_presigned_get_url(&bucket, &key, expires_seconds)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }
}

/// Open an S3 session.
///
/// `secret_key_secret_id` is the SecretStore id under which the
/// secret access key has been staged (canonical form
/// `session.s3.<session_id>`). The connect path resolves the id,
/// builds the `S3Config`, constructs the `S3Client`, and runs a
/// `ListObjectsV2` against `default_bucket` (or the empty bucket
/// when none is configured) as a connect probe — so a bad
/// credential / wrong region / missing bucket surfaces at connect
/// time rather than at the first list.
/// Configuration tuple for [`s3_connect`]. Bundled into a struct
/// because the field count would otherwise cross clippy's
/// `too_many_arguments` ceiling — every field is a connect-time
/// required input (none has a meaningful default the call site
/// could omit), so factoring them out of the positional argument
/// list is a readability win as well.
#[derive(Debug, Clone)]
pub struct S3ConnectRequest {
    pub connection_id: String,
    pub access_key_id: String,
    pub secret_key_secret_id: String,
    pub region: String,
    pub endpoint: String,
    pub path_style: bool,
    pub default_bucket: String,
    pub default_prefix: String,
    /// PEM blob (one or more `-----BEGIN CERTIFICATE-----` blocks)
    /// added as an additional root for the reqwest client. `None`
    /// falls back to the system trust store.
    pub trusted_cert_pem: Option<String>,
    /// Last-resort skip-all-cert-verification toggle. The dialog
    /// renders an explicit MITM warning before letting the user
    /// flip it on.
    pub insecure_skip_verify: bool,
}

pub async fn s3_connect(req: S3ConnectRequest) -> Result<S3Connection, String> {
    let S3ConnectRequest {
        connection_id,
        access_key_id,
        secret_key_secret_id,
        region,
        endpoint,
        path_style,
        default_bucket,
        default_prefix,
        trusted_cert_pem,
        insecure_skip_verify,
    } = req;
    // Borrow UTF-8 via `&secret_bytes` so the `Zeroizing<Vec<u8>>`
    // scrubs on the early-return path. `String::from_utf8(_.to_vec())`
    // would shed the bytes into a `FromUtf8Error` that drops without
    // scrubbing — a plaintext leak on invalid input.
    let secret_bytes = lfs_core::app::instance()
        .secrets
        .get(&secret_key_secret_id)
        .ok_or_else(|| format!("S3 secret not staged: {secret_key_secret_id}"))?;
    let secret_str =
        std::str::from_utf8(&secret_bytes).map_err(|e| format!("S3 secret not UTF-8: {e}"))?;
    let secret = Zeroizing::new(secret_str.to_owned());
    let cfg = S3Config {
        access_key_id,
        secret_access_key: secret,
        region,
        endpoint,
        path_style,
        default_bucket: default_bucket.clone(),
        default_prefix,
        trusted_cert_pem,
        insecure_skip_verify,
    };
    let client = Arc::new(S3Client::new(cfg).map_err(|e| crate::api::frb_err::from_core(&e))?);
    // Connect probe — only meaningful when `default_bucket` is set;
    // otherwise we cannot pick a bucket to ping without an
    // explicit caller-supplied target. Skipping the probe in that
    // case keeps connect-time fast at the cost of the first
    // `list()` surfacing any auth / endpoint issue.
    if !default_bucket.is_empty() {
        client
            .list_objects_v2(&default_bucket, "", None)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
    }
    let provider = Arc::new(S3Provider::new(Arc::clone(&client)));
    // Register the live provider so the transfer worker pool can
    // dispatch by connection id. See `WebDavConnection` for the
    // matching guard contract.
    let app = lfs_core::app::instance();
    let registry = app.providers.clone();
    registry.register(&connection_id, provider.clone());
    let registration =
        lfs_core::storage::ProviderRegistration::new(Arc::downgrade(&registry), connection_id);
    Ok(S3Connection {
        provider,
        client,
        _registration: Some(registration),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn s3_connect_rejects_secret_with_invalid_utf8() {
        // Pin the contract: when the staged secret is not valid
        // UTF-8, the connect path returns the UTF-8 error before
        // any S3Client / network construction runs. This is the
        // failure branch where leaking a plaintext copy through
        // `FromUtf8Error` would matter — the test fixes the shape
        // so the regression cannot return.
        let app = lfs_core::app::init();
        let secret_id = "test.s3.invalid-utf8";
        // 0xFF / 0xFE / 0xFD are illegal as the first byte of a
        // UTF-8 sequence, so `str::from_utf8` rejects deterministically.
        app.secrets.put(secret_id, &[0xFF, 0xFE, 0xFD]);
        let result = s3_connect(S3ConnectRequest {
            connection_id: "test-conn-utf8".into(),
            access_key_id: "AKIATESTKEY".into(),
            secret_key_secret_id: secret_id.into(),
            region: "us-east-1".into(),
            endpoint: String::new(),
            path_style: false,
            default_bucket: String::new(),
            default_prefix: String::new(),
            trusted_cert_pem: None,
            insecure_skip_verify: false,
        })
        .await;
        app.secrets.drop_id(secret_id);
        // `S3Connection` is `#[frb(opaque)]` and intentionally does
        // not implement `Debug`, so `expect_err` is unavailable here.
        let err = match result {
            Ok(_) => panic!("invalid UTF-8 secret must fail"),
            Err(e) => e,
        };
        assert!(
            err.contains("S3 secret not UTF-8"),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn s3_connect_rejects_missing_secret_id() {
        // Pin the sibling early-return: an unknown secret id
        // surfaces "not staged" before any network construction.
        // Together with the UTF-8 test, this pins both branches
        // of the resolve-then-validate step.
        let _app = lfs_core::app::init();
        let result = s3_connect(S3ConnectRequest {
            connection_id: "test-conn-missing-secret".into(),
            access_key_id: "AKIATESTKEY".into(),
            secret_key_secret_id: "test.s3.does-not-exist".into(),
            region: "us-east-1".into(),
            endpoint: String::new(),
            path_style: false,
            default_bucket: String::new(),
            default_prefix: String::new(),
            trusted_cert_pem: None,
            insecure_skip_verify: false,
        })
        .await;
        let err = match result {
            Ok(_) => panic!("missing secret id must fail"),
            Err(e) => e,
        };
        assert!(
            err.contains("S3 secret not staged"),
            "unexpected error: {err}"
        );
    }
}
