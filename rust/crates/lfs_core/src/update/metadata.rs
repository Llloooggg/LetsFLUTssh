//! Pure-function helpers for the auto-update channel.
//!
//! Mirrors the parsing / string-rule helpers in
//! `UpdateService` byte-for-byte:
//!   - semver compare ([`compare_versions`])
//!   - trusted release-asset URI predicate
//!     ([`is_trusted_release_asset_uri`])
//!   - platform-specific asset filename suffix
//!     ([`asset_suffix`])
//!   - regex-shaped version extraction from a release asset
//!     filename ([`parse_asset_version`])
//!   - `sha256sum`-format manifest parser
//!     ([`parse_sha256_manifest`])
//!   - cumulative changelog walker
//!     ([`build_cumulative_changelog`])
//!
//! HTTP fetch + Ed25519 verify plumbing live next door in
//! [`crate::update::http`] / [`crate::update::orchestrator`];
//! this module is the small
//! pure-function half — semver compare, asset-URI predicate,
//! filename heuristics, manifest parsing, changelog walker.

use std::collections::HashMap;

/// Compare two semver strings. Returns `Ordering::Greater` when
/// `a > b`. Mirrors `UpdateInfo.compareVersions`: tolerates a
/// leading `v`, missing components default to 0, non-numeric
/// components also default to 0.
pub fn compare_versions(a: &str, b: &str) -> std::cmp::Ordering {
    let pa = parse_version(a);
    let pb = parse_version(b);
    pa.cmp(&pb)
}

fn parse_version(v: &str) -> [i64; 3] {
    let cleaned = v.strip_prefix('v').unwrap_or(v);
    let mut out = [0i64; 3];
    for (i, part) in cleaned.split('.').take(3).enumerate() {
        out[i] = part.parse().unwrap_or(0);
    }
    out
}

/// True when `uri` is HTTPS and a host GitHub uses for release
/// assets or the Releases API. Accepts:
///   - `github.com` — release HTML / direct download routes,
///   - `*.github.com` — `api.github.com` (Releases JSON) plus any
///     other GitHub-served subdomain that ships a release asset,
///   - `*.githubusercontent.com` — the asset CDN that
///     `browser_download_url` redirects into.
///
/// Everything else fails closed. Parses host-only with a tiny
/// scheme + authority extractor — no `url` crate dep for a few
/// lines of allowlist matching.
pub fn is_trusted_release_asset_uri(uri: &str) -> bool {
    let after_scheme = match uri.strip_prefix("https://") {
        Some(rest) => rest,
        None => return false,
    };
    let host_end = after_scheme
        .find(['/', '?', '#', ':'])
        .unwrap_or(after_scheme.len());
    let host = &after_scheme[..host_end];
    if host.is_empty() {
        return false;
    }
    host == "github.com"
        || host.ends_with(".github.com")
        || host.ends_with(".githubusercontent.com")
}

/// Map a `(os, arch)` pair to the release asset filename suffix the
/// CI bakes for that target. `os` is a `Platform.operatingSystem`
/// value; `arch` is the normalised host arch (`x64` / `arm64` /
/// `arm32`) from [`crate::update::orchestrator::host_arch`]. `None`
/// for platforms with no self-update channel (iOS / fuchsia / …) and
/// for arch combinations CI does not publish.
///
/// macOS ships a single universal binary, so its suffix is
/// arch-independent. Every other OS publishes per-arch assets — an
/// arm64 host must not be handed the x64 artefact (it would fail to
/// install on Android, and self-update to the wrong binary on Linux).
/// The suffix is the format the in-app updater applies in place
/// (AppImage on Linux, setup.exe on Windows, apk on Android); the
/// deb / rpm / tar.gz variants are for package-manager installs that
/// update through their own channel, not this one.
pub fn asset_suffix(os: &str, arch: &str) -> Option<&'static str> {
    match (os, arch) {
        ("linux", "x64") => Some("-linux-x64.AppImage"),
        ("linux", "arm64") => Some("-linux-arm64.AppImage"),
        ("windows", "x64") => Some("-windows-x64-setup.exe"),
        ("windows", "arm64") => Some("-windows-arm64-setup.exe"),
        ("macos", _) => Some("-macos-universal.dmg"),
        ("android", "arm64") => Some("-android-arm64.apk"),
        ("android", "arm32") => Some("-android-arm32.apk"),
        ("android", "x64") => Some("-android-x64.apk"),
        _ => None,
    }
}

/// Find the GitHub release asset matching the host platform's
/// expected suffix from a list of `(name, browser_download_url)`
/// pairs. Returns the URL of the first match, or `None` when no
/// asset's `name` ends with the platform's suffix (or the
/// platform itself has no self-update channel).
///
/// Called from `update_orchestrator::check_for_update_from_body`
/// after the Dart `UpdateService` hands the pre-fetched releases
/// JSON across the FRB boundary; the same allowlist
/// (`asset_suffix`) gates both the orchestrator's pick and the
/// FRB shim that surfaces individual lookups for tests.
pub fn asset_url_for_platform<'a, I>(assets: I, os: &str, arch: &str) -> Option<String>
where
    I: IntoIterator<Item = (&'a str, &'a str)>,
{
    let suffix = asset_suffix(os, arch)?;
    for (name, url) in assets {
        if name.ends_with(suffix) {
            return Some(url.to_string());
        }
    }
    None
}

/// Filename prefix shared by every release artefact
/// (`letsflutssh-<version>-<platform>…`, `letsflutssh-<version>.sha256sums`
/// and its `.sig`). Must match the asset names the release workflow
/// produces (`.github/workflows/build-release.yml`); the update flow
/// both builds (manifest name) and sweeps (stale-download cleanup)
/// artefacts off this single prefix.
pub const RELEASE_ASSET_PREFIX: &str = "letsflutssh-";

/// Extract the semver version from a release asset filename.
/// Mirrors `UpdateService._parseAssetVersion` regex
/// `^letsflutssh-([0-9]+\.[0-9]+\.[0-9]+)-`.
pub fn parse_asset_version(asset_name: &str) -> Option<String> {
    let rest = asset_name.strip_prefix(RELEASE_ASSET_PREFIX)?;
    let dash = rest.find('-')?;
    let candidate = &rest[..dash];
    // Validate `<digits>.<digits>.<digits>` — three numeric
    // components separated by dots.
    let mut parts = candidate.split('.');
    let p1 = parts.next()?;
    let p2 = parts.next()?;
    let p3 = parts.next()?;
    if parts.next().is_some() {
        return None;
    }
    if !p1.bytes().all(|b| b.is_ascii_digit())
        || !p2.bytes().all(|b| b.is_ascii_digit())
        || !p3.bytes().all(|b| b.is_ascii_digit())
        || p1.is_empty()
        || p2.is_empty()
        || p3.is_empty()
    {
        return None;
    }
    Some(candidate.to_string())
}

/// Parse a `sha256sum`-format manifest into a `{name: hash}`
/// map. Accepts both text mode (`<hash>  <name>`) and binary
/// mode (`<hash> *<name>`). Blank lines and `#` comments are
/// skipped.
pub fn parse_sha256_manifest(content: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let space_idx = match line.find(char::is_whitespace) {
            Some(i) if i > 0 => i,
            _ => continue,
        };
        let hash = &line[..space_idx];
        let mut name = line[space_idx..].trim_start();
        if let Some(stripped) = name.strip_prefix('*') {
            name = stripped;
        }
        if hash.len() != 64 || name.is_empty() {
            continue;
        }
        out.insert(name.to_string(), hash.to_string());
    }
    out
}

/// One release entry the changelog builder reads from. Mirrors
/// the shape `UpdateService.checkForUpdate` parses out of the
/// GitHub Releases API JSON — the FRB caller hands us tag + body
/// pre-extracted so we don't need a JSON parser here.
#[derive(Debug, Clone)]
pub struct ChangelogRelease {
    pub tag: String,
    pub body: String,
}

/// Walk the release list (newest → oldest) and concatenate the
/// release notes for every version strictly newer than
/// `current_version`. Stops on the first release at-or-below the
/// current version. Returns `None` when nothing remains.
pub fn build_cumulative_changelog(
    releases: &[ChangelogRelease],
    current_version: &str,
) -> Option<String> {
    let mut buf = String::new();
    for release in releases {
        let ver = release.tag.strip_prefix('v').unwrap_or(&release.tag);
        if compare_versions(ver, current_version) != std::cmp::Ordering::Greater {
            break;
        }
        let body = release.body.trim();
        if body.is_empty() {
            continue;
        }
        if !buf.is_empty() {
            buf.push('\n');
        }
        buf.push_str("## ");
        buf.push_str(&release.tag);
        buf.push('\n');
        buf.push_str(body);
        buf.push('\n');
    }
    let trimmed = buf.trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}
#[cfg(test)]
#[path = "../../tests/unit/update_metadata.rs"]
mod tests;
