//! S3-compatible transport.
//!
//! Speaks the AWS REST surface every S3-compatible vendor implements
//! (AWS S3 itself, MinIO, Wasabi, Backblaze B2-S3, Cloudflare R2,
//! DigitalOcean Spaces, Scaleway Object Storage). Sits at the same
//! layer as [`crate::ssh`] / [`crate::sftp`] / [`crate::webdav`]:
//! typed wrappers around `reqwest` for the verbs the rest of the
//! stack needs, an inline AWS Signature V4 signer, and a multipart
//! upload orchestrator.
//!
//! ## Module surface
//!
//! - [`client`] — [`S3Client`], the public verb surface (list /
//!   head / get / put / delete / copy + multipart helpers +
//!   presigned URL signing).
//! - [`config`] — [`S3Config`], the per-session credential +
//!   addressing tuple the client consumes.
//! - [`signer`] — AWS SigV4 implementation. Reused by [`client`]
//!   on every request and by the presigned-URL helper for
//!   time-limited downloads.
//! - [`multipart`] — multipart-upload orchestration: Initiate →
//!   `UploadPart` loop → Complete (with abort on error).
//!
//! ## What lives here vs. above
//!
//! This module is transport-only — credentials in, requests out,
//! parsed entries back. It does not know about session storage,
//! the encrypted `.lfs` archive format, or the `storage::Provider`
//! trait. The provider adapter (`crate::storage::s3::S3Provider`)
//! imports [`S3Client`] from here.
//!
//! ## Why an inline SigV4 signer (not aws-sigv4)
//!
//! The upstream `aws-sigv4` crate transitively pulls the
//! `aws-smithy-*` runtime tree (~25 crates, several MiB compiled),
//! which dwarfs every other dep we own. SigV4 itself is a tight
//! algorithm with a clear test-vector set; the implementation
//! below fits in one file, depends only on crates already in the
//! tree (`hmac`, `sha2`), and stays under-test through the
//! published AWS test vectors. Tracked under `crate::s3::signer`
//! tests.
//!
//! ## TLS posture
//!
//! Same posture as [`crate::webdav`] / [`crate::update_http`]:
//! `reqwest` with `rustls-tls` (pure-Rust, no openssl link),
//! standard chain validation against the bundled webpki-roots.

pub mod client;
pub mod config;
pub mod multipart;
pub mod signer;

pub use client::{S3Client, S3ObjectMetadata, S3ObjectPage};
pub use config::S3Config;

/// Server-address projection (host + port) for an S3 session
/// derived from the user-typed endpoint URL. When `endpoint` is
/// empty the host falls back to `s3.<region>.amazonaws.com` —
/// the canonical AWS endpoint for the picked region (`us-east-1`
/// when `region` is empty). Port defaults to 443; an `http://`
/// endpoint with no explicit port maps to 80; an explicit
/// `:port` always wins.
///
/// The same `ServerAddressFields` shape WebDAV uses keeps the
/// session-edit dialog's two endpoint paths uniform Rust-side.
pub fn server_address_from_s3_endpoint(
    endpoint: &str,
    region: &str,
) -> crate::webdav::ServerAddressFields {
    let trimmed = endpoint.trim();
    if trimmed.is_empty() {
        let r = region.trim();
        let region_label = if r.is_empty() { "us-east-1" } else { r };
        return crate::webdav::ServerAddressFields {
            host: format!("s3.{region_label}.amazonaws.com"),
            port: 443,
        };
    }
    let parsed = match url::Url::parse(trimmed) {
        Ok(u) => u,
        Err(_) => {
            return crate::webdav::ServerAddressFields {
                host: String::new(),
                port: 443,
            };
        }
    };
    let host = parsed.host_str().unwrap_or("").to_string();
    let port = if let Some(p) = parsed.port() {
        u32::from(p)
    } else if parsed.scheme().eq_ignore_ascii_case("http") {
        80
    } else {
        443
    };
    crate::webdav::ServerAddressFields { host, port }
}

#[cfg(test)]
mod server_address_tests {
    use super::*;

    #[test]
    fn empty_endpoint_falls_back_to_aws_region_host() {
        let r = server_address_from_s3_endpoint("", "eu-west-1");
        assert_eq!(r.host, "s3.eu-west-1.amazonaws.com");
        assert_eq!(r.port, 443);
    }

    #[test]
    fn empty_endpoint_empty_region_defaults_us_east_1() {
        let r = server_address_from_s3_endpoint("", "");
        assert_eq!(r.host, "s3.us-east-1.amazonaws.com");
    }

    #[test]
    fn https_endpoint_defaults_443() {
        let r = server_address_from_s3_endpoint("https://minio.local", "");
        assert_eq!(r.host, "minio.local");
        assert_eq!(r.port, 443);
    }

    #[test]
    fn http_endpoint_defaults_80() {
        let r = server_address_from_s3_endpoint("http://minio.local", "");
        assert_eq!(r.host, "minio.local");
        assert_eq!(r.port, 80);
    }

    #[test]
    fn explicit_port_wins() {
        let r = server_address_from_s3_endpoint("https://minio.local:9000", "");
        assert_eq!(r.port, 9000);
    }
}
