//! End-to-end TLS handshake coverage for the trusted-cert-pin and
//! accept-any-cert paths through `WebDavClient::new`.
//!
//! The constructor-level tests in `webdav::client` only exercise the
//! reqwest builder shape — they do not drive a real TLS handshake.
//! This file plugs that gap: it spins up a loopback `tokio-rustls`
//! TCP listener with a freshly-generated self-signed certificate,
//! then runs the WebDAV client against `https://127.0.0.1:<port>/`
//! through three configurations the dialog can produce:
//!
//!   1. **Plain** — no pin, no insecure. System trust store rejects
//!      the self-signed cert; the connect probe must fail.
//!   2. **Trusted-cert PEM** — pinned cert added as an additional
//!      root CA. Connect probe must succeed.
//!   3. **Insecure skip-verify** — every cert / hostname check
//!      turned off. Connect probe must succeed regardless of the
//!      pin.
//!
//! The listener serves one MULTISTATUS XML response and shuts
//! down. Each scenario uses a fresh listener (and ephemeral port)
//! so parallel `cargo test` runs do not collide.

use std::sync::Arc;

use lfs_core::webdav::auth::{AuthMethod, Credentials};
use lfs_core::webdav::client::WebDavClient;
use rcgen::CertifiedKey;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio_rustls::rustls::crypto::CryptoProvider;
use tokio_rustls::rustls::pki_types::pem::PemObject;
use tokio_rustls::rustls::pki_types::{CertificateDer, PrivateKeyDer};
use tokio_rustls::rustls::ServerConfig;
use tokio_rustls::TlsAcceptor;
use zeroize::Zeroizing;

/// Minimal multistatus body the WebDAV client's `propfind("", 0)`
/// happily consumes. The dialog calls the propfind as a connect
/// probe — the body content is irrelevant for the TLS-path tests
/// as long as the response parses.
const MULTISTATUS_BODY: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>"#;

/// Generate a fresh self-signed certificate covering `127.0.0.1`.
/// Returns `(cert_pem, key_pem)` — the cert flows into the WebDAV
/// client's `trusted_cert_pem` arg, the key configures the test
/// listener.
fn make_self_signed_cert() -> (String, String) {
    let CertifiedKey { cert, key_pair } =
        rcgen::generate_simple_self_signed(vec!["127.0.0.1".to_string()])
            .expect("rcgen self-signed");
    (cert.pem(), key_pair.serialize_pem())
}

/// Install the rustls AWS-LC crypto provider exactly once for the
/// test process. `tokio-rustls` 0.26 dropped the per-feature
/// CryptoProvider default — every test that builds a rustls
/// `ServerConfig` has to opt in. The double-install no-ops after
/// the first call so parallel test threads stay safe.
fn ensure_crypto_provider_installed() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let _ = CryptoProvider::install_default(
            tokio_rustls::rustls::crypto::aws_lc_rs::default_provider(),
        );
    });
}

/// Build a rustls `ServerConfig` from the PEM cert + key pair.
/// Mirrors what an HTTPS server bootstrap step would do — single
/// cert, no chain, ALPN left default.
fn server_config_from_pem(cert_pem: &str, key_pem: &str) -> Arc<ServerConfig> {
    ensure_crypto_provider_installed();
    let cert_chain: Vec<CertificateDer<'static>> =
        CertificateDer::pem_slice_iter(cert_pem.as_bytes())
            .collect::<Result<_, _>>()
            .expect("parse server cert");
    let key = PrivateKeyDer::from_pem_slice(key_pem.as_bytes()).expect("parse server key");
    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(cert_chain, key)
        .expect("rustls ServerConfig");
    Arc::new(config)
}

/// Spawn a one-shot TLS listener that:
///   1. Binds to `127.0.0.1:0` (ephemeral port).
///   2. Returns the chosen port to the caller.
///   3. Accepts exactly ONE connection, completes the TLS handshake,
///      reads the request bytes until it sees the blank `\r\n\r\n`
///      separator (no body parsing — the response is unconditional),
///      writes a `207 Multi-Status` response with [`MULTISTATUS_BODY`].
///
/// The listener future returns once the response flushes; the
/// caller can drop the join handle without affecting the test
/// outcome (the response already landed on the wire).
async fn spawn_one_shot_tls_server(server_config: Arc<ServerConfig>) -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind loopback");
    let port = listener.local_addr().unwrap().port();
    let acceptor = TlsAcceptor::from(server_config);
    tokio::spawn(async move {
        let (stream, _) = match listener.accept().await {
            Ok(v) => v,
            Err(_) => return,
        };
        let mut tls = match acceptor.accept(stream).await {
            Ok(v) => v,
            Err(_) => return,
        };
        // Drain the request until end of headers — `propfind` sends a
        // small body, but the response does not depend on it so we
        // skip parsing and just read until the request stops coming.
        let mut buf = [0u8; 1024];
        loop {
            match tls.read(&mut buf).await {
                Ok(0) => break,
                Ok(_) => {
                    if buf.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                Err(_) => return,
            }
        }
        let response = format!(
            "HTTP/1.1 207 Multi-Status\r\nContent-Type: application/xml; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            MULTISTATUS_BODY.len(),
            MULTISTATUS_BODY
        );
        let _ = tls.write_all(response.as_bytes()).await;
        let _ = tls.shutdown().await;
    });
    port
}

fn basic_creds() -> Credentials {
    Credentials {
        method: AuthMethod::Basic,
        username: Some("alice".to_string()),
        password_or_token: Zeroizing::new("p".to_string()),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn webdav_tls_plain_rejects_self_signed_cert() {
    // Sanity check: the same self-signed cert that the pin/insecure
    // paths happily accept must be rejected by the plain client
    // path. Without this assertion the other two tests degenerate
    // into "any TLS connect works" — which would also pass if the
    // pin / insecure flags were completely no-ops.
    let (cert_pem, key_pem) = make_self_signed_cert();
    let port = spawn_one_shot_tls_server(server_config_from_pem(&cert_pem, &key_pem)).await;
    let base = format!("https://127.0.0.1:{port}/");
    let client = WebDavClient::new(&base, basic_creds(), None, false).expect("build");
    let res = client.propfind("", 0).await;
    assert!(
        res.is_err(),
        "plain client must reject the self-signed cert; got Ok"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn webdav_tls_trusted_cert_pin_accepts_pinned_self_signed() {
    let (cert_pem, key_pem) = make_self_signed_cert();
    let port = spawn_one_shot_tls_server(server_config_from_pem(&cert_pem, &key_pem)).await;
    let base = format!("https://127.0.0.1:{port}/");
    let client = WebDavClient::new(&base, basic_creds(), Some(&cert_pem), false).expect("build");
    let res = client.propfind("", 0).await;
    assert!(
        res.is_ok(),
        "trusted-cert pin must accept the matching self-signed cert; got {res:?}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn webdav_tls_insecure_skip_verify_accepts_any_cert() {
    let (cert_pem, key_pem) = make_self_signed_cert();
    let port = spawn_one_shot_tls_server(server_config_from_pem(&cert_pem, &key_pem)).await;
    let base = format!("https://127.0.0.1:{port}/");
    // No cert pin — relies entirely on the insecure flag.
    let client = WebDavClient::new(&base, basic_creds(), None, true).expect("build");
    let res = client.propfind("", 0).await;
    assert!(
        res.is_ok(),
        "insecure-skip-verify must accept the self-signed cert; got {res:?}"
    );
}
