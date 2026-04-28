//! FRB adapter for `lfs_core::update_http` — the auto-update
//! HTTP fetch path — plus the higher-level orchestrator
//! ([`update_check`] / [`update_download_with_verification`]) that
//! glues the HTTP, metadata, and signing primitives together so the
//! Dart side is a thin observer over typed return values + bus
//! progress events.

/// GET `url`, follow redirects bounded by the trusted-host
/// allowlist, return the response body as a `String`. Used by
/// the Dart `UpdateService.checkForUpdate` to read the GitHub
/// Releases API JSON without staging an HTTP client on the
/// Dart side.
pub async fn update_fetch_text(url: String) -> Result<String, String> {
    lfs_core::update_http::fetch_text(&url)
        .await
        .map_err(|e| e.to_string())
}

/// GET `url`, stream the body into `target_path` while hashing
/// each chunk with SHA-256. Returns the final hex digest. The
/// Dart caller compares it against the manifest entry to gate
/// install. No progress streaming in this surface yet —
/// follow-up arc adds a bus event variant if the UI grows
/// determinate progress on the Rust path.
pub async fn update_download_to_file(url: String, target_path: String) -> Result<String, String> {
    let path = std::path::PathBuf::from(target_path);
    let url_for_progress = url.clone();
    lfs_core::update_http::download_to_file(&url, &path, move |written, total| {
        // `app::instance()` is a process-singleton getter — every
        // call returns the same `&'static AppState`, so the
        // closure's `'static` bound holds without a clone.
        lfs_core::app::instance()
            .bus
            .publish(lfs_core::bus::Event::UpdateDownloadProgress {
                url: url_for_progress.clone(),
                written_bytes: written,
                total_bytes: total,
            });
    })
    .await
    .map_err(|e| e.to_string())
}

/// FRB mirror of `lfs_core::update_orchestrator::UpdateInfo`. Same
/// field set + a derived `has_update` getter for the Dart caller.
#[derive(Debug, Clone)]
pub struct DbUpdateInfo {
    pub latest_version: String,
    pub current_version: String,
    pub release_url: String,
    pub asset_url: Option<String>,
    pub asset_digest: Option<String>,
    pub changelog: Option<String>,
}

impl From<lfs_core::update_orchestrator::UpdateInfo> for DbUpdateInfo {
    fn from(i: lfs_core::update_orchestrator::UpdateInfo) -> Self {
        Self {
            latest_version: i.latest_version,
            current_version: i.current_version,
            release_url: i.release_url,
            asset_url: i.asset_url,
            asset_digest: i.asset_digest,
            changelog: i.changelog,
        }
    }
}

/// Query GitHub Releases for the configured repository, pick the
/// asset that matches the host platform, and return the resulting
/// [`DbUpdateInfo`]. Mirrors the Dart-era
/// `UpdateService.checkForUpdate` end-to-end.
///
/// Pass an empty `repo` to use
/// `lfs_core::update_orchestrator::DEFAULT_REPO`.
pub async fn update_check(current_version: String, repo: String) -> Result<DbUpdateInfo, String> {
    let target_repo = if repo.is_empty() {
        lfs_core::update_orchestrator::DEFAULT_REPO
    } else {
        repo.as_str()
    };
    lfs_core::update_orchestrator::check_for_update(&current_version, target_repo)
        .await
        .map(DbUpdateInfo::from)
        .map_err(|e| e.to_string())
}

/// FRB mirror of `lfs_core::update_orchestrator::DownloadedAsset`.
#[derive(Debug, Clone)]
pub struct DbDownloadedAsset {
    pub asset_path: String,
    pub manifest_path: String,
    pub manifest_sig_path: String,
}

/// Categorical failure shape — surfaces the same split the
/// Dart-era `InvalidReleaseSignatureException` /
/// `ReleaseManifestUnavailableException` exposed so the UI can
/// pick the right toast (security warning vs retry).
#[derive(Debug, Clone)]
pub enum DbDownloadErrorKind {
    Untrusted,
    Network,
    ManifestUnavailable,
    InvalidSignature,
}

#[derive(Debug, Clone)]
pub struct DbDownloadResult {
    pub asset: Option<DbDownloadedAsset>,
    pub error_kind: Option<DbDownloadErrorKind>,
    pub error_detail: Option<String>,
}

/// Download the asset at `url` into `target_dir`, verify its
/// SHA-256 against `expected_digest` (when non-empty), then fetch +
/// verify the signed manifest. Returns the typed
/// [`DbDownloadResult`] — `asset` populated on success, `error_*`
/// populated on failure. The Result wrapper carries no `Err` arm so
/// the FRB caller doesn't have to branch twice on outcome.
///
/// Bus events emitted along the way (subscribe to
/// `BusTopic::Update`):
///   - `UpdateDownloadProgress` per HTTP chunk,
///   - `UpdateVerifyingStarted` once HTTP completes,
///   - `UpdateDownloadCompleted` on terminal success.
pub async fn update_download_with_verification(
    url: String,
    target_dir: String,
    expected_digest: String,
) -> DbDownloadResult {
    let digest_opt = if expected_digest.is_empty() {
        None
    } else {
        Some(expected_digest.as_str())
    };
    match lfs_core::update_orchestrator::download_with_verification(&url, &target_dir, digest_opt)
        .await
    {
        Ok(asset) => DbDownloadResult {
            asset: Some(DbDownloadedAsset {
                asset_path: asset.asset_path,
                manifest_path: asset.manifest_path,
                manifest_sig_path: asset.manifest_sig_path,
            }),
            error_kind: None,
            error_detail: None,
        },
        Err(e) => {
            let (kind, detail) = match e {
                lfs_core::update_orchestrator::DownloadError::Untrusted(s) => {
                    (DbDownloadErrorKind::Untrusted, s)
                }
                lfs_core::update_orchestrator::DownloadError::Network(err) => {
                    (DbDownloadErrorKind::Network, err.to_string())
                }
                lfs_core::update_orchestrator::DownloadError::ManifestUnavailable(s) => {
                    (DbDownloadErrorKind::ManifestUnavailable, s)
                }
                lfs_core::update_orchestrator::DownloadError::InvalidSignature(s) => {
                    (DbDownloadErrorKind::InvalidSignature, s)
                }
            };
            DbDownloadResult {
                asset: None,
                error_kind: Some(kind),
                error_detail: Some(detail),
            }
        }
    }
}
