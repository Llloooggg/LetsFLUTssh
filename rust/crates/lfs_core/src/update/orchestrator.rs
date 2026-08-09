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

/// Normalise the host CPU architecture into the token CI bakes into
/// release-asset filenames (`x64` / `arm64` / `arm32`), the second
/// half of the [`update_metadata::asset_suffix`] key. An unrecognised
/// arch falls through to `unknown`, which yields no asset match (the
/// caller then points the user at the release page rather than
/// self-updating to a binary built for the wrong CPU).
pub fn host_arch() -> &'static str {
    match std::env::consts::ARCH {
        "x86_64" => "x64",
        "aarch64" => "arm64",
        // 32-bit ARM (armv7 Android) reports plain `arm`.
        "arm" => "arm32",
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

    let suffix = update_metadata::asset_suffix(host_platform(), host_arch());
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
#[path = "../../tests/unit/update_orchestrator.rs"]
mod tests;
