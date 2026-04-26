//! FRB adapter for `lfs_core::update_http` — the auto-update
//! HTTP fetch path.

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
