/// Unit tests extracted from ssh/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use russh::keys::{ssh_key::LineEnding, Algorithm, PrivateKey};

#[test]
fn check_auth_result_success_is_ok() {
    assert!(check_auth_result(AuthResult::Success).is_ok());
}

#[test]
fn check_auth_result_failure_lists_remaining_methods() {
    // Spec: a rejection must carry the methods the server still
    // offers so the connection log explains *why* — not a bare
    // "authentication failed".
    let err = check_auth_result(AuthResult::Failure {
        remaining_methods: russh::MethodSet::all(),
        partial_success: false,
    })
    .unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("password"), "got: {msg}");
    assert!(msg.contains("publickey"), "got: {msg}");
    assert!(!msg.contains("partial success"), "got: {msg}");
    // A plain rejection is `AuthFailed` (→ auth_failed wire kind),
    // so the Dart router re-prompts the matching credential tier.
    assert!(
        matches!(err, Error::AuthFailed(_)),
        "plain rejection must be AuthFailed: {err:?}"
    );
}

#[test]
fn check_auth_result_failure_flags_partial_success() {
    let err = check_auth_result(AuthResult::Failure {
        remaining_methods: russh::MethodSet::empty(),
        partial_success: true,
    })
    .unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("partial success"), "got: {msg}");
    assert!(msg.contains("none"), "got: {msg}");
    // Partial success means "further auth required" — genuinely
    // other, so it rides `Auth` (→ auth_other) for manual retry,
    // never `AuthFailed`.
    assert!(
        matches!(err, Error::Auth(_)),
        "partial success must be Auth (auth_other): {err:?}"
    );
}

fn random_ed25519_pem() -> Vec<u8> {
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).expect("ed25519 keygen");
    key.to_openssh(LineEnding::LF)
        .expect("openssh encode")
        .as_bytes()
        .to_vec()
}

#[test]
fn parses_unencrypted_ed25519() {
    let pem = random_ed25519_pem();
    let parsed = parse_private_key(&pem, None);
    assert!(parsed.is_ok(), "expected Ok, got: {parsed:?}");
}

#[test]
fn rejects_garbage_bytes() {
    let result = parse_private_key(b"not-a-key", None);
    assert!(
        matches!(result, Err(Error::KeyParse(_))),
        "expected KeyParse, got: {result:?}",
    );
}

#[test]
fn rejects_empty_bytes() {
    let result = parse_private_key(b"", None);
    assert!(
        matches!(result, Err(Error::KeyParse(_))),
        "expected KeyParse, got: {result:?}",
    );
}

#[tokio::test]
async fn try_connect_password_against_closed_port_returns_connect_error() {
    // Port 1 is privileged and almost always refused — deterministic
    // negative test for the connect path. Avoids a network round-trip
    // to a real server while still exercising the full code path.
    let result = try_connect_password("127.0.0.1", 1, "anyone", "irrelevant").await;
    assert!(
        matches!(result, Err(Error::Connect(_))),
        "expected Connect, got: {result:?}",
    );
}

#[tokio::test]
async fn session_connect_password_against_closed_port_returns_connect_error() {
    // `Session` wraps russh's Handle which is not Debug; format
    // only the error path explicitly for assertion messages.
    let result = Session::connect_password("127.0.0.1", 1, "anyone", "irrelevant").await;
    match result {
        Err(Error::Connect(_)) => {} // expected
        Err(other) => panic!("expected Connect, got: {other:?}"),
        Ok(_) => panic!("expected Connect error, got Ok session"),
    }
}

#[test]
fn routes_ppk_marker_to_ppk_parser() {
    // Truncated PPK header is rejected at parse time — but the
    // dispatch must be the PPK arm, so the error wraps the PPK
    // parser's complaint, not OpenSSH's.
    let result = parse_private_key(b"PuTTY-User-Key-File-3: ssh-rsa\nEncryption: none\n", None);
    // PassphraseIncorrect maps from "mac"/"crypto"/"decrypt" lines;
    // KeyParse covers everything else. Either is acceptable here —
    // the body is incomplete so PPK parser fails for either reason.
    match result {
        Err(Error::KeyParse(_)) | Err(Error::PassphraseIncorrect) => {}
        other => panic!("expected KeyParse / PassphraseIncorrect, got: {other:?}"),
    }
}

#[test]
fn ppk_marker_with_leading_whitespace_is_recognised() {
    // Real-world keys often arrive with a stray leading newline
    // from copy-paste. The parser strips ASCII whitespace before
    // looking at the magic, so this still routes to PPK.
    let result = parse_private_key(b"\n\n  PuTTY-User-Key-File-3: bogus\n", None);
    match result {
        Err(Error::KeyParse(_)) | Err(Error::PassphraseIncorrect) => {}
        other => panic!("expected KeyParse / PassphraseIncorrect, got: {other:?}"),
    }
}

#[test]
fn key_parse_error_carries_message() {
    let result = parse_private_key(
        b"-----BEGIN OPENSSH PRIVATE KEY-----\nnope\n-----END OPENSSH PRIVATE KEY-----\n",
        None,
    );
    let err = result.expect_err("garbage payload");
    let formatted = format!("{err}");
    assert!(formatted.starts_with("key parse failed:"), "{formatted}");
}

/// End-to-end against a real russh server that VERIFIES the userauth
/// signature: authenticate with a freshly generated software RSA key
/// through `SoftwareRsaSigner` and assert the server accepts it. This
/// is the test whose absence let the missing-outer-string signature
/// bug ship — the only prior pubkey handshake test used Ed25519,
/// which never goes through the custom signer.
#[tokio::test]
async fn software_rsa_signer_authenticates_against_real_server() {
    struct AcceptAll;
    impl client::Handler for AcceptAll {
        type Error = russh::Error;
        async fn check_server_key(
            &mut self,
            _key: &ssh_key::PublicKey,
        ) -> Result<bool, Self::Error> {
            Ok(true)
        }
    }

    let server = crate::connection::test_server::start()
        .await
        .expect("start test server");
    let config = std::sync::Arc::new(client::Config::default());
    let mut handle = client::connect(config, ("127.0.0.1", server.port), AcceptAll)
        .await
        .expect("connect to test server");

    let km = crate::keys::generate_rsa(2048, "e2e-rsa").expect("generate rsa key");
    let key = parse_private_key(km.private_pem.as_bytes(), None).expect("parse rsa key");
    let mut signer = super::software_rsa_signer::SoftwareRsaSigner::try_new(&key)
        .expect("build signer")
        .expect("RSA key yields a ring signer");
    let public = key.public_key().clone();

    let result = handle
        .authenticate_publickey_with("tester", public, Some(HashAlg::Sha256), &mut signer)
        .await
        .expect("auth call");
    assert!(
        matches!(result, AuthResult::Success),
        "the real russh server verifies the signature — software RSA \
         userauth must be accepted, got: {result:?}"
    );
}
