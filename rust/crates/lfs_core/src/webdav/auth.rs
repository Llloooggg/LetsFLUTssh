//! WebDAV authentication helpers.
//!
//! Three schemes the transport understands:
//!
//! - **Basic** (RFC 7617) — `Authorization: Basic <b64(user:pass)>`.
//!   Stamped on every request unconditionally. Fine over TLS;
//!   reckless over plain HTTP. The transport does not enforce
//!   the scheme; the URL the caller hands [`WebDavClient::new`]
//!   does.
//! - **Bearer** (RFC 6750) — `Authorization: Bearer <token>`.
//!   Used by Nextcloud / Box OAuth flows where the caller has
//!   already exchanged credentials for an opaque access token.
//! - **Digest** (RFC 7616) — challenge / response. The transport
//!   sends the request without an `Authorization` header first,
//!   reads `WWW-Authenticate: Digest …` from the 401 response,
//!   computes the MD5 hashes, retries once. The parsed challenge
//!   is cached inside the client so subsequent calls send the
//!   digest header up-front (saves one round-trip per call).
//!   Stale-nonce handling: when the server returns `stale=true`,
//!   the client re-parses the new challenge and retries.
//!
//! ## Why MD5
//!
//! RFC 7616 lists MD5 + SHA-256 + SHA-512/256 as algorithm
//! options. Real-world WebDAV servers (Apache mod_dav, nginx
//! ngx_http_auth_basic, IIS, Nextcloud's php-built-in) overwhelmingly
//! advertise `algorithm=MD5`. We support MD5 only — adding the
//! SHA variants when a server is found that requires them is
//! straightforward (`md-5` and `sha2` share the `Digest` trait
//! surface). MD5 is cryptographically broken for collision
//! resistance, but Digest auth uses it as a one-shot HMAC-style
//! mixer; the attack model is a network observer not a broken
//! hash. Real crypto in the rest of the app stays on the SHA-2
//! / AES-GCM / Argon2 stack.
//!
//! ## Plaintext discipline
//!
//! `Credentials.password_or_token` is wrapped in
//! [`Zeroizing<String>`] so the buffer scrubs on drop. The header
//! stamping path materialises the assembled `Basic <enc>` /
//! `Bearer <tok>` string only for the lifetime of the
//! `reqwest::RequestBuilder` call; the request object itself
//! holds the bytes inside `hyper`'s internal buffers, which we
//! do not control. That's the same trade-off [`crate::update::http`]
//! lives with — secrets cross into reqwest's hands once per
//! request and we cannot zero its copies.

use std::collections::HashMap;
use std::sync::Mutex;

use base64::Engine;
use md5::{Digest as _, Md5};
use zeroize::Zeroizing;

use crate::error::Error;

/// HTTP authentication scheme the server expects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthMethod {
    Basic,
    Digest,
    Bearer,
}

/// Caller-supplied credentials. `username` is `None` only when
/// `method == Bearer`; the password / token field carries the
/// secret in both other cases.
pub struct Credentials {
    pub method: AuthMethod,
    pub username: Option<String>,
    pub password_or_token: Zeroizing<String>,
}

impl std::fmt::Debug for Credentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never render the secret in Debug; the rest of the crate
        // logs `Credentials` via `{:?}` in tracing-style breadcrumbs.
        f.debug_struct("Credentials")
            .field("method", &self.method)
            .field("username", &self.username)
            .field("password_or_token", &"<redacted>")
            .finish()
    }
}

/// Render the `Authorization:` header value for a Basic /
/// Bearer scheme. Digest needs the response context (method +
/// URI + server challenge), so it lives on [`DigestState`].
pub fn header_value_basic_or_bearer(creds: &Credentials) -> Result<String, Error> {
    match creds.method {
        AuthMethod::Basic => {
            let user = creds.username.as_deref().unwrap_or("");
            let raw = format!("{user}:{}", &*creds.password_or_token);
            let enc = base64::engine::general_purpose::STANDARD.encode(raw.as_bytes());
            Ok(format!("Basic {enc}"))
        }
        AuthMethod::Bearer => Ok(format!("Bearer {}", &*creds.password_or_token)),
        AuthMethod::Digest => Err(Error::WebDav(
            "digest header needs challenge context".into(),
        )),
    }
}

/// Parsed `WWW-Authenticate: Digest …` challenge from a 401
/// response. Carries the fields the request hash needs plus
/// per-request bookkeeping (nonce-count) the client updates on
/// each retry.
#[derive(Debug, Clone)]
pub struct DigestChallenge {
    pub realm: String,
    pub nonce: String,
    pub qop: Option<String>,
    pub opaque: Option<String>,
    pub algorithm: String,
    pub stale: bool,
}

impl DigestChallenge {
    /// Parse a single `WWW-Authenticate` header value. Accepts
    /// only the `Digest` scheme; returns `None` otherwise so the
    /// caller can fall through to whatever default behaviour it
    /// has (typically: propagate the 401).
    pub fn parse(header_value: &str) -> Option<Self> {
        let trimmed = header_value.trim();
        let rest = trimmed
            .strip_prefix("Digest ")
            .or_else(|| trimmed.strip_prefix("digest "))?;
        let pairs = parse_auth_pairs(rest);
        Some(Self {
            realm: pairs.get("realm").cloned().unwrap_or_default(),
            nonce: pairs.get("nonce").cloned().unwrap_or_default(),
            qop: pairs.get("qop").cloned(),
            opaque: pairs.get("opaque").cloned(),
            algorithm: pairs
                .get("algorithm")
                .cloned()
                .unwrap_or_else(|| "MD5".into()),
            stale: pairs
                .get("stale")
                .map(|v| v.eq_ignore_ascii_case("true"))
                .unwrap_or(false),
        })
    }
}

/// Inline parser for the comma-separated `key=value` / `key="value"`
/// pairs in a `WWW-Authenticate: Digest` header. Tolerant of
/// optional whitespace and missing quoting on tokens that don't
/// need them (`algorithm=MD5`, `stale=true`, `qop=auth`).
fn parse_auth_pairs(input: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let bytes = input.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        // skip ws + leading commas
        while i < bytes.len() && (bytes[i] == b' ' || bytes[i] == b'\t' || bytes[i] == b',') {
            i += 1;
        }
        if i >= bytes.len() {
            break;
        }
        let key_start = i;
        while i < bytes.len() && bytes[i] != b'=' && bytes[i] != b',' {
            i += 1;
        }
        let key = input[key_start..i].trim().to_ascii_lowercase();
        if i >= bytes.len() || bytes[i] != b'=' {
            // bare key with no value — skip
            continue;
        }
        i += 1; // consume '='
                // quoted or token?
        let value = if i < bytes.len() && bytes[i] == b'"' {
            i += 1;
            let val_start = i;
            // accept escaped quotes per RFC 7235 quoted-string rules
            while i < bytes.len() {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    i += 2;
                    continue;
                }
                if bytes[i] == b'"' {
                    break;
                }
                i += 1;
            }
            let v = input[val_start..i].to_string();
            if i < bytes.len() {
                i += 1; // consume closing quote
            }
            v
        } else {
            let val_start = i;
            while i < bytes.len() && bytes[i] != b',' {
                i += 1;
            }
            input[val_start..i].trim().to_string()
        };
        if !key.is_empty() {
            out.insert(key, value);
        }
    }
    out
}

/// Per-client digest state. Holds the latest challenge so
/// subsequent requests stamp `Authorization` up-front; bumps the
/// nonce-count on each use so the server's replay defence (`nc=`
/// must monotonically increase per nonce) stays satisfied.
#[derive(Default, Debug)]
pub struct DigestState {
    inner: Mutex<Option<DigestStateInner>>,
}

#[derive(Debug)]
struct DigestStateInner {
    challenge: DigestChallenge,
    nc: u32,
}

impl DigestState {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(None),
        }
    }

    /// Store a fresh challenge (after parsing it from a 401) and
    /// reset the nonce-count. Called both on the first 401 and
    /// whenever the server returns `stale=true`.
    pub fn set_challenge(&self, challenge: DigestChallenge) {
        let mut g = self.inner.lock().expect("digest state mutex poisoned");
        *g = Some(DigestStateInner { challenge, nc: 0 });
    }

    /// Whether the state currently holds a challenge — drives
    /// the client's decision to stamp `Authorization` up-front vs.
    /// fire-and-handle-401.
    pub fn has_challenge(&self) -> bool {
        self.inner
            .lock()
            .expect("digest state mutex poisoned")
            .is_some()
    }

    /// Build the response header for `method` + `request_uri`
    /// using the cached challenge and `creds`. Returns `Err`
    /// when no challenge has been seen yet (the client is
    /// expected to fire one un-authenticated probe first).
    ///
    /// `cnonce` is required when the server advertised `qop`;
    /// callers pass a fresh random nonce per call.
    pub fn build_response(
        &self,
        creds: &Credentials,
        method: &str,
        request_uri: &str,
        cnonce: &str,
    ) -> Result<String, Error> {
        let mut g = self.inner.lock().expect("digest state mutex poisoned");
        let inner = g
            .as_mut()
            .ok_or_else(|| Error::WebDav("digest challenge not yet received".into()))?;
        inner.nc = inner.nc.checked_add(1).ok_or_else(|| {
            Error::WebDav("digest nonce-count overflow — re-auth required".into())
        })?;
        let user = creds.username.as_deref().unwrap_or("");
        let realm = &inner.challenge.realm;
        let nonce = &inner.challenge.nonce;
        let algo = inner.challenge.algorithm.to_ascii_uppercase();
        if algo != "MD5" {
            return Err(Error::WebDav(format!(
                "unsupported digest algorithm: {algo}"
            )));
        }
        let ha1 = md5_hex(&format!("{user}:{realm}:{}", &*creds.password_or_token));
        let ha2 = md5_hex(&format!("{method}:{request_uri}"));
        let nc_str = format!("{:08x}", inner.nc);
        let (response, qop_part) = if let Some(qop) = inner.challenge.qop.as_deref() {
            // qop may be a comma-separated list — prefer "auth"
            let chosen = qop
                .split(',')
                .map(|s| s.trim())
                .find(|s| s.eq_ignore_ascii_case("auth"))
                .unwrap_or("auth");
            let resp = md5_hex(&format!("{ha1}:{nonce}:{nc_str}:{cnonce}:{chosen}:{ha2}"));
            (
                resp,
                format!(", qop={chosen}, nc={nc_str}, cnonce=\"{cnonce}\""),
            )
        } else {
            (md5_hex(&format!("{ha1}:{nonce}:{ha2}")), String::new())
        };
        let opaque_part = inner
            .challenge
            .opaque
            .as_deref()
            .map(|o| format!(", opaque=\"{o}\""))
            .unwrap_or_default();
        let header = format!(
            "Digest username=\"{user}\", realm=\"{realm}\", \
             nonce=\"{nonce}\", uri=\"{request_uri}\", \
             algorithm={algo}, response=\"{response}\"{qop_part}{opaque_part}"
        );
        Ok(header)
    }
}

fn md5_hex(input: &str) -> String {
    let mut h = Md5::new();
    h.update(input.as_bytes());
    let out = h.finalize();
    let mut s = String::with_capacity(out.len() * 2);
    use std::fmt::Write as _;
    for b in out.iter() {
        let _ = write!(s, "{b:02x}");
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_header_matches_b64_user_colon_pass() {
        let creds = Credentials {
            method: AuthMethod::Basic,
            username: Some("Aladdin".into()),
            password_or_token: Zeroizing::new("open sesame".into()),
        };
        // RFC 7617 reference value.
        assert_eq!(
            header_value_basic_or_bearer(&creds).unwrap(),
            "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
        );
    }

    #[test]
    fn basic_header_empty_username_renders_colon_pass() {
        let creds = Credentials {
            method: AuthMethod::Basic,
            username: None,
            password_or_token: Zeroizing::new("t0p".into()),
        };
        // base64(":t0p")
        assert_eq!(
            header_value_basic_or_bearer(&creds).unwrap(),
            "Basic OnQwcA=="
        );
    }

    #[test]
    fn bearer_header_pass_through_token() {
        let creds = Credentials {
            method: AuthMethod::Bearer,
            username: None,
            password_or_token: Zeroizing::new("opaque-token-xyz".into()),
        };
        assert_eq!(
            header_value_basic_or_bearer(&creds).unwrap(),
            "Bearer opaque-token-xyz"
        );
    }

    #[test]
    fn digest_method_rejects_basic_helper() {
        let creds = Credentials {
            method: AuthMethod::Digest,
            username: Some("u".into()),
            password_or_token: Zeroizing::new("p".into()),
        };
        assert!(header_value_basic_or_bearer(&creds).is_err());
    }

    #[test]
    fn parse_challenge_rejects_non_digest_scheme() {
        assert!(DigestChallenge::parse("Basic realm=\"x\"").is_none());
        assert!(DigestChallenge::parse("Bearer token=\"x\"").is_none());
    }

    #[test]
    fn parse_challenge_extracts_quoted_and_token_fields() {
        let ch = DigestChallenge::parse(
            "Digest realm=\"testrealm@host.com\", \
             qop=\"auth,auth-int\", \
             nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\", \
             opaque=\"5ccc069c403ebaf9f0171e9517f40e41\", \
             algorithm=MD5, stale=false",
        )
        .unwrap();
        assert_eq!(ch.realm, "testrealm@host.com");
        assert_eq!(ch.qop.as_deref(), Some("auth,auth-int"));
        assert_eq!(ch.nonce, "dcd98b7102dd2f0e8b11d0f600bfb0c093");
        assert_eq!(
            ch.opaque.as_deref(),
            Some("5ccc069c403ebaf9f0171e9517f40e41")
        );
        assert_eq!(ch.algorithm, "MD5");
        assert!(!ch.stale);
    }

    #[test]
    fn parse_challenge_picks_up_stale_true() {
        let ch = DigestChallenge::parse("Digest realm=\"r\", nonce=\"n\", stale=true").unwrap();
        assert!(ch.stale);
    }

    #[test]
    fn digest_response_matches_rfc7616_known_vector() {
        // RFC 7616 §3.9.1 worked example, MD5 algorithm + qop=auth.
        // Username "Mufasa", password "Circle of Life", realm
        // "http-auth@example.org", nonce "7ypf/xlj9XXwfDPEoM4URrv/xwf...",
        // cnonce "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ",
        // method GET, uri /dir/index.html, qop=auth, nc=00000001.
        //
        // Expected response = 8ca523f5e9506fed4657c9700eebdbec
        let state = DigestState::new();
        state.set_challenge(DigestChallenge {
            realm: "http-auth@example.org".into(),
            nonce: "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v".into(),
            qop: Some("auth".into()),
            opaque: Some("FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS".into()),
            algorithm: "MD5".into(),
            stale: false,
        });
        let creds = Credentials {
            method: AuthMethod::Digest,
            username: Some("Mufasa".into()),
            password_or_token: Zeroizing::new("Circle of Life".into()),
        };
        let header = state
            .build_response(
                &creds,
                "GET",
                "/dir/index.html",
                "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ",
            )
            .unwrap();
        assert!(
            header.contains("response=\"8ca523f5e9506fed4657c9700eebdbec\""),
            "header did not contain expected MD5 response: {header}"
        );
        assert!(header.contains("nc=00000001"));
    }

    #[test]
    fn digest_response_without_qop_falls_back_to_legacy_format() {
        // RFC 2069 fall-through path — qop absent.
        let state = DigestState::new();
        state.set_challenge(DigestChallenge {
            realm: "realm".into(),
            nonce: "abc".into(),
            qop: None,
            opaque: None,
            algorithm: "MD5".into(),
            stale: false,
        });
        let creds = Credentials {
            method: AuthMethod::Digest,
            username: Some("u".into()),
            password_or_token: Zeroizing::new("p".into()),
        };
        let header = state
            .build_response(&creds, "GET", "/x", "ignored-without-qop")
            .unwrap();
        // No qop / nc / cnonce parameters when challenge omitted qop.
        assert!(!header.contains("qop="));
        assert!(!header.contains("nc="));
        assert!(header.contains("response="));
    }

    #[test]
    fn digest_response_rejects_unsupported_algorithm() {
        let state = DigestState::new();
        state.set_challenge(DigestChallenge {
            realm: "r".into(),
            nonce: "n".into(),
            qop: None,
            opaque: None,
            algorithm: "SHA-256".into(),
            stale: false,
        });
        let creds = Credentials {
            method: AuthMethod::Digest,
            username: Some("u".into()),
            password_or_token: Zeroizing::new("p".into()),
        };
        let err = state.build_response(&creds, "GET", "/", "c").unwrap_err();
        assert!(err.to_string().contains("unsupported digest algorithm"));
    }

    #[test]
    fn digest_response_errors_when_no_challenge_seen() {
        let state = DigestState::new();
        let creds = Credentials {
            method: AuthMethod::Digest,
            username: Some("u".into()),
            password_or_token: Zeroizing::new("p".into()),
        };
        let err = state.build_response(&creds, "GET", "/", "c").unwrap_err();
        assert!(err.to_string().contains("digest challenge"));
    }
}
