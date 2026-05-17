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

/// Server-address projection (host + port) for a WebDAV session
/// derived from the user-typed base URL. The Dart session-edit
/// dialog feeds the result into the legacy `sessions.host` /
/// `.port` columns so SQL filters keyed on those stay working;
/// the live transport reads the full URL from
/// `webdav_session_details`.
///
/// Port resolution: explicit `:port` wins; otherwise scheme
/// default (`https` → 443, `http` → 80); else `0`.
///
/// `base_url` may be empty / malformed — the validator catches
/// that ahead of save. This helper returns an empty host / port
/// `0` so a benign code path (live preview, debug log) degrades
/// gracefully.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerAddressFields {
    pub host: String,
    pub port: u32,
}

pub fn server_address_from_base_url(base_url: &str) -> ServerAddressFields {
    let trimmed = base_url.trim();
    if trimmed.is_empty() {
        return ServerAddressFields {
            host: String::new(),
            port: 0,
        };
    }
    let parsed = match url::Url::parse(trimmed) {
        Ok(u) => u,
        Err(_) => {
            return ServerAddressFields {
                host: String::new(),
                port: 0,
            };
        }
    };
    let host = parsed.host_str().unwrap_or("").to_string();
    let port = if let Some(p) = parsed.port() {
        u32::from(p)
    } else {
        match parsed.scheme().to_ascii_lowercase().as_str() {
            "https" => 443,
            "http" => 80,
            _ => 0,
        }
    };
    ServerAddressFields { host, port }
}

#[cfg(test)]
mod server_address_tests {
    use super::*;

    #[test]
    fn empty_url_yields_empty_host_zero_port() {
        let r = server_address_from_base_url("");
        assert_eq!(r.host, "");
        assert_eq!(r.port, 0);
    }

    #[test]
    fn malformed_url_yields_empty_host_zero_port() {
        let r = server_address_from_base_url("not a url");
        assert_eq!(r.host, "");
        assert_eq!(r.port, 0);
    }

    #[test]
    fn https_default_port_443() {
        let r = server_address_from_base_url("https://dav.example.com/remote.php");
        assert_eq!(r.host, "dav.example.com");
        assert_eq!(r.port, 443);
    }

    #[test]
    fn http_default_port_80() {
        let r = server_address_from_base_url("http://dav.example.com/dav");
        assert_eq!(r.host, "dav.example.com");
        assert_eq!(r.port, 80);
    }

    #[test]
    fn explicit_port_wins() {
        let r = server_address_from_base_url("https://dav.example.com:8443/dav");
        assert_eq!(r.host, "dav.example.com");
        assert_eq!(r.port, 8443);
    }
}
