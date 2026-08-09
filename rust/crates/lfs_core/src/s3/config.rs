//! [`S3Config`] — the credentials + addressing tuple every
//! [`crate::s3::client::S3Client`] is constructed from.
//!
//! The secret access key crosses through here as `Zeroizing<String>`
//! so a dropped config wipes the key bytes without depending on
//! the allocator's reuse pattern.

use zeroize::Zeroizing;

/// Per-session S3 configuration. Built by the connect path from
/// `lfs_core::db::s3_sessions::S3SessionRow` + the SecretStore-
/// resolved secret access key.
#[derive(Clone)]
pub struct S3Config {
    /// AWS access key id (`AKIA…`, MinIO console-generated key,
    /// R2 access key id, etc.). Public-side credential.
    pub access_key_id: String,
    /// Secret access key. `Zeroizing` so the buffer wipes on drop.
    pub secret_access_key: Zeroizing<String>,
    /// Region wire value. AWS-specific endpoints derive their host
    /// from this; non-AWS endpoints use the value verbatim for the
    /// SigV4 credential scope.
    pub region: String,
    /// Optional endpoint URL. Empty selects the AWS regional
    /// default (`https://s3.<region>.amazonaws.com`). Non-empty is
    /// used verbatim (e.g. `https://minio.local:9000`,
    /// `https://<account>.r2.cloudflarestorage.com`).
    pub endpoint: String,
    /// Addressing style. `false` (virtual-host) is the AWS default
    /// — bucket name is part of the host
    /// (`<bucket>.s3.<region>.amazonaws.com`). `true` (path) puts
    /// the bucket in the path component
    /// (`<endpoint>/<bucket>/<key>`); MinIO and some private S3
    /// deployments require this style.
    pub path_style: bool,
    /// Optional default bucket — used when an `s3://key` style
    /// path is passed without an explicit bucket. Empty disables
    /// the shorthand; every call must then carry `s3://bucket/key`.
    pub default_bucket: String,
    /// Optional default prefix — prepended to every relative key
    /// before the request is signed. Empty disables the rewrite.
    pub default_prefix: String,
    /// Trusted certificate PEM (one or more `-----BEGIN
    /// CERTIFICATE-----` blocks) added as an additional root for
    /// the reqwest client. `None` falls back to the system trust
    /// store. Mirrors the WebDAV transport's self-signed-endpoint
    /// surface.
    pub trusted_cert_pem: Option<String>,
    /// Last-resort `danger_accept_invalid_certs(true)` toggle. The
    /// dialog renders an explicit MITM warning before letting the
    /// user flip it on.
    pub insecure_skip_verify: bool,
}

// Hand-written so `{:?}` never prints the secret access key. The
// derived `Debug` would forward to `Zeroizing<String>`'s inner
// `String` and leak it into any log line / panic message that
// formats an `S3Config`. Mirrors `webdav::Credentials`'s redacting
// `Debug`.
impl std::fmt::Debug for S3Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("S3Config")
            .field("access_key_id", &self.access_key_id)
            .field("secret_access_key", &"<redacted>")
            .field("region", &self.region)
            .field("endpoint", &self.endpoint)
            .field("path_style", &self.path_style)
            .field("default_bucket", &self.default_bucket)
            .field("default_prefix", &self.default_prefix)
            .field("trusted_cert_pem", &self.trusted_cert_pem)
            .field("insecure_skip_verify", &self.insecure_skip_verify)
            .finish()
    }
}

/// Validate a bucket name against AWS S3 naming rules (RFC-grade
/// subset: lowercase, 3..=63 chars, ASCII letters/digits/hyphens,
/// no consecutive dots, no leading/trailing dot or hyphen, not
/// formatted as an IPv4 address). Returns the original error
/// message string AWS would surface from a 400 BadRequest so the
/// user sees the same wording regardless of whether the rejection
/// fired client-side or after a round-trip. Path-style endpoints
/// accept slightly relaxed rules (dots are fine, uppercase is
/// fine on MinIO) but the strict AWS rule set is the common
/// denominator that travels across every vendor — rejecting here
/// keeps every downstream signing / URL composition step from
/// emitting a malformed request the server has to debug.
///
/// The empty bucket is rejected up front because empty strings
/// would compose into `https://./host` (virtual-host) or
/// `<endpoint>//key` (path-style); both shapes produce confusing
/// remote errors.
pub fn validate_bucket_name(name: &str) -> Result<(), crate::error::Error> {
    if name.is_empty() {
        return Err(crate::error::Error::S3(
            "bucket name must not be empty".into(),
        ));
    }
    if name.len() < 3 || name.len() > 63 {
        return Err(crate::error::Error::S3(format!(
            "bucket name {name:?} must be 3..=63 characters"
        )));
    }
    let first = name.as_bytes()[0];
    let last = name.as_bytes()[name.len() - 1];
    if !first.is_ascii_lowercase() && !first.is_ascii_digit() {
        return Err(crate::error::Error::S3(format!(
            "bucket name {name:?} must start with a lowercase letter or digit"
        )));
    }
    if !last.is_ascii_lowercase() && !last.is_ascii_digit() {
        return Err(crate::error::Error::S3(format!(
            "bucket name {name:?} must end with a lowercase letter or digit"
        )));
    }
    for (i, b) in name.as_bytes().iter().enumerate() {
        let ok = b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'-' || *b == b'.';
        if !ok {
            return Err(crate::error::Error::S3(format!(
                "bucket name {name:?} has invalid character at position {i}"
            )));
        }
        if *b == b'.' && i + 1 < name.len() && name.as_bytes()[i + 1] == b'.' {
            return Err(crate::error::Error::S3(format!(
                "bucket name {name:?} must not contain consecutive dots"
            )));
        }
    }
    if name.parse::<std::net::Ipv4Addr>().is_ok() {
        return Err(crate::error::Error::S3(format!(
            "bucket name {name:?} must not be formatted as an IPv4 address"
        )));
    }
    Ok(())
}

impl S3Config {
    /// Resolve the base URL for a request against `bucket`.
    /// Returns the scheme+host (no trailing slash) plus the
    /// bucket-segment when path-style addressing is in effect.
    /// Virtual-host returns `https://<bucket>.<host>` without a
    /// bucket path segment.
    pub fn resolve_bucket_base(&self, bucket: &str) -> Result<String, crate::error::Error> {
        validate_bucket_name(bucket)?;
        let endpoint = self.resolve_endpoint();
        let url = url::Url::parse(&endpoint)
            .map_err(|e| crate::error::Error::S3(format!("invalid endpoint {endpoint}: {e}")))?;
        if self.path_style {
            // `<endpoint>/<bucket>` — caller appends `/<key>` on
            // top. Strip any trailing slash from `endpoint` so the
            // concat stays single-slash.
            let trimmed = endpoint.trim_end_matches('/');
            Ok(format!("{trimmed}/{bucket}"))
        } else {
            let scheme = url.scheme();
            let host = url
                .host_str()
                .ok_or_else(|| crate::error::Error::S3("endpoint has no host".into()))?;
            let port_seg = url.port().map(|p| format!(":{p}")).unwrap_or_default();
            Ok(format!("{scheme}://{bucket}.{host}{port_seg}"))
        }
    }

    /// Resolve the canonical endpoint URL. Empty config falls back
    /// to the AWS regional default.
    pub fn resolve_endpoint(&self) -> String {
        if !self.endpoint.is_empty() {
            return self.endpoint.clone();
        }
        // AWS legacy quirk: us-east-1 historically routed through
        // the bare `s3.amazonaws.com` host. Modern SDKs route every
        // region through the regional shape, so we mirror that.
        let region = if self.region.is_empty() {
            "us-east-1"
        } else {
            &self.region
        };
        format!("https://s3.{region}.amazonaws.com")
    }

    /// Resolve the SigV4 host header value for a request against
    /// `bucket`. Same shape as [`resolve_bucket_base`] but only
    /// the host component (no scheme, no port) — SigV4 puts the
    /// `host` header into the canonical request.
    pub fn resolve_host_header(&self, bucket: &str) -> Result<String, crate::error::Error> {
        validate_bucket_name(bucket)?;
        let endpoint = self.resolve_endpoint();
        let url = url::Url::parse(&endpoint)
            .map_err(|e| crate::error::Error::S3(format!("invalid endpoint {endpoint}: {e}")))?;
        let base_host = url
            .host_str()
            .ok_or_else(|| crate::error::Error::S3("endpoint has no host".into()))?;
        let port_seg = url.port().map(|p| format!(":{p}")).unwrap_or_default();
        if self.path_style {
            Ok(format!("{base_host}{port_seg}"))
        } else {
            Ok(format!("{bucket}.{base_host}{port_seg}"))
        }
    }
}
#[cfg(test)]
#[path = "../../tests/unit/s3_config.rs"]
mod tests;
