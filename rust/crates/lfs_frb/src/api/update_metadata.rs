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
    match lfs_core::update_metadata::compare_versions(&a, &b) {
        std::cmp::Ordering::Less => DbVersionOrder::Less,
        std::cmp::Ordering::Equal => DbVersionOrder::Equal,
        std::cmp::Ordering::Greater => DbVersionOrder::Greater,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_is_trusted_release_asset_uri(uri: String) -> bool {
    lfs_core::update_metadata::is_trusted_release_asset_uri(&uri)
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_asset_suffix(platform: String) -> Option<String> {
    lfs_core::update_metadata::asset_suffix(&platform).map(|s| s.to_string())
}

#[flutter_rust_bridge::frb(sync)]
pub fn update_parse_asset_version(asset_name: String) -> Option<String> {
    lfs_core::update_metadata::parse_asset_version(&asset_name)
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
    lfs_core::update_metadata::parse_sha256_manifest(&content)
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

impl From<DbChangelogRelease> for lfs_core::update_metadata::ChangelogRelease {
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
    let core_releases: Vec<lfs_core::update_metadata::ChangelogRelease> =
        releases.into_iter().map(Into::into).collect();
    lfs_core::update_metadata::build_cumulative_changelog(&core_releases, &current_version)
}
