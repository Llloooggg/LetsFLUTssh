//! OpenSSH `~/.ssh/config` parser.
//!
//! Mirrors the Dart `parseOpenSshConfig` shape so a future
//! Rust-driven importer produces the same set of host entries.
//! Parses the OpenSSH `Host`-block syntax: line-oriented
//! directives, `#`-prefixed comments, optional `=` separator,
//! quoted values, wildcard / negation `Host` patterns
//! (`*.internal`, `!staging.example.com`), and `Include`
//! directives expanded against an injectable reader.
//!
//! Wildcard handling matches OpenSSH's first-value-wins
//! semantics: a concrete-host entry takes its own block's
//! directives and then fills any unset field from every wildcard
//! block whose pattern matches the host, in file order.
//!
//! The supported directive set is intentionally small —
//! enough for our import flow to reconstruct the connection
//! tuple (`Host`, `HostName`, `User`, `Port`, `IdentityFile`,
//! `PreferredAuthentications`). Unknown directives are silently
//! ignored so unfamiliar configs still produce usable entries.

/// Authentication method we map onto for the importer. Mirrors
/// `lib/core/session/session.dart` `AuthType`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AuthType {
    Password,
    Key,
}

/// One concrete host entry extracted from a config file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostEntry {
    pub host: String,
    pub host_name: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
    pub identity_files: Vec<String>,
    /// `None` when the user did not set `PreferredAuthentications`.
    /// `Some(empty)` is normalised to `None` so callers don't
    /// need to special-case "directive present but every method
    /// unknown".
    pub preferred_auth_types: Option<Vec<AuthType>>,
}

impl HostEntry {
    /// HostName when set, otherwise the Host alias.
    pub fn effective_host(&self) -> &str {
        self.host_name.as_deref().unwrap_or(&self.host)
    }
}

/// Caller-supplied reader for `Include` directives. Returns
/// `None` when the file does not exist / cannot be read.
pub type IncludeReader<'a> = &'a dyn Fn(&str) -> Option<String>;

/// Parse `content` into a list of concrete host entries.
///
/// `base_dir` anchors relative `Include` paths (defaults to
/// `<home>/.ssh` Dart-side). `max_include_depth` bounds recursion
/// so a pathological `Include ./config` does not blow the stack;
/// the Dart parser uses 8 by default.
pub fn parse_openssh_config(
    content: &str,
    include_reader: IncludeReader<'_>,
    base_dir: &str,
    max_include_depth: usize,
) -> Vec<HostEntry> {
    let normalised = normalise_line_endings(content);
    let mut visited: std::collections::HashSet<String> = std::collections::HashSet::new();
    let expanded = expand_includes(
        &normalised,
        include_reader,
        base_dir,
        max_include_depth,
        &mut visited,
    );
    parse_expanded(&expanded)
}

/// Convert CRLF and bare-CR line endings to LF.
///
/// Rust's `str::lines()` only splits on `\n` (with optional preceding
/// `\r`); a config file written on classic Mac OS or pasted from
/// Windows-without-trailing-LF would otherwise collapse onto a
/// single line. Normalise at the entry point so the downstream
/// walkers don't have to think about line endings.
fn normalise_line_endings(content: &str) -> String {
    if !content.contains('\r') {
        return content.to_string();
    }
    content.replace("\r\n", "\n").replace('\r', "\n")
}

/// Per-file size cap for `Include` expansion. Mirrors the Dart
/// default — a multi-megabyte include is almost certainly a
/// hostile config trying to run the parser out of memory; better
/// to silently skip.
const MAX_INCLUDE_FILE_BYTES: u64 = 1024 * 1024;

/// Variant of [`parse_openssh_config`] that performs real
/// filesystem reads + glob enumeration for `Include` directives.
/// The Dart `parseOpenSshConfig` no longer needs to maintain its
/// own glob walker / file reader — this is the single entry point
/// for the production import path.
///
/// Glob support matches `ssh_config(5)`'s OpenSSH 7.x behaviour:
/// `*` and `?` in the basename portion of an include token expand
/// against the parent directory; nested `**` is NOT supported.
/// Individual files exceeding [`MAX_INCLUDE_FILE_BYTES`] are
/// skipped silently. Cycle detection + the `max_include_depth`
/// budget mirror the existing reader-driven path.
pub fn parse_openssh_config_with_fs(
    content: &str,
    base_dir: &str,
    max_include_depth: usize,
) -> Vec<HostEntry> {
    let normalised = normalise_line_endings(content);
    let mut visited: std::collections::HashSet<String> = std::collections::HashSet::new();
    let expanded = expand_includes_with_fs(&normalised, base_dir, max_include_depth, &mut visited);
    parse_expanded(&expanded)
}

fn parse_expanded(expanded: &str) -> Vec<HostEntry> {
    let blocks = parse_blocks(expanded);

    let mut wildcard_blocks: Vec<&RawBlock> = Vec::new();
    let mut concrete: Vec<(usize, &str)> = Vec::new();
    for (i, block) in blocks.iter().enumerate() {
        let mut any_concrete = false;
        for pat in &block.patterns {
            if is_wildcard_pattern(pat) {
                continue;
            }
            any_concrete = true;
            concrete.push((i, pat));
        }
        if !any_concrete || block.patterns.iter().any(|p| is_wildcard_pattern(p)) {
            wildcard_blocks.push(block);
        }
    }

    // Per-host match cost is O(N · M) — every concrete host pattern
    // (N) is checked against every wildcard block (M) so unset fields
    // can cascade in file order. Real-world `~/.ssh/config` rarely
    // exceeds ~100 wildcard blocks even on heavily-templated infra
    // configs; the matcher itself is byte-level glob compare so the
    // product stays in microseconds. A pathological config with
    // thousands of wildcard blocks would still terminate but is not
    // a target shape — the Include-size cap upstream
    // (`MAX_INCLUDE_FILE_BYTES`) bounds total input.
    concrete
        .into_iter()
        .map(|(idx, pat)| resolve_entry(pat, &blocks[idx], &wildcard_blocks))
        .collect()
}

#[derive(Debug, Clone)]
struct RawBlock {
    order_index: usize,
    patterns: Vec<String>,
    host_name: Option<String>,
    user: Option<String>,
    port: Option<u16>,
    identity_files: Vec<String>,
    preferred_auth_types: Option<Vec<AuthType>>,
}

impl RawBlock {
    fn matches(&self, host: &str) -> bool {
        let mut positive = false;
        for raw in &self.patterns {
            let (neg, pat) = if let Some(rest) = raw.strip_prefix('!') {
                (true, rest)
            } else {
                (false, raw.as_str())
            };
            if !glob_matches(pat, host) {
                continue;
            }
            if neg {
                return false;
            }
            positive = true;
        }
        positive
    }
}

fn resolve_entry(host: &str, own: &RawBlock, wildcards: &[&RawBlock]) -> HostEntry {
    let mut host_name: Option<String> = None;
    let mut user: Option<String> = None;
    let mut port: Option<u16> = None;
    let mut preferred: Option<Vec<AuthType>> = None;
    let mut identity_files: Vec<String> = Vec::new();

    let mut ordered: Vec<&RawBlock> = wildcards.to_vec();
    if !ordered.iter().any(|b| std::ptr::eq(*b, own)) {
        ordered.push(own);
    }
    ordered.sort_by_key(|b| b.order_index);

    for block in ordered {
        let is_own = std::ptr::eq(block, own);
        if !is_own && !block.matches(host) {
            continue;
        }
        if host_name.is_none() {
            host_name = block.host_name.clone();
        }
        if user.is_none() {
            user = block.user.clone();
        }
        if port.is_none() {
            port = block.port;
        }
        if preferred.is_none() {
            preferred = block.preferred_auth_types.clone();
        }
        identity_files.extend(block.identity_files.iter().cloned());
    }

    HostEntry {
        host: host.to_string(),
        host_name,
        user,
        port,
        identity_files,
        preferred_auth_types: preferred,
    }
}

fn parse_blocks(content: &str) -> Vec<RawBlock> {
    let mut blocks: Vec<RawBlock> = Vec::new();
    let mut patterns: Option<Vec<String>> = None;
    let mut host_name: Option<String> = None;
    let mut user: Option<String> = None;
    let mut port: Option<u16> = None;
    let mut preferred: Option<Vec<AuthType>> = None;
    let mut identity_files: Vec<String> = Vec::new();

    let flush = |blocks: &mut Vec<RawBlock>,
                 patterns: &mut Option<Vec<String>>,
                 host_name: &mut Option<String>,
                 user: &mut Option<String>,
                 port: &mut Option<u16>,
                 preferred: &mut Option<Vec<AuthType>>,
                 identity_files: &mut Vec<String>| {
        if let Some(p) = patterns.take() {
            blocks.push(RawBlock {
                order_index: blocks.len(),
                patterns: p,
                host_name: host_name.take(),
                user: user.take(),
                port: port.take(),
                identity_files: std::mem::take(identity_files),
                preferred_auth_types: preferred.take(),
            });
        }
    };

    for raw_line in content.lines() {
        let stripped = strip_comment(raw_line);
        let line = stripped.trim();
        if line.is_empty() {
            continue;
        }
        let Some((kw_raw, value)) = split_keyword_value(line) else {
            continue;
        };
        let kw = kw_raw.to_ascii_lowercase();
        if kw == "host" {
            flush(
                &mut blocks,
                &mut patterns,
                &mut host_name,
                &mut user,
                &mut port,
                &mut preferred,
                &mut identity_files,
            );
            patterns = Some(split_host_patterns(&value));
            continue;
        }
        if patterns.is_none() {
            continue;
        }
        match kw.as_str() {
            "hostname" if host_name.is_none() => host_name = Some(value),
            "user" if user.is_none() => user = Some(value),
            "port" if port.is_none() => port = value.parse::<u16>().ok(),
            "identityfile" => identity_files.push(value),
            "preferredauthentications" if preferred.is_none() => {
                preferred = parse_preferred_auths(&value);
            }
            _ => {}
        }
    }
    flush(
        &mut blocks,
        &mut patterns,
        &mut host_name,
        &mut user,
        &mut port,
        &mut preferred,
        &mut identity_files,
    );
    blocks
}

/// Map OpenSSH's `PreferredAuthentications` comma-list onto our
/// internal `AuthType` ordering. Methods we don't support
/// (`hostbased`, `gssapi-*`) are dropped so an entry like
/// `gssapi-with-mic,publickey,password` still resolves to
/// `[Key, Password]`.
fn parse_preferred_auths(raw: &str) -> Option<Vec<AuthType>> {
    let mut seen = std::collections::HashSet::<AuthType>::new();
    let mut out: Vec<AuthType> = Vec::new();
    for part in raw.split(',') {
        let mapped = match part.trim().to_ascii_lowercase().as_str() {
            "publickey" => Some(AuthType::Key),
            "password" => Some(AuthType::Password),
            "keyboard-interactive" => Some(AuthType::Password),
            _ => None,
        };
        if let Some(m) = mapped {
            if seen.insert(m) {
                out.push(m);
            }
        }
    }
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

/// Recurse over `Include` directives, deduplicating via `visited`
/// so a self-referencing config terminates instead of looping.
///
/// **Contract:** `base_dir` must be an absolute path. Relative
/// include tokens are anchored to `base_dir`, so cycle detection
/// (string-equality on the anchored path) only deduplicates
/// correctly when the anchor itself is canonical — two callers
/// passing the same file via different relative bases would each
/// produce a distinct `visited` key and recurse without bound.
/// The production callers ([`parse_openssh_config`] / its `_with_fs`
/// sibling) feed `<home>/.ssh` which is already absolute.
fn expand_includes(
    content: &str,
    reader: IncludeReader<'_>,
    base_dir: &str,
    remaining: usize,
    visited: &mut std::collections::HashSet<String>,
) -> String {
    if remaining == 0 {
        return content.to_string();
    }
    // Cycle detection compares canonical absolute paths; relative
    // input would let two paths denoting the same file slip past the
    // `visited` set. Callers that disable expansion entirely pass
    // `remaining == 0` and skip the check.
    debug_assert!(
        base_dir.is_empty() || is_absolute_path(base_dir),
        "cycle-detection requires absolute base_dir; got {base_dir:?}"
    );
    let mut buf = String::new();
    for raw_line in content.lines() {
        if !expand_include_line(raw_line, reader, base_dir, remaining, visited, &mut buf) {
            buf.push_str(raw_line);
            buf.push('\n');
        }
    }
    buf
}

/// Expand a single config line when it is an `Include` directive,
/// appending the recursively-expanded contents to `buf`. Returns true
/// when the line was an include (consumed); false means the caller
/// emits the raw line verbatim.
fn expand_include_line(
    raw_line: &str,
    reader: IncludeReader<'_>,
    base_dir: &str,
    remaining: usize,
    visited: &mut std::collections::HashSet<String>,
    buf: &mut String,
) -> bool {
    let stripped = strip_comment(raw_line);
    let line = stripped.trim();
    let Some((kw, value)) = (!line.is_empty())
        .then(|| split_keyword_value(line))
        .flatten()
    else {
        return false;
    };
    if !kw.eq_ignore_ascii_case("include") {
        return false;
    }
    for token in split_host_patterns(&value) {
        for resolved in resolve_include_paths(&token, base_dir) {
            if !visited.insert(resolved.clone()) {
                continue;
            }
            if let Some(included) = reader(&resolved) {
                buf.push_str(&expand_includes(
                    &included,
                    reader,
                    base_dir,
                    remaining - 1,
                    visited,
                ));
                buf.push('\n');
            }
        }
    }
    true
}

/// Real-filesystem variant of [`expand_includes`]. Walks the
/// parent directory for glob tokens, reads each matched file
/// directly, and recurses with a hard cap on per-file size. Used
/// by [`parse_openssh_config_with_fs`]; the test-seam variant
/// (`expand_includes` + `IncludeReader`) keeps a separate path so
/// unit tests can inject canned content without touching disk.
fn expand_includes_with_fs(
    content: &str,
    base_dir: &str,
    remaining: usize,
    visited: &mut std::collections::HashSet<String>,
) -> String {
    if remaining == 0 {
        return content.to_string();
    }
    // Cycle detection compares canonical absolute paths; relative
    // input would let two paths denoting the same file slip past the
    // `visited` set. Callers that disable expansion entirely pass
    // `remaining == 0` and skip the check.
    debug_assert!(
        base_dir.is_empty() || is_absolute_path(base_dir),
        "cycle-detection requires absolute base_dir; got {base_dir:?}"
    );
    let mut buf = String::new();
    for raw_line in content.lines() {
        if !expand_include_line_with_fs(raw_line, base_dir, remaining, visited, &mut buf) {
            buf.push_str(raw_line);
            buf.push('\n');
        }
    }
    buf
}

/// Real-filesystem counterpart to [`expand_include_line`]: resolves
/// glob tokens against the real parent directory and reads each
/// matched file from disk. Returns true when the line was an
/// `Include` (consumed); false means the caller emits the raw line.
fn expand_include_line_with_fs(
    raw_line: &str,
    base_dir: &str,
    remaining: usize,
    visited: &mut std::collections::HashSet<String>,
    buf: &mut String,
) -> bool {
    let stripped = strip_comment(raw_line);
    let line = stripped.trim();
    let Some((kw, value)) = (!line.is_empty())
        .then(|| split_keyword_value(line))
        .flatten()
    else {
        return false;
    };
    if !kw.eq_ignore_ascii_case("include") {
        return false;
    }
    for token in split_host_patterns(&value) {
        for resolved in resolve_include_paths_with_fs(&token, base_dir) {
            if !visited.insert(resolved.clone()) {
                continue;
            }
            if let Some(included) = read_include_file(&resolved) {
                buf.push_str(&expand_includes_with_fs(
                    &included,
                    base_dir,
                    remaining - 1,
                    visited,
                ));
                buf.push('\n');
            }
        }
    }
    true
}

/// Resolve one include token — possibly containing `*` / `?` —
/// to the concrete files it matches under `base_dir`. Tilde
/// expansion + relative-path anchoring mirror
/// [`resolve_include_paths`]; glob walking lists the parent
/// directory and filters basenames via [`glob_matches`].
fn resolve_include_paths_with_fs(pattern: &str, base_dir: &str) -> Vec<String> {
    let mut resolved = pattern.to_string();
    if resolved == "~" {
        resolved = crate::path::expand_tilde("~");
    } else if resolved.starts_with("~/") {
        resolved = crate::path::expand_tilde(&resolved);
    } else if !is_absolute_path(&resolved) {
        let sep = if cfg!(windows) { '\\' } else { '/' };
        resolved = format!("{base_dir}{sep}{resolved}");
    }
    if !resolved.contains('*') && !resolved.contains('?') {
        return vec![resolved];
    }
    glob_files(&resolved)
}

/// Enumerate concrete files matching a `~/.ssh/config.d/*` style
/// pattern. The directory walk follows OpenSSH 7.x semantics —
/// only the basename is globbed, the parent directory must
/// exist literally. Returns sorted absolute paths; missing or
/// unreadable directories silently produce an empty list so a
/// stale Include doesn't break the whole import.
fn glob_files(pattern: &str) -> Vec<String> {
    let normalised = pattern.replace('\\', "/");
    let Some(idx) = normalised.rfind('/') else {
        return Vec::new();
    };
    let dir_path = &pattern[..idx];
    let base_pattern = &normalised[idx + 1..];
    let read_dir = match std::fs::read_dir(dir_path) {
        Ok(rd) => rd,
        Err(_) => return Vec::new(),
    };
    let mut matches = Vec::new();
    for entry in read_dir.flatten() {
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if !file_type.is_file() {
            continue;
        }
        let path = entry.path();
        let name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        if glob_matches(base_pattern, &name) {
            if let Some(p) = path.to_str() {
                matches.push(p.to_string());
            }
        }
    }
    matches.sort();
    matches
}

/// Read an include file, capping at [`MAX_INCLUDE_FILE_BYTES`].
/// `None` covers all of: file missing, permission denied, file
/// too large (almost always a hostile config), and read errors.
fn read_include_file(path: &str) -> Option<String> {
    let metadata = std::fs::metadata(path).ok()?;
    if !metadata.is_file() {
        return None;
    }
    if metadata.len() > MAX_INCLUDE_FILE_BYTES {
        return None;
    }
    std::fs::read_to_string(path).ok()
}

/// Walk every `Include` directive in [`content`] and return the
/// single-level resolved paths in encounter order. Does NOT recurse,
/// touch the filesystem, or expand globs — each token is resolved
/// through [`resolve_include_paths`] (tilde / relative-anchor handled
/// the same way the in-memory parser does).
///
/// Exposed for the Dart test-seam collector that walks an
/// in-memory include map: the recursion + cycle detection stay
/// Dart-side (the reader callback is Dart-side), but the per-line
/// grammar lives in one place. Production callers use
/// [`parse_openssh_config_with_fs`] which owns the whole walk
/// Rust-side.
pub fn resolve_include_paths_for_content(content: &str, base_dir: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for raw_line in content.lines() {
        let stripped = strip_comment(raw_line);
        let line = stripped.trim();
        if line.is_empty() {
            continue;
        }
        let Some((kw, value)) = split_keyword_value(line) else {
            continue;
        };
        if !kw.eq_ignore_ascii_case("include") {
            continue;
        }
        for token in split_host_patterns(&value) {
            for resolved in resolve_include_paths(&token, base_dir) {
                out.push(resolved);
            }
        }
    }
    out
}

fn resolve_include_paths(pattern: &str, base_dir: &str) -> Vec<String> {
    let mut resolved = pattern.to_string();
    if resolved == "~" {
        resolved = crate::path::expand_tilde("~");
    } else if resolved.starts_with("~/") {
        resolved = crate::path::expand_tilde(&resolved);
    } else if !is_absolute_path(&resolved) {
        let sep = if cfg!(windows) { '\\' } else { '/' };
        resolved = format!("{base_dir}{sep}{resolved}");
    }
    // Glob expansion is filesystem-touching — left to a future
    // commit alongside the Rust-driven importer that owns the
    // reader. Today the parser receives Include readers from the
    // caller for both plain paths and globs; a glob token resolves
    // to one path that the reader can fan out itself, so this
    // entry-point only emits the canonical resolved path.
    vec![resolved]
}

fn is_absolute_path(path: &str) -> bool {
    if path.starts_with('/') {
        return true;
    }
    let bytes = path.as_bytes();
    if bytes.len() >= 2 && bytes[1] == b':' {
        return true;
    }
    if path.starts_with("\\\\") {
        return true;
    }
    false
}

fn is_wildcard_pattern(host: &str) -> bool {
    host.contains('*') || host.contains('?') || host.starts_with('!')
}

/// Recursive minimal glob match. `*` runs of any length, `?`
/// exactly one char, anything else literal. Case-sensitive.
/// Real-world `Host` patterns are short enough that the
/// worst-case backtracking cost stays in microseconds.
///
/// Public so the Dart-side `Include`-directive expander
/// (`openssh_config_parser.dart`, where filesystem glob walks
/// stay Dart-side because of platform path semantics) can reuse
/// the same grammar without compiling its own regex.
pub fn glob_matches(pattern: &str, text: &str) -> bool {
    glob_at(pattern.as_bytes(), 0, text.as_bytes(), 0)
}

fn glob_at(p: &[u8], pi: usize, t: &[u8], ti: usize) -> bool {
    if pi == p.len() {
        return ti == t.len();
    }
    match p[pi] {
        b'*' => {
            for k in ti..=t.len() {
                if glob_at(p, pi + 1, t, k) {
                    return true;
                }
            }
            false
        }
        b'?' => {
            if ti == t.len() {
                return false;
            }
            glob_at(p, pi + 1, t, ti + 1)
        }
        c => {
            if ti == t.len() || t[ti] != c {
                return false;
            }
            glob_at(p, pi + 1, t, ti + 1)
        }
    }
}

/// Strip the `#`-prefixed comment (outside quoted strings) from
/// [`line`]. Public so the Dart Include-directive expander
/// (which needs to peel comments before it knows whether the line
/// is an `Include` line) can route through the canonical grammar.
pub fn strip_comment(line: &str) -> String {
    let mut in_quotes = false;
    let mut out = String::with_capacity(line.len());
    for c in line.chars() {
        if c == '"' {
            in_quotes = !in_quotes;
        }
        if c == '#' && !in_quotes {
            break;
        }
        out.push(c);
    }
    out
}

/// Split a single config line into `(keyword, value)`. Accepts both
/// `keyword value` and `keyword = value` forms; returns `None` for
/// blank lines or lines with only one token. Unquotes the value.
///
/// Public so the Dart Include-directive expander can detect an
/// `Include` line without re-implementing the grammar.
pub fn split_keyword_value(line: &str) -> Option<(String, String)> {
    let eq_idx = line.find('=');
    let space_idx = line.find(|c: char| c.is_whitespace());
    let sep_idx = match (eq_idx, space_idx) {
        (None, None) => return None,
        (Some(e), None) => e,
        (None, Some(s)) => s,
        (Some(e), Some(s)) => std::cmp::min(e, s),
    };
    let keyword = line[..sep_idx].trim().to_string();
    let mut rest = line[sep_idx + 1..].trim().to_string();
    if let Some(stripped) = rest.strip_prefix('=') {
        rest = stripped.trim().to_string();
    }
    if keyword.is_empty() || rest.is_empty() {
        return None;
    }
    Some((keyword, unquote(&rest).to_string()))
}

/// Strip a single matched pair of leading/trailing `"`. The
/// OpenSSH config grammar treats values verbatim except when
/// quoted — `Host "my workstation"` keeps the single token,
/// `Host my workstation` is two tokens. Public so the Dart
/// `_unquote` helper can route through the canonical grammar.
pub fn unquote(value: &str) -> &str {
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        &value[1..value.len() - 1]
    } else {
        value
    }
}

/// Split a Host-line / Include value into whitespace-separated
/// patterns, preserving spaces inside `"…"` quoted runs. Public so
/// the Dart Include-directive expander can route through the
/// canonical grammar.
pub fn split_host_patterns(value: &str) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    let mut buf = String::new();
    let mut in_quotes = false;
    for c in value.chars() {
        if c == '"' {
            in_quotes = !in_quotes;
            continue;
        }
        if !in_quotes && (c == ' ' || c == '\t') {
            if !buf.is_empty() {
                result.push(std::mem::take(&mut buf));
            }
            continue;
        }
        buf.push(c);
    }
    if !buf.is_empty() {
        result.push(buf);
    }
    result
}
#[cfg(test)]
#[path = "../tests/unit/ssh_config.rs"]
mod tests;
