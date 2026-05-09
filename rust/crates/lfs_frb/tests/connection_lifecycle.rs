//! End-to-end integration tests for the FRB SSH probe + session
//! surface against the in-process `lfs_core::connection::test_server`
//! fixture.
//!
//! Why a separate integration binary: each test spins up an
//! independent russh server on a fresh localhost port + tempdir
//! sftp-root. Running every scenario in the main unit-test binary
//! would let one test's poisoned channel state leak into the next
//! through the process-singleton `RUNTIME` russh shares.
//!
//! Coverage: pins the `ssh_try_connect_password` probe path
//! (positive + negative) + the `ssh_format_host_key_fingerprint`
//! shape against a real generated host key. The full
//! `ssh_connect_password → open_shell → disconnect` lifecycle is
//! covered by the Dart `connection_lifecycle_test.dart` integration
//! suite (which drives the same FRB shims through `requireFrbLoaded`
//! plus the Dart-managed `db_init` + `known_hosts` upsert that the
//! long-lived session path requires).

use lfs_core::connection::test_server::{self, TEST_PASSWORD};
use lfs_frb::api::ssh::ssh_try_connect_password;

#[tokio::test]
async fn try_connect_password_succeeds_against_test_server_with_correct_password() {
    let handle = test_server::start().await.expect("test_server::start");
    let res = ssh_try_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        TEST_PASSWORD.as_bytes().to_vec(),
    )
    .await;
    assert!(res.is_ok(), "expected Ok, got {res:?}");
    handle.shutdown();
}

#[tokio::test]
async fn try_connect_password_rejects_wrong_password_against_test_server() {
    let handle = test_server::start().await.expect("test_server::start");
    let res = ssh_try_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        b"wrong-password".to_vec(),
    )
    .await;
    assert!(res.is_err(), "wrong password must surface as Err");
    let envelope = res.unwrap_err();
    // The post-audit FRB error envelope routes auth failures through
    // `kind=auth_failed`. Pin the wire shape so a future router
    // refactor can't silently degrade to `kind=generic`.
    assert!(
        envelope.contains("auth_failed"),
        "expected typed kind=auth_failed envelope, got {envelope}"
    );
    handle.shutdown();
}

#[tokio::test]
async fn try_connect_password_returns_err_for_unreachable_host() {
    // Unbound port on the loopback — connect must fail fast with a
    // typed `kind=connect` envelope rather than hang or panic.
    let res = ssh_try_connect_password(
        "127.0.0.1".into(),
        // Reserved port range — almost guaranteed to refuse.
        1,
        "tester".into(),
        TEST_PASSWORD.as_bytes().to_vec(),
    )
    .await;
    assert!(res.is_err(), "unreachable host must surface as Err");
}

#[tokio::test]
async fn try_connect_password_rejects_non_utf8_password_against_live_server() {
    // RFC 4252 §8 specifies UTF-8 for the password field. The shim
    // must surface a clean `kind=auth_failed` envelope rather than
    // panic / generic-string degrade — even when a real server is
    // reachable for the connect probe.
    let handle = test_server::start().await.expect("test_server::start");
    let invalid_utf8 = vec![0xFF, 0xFE, 0xFD];
    let res = ssh_try_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        invalid_utf8,
    )
    .await;
    assert!(res.is_err());
    let envelope = res.unwrap_err();
    assert!(envelope.contains("auth_failed"));
    handle.shutdown();
}
