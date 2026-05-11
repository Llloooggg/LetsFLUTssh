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
}

impl S3Config {
    /// Resolve the base URL for a request against `bucket`.
    /// Returns the scheme+host (no trailing slash) plus the
    /// bucket-segment when path-style addressing is in effect.
    /// Virtual-host returns `https://<bucket>.<host>` without a
    /// bucket path segment.
    pub fn resolve_bucket_base(&self, bucket: &str) -> Result<String, crate::error::Error> {
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
        assert_eq!(c.resolve_host_header("b").unwrap(), "minio.local:9000");
    }

    #[test]
    fn resolve_host_header_virtual_host_prepends_bucket() {
        let c = cfg("us-east-1", "", false);
        assert_eq!(
            c.resolve_host_header("b").unwrap(),
            "b.s3.us-east-1.amazonaws.com"
        );
    }
}
