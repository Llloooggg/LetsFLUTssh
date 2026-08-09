//! Redaction helpers — mirror Dart `lib/utils/sanitize.dart`.
//!
//! Two surfaces:
//! * [`redact_secrets`] — strip PEM private-key blocks + long
//!   base64 blobs. Called before any user-visible error toast
//!   so a leaked key never ends up in a notification banner.
//! * [`sanitize_error_message`] — strip IPv4 / IPv6 / `user@host`
//!   / `host:port` / Windows + Unix home-directory paths and the
//!   "as <user>" / `user=<user>` / `login=<user>` shapes that SSH
//!   error messages name the principal in.
//!
//! Both functions match the regex shapes the Dart implementation
//! uses byte-for-byte so a future swap of the Dart sanitizer to
//! call into the Rust core produces identical output.

use std::sync::OnceLock;

use regex::Regex;

/// Match any PEM-style block (private key, encrypted private key,
/// proprietary formats with hyphens in the type name like
/// `OPENSSH PRIVATE KEY`). The type-name class is restricted to
/// non-newline characters rather than non-hyphen so types like
/// `OPENSSH-PRIVATE-KEY` or `ENCRYPTED PRIVATE KEY` still match.
fn pem_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        // (?s) — dot matches newline (Dart's `[\s\S]*?`).
        Regex::new(
            r"(?s)-----BEGIN[^\n]*?(PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|OPENSSH PRIVATE KEY)[^\n]*?-----.*?-----END[^\n]*?(PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|OPENSSH PRIVATE KEY)[^\n]*?-----",
        )
        .expect("valid PEM regex")
    })
}

fn long_b64_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"[A-Za-z0-9+/=]{200,}").expect("valid base64 regex"))
}

/// Strip PEM private keys and long base64 blobs.
///
/// Catches the common drift / sqlite leak where a failed
/// `INSERT` dumps its bound parameters — including
/// `-----BEGIN OPENSSH PRIVATE KEY-----…` — into the exception
/// message.
pub fn redact_secrets(input: &str) -> String {
    let after_pem = pem_re().replace_all(input, "[REDACTED PRIVATE KEY]");
    let after_b64 = long_b64_re().replace_all(&after_pem, "[REDACTED BASE64]");
    after_b64.into_owned()
}

/// True when [`text`] looks like it carries secret material — a PEM
/// private-key block or a long base64 run (≥ 200 chars). Mirror of
/// the Dart-side `TerminalClipboard._looksSensitive` heuristic so
/// the clipboard auto-wipe + the log redactor agree on what counts
/// as "do not let this leak". Fast path — single substring scan +
/// one regex match per call.
#[must_use]
pub fn looks_sensitive(text: &str) -> bool {
    if text.contains("-----BEGIN") && text.contains("PRIVATE KEY") {
        return true;
    }
    long_b64_re().is_match(text)
}

// ---- sanitize_error_message — 2-pass combined regex ------------------
//
// Earlier shape ran 8 sequential `replace_all` passes — each
// scanned the full input. The 2-pass shape below collapses them
// to a bare-IP pass + a "everything else" combined pass. ~4×
// reduction. A single-pass combined regex was tried and rejected
// because Rust's `regex` (NFA, no backtracking) and Dart's
// `RegExp` (PCRE-style backtracking) diverge on inputs like
// `fe80::abcd:1234:5678` where the host:port branch wants a
// shorter IPv6 prefix to leave `:5678` for the port slot — Dart
// backtracks and finds it; Rust does not, falling through to the
// bare-IP catch-all and consuming the full IPv6. Two passes
// preserve the per-pass identity between engines.

const IPV6_BRANCH: &str = concat!(
    r"\[?(?:",
    // Full 8-group: 1:2:3:4:5:6:7:8
    r"(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}",
    // 1 leading group, 1..6 trailing groups after ::
    r"|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}",
    r"|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}",
    r"|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}",
    r"|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}",
    r"|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}",
    // 1..6 leading + exactly 1 trailing — `2001:db8::1`
    r"|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}",
    // Pure leading-then-:: (`1::`, `1:2::`)
    r"|(?:[0-9A-Fa-f]{1,4}:){1,7}:",
    // Pure trailing-after-:: (`::8`, `::1:2`)
    r"|:(?::[0-9A-Fa-f]{1,4}){1,7}",
    r"|::",
    r")\]?",
);

const IPV4_BRANCH: &str = r"(?:\d{1,3}\.){3}\d{1,3}";

/// Pass 1: bare IPv6 + IPv4 → `<ip>`. One regex, two alternatives.
fn ip_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        let combined = format!(r"{IPV6_BRANCH}|\b{IPV4_BRANCH}\b");
        Regex::new(&combined).expect("valid ip regex")
    })
}

/// Pass 2: everything else (user@host, as_user, user=, host:port,
/// Windows path, Unix path) — combined into one regex with named
/// captures, dispatched in the replace closure. The host slot
/// after pass 1 is either a literal `<ip>` placeholder or a
/// domain name; the regex matches both.
///
/// `userhost` carries an optional `:port` suffix so the replace
/// closure can render `<user>@host:<port>` in one shot — the
/// alternation can't compose user@host's match with a separate
/// host:port match because each `replace_all` callback span is
/// consumed and the engine continues from after the match.
///
/// `hostport_host` REQUIRES at least one letter
/// (`(?:[a-zA-Z0-9_.\-]*[a-zA-Z][a-zA-Z0-9_.\-]*)`) — pure-digit
/// "hosts" are line numbers from a `file.dart:LINE:COL` stack
/// trace, never network endpoints. The matching `:digit`
/// look-ahead guard that Dart expresses with `(?!:\d)` lives in
/// the replace closure below as a manual post-match check
/// (Rust's `regex` crate has no lookarounds).
fn rest_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(concat!(
            r"(?P<userhost>([a-zA-Z0-9_.\-]+)@(?P<userhost_host>[a-zA-Z0-9_.]+\.[a-zA-Z]{2,}|<ip>)(?::(?P<userhost_port>\d{2,5}))?)",
            r"|(?P<asuser>\bas\s+[a-zA-Z0-9_.\-]+)",
            r"|(?P<usereq>\b(?P<usereq_key>user|login)=[a-zA-Z0-9_.\-]+)",
            r"|(?P<hostport>(?P<hostport_host><ip>|[a-zA-Z0-9_.\-]*[a-zA-Z][a-zA-Z0-9_.\-]*):(?:\d{2,5}))\b",
            r"|(?P<winpath>[A-Z]:\\Users\\[^\\\r\n]+)",
            r"|(?P<unixpath>/(?:Users|home)/[^/\s]+)",
        ))
        .expect("valid combined sanitize regex")
    })
}

/// Remove sensitive data from error messages before logging or
/// surfacing in toasts. Two-pass shape — IPs first (turn into
/// `<ip>` placeholder), then everything else in one combined
/// regex that dispatches in the replace closure based on which
/// named capture matched.
pub fn sanitize_error_message(input: &str) -> String {
    let after_ip = ip_re().replace_all(input, "<ip>");
    let haystack = after_ip.as_ref();
    rest_re()
        .replace_all(&after_ip, |c: &regex::Captures<'_>| {
            replace_rest_match(c, haystack)
        })
        .into_owned()
}

/// Dispatch one match of [`rest_re`] to its redacted replacement,
/// keyed on which named capture fired. `haystack` is the pass-1
/// output the captures index into — needed for the `hostport`
/// manual look-ahead. Returns the original span for the
/// (compile-time unreachable) no-branch-matched case.
fn replace_rest_match(c: &regex::Captures<'_>, haystack: &str) -> String {
    if c.name("userhost").is_some() {
        let host = c.name("userhost_host").map_or("<host>", |m| m.as_str());
        if c.name("userhost_port").is_some() {
            return format!("<user>@{host}:<port>");
        }
        return format!("<user>@{host}");
    }
    if c.name("asuser").is_some() {
        return "as <user>".to_string();
    }
    if c.name("usereq").is_some() {
        let key = c.name("usereq_key").map_or("user", |m| m.as_str());
        return format!("{key}=<user>");
    }
    if let Some(m) = c.name("hostport") {
        // Manual lookahead — Dart writes `(?!:\d)` in the regex,
        // Rust's `regex` crate has no lookaround so we check
        // here. If the byte AFTER the match is `:` followed by
        // a digit, the candidate is a `LINE:COL` continuation
        // of a `file.dart:LINE:COL` stack-trace fragment and
        // we must NOT redact it. Returning the match's literal
        // span preserves the source unchanged.
        let tail = haystack.as_bytes();
        let end = m.end();
        if matches!(tail.get(end), Some(b':'))
            && tail.get(end + 1).is_some_and(|b| b.is_ascii_digit())
        {
            return m.as_str().to_string();
        }
        let host = c.name("hostport_host").map_or("<host>", |m| m.as_str());
        return format!("{host}:<port>");
    }
    if c.name("winpath").is_some() {
        return "<path>".to_string();
    }
    if c.name("unixpath").is_some() {
        return "/<user>".to_string();
    }
    // Unreachable — every branch above is named and one of
    // them must have matched. Preserve the original span if
    // a future regex-vs-dispatch drift slips through.
    c.get(0).map_or(String::new(), |m| m.as_str().to_string())
}
#[cfg(test)]
#[path = "../tests/unit/log_sanitize.rs"]
mod tests;
