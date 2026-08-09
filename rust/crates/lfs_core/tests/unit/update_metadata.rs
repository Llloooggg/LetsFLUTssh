/// Unit tests extracted from update/metadata.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::cmp::Ordering;

#[test]
fn semver_compare_basic() {
    assert_eq!(compare_versions("1.2.3", "1.2.3"), Ordering::Equal);
    assert_eq!(compare_versions("1.2.4", "1.2.3"), Ordering::Greater);
    assert_eq!(compare_versions("1.2.3", "1.2.4"), Ordering::Less);
    assert_eq!(compare_versions("2.0.0", "1.99.99"), Ordering::Greater);
}

#[test]
fn semver_compare_strips_v_prefix() {
    assert_eq!(compare_versions("v1.2.3", "1.2.3"), Ordering::Equal);
    assert_eq!(compare_versions("v2.0.0", "v1.0.0"), Ordering::Greater);
}

#[test]
fn semver_compare_missing_components_default_zero() {
    assert_eq!(compare_versions("1.2", "1.2.0"), Ordering::Equal);
    assert_eq!(compare_versions("1", "1.0.0"), Ordering::Equal);
    assert_eq!(compare_versions("1.0.0", "1"), Ordering::Equal);
}

#[test]
fn semver_compare_garbage_treated_as_zero() {
    assert_eq!(compare_versions("abc", "0.0.0"), Ordering::Equal);
    assert_eq!(compare_versions("1.x.3", "1.0.3"), Ordering::Equal);
}

#[test]
fn trusted_uri_accepts_github_canonical() {
    assert!(is_trusted_release_asset_uri(
        "https://github.com/owner/repo/releases/download/v1/asset.lfs"
    ));
    assert!(is_trusted_release_asset_uri(
        "https://objects.githubusercontent.com/some/path"
    ));
    // Releases API lives on api.github.com — has to be accepted
    // for `UpdateService.checkForUpdate` to read the release list.
    assert!(is_trusted_release_asset_uri(
        "https://api.github.com/repos/owner/repo/releases?per_page=30"
    ));
    assert!(is_trusted_release_asset_uri(
        "https://raw.githubusercontent.com/owner/repo/main/README.md"
    ));
}

#[test]
fn trusted_uri_rejects_non_https() {
    assert!(!is_trusted_release_asset_uri(
        "http://github.com/owner/repo/releases/download/v1/asset.lfs"
    ));
    assert!(!is_trusted_release_asset_uri("ftp://github.com/x"));
}

#[test]
fn trusted_uri_rejects_unrelated_hosts() {
    assert!(!is_trusted_release_asset_uri("https://evil.com/x"));
    assert!(!is_trusted_release_asset_uri(
        "https://github.com.evil.com/x"
    ));
    // `*.github.com` allowance must not match a confusable like
    // `evil-github.com` — the suffix has the leading dot.
    assert!(!is_trusted_release_asset_uri("https://evil-github.com/x"));
    assert!(!is_trusted_release_asset_uri(""));
    assert!(!is_trusted_release_asset_uri("https://"));
}

#[test]
fn asset_suffix_known_targets() {
    assert_eq!(asset_suffix("linux", "x64"), Some("-linux-x64.AppImage"));
    assert_eq!(
        asset_suffix("linux", "arm64"),
        Some("-linux-arm64.AppImage")
    );
    assert_eq!(
        asset_suffix("windows", "x64"),
        Some("-windows-x64-setup.exe")
    );
    assert_eq!(
        asset_suffix("windows", "arm64"),
        Some("-windows-arm64-setup.exe")
    );
    assert_eq!(asset_suffix("android", "arm64"), Some("-android-arm64.apk"));
    assert_eq!(asset_suffix("android", "arm32"), Some("-android-arm32.apk"));
    assert_eq!(asset_suffix("android", "x64"), Some("-android-x64.apk"));
}

#[test]
fn asset_suffix_macos_is_universal_for_any_arch() {
    // macOS ships one universal binary — both host arches resolve
    // to the same dmg, never a per-arch asset.
    assert_eq!(asset_suffix("macos", "x64"), Some("-macos-universal.dmg"));
    assert_eq!(asset_suffix("macos", "arm64"), Some("-macos-universal.dmg"));
}

#[test]
fn asset_suffix_unknown_targets_none() {
    assert_eq!(asset_suffix("ios", "arm64"), None);
    assert_eq!(asset_suffix("fuchsia", "x64"), None);
    assert_eq!(asset_suffix("", ""), None);
    // Known OS, arch CI does not publish → no match (no silent
    // fallback to a different arch's binary).
    assert_eq!(asset_suffix("linux", "arm32"), None);
    assert_eq!(asset_suffix("windows", "arm32"), None);
    assert_eq!(asset_suffix("linux", "unknown"), None);
}

#[test]
fn asset_url_for_platform_returns_first_suffix_match() {
    let assets = [
        ("letsflutssh-5.9.0-android-arm64.apk", "https://a/and"),
        ("letsflutssh-5.9.0-linux-x64.AppImage", "https://a/lin"),
        ("letsflutssh-5.9.0-windows-x64-setup.exe", "https://a/win"),
    ];
    assert_eq!(
        asset_url_for_platform(assets.iter().copied(), "linux", "x64").as_deref(),
        Some("https://a/lin"),
    );
    assert_eq!(
        asset_url_for_platform(assets.iter().copied(), "windows", "x64").as_deref(),
        Some("https://a/win"),
    );
}

#[test]
fn asset_url_for_platform_picks_host_arch_asset() {
    // An arm64 host must select the arm64 asset, not the x64 one
    // that ships in the same release.
    let assets = [
        ("letsflutssh-5.9.0-linux-x64.AppImage", "https://a/x64"),
        ("letsflutssh-5.9.0-linux-arm64.AppImage", "https://a/arm64"),
    ];
    assert_eq!(
        asset_url_for_platform(assets.iter().copied(), "linux", "arm64").as_deref(),
        Some("https://a/arm64"),
    );
    assert_eq!(
        asset_url_for_platform(assets.iter().copied(), "linux", "x64").as_deref(),
        Some("https://a/x64"),
    );
}

#[test]
fn asset_url_for_platform_unknown_platform_is_none() {
    let assets = [("letsflutssh-5.9.0-linux-x64.AppImage", "https://a/lin")];
    assert!(asset_url_for_platform(assets.iter().copied(), "ios", "arm64").is_none());
    assert!(asset_url_for_platform(assets.iter().copied(), "", "").is_none());
}

#[test]
fn asset_url_for_platform_no_match_returns_none() {
    // Suffix lookup succeeds (linux/x64 is known), but no asset
    // carries the matching suffix — filter releases that
    // dropped a platform mid-cycle. Caller falls back to the
    // GitHub release page.
    let assets = [("letsflutssh-5.9.0-android-arm64.apk", "https://a/and")];
    assert!(asset_url_for_platform(assets.iter().copied(), "linux", "x64").is_none());
}

#[test]
fn parse_asset_version_extracts_semver() {
    assert_eq!(
        parse_asset_version("letsflutssh-5.9.0-linux-x64.AppImage"),
        Some("5.9.0".to_string()),
    );
    assert_eq!(
        parse_asset_version("letsflutssh-1.2.3-android-arm64.apk"),
        Some("1.2.3".to_string()),
    );
}

#[test]
fn parse_asset_version_rejects_malformed() {
    assert_eq!(parse_asset_version("letsflutssh-linux"), None);
    assert_eq!(parse_asset_version("letsflutssh-1.2-linux"), None);
    assert_eq!(parse_asset_version("letsflutssh-abc-linux"), None);
    assert_eq!(parse_asset_version("other-1.2.3-linux"), None);
    assert_eq!(parse_asset_version(""), None);
}

#[test]
fn manifest_parser_text_and_binary_modes() {
    let content = "\
abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789  asset1.lfs
1111111111111111111111111111111111111111111111111111111111111111 *asset2.exe
";
    let map = parse_sha256_manifest(content);
    assert_eq!(map.len(), 2);
    assert_eq!(
        map.get("asset1.lfs"),
        Some(&"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789".to_string())
    );
    assert_eq!(
        map.get("asset2.exe"),
        Some(&"1111111111111111111111111111111111111111111111111111111111111111".to_string())
    );
}

#[test]
fn manifest_parser_skips_blank_and_comment_lines() {
    let content = "\
# leading comment

# blank line above

abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789  asset.lfs
";
    let map = parse_sha256_manifest(content);
    assert_eq!(map.len(), 1);
}

#[test]
fn manifest_parser_drops_invalid_hashes() {
    let content = "\
shorthash  asset1.lfs
abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789
abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789  asset.lfs
";
    let map = parse_sha256_manifest(content);
    assert_eq!(map.len(), 1);
    assert!(map.contains_key("asset.lfs"));
}

#[test]
fn changelog_concatenates_newer_releases() {
    let releases = vec![
        ChangelogRelease {
            tag: "v3.0.0".into(),
            body: "Top".into(),
        },
        ChangelogRelease {
            tag: "v2.0.0".into(),
            body: "Mid".into(),
        },
        ChangelogRelease {
            tag: "v1.0.0".into(),
            body: "Old".into(),
        },
    ];
    let out = build_cumulative_changelog(&releases, "1.5.0").unwrap();
    assert!(out.contains("## v3.0.0"));
    assert!(out.contains("Top"));
    assert!(out.contains("## v2.0.0"));
    assert!(out.contains("Mid"));
    assert!(!out.contains("Old"));
}

#[test]
fn changelog_returns_none_when_current_is_latest() {
    let releases = vec![ChangelogRelease {
        tag: "v1.0.0".into(),
        body: "x".into(),
    }];
    assert_eq!(build_cumulative_changelog(&releases, "1.0.0"), None);
}

#[test]
fn changelog_skips_empty_bodies() {
    let releases = vec![
        ChangelogRelease {
            tag: "v3.0.0".into(),
            body: "  ".into(),
        },
        ChangelogRelease {
            tag: "v2.0.0".into(),
            body: "real".into(),
        },
    ];
    let out = build_cumulative_changelog(&releases, "1.0.0").unwrap();
    assert!(!out.contains("## v3.0.0"));
    assert!(out.contains("## v2.0.0"));
}
