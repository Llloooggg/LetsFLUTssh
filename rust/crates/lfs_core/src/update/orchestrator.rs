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
use crate::update::http as update_http;
use crate::update::metadata as update_metadata;
use crate::update::signing as update_signing;

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
    check_for_update_from_body(&body, current_version, repo)
}

/// Same orchestration walk as [`check_for_update`] but against a
/// pre-fetched releases-API response body — caller owns the HTTP
/// transport so flutter_test contexts can drive captured fixture
/// bytes through the Rust parser without a real network round-trip.
/// Returns a parse error only when the body is not valid JSON;
/// every shape branch falls through to the same defaults
/// `check_for_update` uses (empty list → echo current version,
/// missing `tag_name` → empty version, missing `html_url` →
/// `default_release_url`).
pub fn check_for_update_from_body(
    body: &str,
    current_version: &str,
    repo: &str,
) -> Result<UpdateInfo, Error> {
    let parsed: Value = serde_json::from_str(body)
        .map_err(|e| Error::Update(format!("update releases JSON parse: {e}")))?;
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

/// Drop-guard that wipes any tracked partial files unless the
/// caller explicitly disarms it. Closes the cancellation hole in
/// `download_with_verification` — trap: a `task::abort`
/// mid-download leaves bytes on disk that the next retry hashes
/// against an incomplete file.
struct PartialDownloadGuard {
    paths: Vec<String>,
    armed: bool,
}

impl PartialDownloadGuard {
    fn new() -> Self {
        Self {
            paths: Vec::new(),
            armed: true,
        }
    }

    fn track(&mut self, path: String) {
        self.paths.push(path);
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for PartialDownloadGuard {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        // Drop runs sync — best-effort cleanup. Async tokio::fs
        // would need a runtime which may be torn down already
        // when the guard drops (process shutdown / runtime stop).
        for p in self.paths.drain(..) {
            let _ = std::fs::remove_file(&p);
        }
    }
}

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
    let mut guard = PartialDownloadGuard::new();
    guard.track(asset_path_str.clone());

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
                return Err(DownloadError::InvalidSignature(format!(
                    "SHA-256 mismatch: expected {expected}, got {actual}"
                )));
            }
            Err(e) => {
                return Err(DownloadError::Network(e));
            }
        }
    }

    let version = update_metadata::parse_asset_version(asset_name).ok_or_else(|| {
        DownloadError::InvalidSignature(format!(
            "cannot derive version from asset name {asset_name}"
        ))
    })?;
    let manifest_name = format!(
        "{}{version}.sha256sums",
        update_metadata::RELEASE_ASSET_PREFIX
    );
    let manifest_url = replace_path_tail(url, &manifest_name);
    let manifest_sig_url = format!("{manifest_url}.sig");

    if !update_metadata::is_trusted_release_asset_uri(&manifest_url)
        || !update_metadata::is_trusted_release_asset_uri(&manifest_sig_url)
    {
        return Err(DownloadError::Untrusted(format!(
            "manifest pair: {manifest_url} / {manifest_sig_url}"
        )));
    }

    let manifest_path = Path::new(target_dir).join(&manifest_name);
    let manifest_sig_path = Path::new(target_dir).join(format!("{manifest_name}.sig"));
    let manifest_path_str = manifest_path.to_string_lossy().into_owned();
    let manifest_sig_path_str = manifest_sig_path.to_string_lossy().into_owned();

    if let Err(e) = update_http::download_to_file(&manifest_url, &manifest_path, |_, _| {}).await {
        guard.track(manifest_path_str.clone());
        return Err(DownloadError::ManifestUnavailable(format!(
            "fetch manifest: {e}"
        )));
    }
    guard.track(manifest_path_str.clone());

    if let Err(e) =
        update_http::download_to_file(&manifest_sig_url, &manifest_sig_path, |_, _| {}).await
    {
        guard.track(manifest_sig_path_str.clone());
        return Err(DownloadError::ManifestUnavailable(format!(
            "fetch manifest sig: {e}"
        )));
    }
    guard.track(manifest_sig_path_str.clone());

    let manifest_bytes = match tokio::fs::read(&manifest_path_str).await {
        Ok(b) => b,
        Err(e) => {
            return Err(DownloadError::ManifestUnavailable(format!(
                "read manifest: {e}"
            )));
        }
    };
    let sig_bytes = match tokio::fs::read(&manifest_sig_path_str).await {
        Ok(b) => b,
        Err(e) => {
            return Err(DownloadError::ManifestUnavailable(format!(
                "read manifest sig: {e}"
            )));
        }
    };

    if !update_signing::verify_release_signature(&manifest_bytes, &sig_bytes) {
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
            return Err(DownloadError::InvalidSignature(format!(
                "manifest has no entry for {asset_name}"
            )));
        }
    };

    let actual_hash = sha256_file(&asset_path_str)
        .await
        .map_err(DownloadError::Network)?;
    if !actual_hash.eq_ignore_ascii_case(&expected_hash) {
        return Err(DownloadError::InvalidSignature(format!(
            "SHA-256 mismatch for {asset_name}: manifest={expected_hash} actual={actual_hash}"
        )));
    }

    app.bus.publish(crate::bus::Event::UpdateDownloadCompleted {
        url: url.to_string(),
        path: asset_path_str.clone(),
    });

    guard.disarm();
    Ok(DownloadedAsset {
        asset_path: asset_path_str,
        manifest_path: manifest_path_str,
        manifest_sig_path: manifest_sig_path_str,
    })
}

/// Replace the last path segment of `url` with `new_tail`. Derives
/// the manifest URL from the asset URL — both live in the same
/// release directory.
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

/// SHA-256 a file by streaming 64 KiB chunks through the hasher
/// instead of materialising the whole file in memory. The asset
/// can be a multi-MiB / multi-GiB installer; both the digest
/// precheck and the manifest cross-check each read the file once,
/// so the buffer stays a single `[u8; 65_536]` reused per chunk
/// regardless of artefact size.
async fn sha256_file(path: &str) -> Result<String, Error> {
    use tokio::io::AsyncReadExt;

    let mut file = tokio::fs::File::open(path)
        .await
        .map_err(|e| Error::Update(format!("open {path}: {e}")))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file
            .read(&mut buf)
            .await
            .map_err(|e| Error::Update(format!("read {path}: {e}")))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(64);
    for b in digest {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    Ok(hex)
}

/// Walk `dir` and remove every stale update artefact: the
/// per-platform installer (matched by the release-asset suffix —
/// everything from the second dash of the asset filename onwards,
/// `letsflutssh-1.9.0-windows-x64-setup.exe` → `-windows-x64-setup
/// .exe`) plus the shared manifest + Ed25519 signature pair
/// (`letsflutssh-<version>.sha256sums` / `.sha256sums.sig`). The
/// manifest pair carries no platform suffix, so a suffix-only match
/// left every previous version's `.sha256sums` / `.sha256sums.sig`
/// accumulating in app-support. Other persisted files are untouched.
///
/// Returns the count of files actually removed; per-file delete
/// failures are logged but not surfaced as `Err` (the next
/// startup re-runs the sweep). Caller invokes this immediately
/// before downloading a fresh installer so the freshly-arrived
/// artefact is the only one with the suffix on disk.
///
/// Returns 0 on missing directory, missing/garbled asset URL,
/// or a filename with fewer than two dashes — none of which are
/// fatal: a clean install simply has nothing to clean.
pub async fn cleanup_stale_downloads(dir: &Path, asset_url: &str) -> Result<u32, std::io::Error> {
    let Some(suffix) = stale_download_suffix(asset_url) else {
        return Ok(0);
    };
    if !tokio::fs::try_exists(dir).await.unwrap_or(false) {
        return Ok(0);
    }
    let mut entries = match tokio::fs::read_dir(dir).await {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(0),
        Err(e) => return Err(e),
    };
    let mut removed = 0u32;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let file_type = match entry.file_type().await {
            Ok(t) => t,
            Err(_) => continue,
        };
        if !file_type.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        if !(name.ends_with(&suffix) || is_update_manifest_artifact(name)) {
            continue;
        }
        if let Err(e) = tokio::fs::remove_file(&path).await {
            crate::app_log_warn!("UpdateCleanup", "remove stale download failed: {e}");
            continue;
        }
        removed = removed.saturating_add(1);
    }
    Ok(removed)
}

/// Best-effort delete of `path`. Used after the installer
/// hand-off: the installer's already running, so the file can go.
/// Missing target is a no-op (idempotent); other I/O errors
/// surface so the caller can surface a "couldn't tidy up" toast
/// without blocking the install flow.
pub async fn cleanup_file(path: &Path) -> Result<(), std::io::Error> {
    match tokio::fs::remove_file(path).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

/// Extract the per-platform release-asset suffix from a download
/// URL. Mirrors the Dart helper: take the path's last segment, find
/// the first two dashes, and return everything from the second dash
/// onward (inclusive). Returns `None` for URLs whose filename has
/// fewer than two dashes — the caller treats that as "nothing safe
/// to match".
/// True when `name` is one of the release manifest artefacts the
/// update flow downloads alongside the installer
/// (`letsflutssh-<version>.sha256sums` and its `.sig`). They carry no
/// per-platform suffix, so the suffix sweep misses them; matching the
/// manifest extensions keeps stale pairs from accumulating across
/// versions.
fn is_update_manifest_artifact(name: &str) -> bool {
    name.starts_with(update_metadata::RELEASE_ASSET_PREFIX)
        && (name.ends_with(".sha256sums") || name.ends_with(".sha256sums.sig"))
}

fn stale_download_suffix(asset_url: &str) -> Option<String> {
    let url_no_query = asset_url
        .split_once(['?', '#'])
        .map_or(asset_url, |(prefix, _)| prefix);
    let file_name = url_no_query.rsplit('/').find(|s| !s.is_empty())?;
    let first_dash = file_name.find('-')?;
    let after_first = &file_name[first_dash + 1..];
    let second_dash_offset = after_first.find('-')?;
    let second_dash_abs = first_dash + 1 + second_dash_offset;
    Some(file_name[second_dash_abs..].to_string())
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

    #[test]
    fn from_body_empty_array_echoes_current_version() {
        let info = check_for_update_from_body("[]", "1.0.0", "owner/repo").expect("parse");
        assert_eq!(info.latest_version, "1.0.0");
        assert_eq!(info.current_version, "1.0.0");
        assert_eq!(
            info.release_url,
            "https://github.com/owner/repo/releases/latest"
        );
        assert!(info.asset_url.is_none());
        assert!(info.asset_digest.is_none());
        assert!(info.changelog.is_none());
        assert!(!info.has_update());
    }

    #[test]
    fn from_body_array_picks_first_release() {
        let body = r#"[
            {"tag_name":"v2.0.0","html_url":"https://example/r2","assets":[]},
            {"tag_name":"v1.0.0","html_url":"https://example/r1","assets":[]}
        ]"#;
        let info = check_for_update_from_body(body, "1.0.0", "owner/repo").expect("parse");
        assert_eq!(info.latest_version, "2.0.0");
        assert!(info.has_update());
    }

    #[test]
    fn from_body_single_object_treated_as_legacy_latest() {
        let body = r#"{"tag_name":"v2.0.0","html_url":"https://example/r","assets":[]}"#;
        let info = check_for_update_from_body(body, "1.0.0", "owner/repo").expect("parse");
        assert_eq!(info.latest_version, "2.0.0");
        assert_eq!(info.release_url, "https://example/r");
    }

    #[test]
    fn from_body_missing_tag_name_yields_empty_version() {
        let body = r#"[{"html_url":"https://example/r","assets":[]}]"#;
        let info = check_for_update_from_body(body, "1.0.0", "owner/repo").expect("parse");
        assert_eq!(info.latest_version, "");
        assert!(!info.has_update());
    }

    #[test]
    fn from_body_missing_html_url_falls_back_to_default() {
        let body = r#"[{"tag_name":"v2.0.0","assets":[]}]"#;
        let info = check_for_update_from_body(body, "1.0.0", "owner/repo").expect("parse");
        assert_eq!(
            info.release_url,
            "https://github.com/owner/repo/releases/latest"
        );
    }

    #[test]
    fn from_body_missing_assets_yields_no_asset_url() {
        let body = r#"[{"tag_name":"v2.0.0","html_url":"https://example/r"}]"#;
        let info = check_for_update_from_body(body, "1.0.0", "owner/repo").expect("parse");
        assert!(info.asset_url.is_none());
        assert!(info.asset_digest.is_none());
    }

    #[test]
    fn from_body_invalid_json_is_parse_error() {
        let err = check_for_update_from_body("not json", "1.0.0", "owner/repo").unwrap_err();
        assert!(format!("{err}").contains("update releases JSON parse"));
    }

    #[test]
    fn from_body_non_array_non_object_falls_back_to_empty_list() {
        // String / number / bool at the top level → treat as empty list.
        let info = check_for_update_from_body("\"hi\"", "1.0.0", "owner/repo").expect("parse");
        assert_eq!(info.latest_version, "1.0.0");
        assert!(!info.has_update());
    }

    // ── stale_download_suffix ────────────────────────────────────

    #[test]
    fn stale_download_suffix_extracts_platform_tail() {
        assert_eq!(
            stale_download_suffix("https://example/v1.9.0/letsflutssh-1.9.0-windows-x64-setup.exe")
                .as_deref(),
            Some("-windows-x64-setup.exe")
        );
        assert_eq!(
            stale_download_suffix("https://example/letsflutssh-1.9.0-linux-x64.AppImage")
                .as_deref(),
            Some("-linux-x64.AppImage")
        );
    }

    #[test]
    fn stale_download_suffix_handles_query_and_fragment() {
        // Real GitHub Releases URLs sometimes append `?download` or
        // tracking fragments. The basename split has to ignore both.
        assert_eq!(
            stale_download_suffix("https://example/letsflutssh-1.9.0-macos-arm64.dmg?download=1")
                .as_deref(),
            Some("-macos-arm64.dmg")
        );
    }

    #[test]
    fn stale_download_suffix_returns_none_without_two_dashes() {
        // No dash at all.
        assert!(stale_download_suffix("https://example/installer.exe").is_none());
        // Single dash — caller treats this as "nothing safe to match"
        // so the cleanup walk skips the directory entirely.
        assert!(stale_download_suffix("https://example/letsflutssh-installer.exe").is_none());
    }

    #[test]
    fn stale_download_suffix_returns_none_for_empty_basename() {
        assert!(stale_download_suffix("").is_none());
        assert!(stale_download_suffix("https://example/").is_none());
    }

    // ── cleanup_stale_downloads ──────────────────────────────────

    #[tokio::test]
    async fn cleanup_stale_downloads_drops_only_matching_suffix() {
        let dir = tempfile::TempDir::new().expect("tempdir");
        let path = dir.path();
        // Two files share the platform suffix → both go.
        tokio::fs::write(path.join("letsflutssh-1.8.0-windows-x64-setup.exe"), b"old")
            .await
            .unwrap();
        tokio::fs::write(
            path.join("letsflutssh-1.7.0-windows-x64-setup.exe"),
            b"older",
        )
        .await
        .unwrap();
        // Different platform → must stay.
        tokio::fs::write(path.join("letsflutssh-1.8.0-linux-x64.AppImage"), b"keep")
            .await
            .unwrap();
        // Unrelated user file → must stay.
        tokio::fs::write(path.join("config.json"), b"keep")
            .await
            .unwrap();

        let removed = cleanup_stale_downloads(
            path,
            "https://example/v1.9.0/letsflutssh-1.9.0-windows-x64-setup.exe",
        )
        .await
        .expect("cleanup");
        assert_eq!(removed, 2);
        assert!(!path
            .join("letsflutssh-1.8.0-windows-x64-setup.exe")
            .exists());
        assert!(!path
            .join("letsflutssh-1.7.0-windows-x64-setup.exe")
            .exists());
        assert!(path.join("letsflutssh-1.8.0-linux-x64.AppImage").exists());
        assert!(path.join("config.json").exists());
    }

    #[tokio::test]
    async fn cleanup_stale_downloads_sweeps_manifest_and_sig_artifacts() {
        let dir = tempfile::TempDir::new().expect("tempdir");
        let path = dir.path();
        // Manifest + signature pairs from prior versions carry no
        // platform suffix, so before the fix they piled up untouched.
        for name in [
            "letsflutssh-1.7.0.sha256sums",
            "letsflutssh-1.7.0.sha256sums.sig",
            "letsflutssh-1.8.0.sha256sums",
            "letsflutssh-1.8.0.sha256sums.sig",
        ] {
            tokio::fs::write(path.join(name), b"x").await.unwrap();
        }
        // Foreign-prefix lookalike must stay.
        tokio::fs::write(path.join("other-1.8.0.sha256sums"), b"keep")
            .await
            .unwrap();

        let removed = cleanup_stale_downloads(
            path,
            "https://example/v1.9.0/letsflutssh-1.9.0-windows-x64-setup.exe",
        )
        .await
        .expect("cleanup");
        assert_eq!(removed, 4);
        assert!(path.join("other-1.8.0.sha256sums").exists());
    }

    #[test]
    fn is_update_manifest_artifact_matches_manifest_and_sig_only() {
        assert!(is_update_manifest_artifact("letsflutssh-1.9.0.sha256sums"));
        assert!(is_update_manifest_artifact(
            "letsflutssh-1.9.0.sha256sums.sig"
        ));
        // Wrong prefix → not ours.
        assert!(!is_update_manifest_artifact("other-1.9.0.sha256sums"));
        // The installer is matched by the suffix path, not here.
        assert!(!is_update_manifest_artifact(
            "letsflutssh-1.9.0-windows-x64-setup.exe"
        ));
        assert!(!is_update_manifest_artifact("letsflutssh-notes.txt"));
    }

    #[tokio::test]
    async fn cleanup_stale_downloads_no_op_on_missing_dir() {
        let removed = cleanup_stale_downloads(
            std::path::Path::new("/nonexistent/lfs_cleanup_probe"),
            "https://example/letsflutssh-1.9.0-windows-x64-setup.exe",
        )
        .await
        .expect("cleanup");
        assert_eq!(removed, 0);
    }

    #[tokio::test]
    async fn cleanup_stale_downloads_no_op_on_unparseable_url() {
        let dir = tempfile::TempDir::new().expect("tempdir");
        // Pre-existing file: must NOT get touched because the
        // suffix is undetectable, so we have nothing safe to match.
        tokio::fs::write(dir.path().join("anything.bin"), b"keep")
            .await
            .unwrap();
        let removed = cleanup_stale_downloads(dir.path(), "https://example/bogus")
            .await
            .expect("cleanup");
        assert_eq!(removed, 0);
        assert!(dir.path().join("anything.bin").exists());
    }

    // ── cleanup_file ─────────────────────────────────────────────

    #[tokio::test]
    async fn cleanup_file_removes_existing_file() {
        let dir = tempfile::TempDir::new().expect("tempdir");
        let path = dir.path().join("installer.exe");
        tokio::fs::write(&path, b"bytes").await.unwrap();
        cleanup_file(&path).await.expect("cleanup");
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn cleanup_file_is_idempotent_on_missing_file() {
        let dir = tempfile::TempDir::new().expect("tempdir");
        let path = dir.path().join("nope.exe");
        // Already absent — must not error.
        cleanup_file(&path).await.expect("cleanup");
    }
}
