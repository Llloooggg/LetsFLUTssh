//! Update orchestrator — fetches GitHub Releases JSON, picks the
//! platform asset, builds an [`UpdateInfo`], and runs the full
//! download + verify pipeline (HTTPS download, SHA-256 against the
//! release-API digest, signed-manifest fetch, Ed25519 signature
//! verify against the pinned public key, per-asset hash check
//! against the manifest entry).
//!
//! The caller's state machine (Dart `UpdateNotifier`) becomes a
//! thin observer over [`check_for_update`] + [`download_with_verification`]
//! plus the existing `UpdateDownloadProgress` bus stream — every
//! orchestration concern lives here.
//!
//! # Why one module
//!
//! The pieces (`update_http`, `update_metadata`, `update_signing`)
//! already exist as standalone helpers; the Dart side stitched them
//! together with ~600 LOC of orchestration scattered across the
//! `UpdateService` facade. Moving the stitch Rust-side keeps the
//! security path (signature verify pre-install) Rust-resident and
//! shrinks the Dart layer to a stream subscriber.

use std::path::Path;

use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::error::Error;
use crate::update_http;
use crate::update_metadata;
use crate::update_signing;

/// Identifier for the GitHub repository that hosts the releases.
/// Hardcoded constant in the Dart facade today; kept as a parameter
/// here so unit tests / future deployments can target a different
/// fork without recompiling.
pub const DEFAULT_REPO: &str = "Llloooggg/LetsFLUTssh";

/// Result of a `check_for_update` call. Plain-data; FRB mirrors as
/// `DbUpdateInfo` with the same field set.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateInfo {
    pub latest_version: String,
    pub current_version: String,
    pub release_url: String,
    pub asset_url: Option<String>,
    pub asset_digest: Option<String>,
    pub changelog: Option<String>,
}

impl UpdateInfo {
    /// True when `latest_version` is strictly newer than
    /// `current_version` per `update_metadata::compare_versions`.
    pub fn has_update(&self) -> bool {
        update_metadata::compare_versions(&self.latest_version, &self.current_version)
            == std::cmp::Ordering::Greater
    }
}

/// Default asset host fallback when GitHub returns an empty release
/// list (no releases at all → treat current build as latest, point
/// the user at the `/releases/latest` page).
fn default_release_url(repo: &str) -> String {
    format!("https://github.com/{repo}/releases/latest")
}

fn api_url(repo: &str) -> String {
    format!("https://api.github.com/repos/{repo}/releases?per_page=30")
}

/// Detect the host platform suffix used by [`update_metadata::asset_suffix`].
/// Mirrors `UpdateService._hostPlatform` — caps the recognised set so
/// an unknown OS falls through to "no installer".
pub fn host_platform() -> &'static str {
    match std::env::consts::OS {
        "linux" => "linux",
        "macos" => "macos",
        "windows" => "windows",
        "android" => "android",
        _ => "unknown",
    }
}

fn pick_asset_url(assets: &[Value], suffix: &str) -> Option<String> {
    for a in assets {
        let name = a.get("name").and_then(|v| v.as_str()).unwrap_or("");
        if name.ends_with(suffix) {
            return a
                .get("browser_download_url")
                .and_then(|v| v.as_str())
                .map(str::to_string);
        }
    }
    None
}

fn pick_asset_digest(assets: &[Value], suffix: &str) -> Option<String> {
    for a in assets {
        let name = a.get("name").and_then(|v| v.as_str()).unwrap_or("");
        if name.ends_with(suffix) {
            let d = a.get("digest").and_then(|v| v.as_str())?;
            return d.strip_prefix("sha256:").map(str::to_string);
        }
    }
    None
}

/// Query the GitHub releases API for `repo`, choose the asset for
/// the host platform, and assemble an [`UpdateInfo`]. Returns the
/// `current_version` echoed back when the release list is empty so
/// the caller's UI can render an "up-to-date" branch without a
/// separate flow for that edge case.
pub async fn check_for_update(current_version: &str, repo: &str) -> Result<UpdateInfo, Error> {
    let body = update_http::fetch_text(&api_url(repo)).await?;
    let parsed: Value = serde_json::from_str(&body)
        .map_err(|e| Error::Io(format!("update releases JSON parse: {e}")))?;
    let release_list: Vec<Value> = match parsed {
        Value::Array(arr) => arr,
        Value::Object(_) => vec![parsed],
        _ => Vec::new(),
    };

    if release_list.is_empty() {
        return Ok(UpdateInfo {
            latest_version: current_version.to_string(),
            current_version: current_version.to_string(),
            release_url: default_release_url(repo),
            asset_url: None,
            asset_digest: None,
            changelog: None,
        });
    }

    let latest = &release_list[0];
    let tag = latest
        .get("tag_name")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let version = tag.strip_prefix('v').unwrap_or(tag).to_string();
    let release_url = latest
        .get("html_url")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .unwrap_or_else(|| default_release_url(repo));
    let assets: Vec<Value> = latest
        .get("assets")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let suffix = update_metadata::asset_suffix(host_platform());
    let (asset_url, asset_digest) = match suffix {
        Some(s) => (pick_asset_url(&assets, s), pick_asset_digest(&assets, s)),
        None => (None, None),
    };

    let changelog_pairs: Vec<update_metadata::ChangelogRelease> = release_list
        .iter()
        .map(|r| update_metadata::ChangelogRelease {
            tag: r
                .get("tag_name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            body: r
                .get("body")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        })
        .collect();
    let changelog = update_metadata::build_cumulative_changelog(&changelog_pairs, current_version);

    Ok(UpdateInfo {
        latest_version: version,
        current_version: current_version.to_string(),
        release_url,
        asset_url,
        asset_digest,
        changelog,
    })
}

/// Outcome of a successful download.
#[derive(Debug, Clone)]
pub struct DownloadedAsset {
    pub asset_path: String,
    pub manifest_path: String,
    pub manifest_sig_path: String,
}

/// Failure modes the download path surfaces to the caller. Maps
/// onto the Dart-era `InvalidReleaseSignatureException` /
/// `ReleaseManifestUnavailableException` split.
#[derive(Debug)]
pub enum DownloadError {
    /// Untrusted host (URL didn't pass `is_trusted_release_asset_uri`).
    Untrusted(String),
    /// HTTP / IO / SHA-256 problems before the manifest fetch.
    Network(Error),
    /// Couldn't fetch / read the release manifest. Surface as
    /// "try again later" — not a security event.
    ManifestUnavailable(String),
    /// Manifest fetched but signature did not verify, asset name
    /// missing from manifest, or asset SHA differs from the
    /// manifest entry. Surface as "do not install" warning.
    InvalidSignature(String),
}

impl std::fmt::Display for DownloadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DownloadError::Untrusted(msg) => write!(f, "untrusted: {msg}"),
            DownloadError::Network(e) => write!(f, "network: {e}"),
            DownloadError::ManifestUnavailable(msg) => write!(f, "manifest unavailable: {msg}"),
            DownloadError::InvalidSignature(msg) => write!(f, "invalid signature: {msg}"),
        }
    }
}

impl std::error::Error for DownloadError {}

/// Download the asset at `url` into `target_dir`, verify its
/// SHA-256 against `expected_digest` (when provided), then fetch
/// the release's `<name>-<version>.sha256sums` + `.sha256sums.sig`,
/// verify the signature against the pinned Ed25519 public key, and
/// confirm the asset's hash matches the manifest entry.
///
/// Bus events emitted along the way (subscribe to
/// [`crate::bus::EventTopic::Update`]):
/// - `UpdateDownloadProgress` — per-chunk while the asset streams.
/// - `UpdateVerifyingStarted { url }` — after HTTP completes,
///   before SHA hashing + signature verify.
/// - `UpdateDownloadCompleted { url, path }` — terminal success.
///
/// Errors clean up the partial files (`asset`, `manifest`,
/// `manifest.sig`) so a retry starts from a known-empty target dir.
pub async fn download_with_verification(
    url: &str,
    target_dir: &str,
    expected_digest: Option<&str>,
) -> Result<DownloadedAsset, DownloadError> {
    if !update_metadata::is_trusted_release_asset_uri(url) {
        return Err(DownloadError::Untrusted(url.to_string()));
    }

    let asset_name = url
        .rsplit('/')
        .next()
        .ok_or_else(|| DownloadError::Network(Error::Io("asset url has no path".into())))?;
    let asset_path = Path::new(target_dir).join(asset_name);
    let asset_path_str = asset_path.to_string_lossy().into_owned();

    let app = crate::app::instance();

    let url_for_progress = url.to_string();
    let app_for_progress = app.clone();
    update_http::download_to_file(url, &asset_path, move |written, total| {
        app_for_progress
            .bus
            .publish(crate::bus::Event::UpdateDownloadProgress {
                url: url_for_progress.clone(),
                written_bytes: written,
                total_bytes: total,
            });
    })
    .await
    .map_err(DownloadError::Network)?;

    app.bus.publish(crate::bus::Event::UpdateVerifyingStarted {
        url: url.to_string(),
    });

    if let Some(expected) = expected_digest {
        match sha256_file(&asset_path_str).await {
            Ok(actual) if actual.eq_ignore_ascii_case(expected) => {}
            Ok(actual) => {
                let _ = tokio::fs::remove_file(&asset_path_str).await;
                return Err(DownloadError::InvalidSignature(format!(
                    "SHA-256 mismatch: expected {expected}, got {actual}"
                )));
            }
            Err(e) => {
                let _ = tokio::fs::remove_file(&asset_path_str).await;
                return Err(DownloadError::Network(e));
            }
        }
    }

    let version = update_metadata::parse_asset_version(asset_name).ok_or_else(|| {
        DownloadError::InvalidSignature(format!(
            "cannot derive version from asset name {asset_name}"
        ))
    })?;
    let manifest_name = format!("letsflutssh-{version}.sha256sums");
    let manifest_url = replace_path_tail(url, &manifest_name);
    let manifest_sig_url = format!("{manifest_url}.sig");

    if !update_metadata::is_trusted_release_asset_uri(&manifest_url)
        || !update_metadata::is_trusted_release_asset_uri(&manifest_sig_url)
    {
        let _ = tokio::fs::remove_file(&asset_path_str).await;
        return Err(DownloadError::Untrusted(format!(
            "manifest pair: {manifest_url} / {manifest_sig_url}"
        )));
    }

    let manifest_path = Path::new(target_dir).join(&manifest_name);
    let manifest_sig_path = Path::new(target_dir).join(format!("{manifest_name}.sig"));
    let manifest_path_str = manifest_path.to_string_lossy().into_owned();
    let manifest_sig_path_str = manifest_sig_path.to_string_lossy().into_owned();

    if let Err(e) = update_http::download_to_file(&manifest_url, &manifest_path, |_, _| {}).await {
        let _ = tokio::fs::remove_file(&asset_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_path_str).await;
        return Err(DownloadError::ManifestUnavailable(format!(
            "fetch manifest: {e}"
        )));
    }
    if let Err(e) =
        update_http::download_to_file(&manifest_sig_url, &manifest_sig_path, |_, _| {}).await
    {
        let _ = tokio::fs::remove_file(&asset_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_sig_path_str).await;
        return Err(DownloadError::ManifestUnavailable(format!(
            "fetch manifest sig: {e}"
        )));
    }

    let manifest_bytes = match tokio::fs::read(&manifest_path_str).await {
        Ok(b) => b,
        Err(e) => {
            let _ = tokio::fs::remove_file(&asset_path_str).await;
            let _ = tokio::fs::remove_file(&manifest_path_str).await;
            let _ = tokio::fs::remove_file(&manifest_sig_path_str).await;
            return Err(DownloadError::ManifestUnavailable(format!(
                "read manifest: {e}"
            )));
        }
    };
    let sig_bytes = match tokio::fs::read(&manifest_sig_path_str).await {
        Ok(b) => b,
        Err(e) => {
            let _ = tokio::fs::remove_file(&asset_path_str).await;
            let _ = tokio::fs::remove_file(&manifest_path_str).await;
            let _ = tokio::fs::remove_file(&manifest_sig_path_str).await;
            return Err(DownloadError::ManifestUnavailable(format!(
                "read manifest sig: {e}"
            )));
        }
    };

    if !update_signing::verify_release_signature(&manifest_bytes, &sig_bytes) {
        let _ = tokio::fs::remove_file(&asset_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_sig_path_str).await;
        return Err(DownloadError::InvalidSignature(
            "manifest signature did not verify against the pinned Ed25519 key".into(),
        ));
    }

    let manifest_text = String::from_utf8(manifest_bytes)
        .map_err(|e| DownloadError::InvalidSignature(format!("manifest text not utf-8: {e}")))?;
    let manifest = update_metadata::parse_sha256_manifest(&manifest_text);
    let expected_hash = match manifest.get(asset_name) {
        Some(h) => h.clone(),
        None => {
            let _ = tokio::fs::remove_file(&asset_path_str).await;
            let _ = tokio::fs::remove_file(&manifest_path_str).await;
            let _ = tokio::fs::remove_file(&manifest_sig_path_str).await;
            return Err(DownloadError::InvalidSignature(format!(
                "manifest has no entry for {asset_name}"
            )));
        }
    };

    let actual_hash = sha256_file(&asset_path_str)
        .await
        .map_err(DownloadError::Network)?;
    if !actual_hash.eq_ignore_ascii_case(&expected_hash) {
        let _ = tokio::fs::remove_file(&asset_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_path_str).await;
        let _ = tokio::fs::remove_file(&manifest_sig_path_str).await;
        return Err(DownloadError::InvalidSignature(format!(
            "SHA-256 mismatch for {asset_name}: manifest={expected_hash} actual={actual_hash}"
        )));
    }

    app.bus.publish(crate::bus::Event::UpdateDownloadCompleted {
        url: url.to_string(),
        path: asset_path_str.clone(),
    });

    Ok(DownloadedAsset {
        asset_path: asset_path_str,
        manifest_path: manifest_path_str,
        manifest_sig_path: manifest_sig_path_str,
    })
}

/// Replace the last path segment of `url` with `new_tail`. Used to
/// derive the manifest URL from the asset URL — both live in the
/// same release directory.
fn replace_path_tail(url: &str, new_tail: &str) -> String {
    match url.rfind('/') {
        Some(idx) => {
            let mut s = String::with_capacity(idx + 1 + new_tail.len());
            s.push_str(&url[..=idx]);
            s.push_str(new_tail);
            s
        }
        None => new_tail.to_string(),
    }
}

async fn sha256_file(path: &str) -> Result<String, Error> {
    let bytes = tokio::fs::read(path)
        .await
        .map_err(|e| Error::Io(format!("read {path}: {e}")))?;
    let mut h = Sha256::new();
    h.update(&bytes);
    let digest = h.finalize();
    let mut hex = String::with_capacity(64);
    for b in digest {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    Ok(hex)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_platform_recognises_supported_targets() {
        // We can't override `std::env::consts::OS`, so just sanity-
        // check the function returns one of the documented values.
        let p = host_platform();
        assert!(matches!(
            p,
            "linux" | "macos" | "windows" | "android" | "unknown"
        ));
    }

    #[test]
    fn replace_path_tail_swaps_only_basename() {
        assert_eq!(
            replace_path_tail("https://x.com/a/b/c.bin", "manifest.sha256sums"),
            "https://x.com/a/b/manifest.sha256sums"
        );
    }

    #[test]
    fn replace_path_tail_handles_no_slash() {
        assert_eq!(
            replace_path_tail("plain", "manifest.sha256sums"),
            "manifest.sha256sums"
        );
    }

    #[tokio::test]
    async fn sha256_file_matches_known_vector() {
        // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        let dir = std::env::temp_dir();
        let pid = std::process::id();
        let path = dir
            .join(format!("lfs_orchestrator_test_sha_{pid}.bin"))
            .to_string_lossy()
            .into_owned();
        tokio::fs::write(&path, b"abc").await.expect("write");
        let h = sha256_file(&path).await.expect("hash");
        assert_eq!(
            h,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        let _ = tokio::fs::remove_file(&path).await;
    }

    #[test]
    fn pick_asset_url_matches_suffix() {
        let assets = vec![
            serde_json::json!({"name": "letsflutssh-1.0.0-windows-x64-setup.exe", "browser_download_url": "https://example/a.exe"}),
            serde_json::json!({"name": "letsflutssh-1.0.0-linux-x64.AppImage", "browser_download_url": "https://example/a.appimage"}),
        ];
        assert_eq!(
            pick_asset_url(&assets, "-linux-x64.AppImage").as_deref(),
            Some("https://example/a.appimage")
        );
        assert_eq!(
            pick_asset_url(&assets, "-android-arm64.apk").as_deref(),
            None
        );
    }

    #[test]
    fn pick_asset_digest_strips_sha256_prefix() {
        let assets = vec![serde_json::json!({
            "name": "letsflutssh-1.0.0-linux-x64.AppImage",
            "browser_download_url": "u",
            "digest": "sha256:deadbeef"
        })];
        assert_eq!(
            pick_asset_digest(&assets, "-linux-x64.AppImage").as_deref(),
            Some("deadbeef")
        );
    }

    #[test]
    fn update_info_has_update_compares_versions() {
        let info = UpdateInfo {
            latest_version: "1.2.3".into(),
            current_version: "1.2.0".into(),
            release_url: "u".into(),
            asset_url: None,
            asset_digest: None,
            changelog: None,
        };
        assert!(info.has_update());
        let same = UpdateInfo {
            latest_version: "1.2.0".into(),
            current_version: "1.2.0".into(),
            ..info.clone()
        };
        assert!(!same.has_update());
    }
}
