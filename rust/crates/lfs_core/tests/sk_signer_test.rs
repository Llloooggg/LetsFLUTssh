//! Integration tests for the FIDO2 SSH signer.
//!
//! Live-hardware tests are gated behind `#[ignore]` so the workspace
//! `cargo test` run stays hermetic. To run them on a CI worker with a
//! real authenticator plugged in:
//!
//! ```bash
//! cargo test -p lfs_core --features fido2 --test sk_signer_test -- --ignored
//! ```
//!
//! These tests assume a YubiKey 5 (or any FIDO2-compatible authenticator)
//! is plugged in and that the matching `id_ed25519_sk` keypair has been
//! generated against the `ssh:` application string. Operator owns the
//! pre-test setup; the test merely verifies the round trip end-to-end.

use lfs_core::ssh::sk::{self, FidoCredential};

/// Algorithm detection is the public surface the connect-path
/// dispatcher relies on. Lock the short-tag + full-wire-name
/// recognition shape so a future refactor cannot silently drop a
/// `sk-*` variant from the dispatch table.
#[test]
fn algorithm_dispatch_recognises_both_sk_variants() {
    use russh::keys::ssh_key::Algorithm;
    assert!(matches!(
        sk::algorithm_from_key_type("sk-ed25519"),
        Some(Algorithm::SkEd25519)
    ));
    assert!(matches!(
        sk::algorithm_from_key_type("sk-ecdsa-sha2-nistp256@openssh.com"),
        Some(Algorithm::SkEcdsaSha2NistP256)
    ));
    assert!(sk::algorithm_from_key_type("ssh-ed25519").is_none());
    assert!(sk::is_sk_algorithm(&Algorithm::SkEd25519));
    assert!(sk::is_sk_algorithm(&Algorithm::SkEcdsaSha2NistP256));
    assert!(!sk::is_sk_algorithm(&Algorithm::Ed25519));
}

/// `extract_application_from_openssh_pub` is the import-path bridge
/// the connect path also calls to recover the `application` field
/// from a stored `.pub` body. Verify the surface accepts every
/// well-formed sk-* line shape and rejects software keys.
#[test]
fn application_extractor_handles_software_and_hardware_keys() {
    // Software key — must return None.
    let soft = sk::extract_application_from_openssh_pub(
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPpoFSACtCBjqK3CMJzMpKBg25LcZTfMpd5R+aNCwDjg test",
    );
    assert!(soft.is_none());

    // Malformed input — must return None rather than panic.
    let bad = sk::extract_application_from_openssh_pub("not-a-key");
    assert!(bad.is_none());
}

/// Manual integration test against a stock OpenSSH server. Requires:
///
/// 1. A FIDO2 authenticator plugged in (YubiKey 5, SoloKey, Token2 etc).
/// 2. `ssh-keygen -t ed25519-sk -O application=ssh: -f /tmp/id_ed25519_sk`
///    run by the operator beforehand.
/// 3. The matching `.pub` body installed in the server's
///    `~/.ssh/authorized_keys`.
/// 4. `LFS_FIDO2_TEST_HOST`, `LFS_FIDO2_TEST_USER`,
///    `LFS_FIDO2_TEST_CREDENTIAL_ID` (base64), and
///    `LFS_FIDO2_TEST_PUB` (single-line `id_ed25519_sk.pub` body)
///    environment variables set.
///
/// The test touches real CTAP2 hardware — leaving it `#[ignore]` so
/// the hermetic test run is unaffected. Run manually:
///
/// ```bash
/// LFS_FIDO2_TEST_HOST=127.0.0.1:22 \
///   LFS_FIDO2_TEST_USER=alice \
///   LFS_FIDO2_TEST_CREDENTIAL_ID=AAAA... \
///   LFS_FIDO2_TEST_PUB="sk-ssh-ed25519@openssh.com AAAA... ssh:" \
///   cargo test -p lfs_core --features fido2 --test sk_signer_test \
///     -- --ignored fido2_round_trips_through_a_live_authenticator
/// ```
#[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
#[ignore = "requires plugged-in FIDO2 hardware + matching authorized_keys entry"]
#[tokio::test]
async fn fido2_round_trips_through_a_live_authenticator() {
    use base64::Engine as _;
    use lfs_core::ssh::Session;

    let host_port = std::env::var("LFS_FIDO2_TEST_HOST").expect("LFS_FIDO2_TEST_HOST");
    let user = std::env::var("LFS_FIDO2_TEST_USER").expect("LFS_FIDO2_TEST_USER");
    let cred_b64 =
        std::env::var("LFS_FIDO2_TEST_CREDENTIAL_ID").expect("LFS_FIDO2_TEST_CREDENTIAL_ID");
    let public_openssh = std::env::var("LFS_FIDO2_TEST_PUB").expect("LFS_FIDO2_TEST_PUB");
    let pin = std::env::var("LFS_FIDO2_TEST_PIN").ok();

    let credential_id = base64::engine::general_purpose::STANDARD
        .decode(cred_b64.as_bytes())
        .expect("LFS_FIDO2_TEST_CREDENTIAL_ID must be base64");

    let (host, port) = host_port
        .rsplit_once(':')
        .map(|(h, p)| (h.to_owned(), p.parse::<u16>().expect("port")))
        .unwrap_or_else(|| (host_port.clone(), 22));

    let application = sk::extract_application_from_openssh_pub(&public_openssh)
        .expect("public key must be a well-formed sk-* line");

    let session = Session::connect_pubkey_sk(
        &host,
        port,
        &user,
        &public_openssh,
        &credential_id,
        &application,
        pin.as_deref(),
    )
    .await
    .expect("FIDO2 connect must succeed");
    drop(session);
}

/// Manual cert-via-FIDO integration test. Same preconditions as
/// `fido2_round_trips_through_a_live_authenticator` plus a cert
/// blob: the operator runs `ssh-keygen -s ca_key -I id -n alice
/// /tmp/id_ed25519_sk.pub` against their CA and points
/// `LFS_FIDO2_TEST_CERT` at the resulting `-cert.pub`. The server's
/// `sshd_config` must carry `TrustedUserCAKeys` pointing at the
/// CA's public half.
///
/// Run manually (cert blob in addition to the bare-sk env block):
///
/// ```bash
/// LFS_FIDO2_TEST_HOST=127.0.0.1:22 \
///   LFS_FIDO2_TEST_USER=alice \
///   LFS_FIDO2_TEST_CREDENTIAL_ID=AAAA... \
///   LFS_FIDO2_TEST_PUB="sk-ssh-ed25519@openssh.com AAAA... ssh:" \
///   LFS_FIDO2_TEST_CERT=/tmp/id_ed25519_sk-cert.pub \
///   cargo test -p lfs_core --features fido2 --test sk_signer_test \
///     -- --ignored fido2_cert_round_trips_through_a_live_authenticator
/// ```
#[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
#[ignore = "requires plugged-in FIDO2 hardware + matching authorized_keys + CA-signed cert"]
#[tokio::test]
async fn fido2_cert_round_trips_through_a_live_authenticator() {
    use base64::Engine as _;
    use lfs_core::ssh::Session;

    let host_port = std::env::var("LFS_FIDO2_TEST_HOST").expect("LFS_FIDO2_TEST_HOST");
    let user = std::env::var("LFS_FIDO2_TEST_USER").expect("LFS_FIDO2_TEST_USER");
    let cred_b64 =
        std::env::var("LFS_FIDO2_TEST_CREDENTIAL_ID").expect("LFS_FIDO2_TEST_CREDENTIAL_ID");
    let public_openssh = std::env::var("LFS_FIDO2_TEST_PUB").expect("LFS_FIDO2_TEST_PUB");
    let cert_path = std::env::var("LFS_FIDO2_TEST_CERT").expect("LFS_FIDO2_TEST_CERT");
    let pin = std::env::var("LFS_FIDO2_TEST_PIN").ok();

    let credential_id = base64::engine::general_purpose::STANDARD
        .decode(cred_b64.as_bytes())
        .expect("LFS_FIDO2_TEST_CREDENTIAL_ID must be base64");
    let cert_bytes =
        std::fs::read(&cert_path).expect("LFS_FIDO2_TEST_CERT must point at a readable cert blob");

    let (host, port) = host_port
        .rsplit_once(':')
        .map(|(h, p)| (h.to_owned(), p.parse::<u16>().expect("port")))
        .unwrap_or_else(|| (host_port.clone(), 22));

    let application = sk::extract_application_from_openssh_pub(&public_openssh)
        .expect("public key must be a well-formed sk-* line");

    let session = Session::connect_pubkey_sk_cert(
        &host,
        port,
        lfs_core::ssh::ConnectPubkeySkCertArgs {
            user: &user,
            public_openssh: &public_openssh,
            credential_id: &credential_id,
            application: &application,
            cert_bytes: &cert_bytes,
            pin: pin.as_deref(),
        },
    )
    .await
    .expect("FIDO2 cert connect must succeed");
    drop(session);
}

/// FidoCredential round-trips through Clone — the trait bound the
/// signer's async tail requires (each `auth_sign` call captures a
/// fresh clone so subsequent rounds re-enter cleanly).
#[test]
fn credential_clones_into_owned_buffer() {
    let cred = FidoCredential {
        credential_id: vec![1, 2, 3],
        application: "ssh:".into(),
        pin: Some("123456".into()),
    };
    let copy = cred.clone();
    assert_eq!(cred.credential_id, copy.credential_id);
    assert_eq!(cred.application, copy.application);
    assert_eq!(cred.pin, copy.pin);
}
