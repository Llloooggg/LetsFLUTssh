//! Raw WebDAV transport — shared between the sync orchestrator
//! and the WebDAV file-browser `storage::Provider` impl.
//!
//! WebDAV is the smallest cross-platform protocol that gives the
//! app a remote file store the user already trusts (Nextcloud,
//! ownCloud, Apache mod_dav, nginx, IIS, Synology DSM, Box,
//! Yandex.Disk). The transport sits at the same layer as
//! [`crate::ssh`] / [`crate::sftp`]: typed wrappers around
//! `reqwest` for the six verbs the rest of the stack needs
//! ([`WebDavClient::propfind`], [`WebDavClient::get`],
//! [`WebDavClient::put`], [`WebDavClient::delete`],
//! [`WebDavClient::mkcol`], [`WebDavClient::move_resource`]),
//! pluggable [`AuthMethod`] (basic / digest / bearer), and a
//! multistatus XML parser ([`parser::parse_propfind`]) that
//! covers the namespace / element-ordering variants every
//! mainstream server emits.
//!
//! ## Module surface
//!
//! - [`client`] — [`WebDavClient`], the public verb surface.
//! - [`auth`] — [`AuthMethod`] / [`Credentials`] + the helper that
//!   stamps the right `Authorization:` header on each request.
//! - [`parser`] — multistatus XML reader ([`PropfindEntry`],
//!   [`MultistatusError`], [`parse_propfind`]).
//!
//! ## What lives here vs. above
//!
//! This module is transport-only — credentials in, requests out,
//! parsed entries back. It does not know about sync orchestration
//! state, conflict resolution, the encrypted `.lfs` archive
//! format, or the `storage::Provider` trait. The sync state
//! machine and the `storage::Provider` adapter are sibling
//! modules that import [`WebDavClient`]; both depend on the same
//! transport surface so a bug fix in PROPFIND parsing helps both
//! call sites in one place.
//!
//! ## TLS posture
//!
//! Same posture as [`crate::update_http`]: `reqwest` with
//! `rustls-tls` (pure-Rust, no openssl link), standard chain
//! validation against the bundled webpki-roots. Self-signed-cert
//! TOFU pinning lives outside this module — when it lands, the
//! caller will hand the client a pre-configured `reqwest::Client`
//! instead of letting `WebDavClient::new` build one. The current
//! constructor takes the default client for the same reason
//! [`crate::update_http`] does: the update channel and the sync
//! channel both rely on standard CA validation today.

pub mod auth;
pub mod client;
pub mod parser;

pub use auth::{AuthMethod, Credentials};
pub use client::{PutOutcome, WebDavClient};
pub use parser::{parse_propfind, MultistatusError, PropfindEntry};
