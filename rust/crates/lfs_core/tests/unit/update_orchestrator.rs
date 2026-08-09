/// Unit tests extracted from update/orchestrator.rs
/// Declared via `#[path] mod tests;` in the source file.
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
fn host_arch_normalises_to_documented_tokens() {
    // `std::env::consts::ARCH` isn't overridable; assert the
    // function only ever yields a token `asset_suffix` understands.
    let a = host_arch();
    assert!(matches!(a, "x64" | "arm64" | "arm32" | "unknown"));
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
        stale_download_suffix("https://example/letsflutssh-1.9.0-linux-x64.AppImage").as_deref(),
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
