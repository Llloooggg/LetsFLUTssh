/// Unit tests extracted from keys.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn fingerprint_returns_empty_for_empty_input() {
    assert_eq!(normalized_text_fingerprint(""), "");
    assert_eq!(normalized_text_fingerprint("   \n\n   "), "");
}

#[test]
fn fingerprint_normalizes_crlf_to_lf_before_hashing() {
    let lf = "ssh-ed25519 AAAA...\nuser@host\n";
    let crlf = "ssh-ed25519 AAAA...\r\nuser@host\r\n";
    assert_eq!(
        normalized_text_fingerprint(lf),
        normalized_text_fingerprint(crlf)
    );
}

#[test]
fn fingerprint_trims_surrounding_whitespace() {
    let bare = "ssh-ed25519 AAAA";
    let padded = "  \n\nssh-ed25519 AAAA\n  ";
    assert_eq!(
        normalized_text_fingerprint(bare),
        normalized_text_fingerprint(padded)
    );
}

#[test]
fn fingerprint_is_lowercase_hex_64_chars() {
    let fp = normalized_text_fingerprint("ssh-ed25519 AAAA");
    assert_eq!(fp.len(), 64);
    assert!(fp
        .chars()
        .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
}

#[test]
fn fingerprint_distinguishes_different_inputs() {
    let a = normalized_text_fingerprint("ssh-ed25519 AAAA1");
    let b = normalized_text_fingerprint("ssh-ed25519 AAAA2");
    assert_ne!(a, b);
}

#[test]
fn obvious_non_key_filename_flags_dot_pub() {
    assert!(is_obvious_non_key_filename("id_ed25519.pub"));
}

#[test]
fn obvious_non_key_filename_flags_config() {
    assert!(is_obvious_non_key_filename("config"));
}

#[test]
fn obvious_non_key_filename_flags_authorized_keys_variants() {
    assert!(is_obvious_non_key_filename("authorized_keys"));
    assert!(is_obvious_non_key_filename("authorized_keys.bak"));
    assert!(is_obvious_non_key_filename("authorized_keys2"));
}

#[test]
fn obvious_non_key_filename_flags_known_hosts_variants() {
    assert!(is_obvious_non_key_filename("known_hosts"));
    assert!(is_obvious_non_key_filename("known_hosts.old"));
}

#[test]
fn obvious_non_key_filename_passes_actual_keys() {
    assert!(!is_obvious_non_key_filename("id_ed25519"));
    assert!(!is_obvious_non_key_filename("id_rsa"));
    assert!(!is_obvious_non_key_filename("my-deploy-key"));
}

#[test]
fn looks_like_ppk_matches_v2_and_v3_headers() {
    assert!(looks_like_ppk("PuTTY-User-Key-File-2: ssh-rsa\n…"));
    assert!(looks_like_ppk("PuTTY-User-Key-File-3: ssh-ed25519\n…"));
}

#[test]
fn looks_like_ppk_skips_leading_whitespace() {
    // Leading newline / spaces shouldn't confuse the sniff —
    // some pickers paste content with stray whitespace.
    assert!(looks_like_ppk("\n  PuTTY-User-Key-File-3: ssh-ed25519\n"));
}

#[test]
fn looks_like_ppk_rejects_pem_armor() {
    assert!(!looks_like_ppk("-----BEGIN OPENSSH PRIVATE KEY-----\n"));
}

#[test]
fn looks_like_ppk_rejects_unknown_text() {
    assert!(!looks_like_ppk(""));
    assert!(!looks_like_ppk("PuTTY-User-Key-File-1: ssh-rsa\n"));
    assert!(!looks_like_ppk("hello world"));
}

#[test]
fn pkcs1_dek_info_marks_encrypted() {
    let pem = "-----BEGIN RSA PRIVATE KEY-----\n\
               Proc-Type: 4,ENCRYPTED\n\
               DEK-Info: AES-128-CBC,1234\n\
               payload\n\
               -----END RSA PRIVATE KEY-----\n";
    assert!(is_encrypted_pem(pem));
}

#[test]
fn dek_info_alone_marks_encrypted() {
    // Some real-world keys ship `DEK-Info:` without the
    // matching `Proc-Type:` line — match either marker so the
    // importer doesn't silently try to use them as plaintext.
    let pem = "-----BEGIN RSA PRIVATE KEY-----\n\
               DEK-Info: AES-256-CBC,abcd\n\
               payload\n\
               -----END RSA PRIVATE KEY-----\n";
    assert!(is_encrypted_pem(pem));
}

#[test]
fn pkcs8_encrypted_armor_marks_encrypted() {
    let pem = "-----BEGIN ENCRYPTED PRIVATE KEY-----\n\
               payload\n\
               -----END ENCRYPTED PRIVATE KEY-----\n";
    assert!(is_encrypted_pem(pem));
}

#[test]
fn unencrypted_openssh_round_trips_via_keygen() {
    // Generate a fresh ed25519 key — encoded with `none` KDF —
    // and confirm the encrypted detector says "no".
    let km = generate_ed25519("test").unwrap();
    assert!(!is_encrypted_pem(&km.private_pem));
}

#[test]
fn random_text_is_not_encrypted() {
    // Non-key text never trips the markers.
    assert!(!is_encrypted_pem("just a random string\n"));
    assert!(!is_encrypted_pem(""));
}

#[test]
fn malformed_openssh_body_falls_through_to_unencrypted() {
    // Outer armor matches but the body decodes to nothing
    // useful — caller must not warn the user about a malformed
    // file (returning `false` here lets the importer attempt
    // the real parse, which surfaces the proper format error).
    let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n\
               bm90LXJlYWxseS1iYXNlNjQK\n\
               -----END OPENSSH PRIVATE KEY-----\n";
    assert!(!is_encrypted_pem(pem));
}

// ── try_read_pem_from_path ───────────────────────────────────

#[test]
fn try_read_pem_from_path_returns_pem_for_valid_armor() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("id_ed25519");
    let content =
        "-----BEGIN OPENSSH PRIVATE KEY-----\nbm90LXJlYWw=\n-----END OPENSSH PRIVATE KEY-----\n";
    std::fs::write(&path, content).unwrap();
    assert_eq!(try_read_pem_from_path(&path).as_deref(), Some(content));
}

#[test]
fn try_read_pem_from_path_returns_none_for_missing_file() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("nope");
    assert!(try_read_pem_from_path(&path).is_none());
}

#[test]
fn try_read_pem_from_path_rejects_oversized_file() {
    // 33 KiB → over the documented 32 KiB ceiling. The file's
    // body is irrelevant; the size check trips before any
    // PEM / PPK detection.
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("oversized");
    std::fs::write(&path, vec![b'x'; 33 * 1024]).unwrap();
    assert!(try_read_pem_from_path(&path).is_none());
}

#[test]
fn try_read_pem_from_path_rejects_non_pem_content() {
    // A small file with no `PRIVATE KEY` armor — picker
    // legitimately picked something else (config, log, random
    // text). Helper says "not a key" and the silent path moves
    // on without surfacing a parse error.
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("random.txt");
    std::fs::write(&path, b"hello world").unwrap();
    assert!(try_read_pem_from_path(&path).is_none());
}

#[test]
fn try_read_pem_from_path_rejects_directory() {
    // A directory at the picked path → must collapse to None
    // rather than blowing up — the file picker on iOS / Android
    // can hand us a directory under a sandbox alias.
    let dir = tempfile::TempDir::new().unwrap();
    assert!(try_read_pem_from_path(dir.path()).is_none());
}

// ── parse_openssh_cert ───────────────────────────────────────
//
// Real OpenSSH ed25519 cert blob — taken from the
// `internal-russh-forked-ssh-key` test corpus
// (`tests/examples/id_ed25519-cert.pub`). The corresponding
// upstream test asserts `valid_principals[0] == "host.example.com"`
// and one principal entry; we re-assert those invariants here so
// a russh-fork bump that silently changes the parser surface is
// caught at our DAO boundary, not at runtime.
const ED25519_CERT_FIXTURE: &str = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIAYkJPGaYen7NK8MwZwWmNAyRaFNsc86AU9NObU2cM2uAAAAILM+rvN+ot98qgEN796jTiQfZfG1KaT0PtFDJ/XFSqtiAAAAAAAAAAAAAAACAAAAB2VkMjU1MTkAAAAUAAAAEGhvc3QuZXhhbXBsZS5jb20AAAAAYkx3NwAAAAB8DuY3AAAAAAAAAAAAAAAAAAAAMwAAAAtzc2gtZWQyNTUxOQAAACCzPq7zfqLffKoBDe/eo04kH2XxtSmk9D7RQyf1xUqrYgAAAFMAAAALc3NoLWVkMjU1MTkAAABApVXBNiYPlPoa1BYH5G4NP9XtjTMZlm7HO5GdbLSvvAw5Vdob7Ka+23hB7isJKHYtzFGGSKXAqxp/Zi8REbCaAw== user@example.com";

// Cert with a `force-command` critical option. Confirms we
// surface the option name + value verbatim; pulled from the
// forked-ssh-key crit-options round-trip test.
const ED25519_CERT_WITH_CRIT_OPTIONS: &str = "ssh-ed25519-cert-v01@openssh.com AAAAIHNzaC1lZDI1NTE5LWNlcnQtdjAxQG9wZW5zc2guY29tAAAAIBW/4zLqXWROWmN1sPgdySnH1GUsEFBjFrRwKKw71BoBAAAAIH1MFwI1oRdEifXgBQvWQfCBBtA/Pi8YCUE/I3wXFJo2AAAAAAAAAAAAAAABAAAAA2ZvbwAAAAAAAAAAAAAAAH//////////AAAAIwAAABFoZWxsb0BleGFtcGxlLmNvbQAAAAoAAAAGZm9vYmFyAAAAAAAAAAAAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIH1MFwI1oRdEifXgBQvWQfCBBtA/Pi8YCUE/I3wXFJo2AAAAUwAAAAtzc2gtZWQyNTUxOQAAAEDRoPdI48KyoaLgaDZsSGs80qBeYQOXBd84CX8GYzFt/L21rxF1EeuPOkgsx7Q39WllXp+FgMMojsHftK/DJHEN";

#[test]
fn parse_openssh_cert_extracts_principals() {
    let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
    assert_eq!(parsed.principals, vec!["host.example.com".to_string()]);
}

#[test]
fn parse_openssh_cert_extracts_validity_window() {
    let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
    // Validity is encoded in the fixture as unix seconds; we
    // assert window monotonicity (after < before) rather than
    // exact values so a russh-fork bump that switches encoding
    // surfaces here before downstream UI assertions.
    assert!(parsed.valid_after_unix > 0);
    assert!(parsed.valid_before_unix > parsed.valid_after_unix);
}

#[test]
fn parse_openssh_cert_extracts_critical_options() {
    let parsed = parse_openssh_cert(ED25519_CERT_WITH_CRIT_OPTIONS.as_bytes()).unwrap();
    assert_eq!(parsed.critical_options.len(), 1);
    assert_eq!(
        parsed
            .critical_options
            .get("hello@example.com")
            .map(String::as_str),
        Some("foobar"),
    );
}

#[test]
fn parse_openssh_cert_no_crit_options_returns_empty_map() {
    let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
    assert!(parsed.critical_options.is_empty());
}

#[test]
fn parse_openssh_cert_fingerprint_is_stable_sha256_base64_shape() {
    // SHA-256 in `SHA256:<base64-no-pad>` form — 43 chars of
    // base64-no-pad after the prefix (32 bytes → 43 base64).
    let parsed = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
    assert!(parsed.fingerprint.starts_with("SHA256:"));
    let body = &parsed.fingerprint["SHA256:".len()..];
    assert_eq!(body.len(), 43);
    // Re-parse must produce the same fingerprint; deterministic
    // hash of canonical-encoded blob bytes.
    let parsed2 = parse_openssh_cert(ED25519_CERT_FIXTURE.as_bytes()).unwrap();
    assert_eq!(parsed.fingerprint, parsed2.fingerprint);
}

#[test]
fn parse_openssh_cert_rejects_random_bytes() {
    let result = parse_openssh_cert(b"not-a-certificate");
    assert!(matches!(result, Err(Error::KeyParse(_))));
}

#[test]
fn parse_openssh_cert_rejects_non_utf8() {
    let result = parse_openssh_cert(&[0xFF, 0xFE, 0x00, 0xC0]);
    assert!(matches!(result, Err(Error::KeyParse(_))));
}

#[test]
fn parse_openssh_cert_strips_leading_whitespace() {
    // Real-world paste often arrives with a stray leading
    // newline; the parser must still resolve the cert content.
    let padded = format!("\n  {ED25519_CERT_FIXTURE}");
    let parsed = parse_openssh_cert(padded.as_bytes()).unwrap();
    assert_eq!(parsed.principals, vec!["host.example.com".to_string()]);
}

#[test]
fn parse_ppk_argon2_u32_returns_none_when_line_missing() {
    // v2 PPK header — no `Argon2-Memory` line. The caller treats
    // `Ok(None)` as "no cap to enforce".
    let v2 = "PuTTY-User-Key-File-2: ssh-rsa\nEncryption: none\n";
    assert_eq!(parse_ppk_argon2_u32(v2, "Argon2-Memory").unwrap(), None);
}

#[test]
fn parse_ppk_argon2_u32_parses_valid_value() {
    let header = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 8192\nArgon2-Passes: 13\n";
    assert_eq!(
        parse_ppk_argon2_u32(header, "Argon2-Memory").unwrap(),
        Some(8192)
    );
    assert_eq!(
        parse_ppk_argon2_u32(header, "Argon2-Passes").unwrap(),
        Some(13)
    );
}

#[test]
fn parse_ppk_argon2_u32_rejects_value_above_u32_max() {
    // `99999999999999999999` is larger than `u32::MAX`. Trap:
    // folding the parse failure into the "no cap to enforce"
    // branch via `parse::<u32>().ok()` silently bypasses the
    // cap. The typed parse error makes the caller reject.
    let hostile = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 99999999999999999999\n";
    let err = parse_ppk_argon2_u32(hostile, "Argon2-Memory").unwrap_err();
    match err {
        Error::KeyParse(msg) => {
            assert!(msg.contains("Argon2-Memory"), "unexpected message: {msg}");
        }
        other => panic!("expected KeyParse, got {other:?}"),
    }
}

#[test]
fn parse_ppk_argon2_u32_rejects_non_numeric_value() {
    let bad = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: abcd\n";
    assert!(matches!(
        parse_ppk_argon2_u32(bad, "Argon2-Memory"),
        Err(Error::KeyParse(_))
    ));
}

#[test]
fn validate_ppk_argon2_params_accepts_realistic_putty_costs() {
    // A normal PuTTY v3 export — well under every cap.
    let ok = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 8192\nArgon2-Passes: 13\nArgon2-Parallelism: 1\n";
    assert!(validate_ppk_argon2_params(ok).is_ok());
    // v2 PPK (no Argon2 lines) passes through untouched.
    assert!(validate_ppk_argon2_params("PuTTY-User-Key-File-2: ssh-rsa\n").is_ok());
}

#[test]
fn validate_ppk_argon2_params_caps_passes_and_parallelism_not_just_memory() {
    // The pre-fix gap: only memory was capped, so a hostile file
    // could set a huge time-cost (passes) or lane count and still
    // import. All three must now be bounded before the derive.
    for hostile in [
        "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Passes: 2000000000\n",
        "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Parallelism: 1000000\n",
        "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 2000000\n",
    ] {
        assert!(
            matches!(validate_ppk_argon2_params(hostile), Err(Error::KeyParse(_))),
            "expected rejection for {hostile:?}"
        );
    }
}

#[test]
fn import_ppk_rejects_argon2_memory_above_u32_max() {
    // End-to-end: a hostile `.ppk` whose `Argon2-Memory` value
    // exceeds `u32::MAX` must short-circuit with a typed
    // `KeyParse` error before russh-keys touches the file.
    let hostile = "PuTTY-User-Key-File-3: ssh-ed25519\nArgon2-Memory: 9999999999999\nEncryption: aes256-cbc\n";
    let err = import_ppk(hostile, Some("pw"), "comment").unwrap_err();
    match err {
        Error::KeyParse(msg) => {
            assert!(msg.contains("Argon2-Memory"), "unexpected message: {msg}");
        }
        other => panic!("expected KeyParse, got {other:?}"),
    }
}
