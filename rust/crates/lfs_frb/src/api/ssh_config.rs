//! FRB adapter for `lfs_core::ssh_config`.
//!
//! Three sync entry points cover every caller:
//!
//! * [`parse_openssh_config`] — no `Include` expansion. Used by
//!   callers that want a pure parse with no filesystem touch.
//! * [`parse_openssh_config_resolving`] — production path. Routes
//!   through `lfs_core::ssh_config::parse_openssh_config_with_fs`
//!   so include directives, glob expansion, cycle detection, and
//!   the per-file size cap all live Rust-side.
//! * [`parse_openssh_config_with_includes`] — test seam. Caller
//!   pre-supplies a `path → content` map; useful for unit tests
//!   that don't want to stage files on disk.
//!
//! The grammar primitives (`glob_matches`, `strip_comment`,
//! `split_keyword_value`, `split_host_patterns`, `unquote`) are
//! exposed alongside so the Dart-side test include-map collector
//! can apply identical lexing without re-implementing it.

/// FRB-visible mirror of `lfs_core::ssh_config::AuthType`.
#[derive(Debug, Clone, Copy)]
pub enum DbOpenSshAuthType {
    Password,
    Key,
}

impl From<lfs_core::ssh_config::AuthType> for DbOpenSshAuthType {
    fn from(a: lfs_core::ssh_config::AuthType) -> Self {
        match a {
            lfs_core::ssh_config::AuthType::Password => DbOpenSshAuthType::Password,
            lfs_core::ssh_config::AuthType::Key => DbOpenSshAuthType::Key,
        }
    }
}

/// FRB-visible mirror of `lfs_core::ssh_config::HostEntry`.
#[derive(Debug, Clone)]
pub struct DbOpenSshHostEntry {
    pub host: String,
    pub host_name: Option<String>,
    pub user: Option<String>,
    pub port: Option<u32>,
    pub identity_files: Vec<String>,
    pub preferred_auth_types: Option<Vec<DbOpenSshAuthType>>,
}

impl From<lfs_core::ssh_config::HostEntry> for DbOpenSshHostEntry {
    fn from(e: lfs_core::ssh_config::HostEntry) -> Self {
        DbOpenSshHostEntry {
            host: e.host,
            host_name: e.host_name,
            user: e.user,
            port: e.port.map(|p| p as u32),
            identity_files: e.identity_files,
            preferred_auth_types: e
                .preferred_auth_types
                .map(|v| v.into_iter().map(DbOpenSshAuthType::from).collect()),
        }
    }
}

/// Parse OpenSSH config content with no `Include` expansion.
/// Returns one entry per concrete host; wildcard / negation
/// blocks fold into the concretes.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_openssh_config(content: String) -> Vec<DbOpenSshHostEntry> {
    let no_includes = |_: &str| -> Option<String> { None };
    lfs_core::ssh_config::parse_openssh_config(&content, &no_includes, "", 0)
        .into_iter()
        .map(DbOpenSshHostEntry::from)
        .collect()
}

/// Parse OpenSSH config content + resolve `Include` directives
/// against the real filesystem. Glob tokens (`config.d/*`) walk
/// the parent directory; per-file size capped at 1 MiB; cycle
/// detection via a visited set; `max_include_depth` bounds
/// recursion. Production callers route through here so the
/// filesystem walk lives Rust-side; tests that need to inject
/// canned content stay on
/// [`parse_openssh_config_with_includes`] which takes a
/// path → content map.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_openssh_config_resolving(
    content: String,
    base_dir: String,
    max_include_depth: u32,
) -> Vec<DbOpenSshHostEntry> {
    lfs_core::ssh_config::parse_openssh_config_with_fs(
        &content,
        &base_dir,
        max_include_depth as usize,
    )
    .into_iter()
    .map(DbOpenSshHostEntry::from)
    .collect()
}

/// Same as [`parse_openssh_config`] but resolves `Include`
/// directives against [`includes`] — Dart pre-reads each
/// referenced file (handling glob expansion + filesystem walks
/// itself) and hands a `path → content` map across the boundary.
/// Paths that aren't in the map silently no-op, mirroring the
/// Dart `IncludeReader` returning `null`.
///
/// `base_dir` anchors relative `Include` paths the same way the
/// underlying parser does. `max_include_depth` bounds recursion;
/// pass the same default the Dart parser uses (8) for parity.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_openssh_config_with_includes(
    content: String,
    base_dir: String,
    includes: std::collections::HashMap<String, String>,
    max_include_depth: u32,
) -> Vec<DbOpenSshHostEntry> {
    let reader = |p: &str| -> Option<String> { includes.get(p).cloned() };
    lfs_core::ssh_config::parse_openssh_config(
        &content,
        &reader,
        &base_dir,
        max_include_depth as usize,
    )
    .into_iter()
    .map(DbOpenSshHostEntry::from)
    .collect()
}

/// Minimal OpenSSH-style glob match. `*` matches any run, `?`
/// matches exactly one char, anything else literal. Same grammar
/// as the parser's internal pattern matcher; exposed so the Dart
/// `Include`-directive expander (which keeps filesystem walks
/// Dart-side for per-platform path semantics) can reuse the
/// canonical implementation rather than compile its own regex.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_config_glob_matches(pattern: String, text: String) -> bool {
    lfs_core::ssh_config::glob_matches(&pattern, &text)
}

/// Strip a `#`-prefixed comment (outside quoted strings).
/// Mirrors the parser's internal pre-processing pass so the
/// Dart Include-directive expander applies the same grammar.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_config_strip_comment(line: String) -> String {
    lfs_core::ssh_config::strip_comment(&line)
}

/// Split a `keyword value` or `keyword = value` config line into
/// `(keyword, value)`. Returns `None` for blank / malformed lines.
/// The value is unquoted; quoting rules match `ssh_config(5)`.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_config_split_keyword_value(line: String) -> Option<(String, String)> {
    lfs_core::ssh_config::split_keyword_value(&line)
}

/// Split a Host / Include value into whitespace-separated
/// patterns, preserving spaces inside `"…"` quoted runs.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_config_split_host_patterns(value: String) -> Vec<String> {
    lfs_core::ssh_config::split_host_patterns(&value)
}

/// Strip a single matched pair of leading/trailing `"`. Mirrors
/// the OpenSSH config grammar: `Host "my workstation"` keeps
/// the single token, `Host my workstation` is two tokens. The
/// Dart `openssh_config_parser._unquote` routes through here.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_config_unquote(value: String) -> String {
    lfs_core::ssh_config::unquote(&value).to_string()
}

/// Walk every `Include` directive in [`content`] and return the
/// single-level resolved paths in encounter order. No recursion,
/// no filesystem touch, no glob expansion — each token resolves
/// through the same tilde + relative-anchor rules the in-memory
/// parser applies.
///
/// Used by the Dart test-seam include-map collector
/// (`openssh_config_parser._collectIncludeMap`): the visited-set
/// + recursion stay Dart-side because the `IncludeReader` callback
/// is Dart-side, but the per-line grammar lives in one place. The
/// production path is [`parse_openssh_config_resolving`] which
/// owns the whole walk Rust-side.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_config_resolve_include_paths(content: String, base_dir: String) -> Vec<String> {
    lfs_core::ssh_config::resolve_include_paths_for_content(&content, &base_dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn parse_openssh_config_extracts_host_block_fields() {
        let cfg = "\
Host edge\n\
    HostName edge.example.com\n\
    User deploy\n\
    Port 2222\n\
    IdentityFile ~/.ssh/edge_ed25519\n";
        let entries = parse_openssh_config(cfg.into());
        assert_eq!(entries.len(), 1);
        let e = &entries[0];
        assert_eq!(e.host, "edge");
        assert_eq!(e.host_name.as_deref(), Some("edge.example.com"));
        assert_eq!(e.user.as_deref(), Some("deploy"));
        assert_eq!(e.port, Some(2222));
        assert_eq!(e.identity_files.len(), 1);
    }

    #[test]
    fn parse_openssh_config_returns_empty_for_blank_input() {
        assert!(parse_openssh_config(String::new()).is_empty());
    }

    #[test]
    fn parse_openssh_config_with_includes_no_includes_directives_passes_through() {
        // The path-keying contract for the include map (relative vs
        // absolute, base_dir-anchored, OpenSSH `~/` expansion) lives
        // in `lfs_core::ssh_config` and is covered by the integration
        // suite there. Pin only the contract that an empty map +
        // include-free content round-trips — this catches a future
        // refactor that accidentally wires the no-include path
        // through the `with_includes` shape.
        let cfg = "\
Host plain\n\
    HostName plain.example.com\n";
        let entries =
            parse_openssh_config_with_includes(cfg.into(), String::new(), HashMap::new(), 8);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].host, "plain");
    }

    #[test]
    fn glob_matches_handles_star_question_and_literal() {
        assert!(ssh_config_glob_matches(
            "*.example.com".into(),
            "edge.example.com".into()
        ));
        assert!(ssh_config_glob_matches("h?st".into(), "host".into()));
        assert!(!ssh_config_glob_matches("h?st".into(), "haaast".into()));
        assert!(!ssh_config_glob_matches(
            "*.example.com".into(),
            "example.org".into()
        ));
        assert!(ssh_config_glob_matches("literal".into(), "literal".into()));
    }

    #[test]
    fn strip_comment_removes_unquoted_hash_run() {
        assert_eq!(
            ssh_config_strip_comment("Host edge # trailing".into()),
            "Host edge "
        );
        assert_eq!(ssh_config_strip_comment("# pure comment".into()), "");
    }

    #[test]
    fn strip_comment_preserves_hash_inside_quotes() {
        // Pin the contract — `#` inside `"…"` is literal, not a
        // comment marker. The Dart Include-expander relies on it.
        assert_eq!(
            ssh_config_strip_comment("Host \"name #1\"".into()),
            "Host \"name #1\""
        );
    }

    #[test]
    fn split_keyword_value_handles_space_and_equals() {
        assert_eq!(
            ssh_config_split_keyword_value("Host edge".into()),
            Some(("Host".to_string(), "edge".to_string()))
        );
        assert_eq!(
            ssh_config_split_keyword_value("Port=2222".into()),
            Some(("Port".to_string(), "2222".to_string()))
        );
        assert!(ssh_config_split_keyword_value(String::new()).is_none());
    }

    #[test]
    fn split_host_patterns_keeps_quoted_runs_intact() {
        let parts = ssh_config_split_host_patterns("edge \"my workstation\" prod-*".into());
        assert_eq!(parts.len(), 3);
        assert!(parts.iter().any(|p| p == "my workstation"));
    }

    #[test]
    fn unquote_strips_only_matched_outer_quotes() {
        assert_eq!(ssh_config_unquote("\"quoted\"".into()), "quoted");
        assert_eq!(ssh_config_unquote("plain".into()), "plain");
        // Unmatched leading quote — left as-is.
        assert_eq!(ssh_config_unquote("\"unbalanced".into()), "\"unbalanced");
    }

    #[test]
    fn db_openssh_auth_type_maps_each_variant_distinctly() {
        let p: DbOpenSshAuthType = lfs_core::ssh_config::AuthType::Password.into();
        let k: DbOpenSshAuthType = lfs_core::ssh_config::AuthType::Key.into();
        assert!(matches!(p, DbOpenSshAuthType::Password));
        assert!(matches!(k, DbOpenSshAuthType::Key));
    }

    #[test]
    fn resolve_include_paths_anchors_relative_tokens_against_base_dir() {
        // Pin the FRB contract: relative tokens get anchored,
        // absolute ones pass through. The Dart caller's visited-set
        // deduplication relies on the canonical anchored form.
        let sep = if cfg!(windows) { '\\' } else { '/' };
        let out = ssh_config_resolve_include_paths(
            "Include extras\nInclude /etc/ssh/ssh_config\n".into(),
            "/cfg".into(),
        );
        assert_eq!(
            out,
            vec![
                format!("/cfg{sep}extras"),
                "/etc/ssh/ssh_config".to_string(),
            ]
        );
    }

    #[test]
    fn resolve_include_paths_returns_empty_for_include_free_content() {
        let out =
            ssh_config_resolve_include_paths("Host x\n    HostName y\n".into(), "/cfg".into());
        assert!(out.is_empty());
    }
}
