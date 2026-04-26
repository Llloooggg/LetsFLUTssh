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

// ---- sanitize_error_message regex pool ------------------------------

/// IPv6 literals (full + every compression shape, including
/// link-local / loopback / unspecified). Optionally bracketed
/// — Dart's pattern eats `[…]` so the trailing host:port rule
/// can redact the port cleanly. Branches ordered most-specific
/// first because Rust's `regex` (like Dart's `RegExp`) picks
/// the first match, not the longest.
fn ipv6_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(concat!(
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
        ))
        .expect("valid IPv6 regex")
    })
}

fn ipv4_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"\b(\d{1,3}\.){3}\d{1,3}\b").expect("valid IPv4 regex"))
}

fn user_at_host_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(r"([a-zA-Z0-9_.\-]+)@([a-zA-Z0-9_.]+\.[a-zA-Z]{2,}|<ip>)")
            .expect("valid user@host regex")
    })
}

fn as_user_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"\bas\s+([a-zA-Z0-9_.\-]+)").expect("valid as-user regex"))
}

fn user_eq_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(r"\b(user|login)=([a-zA-Z0-9_.\-]+)").expect("valid user= regex")
    })
}

fn host_port_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        Regex::new(r"(<ip>|[a-zA-Z0-9_.\-]+):(\d{2,5})\b").expect("valid host:port regex")
    })
}

fn windows_path_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"[A-Z]:\\Users\\[^\\\r\n]+").expect("valid windows path regex"))
}

fn unix_path_re() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(r"/(?:Users|home)/[^/\s]+").expect("valid unix path regex"))
}

/// Remove sensitive data from error messages before logging or
/// surfacing in toasts. Order mirrors the Dart pipeline:
/// IPv6 → IPv4 → user@host → as/user/login=value → host:port →
/// Windows path → Unix path. Each step rewrites the buffer the
/// next step scans, so e.g. host:port redaction operates after
/// the IP rewrites have already turned bare IPs into `<ip>`.
pub fn sanitize_error_message(input: &str) -> String {
    let after_v6 = ipv6_re().replace_all(input, "<ip>");
    let after_v4 = ipv4_re().replace_all(&after_v6, "<ip>");
    let after_userhost = user_at_host_re()
        .replace_all(&after_v4, |c: &regex::Captures<'_>| {
            let host = c.get(2).map_or("<host>", |m| m.as_str());
            format!("<user>@{host}")
        });
    let after_as = as_user_re().replace_all(&after_userhost, "as <user>");
    let after_userq = user_eq_re().replace_all(&after_as, |c: &regex::Captures<'_>| {
        let key = c.get(1).map_or("user", |m| m.as_str());
        format!("{key}=<user>")
    });
    let after_hp = host_port_re().replace_all(&after_userq, |c: &regex::Captures<'_>| {
        let host = c.get(1).map_or("<host>", |m| m.as_str());
        format!("{host}:<port>")
    });
    let after_win = windows_path_re().replace_all(&after_hp, "<path>");
    let after_unix = unix_path_re().replace_all(&after_win, "/<user>");
    after_unix.into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_pem_block() {
        let msg = "INSERT failed: -----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaA==\n-----END OPENSSH PRIVATE KEY-----\nat row 5";
        let r = redact_secrets(msg);
        assert!(r.contains("[REDACTED PRIVATE KEY]"));
        assert!(!r.contains("OPENSSH PRIVATE KEY"));
        assert!(r.contains("at row 5"));
    }

    #[test]
    fn redacts_rsa_pem_block() {
        let msg = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----";
        let r = redact_secrets(msg);
        assert_eq!(r, "[REDACTED PRIVATE KEY]");
    }

    #[test]
    fn redacts_long_base64_blob() {
        let blob = "A".repeat(250);
        let msg = format!("error: {blob}, retry");
        let r = redact_secrets(&msg);
        assert!(r.contains("[REDACTED BASE64]"));
        assert!(r.contains(", retry"));
    }

    #[test]
    fn short_base64_left_alone() {
        let msg = "hash=AAAAB3NzaC1yc2EAAAADAQAB"; // < 200 chars
        let r = redact_secrets(msg);
        assert_eq!(r, msg);
    }

    #[test]
    fn sanitize_strips_ipv4() {
        let r = sanitize_error_message("connect 192.168.1.1 failed");
        assert_eq!(r, "connect <ip> failed");
    }

    #[test]
    fn sanitize_strips_ipv6_full_form() {
        let r = sanitize_error_message("at 2001:0db8:85a3:0000:0000:8a2e:0370:7334");
        assert_eq!(r, "at <ip>");
    }

    #[test]
    fn sanitize_strips_ipv6_compressed() {
        let r = sanitize_error_message("dial 2001:db8::1 down");
        assert_eq!(r, "dial <ip> down");
    }

    #[test]
    fn sanitize_strips_loopback_v6() {
        let r = sanitize_error_message("bind ::1 fail");
        assert_eq!(r, "bind <ip> fail");
    }

    #[test]
    fn sanitize_strips_user_at_host() {
        let r = sanitize_error_message("admin@example.com refused");
        assert_eq!(r, "<user>@example.com refused");
    }

    #[test]
    fn sanitize_strips_user_at_ip() {
        let r = sanitize_error_message("alice@10.0.0.1 timed out");
        assert_eq!(r, "<user>@<ip> timed out");
    }

    #[test]
    fn sanitize_strips_as_user() {
        let r = sanitize_error_message("Connecting to host as burzuf");
        assert_eq!(r, "Connecting to host as <user>");
    }

    #[test]
    fn sanitize_does_not_eat_word_starting_with_as() {
        // Per Dart pipeline: the `as` arm requires whitespace
        // before the name so `dart:async` does not get rewritten
        // to `as <user>`. The Rust copy mirrors the `\s+` clause.
        let r = sanitize_error_message("at dart:async/zone_root.dart");
        assert_eq!(r, "at dart:async/zone_root.dart");
    }

    #[test]
    fn sanitize_strips_user_eq_login() {
        let r = sanitize_error_message("user=alice login=alice");
        assert_eq!(r, "user=<user> login=<user>");
    }

    #[test]
    fn sanitize_strips_host_port() {
        let r = sanitize_error_message("dial example.com:2222 failed");
        assert_eq!(r, "dial example.com:<port> failed");
    }

    #[test]
    fn sanitize_strips_ip_port_pair() {
        let r = sanitize_error_message("dial 10.0.0.1:22 dropped");
        assert_eq!(r, "dial <ip>:<port> dropped");
    }

    #[test]
    fn sanitize_strips_windows_user_path() {
        let r = sanitize_error_message(r"open C:\Users\alice\file failed");
        assert_eq!(r, r"open <path>\file failed");
    }

    #[test]
    fn sanitize_strips_unix_home_path() {
        let r = sanitize_error_message("read /home/bob/.ssh/id_rsa");
        assert_eq!(r, "read /<user>/.ssh/id_rsa");
    }

    #[test]
    fn sanitize_strips_macos_users_path() {
        let r = sanitize_error_message("read /Users/alice/Documents");
        assert_eq!(r, "read /<user>/Documents");
    }

    #[test]
    fn sanitize_full_error_chain() {
        let r = sanitize_error_message(
            "Connecting to 10.0.0.1:22 as burzuf for /home/burzuf/.ssh/key",
        );
        assert_eq!(
            r,
            "Connecting to <ip>:<port> as <user> for /<user>/.ssh/key"
        );
    }

    #[test]
    fn empty_input_round_trips() {
        assert_eq!(sanitize_error_message(""), "");
        assert_eq!(redact_secrets(""), "");
    }
}
