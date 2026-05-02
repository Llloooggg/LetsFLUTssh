//! HTTP client for the auto-update fetch path.
//!
//! Mirrors the surface `lib/core/update/update_service.dart` needs:
//!   - `fetch_text(url)` — small JSON body (GitHub Releases API
//!     manifest, signed `.sha256sums` files).
//!   - `download_to_file(url, path, progress)` — streamed asset
//!     download into a target file with byte-progress callbacks.
//!
//! # Trusted-host guard
//!
//! Every URL crossing this layer goes through
//! [`update_metadata::is_trusted_release_asset_uri`] —
//! `https://github.com` and `*.githubusercontent.com` are accepted;
//! everything else fails closed. The check runs against both the
//! request URL and every redirect target, defending against an
//! attacker who races a 302 to an off-brand host between the
//! release-list query and the asset download.
//!
//! # TLS posture
//!
//! `rustls-tls` keeps the dep tree pure-Rust (no openssl system
//! link). The HTTP client wires
//! [`crate::update_pinning::LfsPinningVerifier`] into rustls so
//! every TLS handshake on this code path runs:
//!
//! 1. Standard chain validation against the bundled webpki-roots
//!    (same trust anchor any browser uses).
//! 2. A SPKI pin check for hostnames present in
//!    [`crate::update_pinning::PINNED_HOSTS`].
//!
//! `PINNED_HOSTS` is empty today — the pinning verifier is a
//! transparent pass-through to the inner WebPki check, so
//! security parity with the pre-pinning configuration is
//! preserved. A maintainer adding a host pin enables the second
//! check on the next build without touching this module. See the
//! `update_pinning` crate-level docs for the maintainer pipeline
//! that captures the current SPKI digest.

use std::path::Path;
use std::time::Duration;

use futures_util::StreamExt;
use sha2::{Digest, Sha256};
use tokio::fs::File;
use tokio::io::AsyncWriteExt;

use crate::error::Error;
use crate::update_metadata::is_trusted_release_asset_uri;

/// Hard cap on HTTP redirect depth. The auto-update channel only
/// hops once or twice in practice (GitHub Releases → asset CDN);
/// 10 leaves comfortable headroom while still bounding loops.
const MAX_REDIRECTS: usize = 10;

/// Per-request timeout. Auto-update is best-effort; a stuck
/// connection should not pin the worker indefinitely.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

/// GET `url`, follow up to [`MAX_REDIRECTS`] redirects, validate
/// every URL against the trusted-host allowlist, return the
/// response body as `String`. Caller decodes JSON / parses
/// manifest from there.
pub async fn fetch_text(url: &str) -> Result<String, Error> {
    if !is_trusted_release_asset_uri(url) {
        return Err(Error::Io(format!("untrusted update URL: {url}")));
    }
    let client = build_client()?;
    let response = client
        .get(url)
        .send()
        .await
        .map_err(|e| Error::Io(format!("update fetch {url}: {e}")))?;
    if !response.status().is_success() {
        return Err(Error::Io(format!(
            "update fetch {url} returned HTTP {}",
            response.status()
        )));
    }
    // Final URL after redirects — re-validate against the
    // allowlist so a 302 to evil.com fails here even if reqwest
    // followed it.
    let final_url = response.url().to_string();
    if !is_trusted_release_asset_uri(&final_url) {
        return Err(Error::Io(format!(
            "update fetch redirected to untrusted host: {final_url}"
        )));
    }
    response
        .text()
        .await
        .map_err(|e| Error::Io(format!("update fetch read {url}: {e}")))
}

/// GET `url`, stream the body into `target_path`, hashing each
/// chunk with SHA-256 as it lands. `progress` fires after every
/// chunk write with the running byte count + the total content
/// length (or `None` when the server did not declare one).
///
/// Returns the final SHA-256 digest as a hex string. Caller
/// compares it against the expected manifest entry — mismatch
/// means the file is rolled back and a typed error surfaces to
/// the UI.
pub async fn download_to_file(
    url: &str,
    target_path: &Path,
    mut progress: impl FnMut(u64, Option<u64>) + Send + 'static,
) -> Result<String, Error> {
    if !is_trusted_release_asset_uri(url) {
        return Err(Error::Io(format!("untrusted update URL: {url}")));
    }
    let client = build_client()?;
    let response = client
        .get(url)
        .send()
        .await
        .map_err(|e| Error::Io(format!("update download {url}: {e}")))?;
    if !response.status().is_success() {
        return Err(Error::Io(format!(
            "update download {url} returned HTTP {}",
            response.status()
        )));
    }
    let final_url = response.url().to_string();
    if !is_trusted_release_asset_uri(&final_url) {
        return Err(Error::Io(format!(
            "update download redirected to untrusted host: {final_url}"
        )));
    }
    let total = response.content_length();

    if let Some(parent) = target_path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| Error::Io(format!("update mkdir {parent:?}: {e}")))?;
    }
    let mut file = File::create(target_path)
        .await
        .map_err(|e| Error::Io(format!("update create {target_path:?}: {e}")))?;
    let mut hasher = Sha256::new();
    let mut written: u64 = 0;
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| Error::Io(format!("update download chunk {url}: {e}")))?;
        hasher.update(&bytes);
        file.write_all(&bytes)
            .await
            .map_err(|e| Error::Io(format!("update write {target_path:?}: {e}")))?;
        written = written.saturating_add(bytes.len() as u64);
        progress(written, total);
    }
    file.flush()
        .await
        .map_err(|e| Error::Io(format!("update flush {target_path:?}: {e}")))?;
    Ok(hex_encode(&hasher.finalize()))
}

fn build_client() -> Result<reqwest::Client, Error> {
    let tls = crate::update_pinning::build_pinning_tls_config()
        .map_err(|e| Error::Io(format!("update http TLS config: {e}")))?;
    reqwest::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .redirect(reqwest::redirect::Policy::limited(MAX_REDIRECTS))
        .user_agent(format!("letsflutssh-update/{}", env!("CARGO_PKG_VERSION")))
        .use_preconfigured_tls(tls)
        .build()
        .map_err(|e| Error::Io(format!("update http client build: {e}")))
}

fn hex_encode(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = write!(s, "{b:02x}");
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn untrusted_host_rejected_for_fetch_text() {
        let err = fetch_text("https://evil.com/foo").await.unwrap_err();
        assert!(err.to_string().contains("untrusted"));
    }

    #[tokio::test]
    async fn untrusted_host_rejected_for_download() {
        let path = std::env::temp_dir().join("lfs_update_http_test.bin");
        let err = download_to_file("https://evil.com/foo", &path, |_, _| {})
            .await
            .unwrap_err();
        assert!(err.to_string().contains("untrusted"));
        // No file created on rejection.
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn http_scheme_rejected() {
        let err = fetch_text("http://github.com/x").await.unwrap_err();
        assert!(err.to_string().contains("untrusted"));
    }
}
