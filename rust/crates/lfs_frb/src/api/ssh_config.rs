//! FRB adapter for `lfs_core::ssh_config`.
//!
//! Surfaces the OpenSSH config parser as a synchronous one-shot.
//! `Include` directives are NOT expanded Rust-side — the FRB
//! boundary cannot easily marshal a callback for the include
//! reader. Callers either pre-expand includes Dart-side and pass
//! the fully-expanded content here, or rely on the Dart parser
//! for now.

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
