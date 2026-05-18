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
#[derive(Debug, Clone)]
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
mod tests {
    use super::*;

    fn cfg(region: &str, endpoint: &str, path_style: bool) -> S3Config {
        S3Config {
            access_key_id: "AKID".into(),
            secret_access_key: Zeroizing::new("SK".into()),
            region: region.into(),
            endpoint: endpoint.into(),
            path_style,
            default_bucket: "".into(),
            default_prefix: "".into(),
            trusted_cert_pem: None,
            insecure_skip_verify: false,
        }
    }

    #[test]
    fn resolve_endpoint_aws_default_uses_regional_shape() {
        let c = cfg("eu-west-2", "", false);
        assert_eq!(c.resolve_endpoint(), "https://s3.eu-west-2.amazonaws.com");
    }

    #[test]
    fn resolve_endpoint_aws_default_us_east_1_when_region_empty() {
        // Empty region falls back to us-east-1, matching modern
        // AWS SDK default behaviour.
        let c = cfg("", "", false);
        assert_eq!(c.resolve_endpoint(), "https://s3.us-east-1.amazonaws.com");
    }

    #[test]
    fn resolve_endpoint_uses_explicit_endpoint_when_set() {
        let c = cfg("auto", "https://minio.local:9000", true);
        assert_eq!(c.resolve_endpoint(), "https://minio.local:9000");
    }

    #[test]
    fn resolve_bucket_base_path_style_appends_bucket_to_endpoint() {
        let c = cfg("auto", "https://minio.local:9000", true);
        assert_eq!(
            c.resolve_bucket_base("my-bucket").unwrap(),
            "https://minio.local:9000/my-bucket"
        );
    }

    #[test]
    fn resolve_bucket_base_virtual_host_prepends_bucket_to_host() {
        let c = cfg("us-east-1", "", false);
        assert_eq!(
            c.resolve_bucket_base("logs").unwrap(),
            "https://logs.s3.us-east-1.amazonaws.com"
        );
    }

    #[test]
    fn resolve_host_header_path_style_drops_bucket() {
        let c = cfg("auto", "https://minio.local:9000", true);
        assert_eq!(c.resolve_host_header("buc").unwrap(), "minio.local:9000");
    }

    #[test]
    fn resolve_host_header_virtual_host_prepends_bucket() {
        let c = cfg("us-east-1", "", false);
        assert_eq!(
            c.resolve_host_header("buc").unwrap(),
            "buc.s3.us-east-1.amazonaws.com"
        );
    }

    #[test]
    fn validate_bucket_name_accepts_aws_canonical_shapes() {
        assert!(validate_bucket_name("logs").is_ok());
        assert!(validate_bucket_name("my-bucket").is_ok());
        assert!(validate_bucket_name("123abc").is_ok());
        assert!(validate_bucket_name("a-b.c-d").is_ok());
        assert!(validate_bucket_name(&"a".repeat(63)).is_ok());
    }

    #[test]
    fn validate_bucket_name_rejects_length_violations() {
        assert!(validate_bucket_name("").is_err());
        assert!(validate_bucket_name("ab").is_err());
        assert!(validate_bucket_name(&"a".repeat(64)).is_err());
    }

    #[test]
    fn validate_bucket_name_rejects_invalid_characters() {
        assert!(validate_bucket_name("My-Bucket").is_err()); // uppercase
        assert!(validate_bucket_name("my_bucket").is_err()); // underscore
        assert!(validate_bucket_name("-bucket").is_err()); // leading hyphen
        assert!(validate_bucket_name("bucket-").is_err()); // trailing hyphen
        assert!(validate_bucket_name(".bucket").is_err()); // leading dot
        assert!(validate_bucket_name("bucket.").is_err()); // trailing dot
        assert!(validate_bucket_name("my..bucket").is_err()); // consecutive dots
        assert!(validate_bucket_name("my bucket").is_err()); // space
    }

    #[test]
    fn validate_bucket_name_rejects_ipv4_format() {
        assert!(validate_bucket_name("192.168.1.1").is_err());
    }

    #[test]
    fn resolve_bucket_base_rejects_invalid_bucket() {
        let c = cfg("us-east-1", "", false);
        assert!(c.resolve_bucket_base("My-Bucket").is_err());
        assert!(c.resolve_bucket_base("").is_err());
    }
}
