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
//! The HTTP fetch + cert-pinning + Ed25519 verify plumbing
//! stays Dart-side for now (separate arc — needs `reqwest` +
//! `rustls`); these helpers are the small pure-function piece
//! that runs whether or not the Rust HTTP stack is wired.

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

/// Map an OS name (`Platform.operatingSystem` value) to the
/// release asset filename suffix the CI bakes for that target.
/// `None` for platforms with no self-update channel
/// (iOS / fuchsia / …).
pub fn asset_suffix(platform: &str) -> Option<&'static str> {
    match platform {
        "linux" => Some("-linux-x64.AppImage"),
        "windows" => Some("-windows-x64-setup.exe"),
        "macos" => Some("-macos-universal.dmg"),
        "android" => Some("-android-arm64.apk"),
        _ => None,
    }
}

/// Extract the semver version from a release asset filename.
/// Mirrors `UpdateService._parseAssetVersion` regex
/// `^letsflutssh-([0-9]+\.[0-9]+\.[0-9]+)-`.
pub fn parse_asset_version(asset_name: &str) -> Option<String> {
    let rest = asset_name.strip_prefix("letsflutssh-")?;
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
mod tests {
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
    fn asset_suffix_known_platforms() {
        assert_eq!(asset_suffix("linux"), Some("-linux-x64.AppImage"));
        assert_eq!(asset_suffix("macos"), Some("-macos-universal.dmg"));
        assert_eq!(asset_suffix("windows"), Some("-windows-x64-setup.exe"));
        assert_eq!(asset_suffix("android"), Some("-android-arm64.apk"));
    }

    #[test]
    fn asset_suffix_unknown_platforms_none() {
        assert_eq!(asset_suffix("ios"), None);
        assert_eq!(asset_suffix("fuchsia"), None);
        assert_eq!(asset_suffix(""), None);
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
}
