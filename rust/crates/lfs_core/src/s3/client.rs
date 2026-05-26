//! [`S3Client`] — verb surface backing the S3 transport.
//!
//! Speaks the AWS S3 REST API every S3-compatible vendor implements.
//! Each call signs the request via [`crate::s3::signer`], shoots it
//! through `reqwest` with the configured TLS posture, and parses
//! the response (XML for list / error documents, bytes for object
//! bodies).
//!
//! The client is `reqwest::Client`-backed so connection pooling
//! and HTTP/2 (where the server supports it) come for free.
//!
//! ## Addressing styles
//!
//! Two ways to identify the bucket in an S3 request URL — the
//! choice is per-`S3Config` and stays fixed for the client's
//! lifetime. The dispatcher reads `cfg.path_style` once per
//! request and selects:
//!
//! 1. **Virtual-host addressing** (`cfg.path_style == false`,
//!    AWS default). Bucket lives in the host header:
//!    `https://<bucket>.s3.<region>.amazonaws.com/<key>`. SigV4
//!    canonical URI is the bucket-free `/<key>` because the host
//!    line already carries the bucket. This is the form AWS
//!    deprecation-notices push every new bucket toward and what
//!    Cloudflare R2 / Wasabi / DigitalOcean Spaces accept by
//!    default.
//! 2. **Path-style addressing** (`cfg.path_style == true`).
//!    Bucket lives in the path: `https://<endpoint>/<bucket>/<key>`.
//!    SigV4 canonical URI is the full `/<bucket>/<key>` because
//!    the host header doesn't carry the bucket. Required by
//!    MinIO, some self-hosted Ceph / Garage deployments, and AWS
//!    buckets whose name violates DNS rules (dots, uppercase) —
//!    the bucket name then can't legally appear as a host segment.
//!
//! Choosing the right style is the user's responsibility on the
//! S3 connection-edit dialog; the dispatcher trusts the setting
//! and signs both URL shapes accordingly. Picking the wrong style
//! surfaces as a SigV4 signature mismatch (the host the server
//! sees does not match the host we signed) — diagnosed via the
//! 403 `SignatureDoesNotMatch` XML body, not by a silent failure.

use std::sync::Arc;

use bytes::Bytes;
use reqwest::{Method, StatusCode};

use crate::error::Error;
use crate::s3::config::S3Config;
use crate::s3::signer::{
    hex_sha256, presign_url, sign_headers, PresignInput, SignHeaderInput, EMPTY_PAYLOAD_HASH,
};

/// `s3` SigV4 service name. AWS, MinIO, Wasabi, R2, B2-S3, Spaces,
/// Scaleway — every S3-compatible vendor signs under this name.
const SERVICE_S3: &str = "s3";

/// Per-request wall-clock cap. Matches the WebDAV transport's 60 s
/// ceiling so a stalled or black-holed endpoint cannot pin a transfer
/// worker indefinitely.
const REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

/// One object surfaced by [`S3Client::list_objects_v2`]. `is_dir`
/// is true when the entry came from `<CommonPrefixes>` (S3's
/// virtual-directory marker); files have an explicit key + size +
/// last-modified.
#[derive(Debug, Clone)]
pub struct S3Object {
    pub key: String,
    pub size: u64,
    pub last_modified_unix_ms: Option<i64>,
    pub etag: String,
    pub is_dir: bool,
}

/// One page of [`S3Client::list_objects_v2`]. `next_continuation_token`
/// is `Some` when the bucket has more entries; the caller threads
/// the token back through a follow-up call.
#[derive(Debug, Clone)]
pub struct S3ObjectPage {
    pub objects: Vec<S3Object>,
    pub next_continuation_token: Option<String>,
}

/// Single-object metadata from a `HEAD` request.
#[derive(Debug, Clone)]
pub struct S3ObjectMetadata {
    pub size: u64,
    pub last_modified_unix_ms: Option<i64>,
    pub etag: String,
    pub content_type: Option<String>,
}

/// Live S3 client tied to one credential set + endpoint. Cloneable
/// (shares the inner `reqwest::Client` Arc internally) so multiple
/// `Provider` calls share one connection pool.
#[derive(Clone)]
/// Bundled args for [`S3Client::signed_request_with_headers`].
/// Grouping cuts the call surface to one struct so clippy's
/// `too_many_arguments` (and a future caller's readability)
/// stay sane.
struct SignedRequestInput<'a> {
    method: Method,
    bucket: &'a str,
    path: &'a str,
    query: &'a str,
    body: Option<Bytes>,
    payload_hash: &'a str,
    extra_headers: &'a [(String, String)],
}

pub struct S3Client {
    cfg: Arc<S3Config>,
    http: reqwest::Client,
}

impl std::fmt::Debug for S3Client {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("S3Client")
            .field("region", &self.cfg.region)
            .field("endpoint", &self.cfg.endpoint)
            .field("path_style", &self.cfg.path_style)
            .field("default_bucket", &self.cfg.default_bucket)
            .field("default_prefix", &self.cfg.default_prefix)
            .finish_non_exhaustive()
    }
}

impl S3Client {
    /// Construct a new client. `cfg.secret_access_key` is moved in
    /// behind `Arc` so the secret bytes wipe on drop alongside the
    /// last clone.
    ///
    /// `cfg.trusted_cert_pem` (when set) feeds every certificate in
    /// the PEM blob into [`reqwest::ClientBuilder::add_root_certificate`]
    /// so the reqwest TLS verifier accepts self-signed endpoints
    /// without OS-trust-store changes. `cfg.insecure_skip_verify`
    /// flips on `danger_accept_invalid_certs` + `danger_accept_invalid_hostnames`
    /// — the escape hatch the dialog guards behind an explicit
    /// MITM warning. Both paths are mutually exclusive at the user
    /// level; the transport prefers insecure when both are set.
    pub fn new(cfg: S3Config) -> Result<Self, Error> {
        // A SigV4 request is signed for one specific host; following a
        // redirect would replay the `Authorization` header to the
        // redirect target (credential leak) and break the signature
        // anyway, so disable redirects outright. The timeout stops a
        // stalled endpoint from pinning a transfer worker forever.
        // WebDAV already sets both; S3 had neither.
        let mut builder = reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .redirect(reqwest::redirect::Policy::none());
        if cfg.insecure_skip_verify {
            builder = builder
                .danger_accept_invalid_certs(true)
                .danger_accept_invalid_hostnames(true);
        } else if let Some(pem) = cfg
            .trusted_cert_pem
            .as_deref()
            .filter(|s| !s.trim().is_empty())
        {
            for cert in crate::webdav::client::parse_pem_certs(pem)
                .map_err(|e| Error::S3(format!("trusted cert PEM: {e}")))?
            {
                builder = builder.add_root_certificate(cert);
            }
        }
        let http = builder
            .build()
            .map_err(|e| Error::S3(format!("reqwest client build: {e}")))?;
        Ok(Self {
            cfg: Arc::new(cfg),
            http,
        })
    }

    /// Read the config the client was built with. Used by the
    /// `Provider` adapter to resolve `default_bucket` /
    /// `default_prefix` shorthand.
    pub fn config(&self) -> &S3Config {
        &self.cfg
    }

    /// `ListObjectsV2` with `delimiter=/` so common prefixes surface
    /// as virtual directories. `continuation_token` is `Some` only
    /// on follow-up pages.
    pub async fn list_objects_v2(
        &self,
        bucket: &str,
        prefix: &str,
        continuation_token: Option<&str>,
    ) -> Result<S3ObjectPage, Error> {
        let mut query = format!(
            "delimiter=%2F&list-type=2&prefix={}",
            crate::s3::signer::uri_encode(prefix, true)
        );
        if let Some(token) = continuation_token {
            query.push_str("&continuation-token=");
            query.push_str(&crate::s3::signer::uri_encode(token, true));
        }
        let response = self
            .signed_request(Method::GET, bucket, "/", &query, None, EMPTY_PAYLOAD_HASH)
            .await?;
        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| Error::S3(format!("list_objects_v2 body: {e}")))?;
        if !status.is_success() {
            return Err(map_xml_error(status, &body));
        }
        parse_list_objects_v2(&body)
    }

    /// HEAD an object. Returns size / mtime / etag / content-type.
    pub async fn head_object(&self, bucket: &str, key: &str) -> Result<S3ObjectMetadata, Error> {
        let path = format!("/{}", key);
        let response = self
            .signed_request(Method::HEAD, bucket, &path, "", None, EMPTY_PAYLOAD_HASH)
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(map_status_error(status, "head_object"));
        }
        let headers = response.headers().clone();
        let size = header_u64(&headers, reqwest::header::CONTENT_LENGTH).unwrap_or(0);
        let etag = header_str(&headers, reqwest::header::ETAG)
            .map(|s| s.trim_matches('"').to_string())
            .unwrap_or_default();
        let last_modified_unix_ms =
            header_str(&headers, reqwest::header::LAST_MODIFIED).and_then(parse_http_date_ms);
        let content_type = header_str(&headers, reqwest::header::CONTENT_TYPE).map(str::to_string);
        Ok(S3ObjectMetadata {
            size,
            last_modified_unix_ms,
            etag,
            content_type,
        })
    }

    /// GET an object. Range is honoured when set — `(start, end)`
    /// is inclusive on both ends per HTTP `Range: bytes=`. Returns
    /// the response so the caller can `bytes_stream()` it.
    pub async fn get_object(
        &self,
        bucket: &str,
        key: &str,
        range: Option<(u64, u64)>,
    ) -> Result<reqwest::Response, Error> {
        let path = format!("/{}", key);
        let extras: Vec<(String, String)> = match range {
            Some((start, end)) => vec![("Range".into(), format!("bytes={start}-{end}"))],
            None => Vec::new(),
        };
        let response = self
            .signed_request_with_headers(SignedRequestInput {
                method: Method::GET,
                bucket,
                path: &path,
                query: "",
                body: None,
                payload_hash: EMPTY_PAYLOAD_HASH,
                extra_headers: &extras,
            })
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(map_status_error(status, "get_object"));
        }
        Ok(response)
    }

    /// Single-shot PUT. Caller must keep this under the 5 GiB AWS
    /// single-object limit; the [`crate::s3::multipart`] orchestrator
    /// handles larger payloads.
    pub async fn put_object_single(
        &self,
        bucket: &str,
        key: &str,
        body: Vec<u8>,
    ) -> Result<(), Error> {
        let path = format!("/{}", key);
        let payload_hash = hex_sha256(&body);
        let response = self
            .signed_request(
                Method::PUT,
                bucket,
                &path,
                "",
                Some(Bytes::from(body)),
                &payload_hash,
            )
            .await?;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(map_xml_error(status, &body));
        }
        Ok(())
    }

    /// DELETE one object.
    pub async fn delete_object(&self, bucket: &str, key: &str) -> Result<(), Error> {
        let path = format!("/{}", key);
        let response = self
            .signed_request(Method::DELETE, bucket, &path, "", None, EMPTY_PAYLOAD_HASH)
            .await?;
        let status = response.status();
        // 204 No Content + 200 OK both surface as success; some
        // S3-compatible servers return 204 on absent keys too,
        // which we treat as idempotent success.
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(map_xml_error(status, &body));
        }
        Ok(())
    }

    /// Server-side copy. Used by the file-browser rename emulation
    /// (S3 has no native rename — copy + delete is the convention).
    pub async fn copy_object(
        &self,
        src_bucket: &str,
        src_key: &str,
        dst_bucket: &str,
        dst_key: &str,
    ) -> Result<(), Error> {
        let path = format!("/{}", dst_key);
        // The copy-source header carries the encoded source path
        // (URL-encode the key but leave the bucket separator alone).
        let source = format!(
            "/{src_bucket}/{}",
            crate::s3::signer::uri_encode(src_key, false)
        );
        let extras: Vec<(String, String)> = vec![("x-amz-copy-source".into(), source)];
        let response = self
            .signed_request_with_headers(SignedRequestInput {
                method: Method::PUT,
                bucket: dst_bucket,
                path: &path,
                query: "",
                body: None,
                payload_hash: EMPTY_PAYLOAD_HASH,
                extra_headers: &extras,
            })
            .await?;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(map_xml_error(status, &body));
        }
        Ok(())
    }

    /// Multipart upload helpers — see [`crate::s3::multipart`] for
    /// the orchestrator. Exposed individually so the orchestrator
    /// can run abort cleanup independent of the success path.
    pub async fn create_multipart_upload(&self, bucket: &str, key: &str) -> Result<String, Error> {
        let path = format!("/{}", key);
        let response = self
            .signed_request(
                Method::POST,
                bucket,
                &path,
                "uploads=",
                Some(Bytes::new()),
                EMPTY_PAYLOAD_HASH,
            )
            .await?;
        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| Error::S3(format!("create_multipart_upload body: {e}")))?;
        if !status.is_success() {
            return Err(map_xml_error(status, &body));
        }
        parse_initiate_multipart_upload_id(&body)
    }

    /// Upload a single part. Returns the part `ETag` so the caller
    /// can stitch it into the Complete call.
    pub async fn upload_part(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
        part_number: i32,
        body: Vec<u8>,
    ) -> Result<String, Error> {
        let path = format!("/{}", key);
        let query = format!(
            "partNumber={}&uploadId={}",
            part_number,
            crate::s3::signer::uri_encode(upload_id, true)
        );
        let payload_hash = hex_sha256(&body);
        let response = self
            .signed_request(
                Method::PUT,
                bucket,
                &path,
                &query,
                Some(Bytes::from(body)),
                &payload_hash,
            )
            .await?;
        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(map_xml_error(status, &text));
        }
        let etag = response
            .headers()
            .get(reqwest::header::ETAG)
            .and_then(|h| h.to_str().ok())
            .map(|s| s.trim_matches('"').to_string())
            .unwrap_or_default();
        Ok(etag)
    }

    /// Complete a multipart upload. `parts` is `(part_number, etag)`
    /// pairs in part-number-ascending order.
    pub async fn complete_multipart_upload(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
        parts: &[(i32, String)],
    ) -> Result<(), Error> {
        let path = format!("/{}", key);
        let query = format!(
            "uploadId={}",
            crate::s3::signer::uri_encode(upload_id, true)
        );
        let body = build_complete_multipart_body(parts);
        let payload_hash = hex_sha256(body.as_bytes());
        let response = self
            .signed_request(
                Method::POST,
                bucket,
                &path,
                &query,
                Some(Bytes::from(body)),
                &payload_hash,
            )
            .await?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        if !status.is_success() {
            return Err(map_xml_error(status, &text));
        }
        // S3 can return 200 OK with an error document in the body
        // when the part-list reconciliation fails (the so-called
        // 200-then-error gotcha). Detect by `<Error>` element.
        if text.contains("<Error>") {
            return Err(map_xml_error(status, &text));
        }
        Ok(())
    }

    /// Abort a multipart upload — releases the staged-parts state
    /// server-side. Best-effort: an abort that itself fails is logged
    /// but never overrides the underlying error the caller is
    /// surfacing.
    pub async fn abort_multipart_upload(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
    ) -> Result<(), Error> {
        let path = format!("/{}", key);
        let query = format!(
            "uploadId={}",
            crate::s3::signer::uri_encode(upload_id, true)
        );
        let response = self
            .signed_request(
                Method::DELETE,
                bucket,
                &path,
                &query,
                None,
                EMPTY_PAYLOAD_HASH,
            )
            .await?;
        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(map_xml_error(status, &text));
        }
        Ok(())
    }

    /// Generate a time-limited presigned `GET` URL for an object.
    /// `expires_seconds` clamps to AWS's 7-day maximum.
    pub fn generate_presigned_get_url(
        &self,
        bucket: &str,
        key: &str,
        expires_seconds: u32,
    ) -> Result<String, Error> {
        let host = self.cfg.resolve_host_header(bucket)?;
        let path = if self.cfg.path_style {
            format!("/{}/{}", bucket, key)
        } else {
            format!("/{}", key)
        };
        let scheme = url::Url::parse(&self.cfg.resolve_endpoint())
            .map_err(|e| Error::S3(format!("invalid endpoint: {e}")))?
            .scheme()
            .to_string();
        let timestamp = format_amz_timestamp(now_unix_seconds());
        let url = presign_url(
            &PresignInput {
                method: "GET",
                host: &host,
                path: &path,
                access_key_id: &self.cfg.access_key_id,
                secret_access_key: &self.cfg.secret_access_key,
                region: &self.cfg.region,
                service: SERVICE_S3,
                timestamp: &timestamp,
                expires_seconds,
            },
            &scheme,
        );
        Ok(url)
    }

    // --- internals ---

    async fn signed_request(
        &self,
        method: Method,
        bucket: &str,
        path: &str,
        query: &str,
        body: Option<Bytes>,
        payload_hash: &str,
    ) -> Result<reqwest::Response, Error> {
        self.signed_request_with_headers(SignedRequestInput {
            method,
            bucket,
            path,
            query,
            body,
            payload_hash,
            extra_headers: &[],
        })
        .await
    }

    async fn signed_request_with_headers(
        &self,
        req: SignedRequestInput<'_>,
    ) -> Result<reqwest::Response, Error> {
        let SignedRequestInput {
            method,
            bucket,
            path,
            query,
            body,
            payload_hash,
            extra_headers,
        } = req;
        let base = self.cfg.resolve_bucket_base(bucket)?;
        let host = self.cfg.resolve_host_header(bucket)?;
        let timestamp = format_amz_timestamp(now_unix_seconds());
        // Path passed into the signer must NOT include the bucket
        // segment under path-style addressing — SigV4 signs the
        // canonical URI as the server sees it. With path-style the
        // server sees `<endpoint>/<bucket>/<key>`, so we sign the
        // full `/<bucket>/<key>`; with virtual-host the path is
        // bucket-free.
        let signed_path = if self.cfg.path_style {
            if path.starts_with('/') {
                format!("/{}{}", bucket, path)
            } else {
                format!("/{}/{}", bucket, path)
            }
        } else {
            path.to_string()
        };
        let signed = sign_headers(&SignHeaderInput {
            method: method.as_str(),
            host: &host,
            path: &signed_path,
            query,
            payload_hash,
            extra_headers,
            access_key_id: &self.cfg.access_key_id,
            secret_access_key: &self.cfg.secret_access_key,
            region: &self.cfg.region,
            service: SERVICE_S3,
            timestamp: &timestamp,
        });

        // Compose the final request URL. Path-style addressing already
        // baked the bucket into `base`; here we only append the
        // resource path + the query. Encode the path through the SAME
        // `canonical_path` the signer uses so the wire URL and the
        // signed canonical request are byte-identical — callers pass
        // the raw key, encoding happens exactly once, here and in the
        // signer.
        let encoded_path = crate::s3::signer::canonical_path(path);
        let url = if query.is_empty() {
            format!("{base}{encoded_path}")
        } else {
            format!("{base}{encoded_path}?{query}")
        };

        let mut builder = self.http.request(method, &url);
        for (k, v) in &signed.headers {
            // `Host` is stamped by reqwest from the URL; setting it
            // again causes hyper to add a second header. Skip it.
            if k.eq_ignore_ascii_case("host") {
                continue;
            }
            builder = builder.header(k, v);
        }
        if let Some(body) = body {
            builder = builder.body(body);
        }
        builder
            .send()
            .await
            .map_err(|e| Error::S3(format!("send: {e}")))
    }
}

// --- helpers ---

fn header_str(h: &reqwest::header::HeaderMap, name: reqwest::header::HeaderName) -> Option<&str> {
    h.get(name).and_then(|v| v.to_str().ok())
}

fn header_u64(h: &reqwest::header::HeaderMap, name: reqwest::header::HeaderName) -> Option<u64> {
    header_str(h, name).and_then(|s| s.parse().ok())
}

fn parse_http_date_ms(value: &str) -> Option<i64> {
    let dt = httpdate::parse_http_date(value).ok()?;
    let dur = dt.duration_since(std::time::UNIX_EPOCH).ok()?;
    i64::try_from(dur.as_millis()).ok()
}

fn format_amz_timestamp(unix_seconds: u64) -> String {
    // SigV4 timestamps are `YYYYMMDDTHHMMSSZ` (no separators). Build
    // the value from epoch seconds without pulling chrono.
    let (year, month, day, hour, minute, second) = unix_to_components(unix_seconds);
    format!("{year:04}{month:02}{day:02}T{hour:02}{minute:02}{second:02}Z")
}

fn now_unix_seconds() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Convert unix-seconds → (year, month, day, hour, min, sec) using
/// the civil-from-days algorithm. UTC only; SigV4 mandates UTC.
/// Saturates if the input lies pre-epoch.
///
/// Thin u64-input adaptor over [`crate::archive::iso8601::unix_to_civil`]
/// — keeps the single Hinnant implementation in one place so a
/// bug fix to the algorithm lands once.
fn unix_to_components(epoch_seconds: u64) -> (u32, u32, u32, u32, u32, u32) {
    // i64::MAX is far past any plausible SigV4 timestamp, but cap
    // the cast to keep the function total on a hostile caller.
    let secs = i64::try_from(epoch_seconds).unwrap_or(i64::MAX);
    let (year, month, day, hh, mm, ss) = crate::archive::iso8601::unix_to_civil(secs);
    // SigV4 timestamps post-1970 fit comfortably in u32 (years
    // 1970..u32::MAX); clamp defensively on the pathological path.
    let year_u32 = u32::try_from(year).unwrap_or(0);
    (year_u32, month, day, hh, mm, ss)
}

/// Build the `<CompleteMultipartUpload>` XML body. Order is
/// part-number ascending — caller is expected to sort beforehand
/// but we re-sort here defensively because a misordered list
/// surfaces as a 400 Bad Request that's hard to diagnose remotely.
fn build_complete_multipart_body(parts: &[(i32, String)]) -> String {
    let mut sorted: Vec<&(i32, String)> = parts.iter().collect();
    sorted.sort_by_key(|p| p.0);
    let mut out = String::from("<CompleteMultipartUpload>");
    for (number, etag) in sorted {
        out.push_str("<Part><PartNumber>");
        out.push_str(&number.to_string());
        out.push_str("</PartNumber><ETag>");
        // ETag in the wire is quoted; round-trip in the body as
        // quoted too. S3 accepts both quoted and unquoted but
        // quoted is the documented form.
        out.push('"');
        out.push_str(etag.trim_matches('"'));
        out.push('"');
        out.push_str("</ETag></Part>");
    }
    out.push_str("</CompleteMultipartUpload>");
    out
}

/// Translate an HTTP status + S3 error-document body into a typed
/// [`Error::S3`] variant message. The body shape is identical
/// across vendors so a single matcher covers every backend.
fn map_xml_error(status: StatusCode, body: &str) -> Error {
    let (code, message) = extract_xml_error(body);
    if status == StatusCode::UNAUTHORIZED || status == StatusCode::FORBIDDEN {
        Error::S3(format!("auth: {code} {message}"))
    } else if status == StatusCode::NOT_FOUND {
        Error::S3(format!("not found: {code} {message}"))
    } else if status.is_server_error() {
        Error::S3(format!("server error {status}: {code} {message}"))
    } else {
        Error::S3(format!("status {status}: {code} {message}"))
    }
}

fn map_status_error(status: StatusCode, ctx: &str) -> Error {
    if status == StatusCode::UNAUTHORIZED || status == StatusCode::FORBIDDEN {
        Error::S3(format!("{ctx}: auth ({status})"))
    } else if status == StatusCode::NOT_FOUND {
        Error::S3(format!("{ctx}: not found"))
    } else {
        Error::S3(format!("{ctx}: status {status}"))
    }
}

fn extract_xml_error(body: &str) -> (String, String) {
    let code = extract_tag(body, "Code").unwrap_or_default();
    let message = extract_tag(body, "Message").unwrap_or_default();
    (code, message)
}

/// Pull the text content of the first `<tag>...</tag>` element out
/// of an S3 error / metadata XML body. Parses via `quick_xml` so
/// CDATA, embedded entities, and whitespace between elements are
/// handled the same way the rest of the S3 client treats response
/// bodies. Returns `None` when the element is absent or the body
/// fails to parse — callers fall back to a generic error message
/// rather than surface a malformed-XML error on top of the actual
/// HTTP failure.
///
/// Local-name match (case-sensitive). S3 vendors all emit the
/// AWS-canonical element names (`Code`, `Message`, `UploadId`)
/// unprefixed; if a hostile gateway slips a namespace prefix in,
/// the lookup falls through to `None` which is the safe answer.
fn extract_tag(body: &str, tag: &str) -> Option<String> {
    use quick_xml::events::Event;
    use quick_xml::Reader;
    let mut reader = Reader::from_str(body);
    // No per-event trim: quick-xml emits entity references as their own
    // events, so trimming each fragment would drop whitespace around an
    // entity inside a value. The accumulated value is trimmed once on
    // return; text outside the target tag is gated by `in_tag`.
    let mut buf: Option<String> = None;
    let mut in_tag = false;
    loop {
        match reader.read_event().ok()? {
            Event::Start(e) if local_name_matches(e.name().as_ref(), tag.as_bytes()) => {
                in_tag = true;
                buf = Some(String::new());
            }
            Event::Text(t) if in_tag => {
                let bytes = t.decode().ok()?;
                if let Some(out) = buf.as_mut() {
                    out.push_str(&bytes);
                }
            }
            Event::GeneralRef(r) if in_tag => {
                let resolved = crate::xml::resolve_general_ref(&r).ok()?;
                if let Some(out) = buf.as_mut() {
                    out.push_str(&resolved);
                }
            }
            Event::CData(t) if in_tag => {
                let text = std::str::from_utf8(t.as_ref()).ok()?;
                if let Some(out) = buf.as_mut() {
                    out.push_str(text);
                }
            }
            Event::End(e) if in_tag && local_name_matches(e.name().as_ref(), tag.as_bytes()) => {
                return buf.map(|s| s.trim().to_string());
            }
            Event::Eof => return None,
            _ => {}
        }
    }
}

/// Local-name comparison stripping any `prefix:` namespace segment.
fn local_name_matches(name: &[u8], expected: &[u8]) -> bool {
    let local = match name.iter().position(|b| *b == b':') {
        Some(idx) => &name[idx + 1..],
        None => name,
    };
    local == expected
}

/// Parse the `<InitiateMultipartUploadResult>` XML and return the
/// `UploadId`. Vendor variants all use the same element name.
fn parse_initiate_multipart_upload_id(body: &str) -> Result<String, Error> {
    extract_tag(body, "UploadId")
        .ok_or_else(|| Error::S3("InitiateMultipartUpload: missing UploadId".into()))
}

/// Parse the `<ListBucketResult>` XML. Streams the document via
/// `quick_xml` because the response body is bounded by S3's 1000-
/// objects-per-page cap so per-page memory stays small, but the
/// element ordering / casing varies enough between vendors that a
/// regex-based parser is fragile.
fn parse_list_objects_v2(body: &str) -> Result<S3ObjectPage, Error> {
    use quick_xml::events::Event;
    use quick_xml::Reader;
    let mut reader = Reader::from_str(body);
    // No per-event trim: entity references arrive as their own events, so
    // trimming each text fragment would drop whitespace around an entity
    // inside a key. Each element's accumulated text is trimmed once when
    // consumed in the `End` handler.

    let mut objects: Vec<S3Object> = Vec::new();
    let mut next_token: Option<String> = None;

    let mut current_text = String::new();
    let mut in_contents = false;
    let mut in_common_prefix = false;
    let mut cur_obj = S3Object {
        key: String::new(),
        size: 0,
        last_modified_unix_ms: None,
        etag: String::new(),
        is_dir: false,
    };
    let mut cur_path: Vec<String> = Vec::new();

    loop {
        let event = reader
            .read_event()
            .map_err(|e| Error::S3(format!("ListObjectsV2 parse: {e}")))?;
        match event {
            Event::Start(start) => {
                let name = String::from_utf8_lossy(start.name().as_ref()).into_owned();
                cur_path.push(name.clone());
                if name == "Contents" {
                    in_contents = true;
                    cur_obj = S3Object {
                        key: String::new(),
                        size: 0,
                        last_modified_unix_ms: None,
                        etag: String::new(),
                        is_dir: false,
                    };
                } else if name == "CommonPrefixes" {
                    in_common_prefix = true;
                    cur_obj = S3Object {
                        key: String::new(),
                        size: 0,
                        last_modified_unix_ms: None,
                        etag: String::new(),
                        is_dir: true,
                    };
                }
                current_text.clear();
            }
            Event::Text(text) => {
                let decoded = text
                    .decode()
                    .map_err(|e| Error::S3(format!("ListObjectsV2 text decode: {e}")))?;
                current_text.push_str(&decoded);
            }
            Event::GeneralRef(r) => {
                let resolved = crate::xml::resolve_general_ref(&r)
                    .map_err(|e| Error::S3(format!("ListObjectsV2 xml entity: {e}")))?;
                current_text.push_str(&resolved);
            }
            Event::End(end) => {
                let name = String::from_utf8_lossy(end.name().as_ref()).into_owned();
                // Trim the assembled value once (the reader no longer trims
                // per event); inner spaces around a resolved entity survive.
                let text = current_text.trim();
                if in_contents {
                    match name.as_str() {
                        "Key" => cur_obj.key = text.to_string(),
                        "Size" => cur_obj.size = text.parse().unwrap_or(0),
                        "LastModified" => {
                            cur_obj.last_modified_unix_ms = parse_iso8601_ms(text);
                        }
                        "ETag" => cur_obj.etag = text.trim_matches('"').to_string(),
                        "Contents" => {
                            objects.push(cur_obj.clone());
                            in_contents = false;
                        }
                        _ => {}
                    }
                } else if in_common_prefix {
                    match name.as_str() {
                        "Prefix" => cur_obj.key = text.to_string(),
                        "CommonPrefixes" => {
                            objects.push(cur_obj.clone());
                            in_common_prefix = false;
                        }
                        _ => {}
                    }
                } else if name == "NextContinuationToken" {
                    next_token = Some(text.to_string());
                }
                current_text.clear();
                cur_path.pop();
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(S3ObjectPage {
        objects,
        next_continuation_token: next_token,
    })
}

/// ISO-8601 → unix epoch ms. S3 timestamps come as
/// `2024-01-02T03:04:05.123Z`. `httpdate` only handles RFC 1123;
/// implement a tiny ISO-8601 parser inline rather than pull
/// `chrono`/`time` for one shape.
fn parse_iso8601_ms(input: &str) -> Option<i64> {
    // Expected shape: YYYY-MM-DDTHH:MM:SS(.fff)?Z
    let s = input.trim();
    if s.len() < 19 || !s.ends_with('Z') {
        return None;
    }
    let year: i64 = s.get(0..4)?.parse().ok()?;
    let month: u32 = s.get(5..7)?.parse().ok()?;
    let day: u32 = s.get(8..10)?.parse().ok()?;
    let hour: u32 = s.get(11..13)?.parse().ok()?;
    let minute: u32 = s.get(14..16)?.parse().ok()?;
    let second: u32 = s.get(17..19)?.parse().ok()?;
    let ms_part: u32 = if let Some(rest) = s.get(19..s.len() - 1) {
        if let Some(stripped) = rest.strip_prefix('.') {
            // Pad / truncate to three digits.
            let mut digits = stripped.chars().take(3).collect::<String>();
            while digits.len() < 3 {
                digits.push('0');
            }
            digits.parse().unwrap_or(0)
        } else {
            0
        }
    } else {
        0
    };
    let base_ms = crate::archive::iso8601::civil_to_unix_ms(year, month, day, hour, minute, second);
    Some(base_ms + ms_part as i64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unix_to_components_round_trips_known_epoch() {
        // 2024-01-02T03:04:05Z — pinned by Linux `date -u
        // --date=@1704164645`.
        assert_eq!(unix_to_components(1_704_164_645), (2024, 1, 2, 3, 4, 5));
    }

    #[test]
    fn format_amz_timestamp_uses_compact_iso_shape() {
        // SigV4 mandates `YYYYMMDDTHHMMSSZ` — no dashes, no colons.
        assert_eq!(format_amz_timestamp(1_704_067_200), "20240101T000000Z");
    }

    #[test]
    fn parse_iso8601_ms_round_trips_with_milliseconds() {
        assert_eq!(
            parse_iso8601_ms("2024-01-01T00:00:00.000Z"),
            Some(1_704_067_200_000)
        );
    }

    #[test]
    fn parse_iso8601_ms_handles_no_fractional_seconds() {
        // Some S3 vendors omit the `.fff` portion entirely; the
        // parser must still produce a valid timestamp.
        assert_eq!(
            parse_iso8601_ms("2024-01-01T00:00:00Z"),
            Some(1_704_067_200_000)
        );
    }

    #[test]
    fn parse_iso8601_ms_returns_none_on_malformed() {
        // Reject inputs missing the `Z` suffix — different tz
        // offsets are not what S3 emits.
        assert_eq!(parse_iso8601_ms("2024-01-01T00:00:00+02:00"), None);
        assert_eq!(parse_iso8601_ms(""), None);
    }

    #[test]
    fn extract_tag_returns_inner_text() {
        assert_eq!(
            extract_tag("<a><Code>NoSuchBucket</Code></a>", "Code"),
            Some("NoSuchBucket".into())
        );
    }

    #[test]
    fn extract_tag_returns_none_when_missing() {
        assert_eq!(extract_tag("<a/>", "Code"), None);
    }

    #[test]
    fn extract_tag_decodes_xml_entities() {
        assert_eq!(
            extract_tag(
                "<Error><Message>Bucket &quot;x&quot; not found</Message></Error>",
                "Message"
            ),
            Some("Bucket \"x\" not found".into())
        );
    }

    #[test]
    fn extract_tag_handles_cdata() {
        assert_eq!(
            extract_tag("<Error><Code><![CDATA[NoSuchKey]]></Code></Error>", "Code"),
            Some("NoSuchKey".into())
        );
    }

    #[test]
    fn extract_tag_ignores_namespace_prefix() {
        assert_eq!(
            extract_tag(
                "<aws:Error xmlns:aws=\"x\"><aws:Code>SignatureDoesNotMatch</aws:Code></aws:Error>",
                "Code"
            ),
            Some("SignatureDoesNotMatch".into())
        );
    }

    #[test]
    fn extract_tag_returns_none_on_unparseable_body() {
        assert_eq!(extract_tag("<<<not xml", "Code"), None);
    }

    #[test]
    fn parse_initiate_multipart_upload_id_extracts_value() {
        let xml = r#"<?xml version="1.0"?>
            <InitiateMultipartUploadResult>
              <Bucket>b</Bucket>
              <Key>k</Key>
              <UploadId>VXBsb2FkSWQ=</UploadId>
            </InitiateMultipartUploadResult>"#;
        assert_eq!(
            parse_initiate_multipart_upload_id(xml).unwrap(),
            "VXBsb2FkSWQ="
        );
    }

    #[test]
    fn parse_initiate_multipart_upload_id_errors_on_missing_id() {
        let xml = "<InitiateMultipartUploadResult/>";
        assert!(parse_initiate_multipart_upload_id(xml).is_err());
    }

    #[test]
    fn build_complete_multipart_body_sorts_and_emits_quoted_etag() {
        // Parts come in out-of-order to verify the defensive resort.
        let parts = vec![
            (2, "etag2".to_string()),
            (1, "etag1".to_string()),
            (3, "\"etag3\"".to_string()),
        ];
        let body = build_complete_multipart_body(&parts);
        // Part 1 comes first, part 3 last; etag is quoted exactly
        // once (already-quoted input is normalised).
        let p1 = body.find("<PartNumber>1</PartNumber>").unwrap();
        let p2 = body.find("<PartNumber>2</PartNumber>").unwrap();
        let p3 = body.find("<PartNumber>3</PartNumber>").unwrap();
        assert!(p1 < p2 && p2 < p3);
        assert!(body.contains(r#"<ETag>"etag1"</ETag>"#));
        assert!(body.contains(r#"<ETag>"etag3"</ETag>"#));
    }

    #[test]
    fn parse_list_objects_v2_resolves_entities_in_key() {
        // quick-xml splits entity references out of the text run, so a key
        // with `&` and surrounding spaces must reassemble exactly — no
        // dropped spaces, no truncation at the entity.
        let xml = r#"<?xml version="1.0"?>
            <ListBucketResult>
              <Contents>
                <Key>My &amp; Files/q &#38; a.txt</Key>
                <Size>7</Size>
              </Contents>
            </ListBucketResult>"#;
        let page = parse_list_objects_v2(xml).unwrap();
        assert_eq!(page.objects.len(), 1);
        assert_eq!(page.objects[0].key, "My & Files/q & a.txt");
        assert_eq!(page.objects[0].size, 7);
    }

    #[test]
    fn parse_list_objects_v2_extracts_objects_and_common_prefixes() {
        let xml = r#"<?xml version="1.0"?>
            <ListBucketResult>
              <Name>b</Name>
              <Contents>
                <Key>a.txt</Key>
                <LastModified>2024-01-01T00:00:00.000Z</LastModified>
                <ETag>"abc"</ETag>
                <Size>42</Size>
              </Contents>
              <CommonPrefixes>
                <Prefix>logs/</Prefix>
              </CommonPrefixes>
              <NextContinuationToken>NEXT</NextContinuationToken>
            </ListBucketResult>"#;
        let page = parse_list_objects_v2(xml).unwrap();
        assert_eq!(page.objects.len(), 2);
        let file = &page.objects[0];
        assert_eq!(file.key, "a.txt");
        assert_eq!(file.size, 42);
        assert_eq!(file.etag, "abc");
        assert!(!file.is_dir);
        let dir = &page.objects[1];
        assert_eq!(dir.key, "logs/");
        assert!(dir.is_dir);
        assert_eq!(page.next_continuation_token.as_deref(), Some("NEXT"));
    }

    #[test]
    fn map_xml_error_categorises_auth_404_5xx() {
        let err = map_xml_error(
            StatusCode::FORBIDDEN,
            "<Error><Code>AccessDenied</Code></Error>",
        );
        assert!(matches!(err, Error::S3(ref s) if s.contains("auth")));
        let err = map_xml_error(
            StatusCode::NOT_FOUND,
            "<Error><Code>NoSuchKey</Code></Error>",
        );
        assert!(matches!(err, Error::S3(ref s) if s.contains("not found")));
        let err = map_xml_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "<Error><Code>InternalError</Code></Error>",
        );
        assert!(matches!(err, Error::S3(ref s) if s.contains("server error")));
    }

    #[test]
    fn parse_iso8601_ms_round_trips_unix_to_components() {
        // The two helpers form a round-trip pair via the shared
        // civil-from-days helper; a regression in either surfaces.
        let unix_ms = 1_704_164_645_000_i64;
        let parsed = parse_iso8601_ms("2024-01-02T03:04:05.000Z").expect("valid iso8601");
        assert_eq!(parsed, unix_ms);
        let (y, m, d, h, mi, s) = unix_to_components(1_704_164_645);
        assert_eq!((y, m, d, h, mi, s), (2024, 1, 2, 3, 4, 5));
    }
}
