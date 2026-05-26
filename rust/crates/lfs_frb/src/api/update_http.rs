//! FRB adapter for `lfs_core::update_http` — the auto-update
//! HTTP fetch path — plus the higher-level orchestrator
//! ([`update_check`] / [`update_download_with_verification`]) that
//! glues the HTTP, metadata, and signing primitives together so the
//! Dart side is a thin observer over typed return values + bus
//! progress events.

use crate::api::frb_err;

/// GET `url`, follow redirects bounded by the trusted-host
/// allowlist, return the response body as a `String`. Used by
/// the Dart `UpdateService.checkForUpdate` to read the GitHub
/// Releases API JSON without staging an HTTP client on the
/// Dart side.
pub async fn update_fetch_text(url: String) -> Result<String, String> {
    lfs_core::update::http::fetch_text(&url)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
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
    lfs_core::update::http::download_to_file(&url, &path, move |written, total| {
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
    .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// FRB mirror of `lfs_core::update::orchestrator::UpdateInfo`. Same
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

impl From<lfs_core::update::orchestrator::UpdateInfo> for DbUpdateInfo {
    fn from(i: lfs_core::update::orchestrator::UpdateInfo) -> Self {
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
/// `lfs_core::update::orchestrator::DEFAULT_REPO`.
pub async fn update_check(current_version: String, repo: String) -> Result<DbUpdateInfo, String> {
    let target_repo = if repo.is_empty() {
        lfs_core::update::orchestrator::DEFAULT_REPO
    } else {
        repo.as_str()
    };
    lfs_core::update::orchestrator::check_for_update(&current_version, target_repo)
        .await
        .map(DbUpdateInfo::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Same orchestration walk as [`update_check`] but against a
/// pre-fetched releases-API response body. The Dart-side
/// `UpdateService.checkForUpdate` test seam fetches the body
/// through an injected `HttpFetcher` (so unit tests can drive
/// captured fixture bytes through the parser without a real
/// network round-trip) and then routes through here so the
/// JSON-shape walk + asset-suffix selection lives one place.
pub fn update_check_from_body(
    body: String,
    current_version: String,
    repo: String,
) -> Result<DbUpdateInfo, String> {
    let target_repo = if repo.is_empty() {
        lfs_core::update::orchestrator::DEFAULT_REPO
    } else {
        repo.as_str()
    };
    lfs_core::update::orchestrator::check_for_update_from_body(&body, &current_version, target_repo)
        .map(DbUpdateInfo::from)
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// FRB mirror of `lfs_core::update::orchestrator::DownloadedAsset`.
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
    match lfs_core::update::orchestrator::download_with_verification(&url, &target_dir, digest_opt)
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
                lfs_core::update::orchestrator::DownloadError::Untrusted(s) => {
                    (DbDownloadErrorKind::Untrusted, s)
                }
                lfs_core::update::orchestrator::DownloadError::Network(err) => {
                    (DbDownloadErrorKind::Network, err.to_string())
                }
                lfs_core::update::orchestrator::DownloadError::ManifestUnavailable(s) => {
                    (DbDownloadErrorKind::ManifestUnavailable, s)
                }
                lfs_core::update::orchestrator::DownloadError::InvalidSignature(s) => {
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

/// Walk the pinned support dir and remove every previous-version
/// installer whose filename shares a platform-suffix with the
/// asset at `asset_url`. Wraps
/// [`lfs_core::update::orchestrator::cleanup_stale_downloads`] —
/// caller invokes it just before kicking off a fresh download so
/// the new installer is the only file with that suffix on disk.
/// Returns the count of files actually removed; both a missing
/// directory and an asset URL with too few dashes to extract a
/// suffix surface as `Ok(0)`.
///
/// The scan root resolves through `app::instance().support_dir()`
/// — the same canonical accessor `recovery::run_destructive_reset`
/// uses — so the Dart caller doesn't pass a path that Rust would
/// just re-derive. Tests scope the singleton per case via
/// `app_reset_support_dir_for_tests` + `config_store_init`.
pub async fn update_cleanup_stale_downloads(asset_url: String) -> Result<u32, String> {
    let dir = lfs_core::app::instance()
        .support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    lfs_core::update::orchestrator::cleanup_stale_downloads(dir, &asset_url)
        .await
        .map_err(|e| {
            frb_err::wire(
                frb_err::kind::UPDATE,
                &format!("cleanup stale downloads: {e}"),
            )
        })
}

/// Best-effort delete of `path`. Idempotent on a missing target
/// (the OS already finished the work for us). Wraps
/// [`lfs_core::update::orchestrator::cleanup_file`] — used by the
/// installer hand-off path to delete the downloaded artefact a
/// few seconds after spawning the installer.
pub async fn update_cleanup_file(path: String) -> Result<(), String> {
    let target = std::path::PathBuf::from(path);
    lfs_core::update::orchestrator::cleanup_file(&target)
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::UPDATE, &format!("cleanup file: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    // The async network endpoints (`update_fetch_text` /
    // `update_download_to_file` / `update_check` /
    // `update_download_with_verification`) issue real HTTP requests
    // against GitHub Releases; covered by the Dart `update_service_test.dart`
    // integration suite under fixture-driven `HttpFetcher` injection
    // + the manual signed-release smoke tests on the user's release
    // process. The standalone tests below pin the pure parser shim
    // `update_check_from_body` + the DTO mappings.

    #[test]
    fn update_check_from_body_returns_err_for_garbage_input() {
        let res = update_check_from_body("not-json".into(), "1.0.0".into(), String::new());
        assert!(res.is_err());
    }

    #[test]
    fn update_check_from_body_returns_err_for_empty_body() {
        let res = update_check_from_body(String::new(), "1.0.0".into(), String::new());
        assert!(res.is_err());
    }

    #[test]
    fn db_download_error_kind_clone_round_trip() {
        // Pin the four-variant taxonomy — the Dart UI surfaces a
        // different toast per kind (security warning vs retry vs
        // network error).
        for v in [
            DbDownloadErrorKind::Untrusted,
            DbDownloadErrorKind::Network,
            DbDownloadErrorKind::ManifestUnavailable,
            DbDownloadErrorKind::InvalidSignature,
        ] {
            let c = v.clone();
            // Pattern-match must hit a concrete arm — exhaustive
            // match here would force a compile error if a variant
            // is added.
            match c {
                DbDownloadErrorKind::Untrusted
                | DbDownloadErrorKind::Network
                | DbDownloadErrorKind::ManifestUnavailable
                | DbDownloadErrorKind::InvalidSignature => (),
            }
        }
    }

    #[test]
    fn db_update_info_carries_every_field_through() {
        let core = lfs_core::update::orchestrator::UpdateInfo {
            latest_version: "2.0.0".into(),
            current_version: "1.0.0".into(),
            release_url: "https://example.org/release/2.0".into(),
            asset_url: Some("https://example.org/asset.dmg".into()),
            asset_digest: Some("abcdef".into()),
            changelog: Some("# 2.0\n- new".into()),
        };
        let db: DbUpdateInfo = core.into();
        assert_eq!(db.latest_version, "2.0.0");
        assert_eq!(db.current_version, "1.0.0");
        assert_eq!(db.release_url, "https://example.org/release/2.0");
        assert_eq!(
            db.asset_url.as_deref(),
            Some("https://example.org/asset.dmg")
        );
        assert_eq!(db.asset_digest.as_deref(), Some("abcdef"));
        assert!(db.changelog.is_some());
    }

    #[test]
    fn db_downloaded_asset_clone_round_trip() {
        let v = DbDownloadedAsset {
            asset_path: "/tmp/asset".into(),
            manifest_path: "/tmp/manifest".into(),
            manifest_sig_path: "/tmp/manifest.sig".into(),
        };
        let c = v.clone();
        assert_eq!(c.asset_path, "/tmp/asset");
        assert_eq!(c.manifest_path, "/tmp/manifest");
        assert_eq!(c.manifest_sig_path, "/tmp/manifest.sig");
    }
}
