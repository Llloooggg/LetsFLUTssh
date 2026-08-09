//! AWS Signature Version 4 — minimal inline implementation.
//!
//! Implements the four-stage canonical-request → string-to-sign →
//! signing-key → signature pipeline AWS documents at
//! `https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html`.
//!
//! Covers two modes:
//!
//! 1. **Header signing** — used by every live request the client
//!    issues. The signature lands in an `Authorization:` header and
//!    the payload SHA-256 (or `UNSIGNED-PAYLOAD` for streaming
//!    bodies) lands in `x-amz-content-sha256`.
//!
//! 2. **Query signing** — used for presigned URLs (time-limited
//!    download links). The signature lands as the `X-Amz-Signature`
//!    query parameter; the payload hash is the
//!    `UNSIGNED-PAYLOAD` sentinel.
//!
//! ## Test vectors
//!
//! The unit tests below pin the canonical AWS example
//! `GET` example.amazonaws.com / from the `sigv4-test-suite`
//! documentation page so a regression hits the build.

use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

/// `UNSIGNED-PAYLOAD` sentinel — used for streamed uploads where
/// computing the payload SHA-256 ahead of time would force the
/// caller to buffer the whole body. AWS S3 accepts this value;
/// other S3-compatible servers (MinIO, R2) do too.
pub const UNSIGNED_PAYLOAD: &str = "UNSIGNED-PAYLOAD";

/// `x-amz-content-sha256` value for an empty body. Saves a hash
/// round on every list / head / delete request.
pub const EMPTY_PAYLOAD_HASH: &str =
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

/// One signed request. `headers` carries every entry the caller
/// must include (`host`, `x-amz-date`, `x-amz-content-sha256`,
/// `authorization`, and any additional caller-provided headers).
#[derive(Debug, Clone)]
pub struct SignedRequest {
    pub headers: Vec<(String, String)>,
}

/// Inputs into header signing. `payload_hash` is the lowercase
/// hex SHA-256 of the body or [`UNSIGNED_PAYLOAD`] /
/// [`EMPTY_PAYLOAD_HASH`].
pub struct SignHeaderInput<'a> {
    pub method: &'a str,
    pub host: &'a str,
    pub path: &'a str,
    pub query: &'a str,
    pub payload_hash: &'a str,
    pub extra_headers: &'a [(String, String)],
    pub access_key_id: &'a str,
    pub secret_access_key: &'a str,
    pub region: &'a str,
    pub service: &'a str,
    /// `YYYYMMDDTHHMMSSZ` — caller controls the clock so tests can
    /// pin a value and so a near-expiry retry can reuse the same
    /// timestamp.
    pub timestamp: &'a str,
}

/// Sign a request via `Authorization` header. Returns the full
/// header bag the caller must apply (extras passed in are merged
/// into the returned list so the call site only needs to walk one
/// vector).
pub fn sign_headers(input: &SignHeaderInput<'_>) -> SignedRequest {
    let date = &input.timestamp[..8];

    // Canonical headers — every header AWS folds into the signed
    // set. host + x-amz-date + x-amz-content-sha256 are mandatory;
    // additional caller-provided headers ride in `extra_headers`.
    let mut all_headers: Vec<(String, String)> = Vec::new();
    all_headers.push(("host".into(), input.host.to_string()));
    all_headers.push(("x-amz-date".into(), input.timestamp.to_string()));
    all_headers.push((
        "x-amz-content-sha256".into(),
        input.payload_hash.to_string(),
    ));
    for (k, v) in input.extra_headers {
        all_headers.push((k.to_ascii_lowercase(), v.trim().to_string()));
    }
    all_headers.sort_by(|a, b| a.0.cmp(&b.0));

    let canonical_headers: String = all_headers
        .iter()
        .map(|(k, v)| format!("{k}:{v}\n"))
        .collect();
    let signed_headers: String = all_headers
        .iter()
        .map(|(k, _)| k.as_str())
        .collect::<Vec<_>>()
        .join(";");

    let canonical_uri = canonical_path(input.path);
    let canonical_query = canonicalize_query(input.query);

    let canonical_request = format!(
        "{}\n{}\n{}\n{}\n{}\n{}",
        input.method,
        canonical_uri,
        canonical_query,
        canonical_headers,
        signed_headers,
        input.payload_hash,
    );

    let credential_scope = format!("{}/{}/{}/aws4_request", date, input.region, input.service);

    let canonical_request_hash = hex_sha256(canonical_request.as_bytes());
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{}\n{}\n{}",
        input.timestamp, credential_scope, canonical_request_hash,
    );

    let signing_key =
        derive_signing_key(input.secret_access_key, date, input.region, input.service);
    let signature = hex_hmac_sha256(&signing_key, string_to_sign.as_bytes());

    let authorization = format!(
        "AWS4-HMAC-SHA256 Credential={}/{}, SignedHeaders={}, Signature={}",
        input.access_key_id, credential_scope, signed_headers, signature,
    );

    let mut out = Vec::with_capacity(all_headers.len() + 1);
    for (k, v) in all_headers {
        // Re-emit `Host` in canonical capitalisation so HTTP libraries
        // that match case-insensitively still keep the wire shape
        // recognisable in logs.
        let header_name = match k.as_str() {
            "host" => "Host".to_string(),
            "x-amz-date" => "x-amz-date".to_string(),
            "x-amz-content-sha256" => "x-amz-content-sha256".to_string(),
            other => other.to_string(),
        };
        out.push((header_name, v));
    }
    out.push(("Authorization".into(), authorization));
    SignedRequest { headers: out }
}

/// Build a presigned URL — same SigV4 algorithm, signature in the
/// query string. `expires_seconds` is clamped to [1, 604800] (7 days
/// AWS maximum).
pub struct PresignInput<'a> {
    pub method: &'a str,
    pub host: &'a str,
    pub path: &'a str,
    pub access_key_id: &'a str,
    pub secret_access_key: &'a str,
    pub region: &'a str,
    pub service: &'a str,
    pub timestamp: &'a str,
    pub expires_seconds: u32,
}

/// Sign a request via query parameters and return the fully-formed
/// URL ready to hand to the user.
pub fn presign_url(input: &PresignInput<'_>, scheme: &str) -> String {
    const ONE_WEEK_SECS: u32 = 7 * 24 * 60 * 60;
    let expires = input.expires_seconds.clamp(1, ONE_WEEK_SECS);
    let date = &input.timestamp[..8];
    let credential_scope = format!("{}/{}/{}/aws4_request", date, input.region, input.service);
    let credential = format!("{}/{}", input.access_key_id, credential_scope);

    // Pre-sign always signs the `host` header (and only `host`).
    let signed_headers = "host";
    let canonical_headers = format!("host:{}\n", input.host);

    let query_params: Vec<(String, String)> = vec![
        ("X-Amz-Algorithm".into(), "AWS4-HMAC-SHA256".into()),
        ("X-Amz-Credential".into(), uri_encode(&credential, true)),
        ("X-Amz-Date".into(), input.timestamp.to_string()),
        ("X-Amz-Expires".into(), expires.to_string()),
        ("X-Amz-SignedHeaders".into(), signed_headers.into()),
    ];
    let canonical_query: String = canonicalize_query_pairs(&query_params);

    let canonical_uri = canonical_path(input.path);
    let canonical_request = format!(
        "{}\n{}\n{}\n{}\n{}\n{}",
        input.method,
        canonical_uri,
        canonical_query,
        canonical_headers,
        signed_headers,
        UNSIGNED_PAYLOAD,
    );

    let canonical_request_hash = hex_sha256(canonical_request.as_bytes());
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{}\n{}\n{}",
        input.timestamp, credential_scope, canonical_request_hash,
    );
    let signing_key =
        derive_signing_key(input.secret_access_key, date, input.region, input.service);
    let signature = hex_hmac_sha256(&signing_key, string_to_sign.as_bytes());

    format!(
        "{scheme}://{host}{path}?{canonical_query}&X-Amz-Signature={signature}",
        host = input.host,
        path = canonical_uri,
    )
}

/// Canonicalise the path component per the SigV4 spec — every
/// segment URI-encoded, slashes preserved. Empty input maps to
/// `/` per the AWS canonical-request grammar.
///
/// Callers pass the **raw** path (un-encoded key); this applies the
/// single encoding the signed canonical request needs. The live
/// request builder reuses it to encode the wire URL too, so the
/// signed path and the wire path stay byte-identical — encoding the
/// key a second time at the call site would sign `%2520` while the
/// wire carried `%20` and every special-char key would 403.
pub(crate) fn canonical_path(path: &str) -> String {
    if path.is_empty() {
        return "/".into();
    }
    // SigV4 expects a path that begins with `/`. The caller's
    // input may or may not have one; we always emit it.
    let mut out = String::from("/");
    let trimmed = path.strip_prefix('/').unwrap_or(path);
    let mut first = true;
    for segment in trimmed.split('/') {
        if !first {
            out.push('/');
        }
        first = false;
        out.push_str(&uri_encode(segment, false));
    }
    if path.ends_with('/') && !out.ends_with('/') {
        out.push('/');
    }
    out
}

/// Canonical-query from a raw `?` string. Empty input yields an
/// empty string (no question mark in canonical form).
fn canonicalize_query(raw: &str) -> String {
    if raw.is_empty() {
        return String::new();
    }
    let mut pairs: Vec<(String, String)> = Vec::new();
    for part in raw.split('&') {
        if part.is_empty() {
            continue;
        }
        let (k, v) = match part.split_once('=') {
            Some((k, v)) => (k.to_string(), v.to_string()),
            None => (part.to_string(), String::new()),
        };
        // Already-URL-encoded query strings (the caller's job)
        // round-trip; we re-encode the decoded form to enforce
        // the SigV4 canonical encoding.
        let dk = url_decode(&k);
        let dv = url_decode(&v);
        pairs.push((uri_encode(&dk, true), uri_encode(&dv, true)));
    }
    canonicalize_query_pairs(&pairs)
}

fn canonicalize_query_pairs(pairs: &[(String, String)]) -> String {
    let mut sorted: Vec<(String, String)> = pairs.to_vec();
    sorted.sort();
    sorted
        .into_iter()
        .map(|(k, v)| format!("{k}={v}"))
        .collect::<Vec<_>>()
        .join("&")
}

/// SigV4 URI-encode. `is_query` controls whether `/` is encoded
/// (yes for query, no for path segments — path segments preserve
/// `/`). The unreserved set per AWS docs is alphanumeric + `_.~-`.
pub fn uri_encode(input: &str, is_query: bool) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.as_bytes() {
        let b = *byte;
        let unreserved = b.is_ascii_alphanumeric()
            || b == b'_'
            || b == b'.'
            || b == b'~'
            || b == b'-'
            || (b == b'/' && !is_query);
        if unreserved {
            out.push(b as char);
        } else {
            out.push('%');
            out.push_str(&format!("{:02X}", b));
        }
    }
    out
}

/// Tiny URL-decoder for the canonical-query rewrite — only needs to
/// undo `%xx`-style escapes and the `+` → ` ` substitution. Errors
/// fall through to the literal character so the canonicaliser never
/// panics on a malformed input the server would reject anyway.
fn url_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        if b == b'%' && i + 2 < bytes.len() {
            let hi = (bytes[i + 1] as char).to_digit(16);
            let lo = (bytes[i + 2] as char).to_digit(16);
            if let (Some(hi), Some(lo)) = (hi, lo) {
                out.push(((hi << 4) | lo) as u8);
                i += 3;
                continue;
            }
        }
        if b == b'+' {
            out.push(b' ');
        } else {
            out.push(b);
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Derive the 32-byte SigV4 signing key:
/// `HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service), "aws4_request")`.
fn derive_signing_key(secret: &str, date: &str, region: &str, service: &str) -> [u8; 32] {
    let k_date = hmac_sha256(format!("AWS4{secret}").as_bytes(), date.as_bytes());
    let k_region = hmac_sha256(&k_date, region.as_bytes());
    let k_service = hmac_sha256(&k_region, service.as_bytes());
    hmac_sha256(&k_service, b"aws4_request")
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
    // Construction moved to the `KeyInit` trait in crypto-common 0.2.
    let mut mac =
        <HmacSha256 as hmac::digest::KeyInit>::new_from_slice(key).expect("HMAC key length");
    mac.update(data);
    mac.finalize().into_bytes().into()
}

fn hex_hmac_sha256(key: &[u8], data: &[u8]) -> String {
    let bytes = hmac_sha256(key, data);
    hex_lower(&bytes)
}

/// Hex-encode a SHA-256 of `data`.
pub fn hex_sha256(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    hex_lower(&h.finalize())
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write as _;
        let _ = write!(out, "{b:02x}");
    }
    out
}
#[cfg(test)]
#[path = "../../tests/unit/s3_signer.rs"]
mod tests;
