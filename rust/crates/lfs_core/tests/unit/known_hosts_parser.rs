/// Unit tests extracted from known_hosts_parser.rs
/// Declared via `#[path] mod tests;` in the source file.
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
