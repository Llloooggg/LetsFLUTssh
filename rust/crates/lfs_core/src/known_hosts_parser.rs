//! Parser for the OpenSSH `~/.ssh/known_hosts` wire format plus
//! the LetsFLUTssh internal `host:port keytype base64key` shape
//! that `.lfs` archives round-trip.
//!
//! Mirrors `KnownHostsManager._parseLine` / `_normaliseHostSpec` /
//! `_isHashedHostsLine` byte-for-byte. Pure functions over user-
//! controllable text; canonical implementation belongs Rust-side
//! so a future imported file blob (drag-dropped, picked from disk,
//! pasted from a real OpenSSH machine) parses identically across
//! frontends.
//!
//! Surface:
//!   - [`parse_line`] — one line in, zero or more entries out.
//!   - [`normalise_host_spec`] — `host:port` / `[host]:port` /
//!     bare hostname → canonical `host:port`.
//!   - [`is_hashed_hosts_line`] — `|1|salt|hash` detection so the
//!     importer can surface the "skipped N hashed entries" warning
//!     to the user.

/// One parsed host:port + key triple from a known_hosts line.
/// Multi-host OpenSSH lines (`host1,host2,host3 keytype b64`) emit
/// one [`ParsedHostEntry`] per resolved host:port.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedHostEntry {
    pub host_port: String,
    pub key_type: String,
    pub key_base64: String,
}

/// Parse a single line into zero or more host entries.
///
/// Accepts both the LetsFLUTssh internal export format
/// (`host:port keytype base64key`) and the OpenSSH
/// `~/.ssh/known_hosts` wire format. Comments / blank lines /
/// hashed entries / @-prefixed markers / unbracketed IPv6 all
/// resolve to an empty list — the importer counts a non-empty
/// hashed line via [`is_hashed_hosts_line`] separately so the user
/// sees a "skipped N hashed entries" warning rather than silently
/// dropping their `HashKnownHosts yes` rows.
pub fn parse_line(line: &str) -> Vec<ParsedHostEntry> {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.starts_with('#') {
        return Vec::new();
    }
    let mut parts: Vec<&str> = trimmed.split_whitespace().collect();
    // Drop leading @-markers (`@cert-authority`, `@revoked`). We
    // don't honour cert-authority semantics today; revoked entries
    // import normally with no effect on TOFU.
    while parts.first().is_some_and(|s| s.starts_with('@')) {
        parts.remove(0);
    }
    if parts.len() < 3 {
        return Vec::new();
    }
    let host_spec = parts[0];
    let key_type = parts[1];
    let key_base64 = parts[2];

    if host_spec.starts_with("|1|") {
        // Hashed entry — caller's `is_hashed_hosts_line` surfaces a
        // separate "skipped N hashed entries" warning. Returning
        // an empty list here means the import loop counts it as
        // skipped.
        return Vec::new();
    }
    // Reject lines whose key body is not valid standard base64.
    // A corrupt/garbage key bytes would otherwise sit in the
    // known_hosts table until the next connect attempt, where
    // russh's base64 decode would surface a host-key mismatch
    // long after the user moved on from the import dialog. The
    // empty payload check is separate so the warning text can
    // call out the distinct shape.
    if key_base64.is_empty() {
        crate::app_log_warn!(
            "KnownHostsImport",
            "skipping known_hosts line with empty key body"
        );
        return Vec::new();
    }
    if !is_valid_standard_base64(key_base64) {
        crate::app_log_warn!(
            "KnownHostsImport",
            "skipping known_hosts line with invalid base64 key body"
        );
        return Vec::new();
    }
    let mut out = Vec::new();
    for spec in host_spec.split(',') {
        if let Some(host_port) = normalise_host_spec(spec) {
            out.push(ParsedHostEntry {
                host_port,
                key_type: key_type.to_string(),
                key_base64: key_base64.to_string(),
            });
        }
    }
    out
}

/// Decode-check a candidate `key_base64` against the standard
/// (`+/`, padded) base64 alphabet used by every OpenSSH-style
/// known_hosts line. Returns `false` for anything that won't make
/// it through `base64::STANDARD.decode` at connect time, so the
/// importer can drop the row before it lands in the DB.
fn is_valid_standard_base64(s: &str) -> bool {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    STANDARD.decode(s).is_ok()
}

/// Convert a single OpenSSH host-spec or LetsFLUTssh internal
/// `host:port` into the canonical wire form. Returns `None` on
/// malformed input (empty, missing closing bracket, port out of
/// 1..=65535, unbracketed IPv6, …).
///
/// Output grammar:
///   - IPv6 host (any `:` in the host part) → `[host]:port`
///   - Anything else → `host:port`
///
/// Preserving brackets for IPv6 is load-bearing: the prior
/// implementation stripped the brackets and emitted `::1:2222`
/// which the consuming `split_host_port` (right-most-`:`) then
/// re-parsed as `host=":1", port=2222`. Stored TOFU rows for IPv6
/// hosts could never be matched at connect time. The canonical
/// form is now unambiguous and `split_host_port` strips the
/// brackets back off when populating the `(host, port)` columns
/// so the DB schema stays unchanged.
pub fn normalise_host_spec(spec: &str) -> Option<String> {
    let s = spec.trim();
    if s.is_empty() {
        return None;
    }
    // OpenSSH bracketed form: `[host]:port` or `[ipv6]` (no port).
    if let Some(rest) = s.strip_prefix('[') {
        let close = rest.find(']')?;
        let host = &rest[..close];
        if host.is_empty() {
            return None;
        }
        let tail = &rest[close + 1..];
        if tail.is_empty() {
            return Some(format_canonical(host, 22));
        }
        let port_str = tail.strip_prefix(':')?;
        let port: u32 = port_str.parse().ok()?;
        if !(1..=65535).contains(&port) {
            return None;
        }
        return Some(format_canonical(host, port));
    }
    // Bare IPv6 without brackets is illegal in OpenSSH — drop
    // anything with multiple `:`.
    let colon_count = s.bytes().filter(|&b| b == b':').count();
    if colon_count > 1 {
        return None;
    }
    if colon_count == 1 {
        let (host, port_str) = s.split_once(':')?;
        let port: u32 = port_str.parse().ok()?;
        if host.is_empty() || !(1..=65535).contains(&port) {
            return None;
        }
        return Some(format_canonical(host, port));
    }
    Some(format_canonical(s, 22))
}

fn format_canonical(host: &str, port: u32) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

/// True when [`line`] is an OpenSSH hashed-known-hosts entry
/// (HashKnownHosts yes — `|1|salt|hash`). Used by the importer to
/// count how many were silently dropped from a real OpenSSH file
/// so the UI can surface the count to the user.
pub fn is_hashed_hosts_line(line: &str) -> bool {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.starts_with('#') {
        return false;
    }
    // Match Dart's `_isHashedHostsLine` exactly: requires at least
    // one whitespace separator before the keytype. A bare `|1|`
    // marker with no key payload is a malformed line, not a
    // recognised hashed entry — return false so the importer
    // doesn't count it in the warning bucket.
    let first_ws = match trimmed.find(char::is_whitespace) {
        Some(i) => i,
        None => return false,
    };
    trimmed[..first_ws].starts_with("|1|")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(host_port: &str, kt: &str, b64: &str) -> ParsedHostEntry {
        ParsedHostEntry {
            host_port: host_port.into(),
            key_type: kt.into(),
            key_base64: b64.into(),
        }
    }

    #[test]
    fn parses_letsflutssh_internal_format() {
        let got = parse_line("example.com:22 ssh-ed25519 AAAA");
        assert_eq!(got, vec![entry("example.com:22", "ssh-ed25519", "AAAA")]);
    }

    #[test]
    fn parses_bare_hostname_defaults_port_22() {
        let got = parse_line("example.com ssh-rsa AAAA");
        assert_eq!(got, vec![entry("example.com:22", "ssh-rsa", "AAAA")]);
    }

    #[test]
    fn parses_bracketed_form_with_port() {
        let got = parse_line("[example.com]:2222 ssh-rsa AAAA");
        assert_eq!(got, vec![entry("example.com:2222", "ssh-rsa", "AAAA")]);
    }

    #[test]
    fn parses_bracketed_ipv6() {
        // IPv6 hosts round-trip with brackets preserved so the
        // consuming `split_host_port` can recover the host and
        // port unambiguously. The previous behaviour emitted
        // `::1:2222` which then re-parsed as `host=":1", port=2222`
        // and orphaned every IPv6 TOFU row at connect time.
        let got = parse_line("[::1]:2222 ssh-ed25519 BBBB");
        assert_eq!(got, vec![entry("[::1]:2222", "ssh-ed25519", "BBBB")]);
    }

    #[test]
    fn ipv6_default_port_keeps_brackets() {
        // A bracketed IPv6 host with no port falls through to the
        // default-22 path — brackets must still be preserved.
        assert_eq!(normalise_host_spec("[::1]"), Some("[::1]:22".to_string()),);
    }

    #[test]
    fn ipv4_host_remains_unbracketed() {
        assert_eq!(
            normalise_host_spec("[127.0.0.1]:2222"),
            Some("127.0.0.1:2222".to_string()),
        );
    }

    #[test]
    fn parses_multi_host_line() {
        let got = parse_line("a.com,b.com,1.2.3.4 ssh-rsa AAAA");
        assert_eq!(
            got,
            vec![
                entry("a.com:22", "ssh-rsa", "AAAA"),
                entry("b.com:22", "ssh-rsa", "AAAA"),
                entry("1.2.3.4:22", "ssh-rsa", "AAAA"),
            ]
        );
    }

    #[test]
    fn skips_blank_and_comment_lines() {
        assert!(parse_line("").is_empty());
        assert!(parse_line("   ").is_empty());
        assert!(parse_line("# top comment").is_empty());
        assert!(parse_line("  # indented").is_empty());
    }

    #[test]
    fn skips_hashed_entries() {
        let got = parse_line("|1|abc=|def= ssh-rsa AAAA");
        assert!(got.is_empty());
    }

    #[test]
    fn drops_at_markers() {
        let got = parse_line("@cert-authority example.com ssh-rsa AAAA");
        assert_eq!(got, vec![entry("example.com:22", "ssh-rsa", "AAAA")]);
        let got2 = parse_line("@revoked example.com ssh-rsa AAAA");
        assert_eq!(got2, vec![entry("example.com:22", "ssh-rsa", "AAAA")]);
    }

    #[test]
    fn drops_too_few_fields() {
        assert!(parse_line("only-host").is_empty());
        assert!(parse_line("host keytype").is_empty());
    }

    #[test]
    fn drops_unbracketed_ipv6() {
        // 2001:db8::1 with port → too many colons, should be rejected.
        assert!(parse_line("2001:db8::1 ssh-rsa AAAA").is_empty());
    }

    #[test]
    fn rejects_bracket_without_close() {
        assert_eq!(normalise_host_spec("[host:22"), None);
    }

    #[test]
    fn rejects_out_of_range_port() {
        assert_eq!(normalise_host_spec("host:0"), None);
        assert_eq!(normalise_host_spec("host:70000"), None);
        assert_eq!(normalise_host_spec("host:abc"), None);
        assert_eq!(normalise_host_spec("[host]:0"), None);
    }

    #[test]
    fn rejects_empty_or_whitespace_spec() {
        assert_eq!(normalise_host_spec(""), None);
        assert_eq!(normalise_host_spec("   "), None);
        assert_eq!(normalise_host_spec("[]"), None);
    }

    #[test]
    fn is_hashed_hosts_line_detects() {
        assert!(is_hashed_hosts_line("|1|abc=|def= ssh-rsa AAAA"));
        assert!(!is_hashed_hosts_line("example.com ssh-rsa AAAA"));
        assert!(!is_hashed_hosts_line(""));
        assert!(!is_hashed_hosts_line("# comment"));
        assert!(!is_hashed_hosts_line("|1|"));
    }

    #[test]
    fn rejects_invalid_base64_key_body() {
        // `not-base64!!!` contains characters outside the standard
        // base64 alphabet — the line must drop at parse time so a
        // corrupt key body never lands in the DB and surfaces as a
        // host-key mismatch on the next connect attempt.
        assert!(parse_line("example.com ssh-ed25519 not-base64!!!").is_empty());
        // 3-character body fails padding requirements.
        assert!(parse_line("example.com ssh-ed25519 KEY").is_empty());
    }

    #[test]
    fn rejects_too_few_columns_before_base64_check() {
        // Two-column lines short-circuit at the `len < 3` check —
        // the base64 validator never runs because there is no
        // third field to validate. Pins the order of the two
        // shape guards.
        assert!(parse_line("example.com ssh-ed25519").is_empty());
    }

    #[test]
    fn fuzz_does_not_panic() {
        for input in [
            "",
            "  ",
            ":",
            "[",
            "]",
            "[]",
            "[]:",
            "host:",
            ":port",
            "@",
            "@x ",
            "host\0\0\0 keytype b64",
            "  \t  \r\n",
            "|1| ssh-rsa AAAA",
            "host,,, ssh-rsa AAAA",
            ",,,",
            "[host]junk",
        ] {
            let _ = parse_line(input);
            let _ = normalise_host_spec(input);
            let _ = is_hashed_hosts_line(input);
        }
    }
}
