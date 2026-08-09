//! WebDAV HTTP client — the public verb surface.
//!
//! Six verbs against a configured base URL:
//!
//! - [`WebDavClient::propfind`] — list a collection (`depth=1`) or
//!   stat a single resource (`depth=0`).
//! - [`WebDavClient::get`] — fetch a resource body, with optional
//!   byte range (HTTP `Range: bytes=START-END`) and optional
//!   conditional `If-None-Match` for a 304-short-circuit GET.
//! - [`WebDavClient::put`] — upload, with optional `If-Match`
//!   ETag for conditional update.
//! - [`WebDavClient::delete`] — remove.
//! - [`WebDavClient::mkcol`] — create a collection.
//! - [`WebDavClient::move_resource`] — server-side rename / move
//!   with `Overwrite: T|F`.
//!
//! ## Path joining
//!
//! Caller-supplied `path` is relative — `notes.txt`,
//! `sub/dir/file.bin`, or starts with `/` to override the base
//! URL's path. The client routes joins through
//! [`url::Url::join`] which percent-encodes path segments per
//! RFC 3986 (space → `%20`, Unicode → UTF-8 + percent). Callers
//! that pre-encode (e.g. forward an already-encoded `href` from
//! a prior PROPFIND response) lose nothing — `Url::join` is
//! idempotent on already-valid percent sequences.
//!
//! ## Depth handling
//!
//! `depth=0` for stat; `depth=1` for one directory level;
//! `depth=infinity` is forbidden — the client rejects the
//! request before sending it. Rationale: most servers reject
//! infinity by default (Nextcloud, ownCloud) and the ones that
//! accept it have known DoS shapes — a recursive walk against a
//! deep tree can pin the server for minutes. Sync orchestration
//! and the file browser both walk one level at a time, so the
//! API restriction matches the consumer pattern.
//!
//! ## Status code mapping
//!
//! | Status | Maps to |
//! |---|---|
//! | 2xx | success |
//! | 304 (GET only) | success (caller branches on `status() == 304`) |
//! | 401 (Digest) | retry once with parsed challenge |
//! | 401 (other) | `Error::WebDav("authentication failed")` |
//! | 403 | `Error::WebDav("forbidden")` |
//! | 404 | `Error::WebDav("not found")` |
//! | 405 | `Error::WebDav("method not allowed")` |
//! | 409 | `Error::WebDav("conflict")` |
//! | 412 | `Error::WebDav("etag mismatch")` |
//! | 423 | `Error::WebDav("locked")` |
//! | 507 | `Error::WebDav("insufficient storage")` |
//! | other 4xx/5xx | `Error::WebDav("HTTP {code}: {reason}")` |
//!
//! ## Sanity caps
//!
//! PROPFIND bodies cap at [`parser::MAX_RESPONSE_BYTES`] (16
//! MiB). GET / PUT have no cap here — they stream chunks
//! through the consumer's progress callback, so a 10 GiB file
//! does not buffer.

use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use rand::Rng;
use reqwest::header::HeaderValue;
use reqwest::Method;
use url::Url;

use crate::error::Error;
use crate::webdav::auth::{
    header_value_basic_or_bearer, AuthMethod, Credentials, DigestChallenge, DigestState,
};
use crate::webdav::parser::{parse_propfind, MAX_RESPONSE_BYTES};
use crate::webdav::PropfindEntry;

/// Per-request timeout. Same default as
/// [`crate::update::http::REQUEST_TIMEOUT`] — auto-update and
/// sync both rate-limit to one outstanding call per resource,
/// so a stuck connection that pins the worker is the failure
/// shape we want a hard cap on.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

/// HTTP redirect cap. WebDAV servers typically don't redirect
/// the verb URLs themselves, but reverse proxies in front may
/// hop once (HTTP → HTTPS) or rewrite paths. 10 leaves
/// headroom; the actual upper bound on real deployments is 1-2.
const MAX_REDIRECTS: usize = 10;

/// Returned by [`WebDavClient::put`] so callers can record the
/// server-assigned ETag for subsequent conditional updates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PutOutcome {
    /// Normalised ETag (quotes + `W/` stripped) when the server
    /// returned one. `None` for servers that don't surface it on
    /// PUT — the caller has to issue a follow-up PROPFIND to pick
    /// up the value.
    pub etag: Option<String>,
}

/// WebDAV client bound to a base URL + auth credentials.
///
/// Clone-friendly: the inner `reqwest::Client` pools connections,
/// the digest state lives behind a `Mutex`. Two clones do not
/// invalidate each other's digest cache because the `Arc` shares
/// one state.
pub struct WebDavClient {
    base_url: Url,
    http: reqwest::Client,
    creds: Arc<Credentials>,
    digest: Arc<DigestState>,
}

impl WebDavClient {
    /// Build a client.
    ///
    /// `base_url` is the WebDAV root collection — must end in
    /// `/` (the URL crate's `join` semantics require a trailing
    /// slash to keep the last segment as a directory). When the
    /// caller omits it, the constructor appends one.
    ///
    /// `trusted_cert_pem` is the per-session "trust this cert"
    /// surface — parse every `-----BEGIN CERTIFICATE-----` block
    /// in the blob and feed it into the reqwest client builder as
    /// an additional root CA via [`reqwest::ClientBuilder::add_root_certificate`].
    /// Self-signed cert presented by the server then chains to
    /// itself (its own DER bytes match the added root) and the
    /// rustls verifier accepts. `None` falls back to the bundled
    /// `webpki-roots` trust store.
    ///
    /// `insecure_skip_verify` is the escape hatch — flip every
    /// rustls cert / hostname check off. Used only when the
    /// caller-side UI has surfaced the MITM-risk warning and the
    /// user explicitly opted in. The two paths are mutually
    /// exclusive at the user level (the dialog disables the cert
    /// textarea when insecure is on); at the transport level
    /// insecure wins.
    pub fn new(
        base_url: &str,
        creds: Credentials,
        trusted_cert_pem: Option<&str>,
        insecure_skip_verify: bool,
    ) -> Result<Self, Error> {
        let mut parsed =
            Url::parse(base_url).map_err(|e| Error::WebDav(format!("base url parse: {e}")))?;
        if !parsed.path().ends_with('/') {
            let path = format!("{}/", parsed.path());
            parsed.set_path(&path);
        }
        let mut builder = reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .redirect(reqwest::redirect::Policy::limited(MAX_REDIRECTS))
            .user_agent(format!("letsflutssh-webdav/{}", env!("CARGO_PKG_VERSION")));
        if insecure_skip_verify {
            builder = builder
                .danger_accept_invalid_certs(true)
                .danger_accept_invalid_hostnames(true);
        } else if let Some(pem) = trusted_cert_pem.filter(|s| !s.trim().is_empty()) {
            for cert in parse_pem_certs(pem)? {
                builder = builder.add_root_certificate(cert);
            }
        }
        let http = builder
            .build()
            .map_err(|e| Error::WebDav(format!("http client build: {e}")))?;
        Ok(Self {
            base_url: parsed,
            http,
            creds: Arc::new(creds),
            digest: Arc::new(DigestState::new()),
        })
    }

    /// `PROPFIND` against `path` with `depth ∈ {0, 1}`. Returns
    /// parsed entries from a 207 multistatus body.
    ///
    /// `depth=2` and above (`infinity`) are rejected without a
    /// network round-trip — see module rationale.
    pub async fn propfind(&self, path: &str, depth: u8) -> Result<Vec<PropfindEntry>, Error> {
        if depth > 1 {
            return Err(Error::WebDav(format!(
                "depth={depth} rejected (only 0 and 1 are supported)"
            )));
        }
        let url = self.join(path)?;
        let body = PROPFIND_ALLPROP_BODY;
        let response = self
            .send(
                Method::from_bytes(b"PROPFIND").expect("static method bytes"),
                &url,
                |rb| {
                    rb.header("Depth", depth.to_string())
                        .header("Content-Type", "application/xml; charset=utf-8")
                        .body(body)
                },
            )
            .await?;
        let status = response.status();
        if status.as_u16() != 207 && !status.is_success() {
            return Err(map_status_error(status, "propfind"));
        }
        let bytes = response_body_capped(response).await?;
        // Depth enforcement is server-side: WebDAV servers honour the
        // `Depth` request header per RFC 4918 §10.2. A reverify pass
        // here would have to know each server's href-prefixing convention
        // (Apache mod_dav returns absolute paths under its mount root,
        // Nextcloud returns paths under `/remote.php/dav/`, owncloud's
        // /webdav/ root, IIS uses the trailing slash differently) — a
        // segment-count heuristic mis-classifies legitimate responses
        // depending on the deployment. The PROPFIND parser already caps
        // body size + entry count via `response_body_capped`, which is
        // the right place to guard against pathological response sizes.
        parse_propfind(&bytes)
    }

    /// `GET` against `path`. When `range` is `Some((start, end))`,
    /// stamps an inclusive `Range: bytes=start-end` header per
    /// HTTP/1.1; the server responds with 206. When `range` is
    /// `None`, requests the full body and expects 200.
    ///
    /// `if_none_match` carries an RFC 7232 `If-None-Match` header
    /// value when the caller wants a conditional GET. The header
    /// accepts a comma-separated list of quoted ETags or `*` and
    /// is forwarded verbatim — callers assemble the list. A 304
    /// response is returned to the caller (NOT mapped to an
    /// `Error`) so the conditional-GET path can branch on
    /// `response.status() == 304` without losing the headers.
    pub async fn get(
        &self,
        path: &str,
        range: Option<(u64, u64)>,
        if_none_match: Option<&str>,
    ) -> Result<reqwest::Response, Error> {
        let url = self.join(path)?;
        let response = self
            .send(Method::GET, &url, |rb| {
                let rb = if let Some((start, end)) = range {
                    rb.header("Range", format!("bytes={start}-{end}"))
                } else {
                    rb
                };
                if let Some(inm) = if_none_match {
                    rb.header("If-None-Match", inm)
                } else {
                    rb
                }
            })
            .await?;
        let status = response.status();
        // 304 is a successful conditional outcome — surface it to
        // the caller with the response intact so headers (ETag,
        // Last-Modified) round-trip without a body read.
        if status.as_u16() == 304 {
            return Ok(response);
        }
        if !status.is_success() {
            return Err(map_status_error(status, "get"));
        }
        Ok(response)
    }

    /// `PUT` `body` at `path`. When `if_match` is `Some`, stamps
    /// `If-Match: "<etag>"` — the server returns 412 if the
    /// remote ETag drifted, which surfaces as
    /// `Error::WebDav("etag mismatch")`.
    pub async fn put(
        &self,
        path: &str,
        body: Bytes,
        if_match: Option<&str>,
    ) -> Result<PutOutcome, Error> {
        let url = self.join(path)?;
        let body_for_request = body.clone();
        let response = self
            .send(Method::PUT, &url, |rb| {
                let rb = rb.body(body_for_request.clone());
                if let Some(etag) = if_match {
                    rb.header("If-Match", quote_etag(etag))
                } else {
                    rb
                }
            })
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(map_status_error(status, "put"));
        }
        // Server may surface the new ETag on 201 / 204.
        let etag = response
            .headers()
            .get(reqwest::header::ETAG)
            .and_then(|v| v.to_str().ok())
            .map(normalise_etag_header);
        Ok(PutOutcome { etag })
    }

    /// `DELETE` `path`. Success on 200 / 204; 404 surfaces as
    /// `Error::WebDav("not found")` for callers that need
    /// idempotent delete semantics to special-case it.
    pub async fn delete(&self, path: &str) -> Result<(), Error> {
        let url = self.join(path)?;
        let response = self.send(Method::DELETE, &url, |rb| rb).await?;
        let status = response.status();
        if !status.is_success() {
            return Err(map_status_error(status, "delete"));
        }
        Ok(())
    }

    /// `MKCOL` `path`. Success on 201; 405 (collection already
    /// exists) maps to `Error::WebDav("method not allowed")` —
    /// the caller decides whether to treat that as idempotent.
    pub async fn mkcol(&self, path: &str) -> Result<(), Error> {
        let url = self.join(path)?;
        let response = self
            .send(
                Method::from_bytes(b"MKCOL").expect("static method bytes"),
                &url,
                |rb| rb,
            )
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(map_status_error(status, "mkcol"));
        }
        Ok(())
    }

    /// `MOVE` `from` → `to` with `Overwrite: T` / `F`. Success on
    /// 201 (created) or 204 (overwritten). Both `from` and `to`
    /// are joined against the base URL.
    pub async fn move_resource(&self, from: &str, to: &str, overwrite: bool) -> Result<(), Error> {
        let from_url = self.join(from)?;
        let to_url = self.join(to)?;
        let dest = HeaderValue::from_str(to_url.as_str())
            .map_err(|e| Error::WebDav(format!("move destination header: {e}")))?;
        let overwrite_header = if overwrite { "T" } else { "F" };
        let response = self
            .send(
                Method::from_bytes(b"MOVE").expect("static method bytes"),
                &from_url,
                |rb| {
                    rb.header("Destination", dest.clone())
                        .header("Overwrite", overwrite_header)
                },
            )
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(map_status_error(status, "move"));
        }
        Ok(())
    }

    /// Resolve `path` against [`base_url`] per RFC 3986. The
    /// callers pass one of three shapes:
    ///
    /// - **Relative** (`"probe.txt"`, `"sub/"`) — merged into the
    ///   base path. `merge` drops the last segment of `base.path`
    ///   unless it ends in `/`; the configured base URL is required
    ///   to end in `/` (asserted at construction), so a relative
    ///   reference appends cleanly.
    /// - **Server-absolute** (`"/dav/probe.txt"`, `"/dav/sub/"`) —
    ///   replaces the path component while keeping scheme + host.
    ///   The Dart pane normalises every navigation path to this
    ///   shape (the configured base URL's path is what
    ///   `WebDavFileSystem.initialDir` returns); PROPFIND returns
    ///   `href` values in this shape too.
    /// - **Full URI** (`"http://other.example/x"`) — replaces
    ///   everything. Used by the initial-list path when the Dart
    ///   side still has a full-URL `currentPath` (legacy callers).
    ///
    /// Prior shape trimmed the leading `/` before calling
    /// `Url::join`, which silently collapsed server-absolute paths
    /// to relative — `/dav/x` against base `http://h/dav/` became
    /// `http://h/dav/dav/x`, which the server 404'd. The
    /// regression surfaced as the user-reported "DELETE 404" /
    /// "drag-drop lands on the wrong path" — every write verb fed
    /// a doubled-up path component to the server.
    fn join(&self, path: &str) -> Result<Url, Error> {
        let resolved = self
            .base_url
            .join(path)
            .map_err(|e| Error::WebDav(format!("path join: {e}")))?;
        // Refuse a path/href that resolves to a different origin than
        // the configured base. A hostile or compromised server can
        // return an absolute `<href>` (e.g. `http://attacker/x`, or a
        // protocol-relative `//attacker/x`) inside a PROPFIND
        // multistatus; the interactive file browser feeds those hrefs
        // straight back into `list`/`get`/`put`/`remove`, and
        // `apply_auth` would then stamp the user's Basic/Bearer
        // credential onto the attacker's host. Same-origin relative
        // and server-absolute paths still resolve normally.
        if resolved.origin() != self.base_url.origin() {
            return Err(Error::WebDav(
                "refusing cross-origin path (server returned an href \
                 outside the configured base URL)"
                    .into(),
            ));
        }
        Ok(resolved)
    }

    /// Send a request, stamping the right `Authorization:` header
    /// based on [`Credentials::method`] and the current digest
    /// state. Retries once on 401 + digest scheme so the first
    /// caller pays the challenge round-trip and every subsequent
    /// one stamps the cached challenge up-front.
    async fn send<F>(
        &self,
        method: Method,
        url: &Url,
        configure: F,
    ) -> Result<reqwest::Response, Error>
    where
        F: Fn(reqwest::RequestBuilder) -> reqwest::RequestBuilder,
    {
        // First attempt — stamp Basic / Bearer directly, or the
        // cached digest challenge when we have one. No header at
        // all on the first digest call so the server emits the
        // challenge.
        let mut response = {
            let rb = self.http.request(method.clone(), url.clone());
            let rb = self.apply_auth(rb, method.as_str(), url)?;
            let rb = configure(rb);
            rb.send()
                .await
                .map_err(|e| Error::WebDav(format!("send: {e}")))?
        };

        // 401 retry for digest. Parse the challenge, store it,
        // re-send once. Stale-nonce handling follows the same
        // code path because we re-parse and re-store every time.
        if response.status().as_u16() == 401 && self.creds.method == AuthMethod::Digest {
            let www = response
                .headers()
                .get(reqwest::header::WWW_AUTHENTICATE)
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());
            let parsed = www
                .as_deref()
                .and_then(DigestChallenge::parse)
                .ok_or_else(|| {
                    Error::WebDav("401 without parseable Digest challenge".to_string())
                })?;
            self.digest.set_challenge(parsed);
            let rb = self.http.request(method.clone(), url.clone());
            let rb = self.apply_auth(rb, method.as_str(), url)?;
            let rb = configure(rb);
            response = rb
                .send()
                .await
                .map_err(|e| Error::WebDav(format!("send retry: {e}")))?;
        }
        Ok(response)
    }

    /// Stamp the credentials header for one request. For Digest,
    /// builds the response hash against the current request's
    /// path + query. Returns the builder unmodified when no
    /// challenge has been seen yet — the un-authenticated probe
    /// triggers the 401 retry loop above.
    fn apply_auth(
        &self,
        rb: reqwest::RequestBuilder,
        method: &str,
        url: &Url,
    ) -> Result<reqwest::RequestBuilder, Error> {
        match self.creds.method {
            AuthMethod::Basic | AuthMethod::Bearer => {
                let value = header_value_basic_or_bearer(&self.creds)?;
                Ok(rb.header(
                    reqwest::header::AUTHORIZATION,
                    HeaderValue::from_str(&value)
                        .map_err(|e| Error::WebDav(format!("auth header: {e}")))?,
                ))
            }
            AuthMethod::Digest => {
                if !self.digest.has_challenge() {
                    return Ok(rb);
                }
                let cnonce = random_cnonce();
                let request_uri = uri_path_and_query(url);
                let header =
                    self.digest
                        .build_response(&self.creds, method, &request_uri, &cnonce)?;
                Ok(rb.header(
                    reqwest::header::AUTHORIZATION,
                    HeaderValue::from_str(&header)
                        .map_err(|e| Error::WebDav(format!("auth header: {e}")))?,
                ))
            }
        }
    }
}

/// Map any reqwest response status outside the 2xx range to a
/// typed `Error::WebDav` variant the rest of the stack matches
/// against. Reason phrases come from `StatusCode::canonical_reason`
/// rather than the raw response body so log lines stay grep-able.
fn map_status_error(status: reqwest::StatusCode, verb: &str) -> Error {
    let code = status.as_u16();
    let label = match code {
        401 => "authentication failed",
        403 => "forbidden",
        404 => "not found",
        405 => "method not allowed",
        409 => "conflict",
        412 => "etag mismatch",
        423 => "locked",
        507 => "insufficient storage",
        _ => status.canonical_reason().unwrap_or("unexpected status"),
    };
    Error::WebDav(format!("{verb}: HTTP {code}: {label}"))
}

/// Buffer the response body with the 16 MiB cap. PROPFIND is
/// the only verb that reads the body in full; GET streams
/// directly to the caller and skips this path.
///
/// When the server advertises `Content-Length`, pre-allocate the
/// buffer up to the cap so a single large response doesn't grow
/// the `Vec` through several power-of-two doublings. The hint is
/// untrusted (a hostile server could lie), so we clamp it against
/// `MAX_RESPONSE_BYTES` — a bad hint can only force one harmless
/// 16 MiB allocation, never an OOM.
async fn response_body_capped(response: reqwest::Response) -> Result<Vec<u8>, Error> {
    use futures_util::StreamExt;
    let hint = response
        .content_length()
        .map(|n| {
            usize::try_from(n)
                .unwrap_or(MAX_RESPONSE_BYTES)
                .min(MAX_RESPONSE_BYTES)
        })
        .unwrap_or(0);
    let mut stream = response.bytes_stream();
    let mut out: Vec<u8> = Vec::with_capacity(hint);
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| Error::WebDav(format!("body chunk: {e}")))?;
        if out.len().saturating_add(bytes.len()) > MAX_RESPONSE_BYTES {
            return Err(Error::WebDav(format!(
                "response body too large (cap {})",
                MAX_RESPONSE_BYTES
            )));
        }
        out.extend_from_slice(&bytes);
    }
    Ok(out)
}

/// Wrap an ETag in double quotes for `If-Match` regardless of
/// whether the caller stripped them. Servers expect the quoted
/// form per RFC 7232.
pub(crate) fn quote_etag(etag: &str) -> String {
    let trimmed = etag.trim();
    if trimmed.starts_with('"') && trimmed.ends_with('"') {
        return trimmed.to_string();
    }
    format!("\"{trimmed}\"")
}

/// Strip `W/` + surrounding quotes from an ETag header value.
/// Same logic as the parser but accepts the value as raw header
/// bytes rather than re-using the parser-internal helper (kept
/// inline to avoid a `pub` widen on the parser fn).
pub(crate) fn normalise_etag_header(raw: &str) -> String {
    let trimmed = raw.trim();
    let stripped = trimmed
        .strip_prefix("W/")
        .or_else(|| trimmed.strip_prefix("w/"))
        .unwrap_or(trimmed);
    stripped
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .unwrap_or(stripped)
        .to_string()
}
/// `https://example.com/dav/files/?x=1` → `/dav/files/?x=1`.
/// Digest's H(A2) hashes the request URI in the form the
/// server sees, which is the path + optional query — host
/// part stripped.
fn uri_path_and_query(url: &Url) -> String {
    match url.query() {
        Some(q) => format!("{}?{q}", url.path()),
        None => url.path().to_string(),
    }
}

/// 16-hex-char random nonce for digest qop=auth. RFC 7616
/// allows any client-chosen value; the only requirement is
/// per-request uniqueness, which 64 bits of entropy satisfies.
fn random_cnonce() -> String {
    let mut buf = [0u8; 8];
    rand::rng().fill_bytes(&mut buf);
    let mut s = String::with_capacity(16);
    use std::fmt::Write as _;
    for b in buf.iter() {
        let _ = write!(s, "{b:02x}");
    }
    s
}

/// Split a PEM blob into one [`reqwest::Certificate`] per
/// `-----BEGIN CERTIFICATE-----` block. Returns an empty `Vec`
/// when the blob contains no certificate blocks, an error when
/// any block fails to parse as a single X.509 cert (corrupt PEM
/// or wrong armoring — encrypted PEMs, public keys, RSA params).
///
/// Multi-cert bundles are common (`fullchain.pem`, internal CA
/// chains); `reqwest::Certificate::from_pem` only consumes the
/// first block per call, so the caller needs the per-block loop
/// to feed the full chain into [`reqwest::ClientBuilder::add_root_certificate`].
pub fn parse_pem_certs(pem: &str) -> Result<Vec<reqwest::Certificate>, Error> {
    const BEGIN: &str = "-----BEGIN CERTIFICATE-----";
    const END: &str = "-----END CERTIFICATE-----";
    let mut out = Vec::new();
    let mut cursor = pem;
    while let Some(begin) = cursor.find(BEGIN) {
        let after_begin = &cursor[begin..];
        let end = after_begin
            .find(END)
            .ok_or_else(|| Error::WebDav("trusted cert PEM: unterminated block".to_string()))?;
        let block_len = end + END.len();
        let block = &after_begin[..block_len];
        let cert = reqwest::Certificate::from_pem(block.as_bytes())
            .map_err(|e| Error::WebDav(format!("trusted cert PEM parse: {e}")))?;
        out.push(cert);
        cursor = &after_begin[block_len..];
    }
    Ok(out)
}

/// Static PROPFIND body that asks for the props the parser
/// actually consumes. RFC 4918 allows `<allprop/>` shorthand
/// but Microsoft IIS in some configurations rejects it; the
/// explicit prop list is the lowest-friction shape.
const PROPFIND_ALLPROP_BODY: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<propfind xmlns="DAV:">
  <prop>
    <displayname/>
    <getcontentlength/>
    <getcontenttype/>
    <getetag/>
    <getlastmodified/>
    <resourcetype/>
  </prop>
</propfind>"#;
#[cfg(test)]
#[path = "../../tests/unit/webdav_client.rs"]
mod tests;
