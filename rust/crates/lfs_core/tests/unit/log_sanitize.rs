/// Unit tests extracted from log_sanitize.rs
/// Declared via `#[path] mod tests;` in the source file.
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
fn looks_sensitive_flags_pem_marker() {
    let pem =
        "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaA==\n-----END OPENSSH PRIVATE KEY-----";
    assert!(looks_sensitive(pem));
}

#[test]
fn looks_sensitive_flags_long_base64_run() {
    let blob = "A".repeat(220);
    assert!(looks_sensitive(&blob));
}

#[test]
fn looks_sensitive_passes_short_base64() {
    assert!(!looks_sensitive("hash=AAAAB3NzaC1yc2EAAAADAQAB"));
}

#[test]
fn looks_sensitive_passes_plain_text() {
    assert!(!looks_sensitive("the quick brown fox"));
    assert!(!looks_sensitive(""));
}

#[test]
fn looks_sensitive_requires_both_pem_markers() {
    // A bare `-----BEGIN` without `PRIVATE KEY` (e.g. a
    // certificate header) is not flagged — clipboard auto-wipe
    // only fires for private-key material.
    assert!(!looks_sensitive(
        "-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----"
    ));
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
    let r = sanitize_error_message("Connecting to 10.0.0.1:22 as burzuf for /home/burzuf/.ssh/key");
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
