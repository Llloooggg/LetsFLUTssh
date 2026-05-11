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
