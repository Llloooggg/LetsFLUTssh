//! FRB adapter for `lfs_core::update_metadata`. Synchronous —
//! pure-function helpers over short strings; no IO, no
//! contention. The Dart `UpdateService` wraps these so semver
//! compare, asset matching, manifest parsing, and changelog
//! composition stay in one canonical place.

/// FRB mirror of `Ordering` — Dart enum-friendly.
pub enum DbVersionOrder {
    Less,
    Equal,
    Greater,
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_compare_versions(a: String, b: String) -> DbVersionOrder {
    match lfs_core::update::metadata::compare_versions(&a, &b) {
        std::cmp::Ordering::Less => DbVersionOrder::Less,
        std::cmp::Ordering::Equal => DbVersionOrder::Equal,
        std::cmp::Ordering::Greater => DbVersionOrder::Greater,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_is_trusted_release_asset_uri(uri: String) -> bool {
    lfs_core::update::metadata::is_trusted_release_asset_uri(&uri)
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_asset_suffix(platform: String) -> Option<String> {
    lfs_core::update::metadata::asset_suffix(&platform).map(|s| s.to_string())
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_parse_asset_version(asset_name: String) -> Option<String> {
    lfs_core::update::metadata::parse_asset_version(&asset_name)
}

/// Single GitHub release asset entry — `(name,
/// browser_download_url)`. Caller flattens the GitHub Releases
/// API JSON's `assets` array into this shape before calling
/// [`update_asset_url_for_platform`].
#[derive(Debug, Clone)]
pub struct DbReleaseAsset {
    pub name: String,
    pub browser_download_url: String,
}

/// Pick the release asset URL whose `name` ends with the
/// platform's expected suffix (`asset_suffix`). Returns `None` for
/// unknown platforms or when no asset matches. Standalone FRB
/// surface kept around for tests; the production update-check
/// path goes through `update_check_from_body`, which calls the
/// underlying `lfs_core::update::metadata::asset_url_for_platform`
/// directly.
#[flutter_rust_bridge::frb(sync)]
pub fn update_asset_url_for_platform(
    assets: Vec<DbReleaseAsset>,
    platform: String,
) -> Option<String> {
    let pairs: Vec<(&str, &str)> = assets
        .iter()
        .map(|a| (a.name.as_str(), a.browser_download_url.as_str()))
        .collect();
    lfs_core::update::metadata::asset_url_for_platform(pairs.into_iter(), &platform)
}

/// Single `(name, hash)` pair from the manifest. Returned as a
/// list because FRB's HashMap support varies across language
/// targets — pairs round-trip cleanly everywhere.
#[derive(Debug, Clone)]
pub struct DbSha256ManifestEntry {
    pub name: String,
    pub hash: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_parse_sha256_manifest(content: String) -> Vec<DbSha256ManifestEntry> {
    lfs_core::update::metadata::parse_sha256_manifest(&content)
        .into_iter()
        .map(|(name, hash)| DbSha256ManifestEntry { name, hash })
        .collect()
}

/// FRB mirror of `ChangelogRelease`. Carries the tag + raw
/// release body as the Dart caller pre-extracted them from the
/// GitHub API JSON.
#[derive(Debug, Clone)]
pub struct DbChangelogRelease {
    pub tag: String,
    pub body: String,
}

impl From<DbChangelogRelease> for lfs_core::update::metadata::ChangelogRelease {
    fn from(c: DbChangelogRelease) -> Self {
        Self {
            tag: c.tag,
            body: c.body,
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_build_cumulative_changelog(
    releases: Vec<DbChangelogRelease>,
    current_version: String,
) -> Option<String> {
    let core_releases: Vec<lfs_core::update::metadata::ChangelogRelease> =
        releases.into_iter().map(Into::into).collect();
    lfs_core::update::metadata::build_cumulative_changelog(&core_releases, &current_version)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compare_versions_orders_semver() {
        assert!(matches!(
            update_compare_versions("1.0.0".into(), "1.0.1".into()),
            DbVersionOrder::Less
        ));
        assert!(matches!(
            update_compare_versions("1.0.1".into(), "1.0.0".into()),
            DbVersionOrder::Greater
        ));
        assert!(matches!(
            update_compare_versions("1.2.3".into(), "1.2.3".into()),
            DbVersionOrder::Equal
        ));
    }

    #[test]
    fn parse_asset_version_extracts_from_filename() {
        // `letsflutssh-X.Y.Z-platform.suffix` → "X.Y.Z". The
        // parser is lowercase-prefix + literal-dash boundary;
        // anything else returns None.
        let v = update_parse_asset_version("letsflutssh-1.2.3-linux-x86_64.AppImage".into());
        assert_eq!(v.as_deref(), Some("1.2.3"));
    }

    #[test]
    fn parse_asset_version_returns_none_on_garbage() {
        assert!(update_parse_asset_version("not-a-release-asset".into()).is_none());
        assert!(update_parse_asset_version("".into()).is_none());
    }

    #[test]
    fn asset_suffix_unknown_platform_returns_none() {
        assert!(update_asset_suffix("plan9".into()).is_none());
        assert!(update_asset_suffix("".into()).is_none());
    }

    #[test]
    fn asset_url_for_platform_returns_none_when_no_match() {
        let assets = vec![DbReleaseAsset {
            name: "LetsFLUTssh-v1.0.0-linux-x86_64.AppImage".into(),
            browser_download_url: "https://example.test/dl".into(),
        }];
        // Unknown platform → no suffix → no match.
        assert!(update_asset_url_for_platform(assets, "plan9".into()).is_none());
    }

    #[test]
    fn parse_sha256_manifest_returns_pairs() {
        // Format: `<hash>  <filename>` per line, two-space gap.
        let content = "\
abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789  LetsFLUTssh-v1.0.0-linux.AppImage\n\
1111111111111111111111111111111111111111111111111111111111111111  LetsFLUTssh-v1.0.0-windows.exe\n";
        let entries = update_parse_sha256_manifest(content.to_string());
        assert!(entries.len() >= 2);
        assert!(entries.iter().any(|e| e.name.contains("AppImage")));
        assert!(entries.iter().any(|e| e.name.contains("windows.exe")));
    }

    #[test]
    fn build_cumulative_changelog_returns_none_when_up_to_date() {
        let releases = vec![DbChangelogRelease {
            tag: "v1.0.0".into(),
            body: "initial".into(),
        }];
        // current == latest → no changelog needed.
        let s = update_build_cumulative_changelog(releases, "1.0.0".into());
        assert!(s.is_none());
    }
}
