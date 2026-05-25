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

use std::time::Duration;

use tokio::sync::Mutex;

use lfs_core::connection::test_server::{self, TEST_PASSWORD};
use lfs_frb::api::app::db_init;
use lfs_frb::api::db::db_known_hosts_upsert_by_host_port;
use lfs_frb::api::forward::ssh_open_direct_tcpip;
use lfs_frb::api::sftp::ssh_open_sftp;
use lfs_frb::api::ssh::{ssh_connect_password, ssh_try_connect_password};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

/// Serialise the DB-bootstrapping path across the binary's tests.
/// `db_init` replaces the process-singleton `app.db` slot, so two
/// parallel tests that both bootstrap would race; the gate keeps
/// the lifecycle deterministic without forcing `--test-threads=1`
/// across every (DB-free) sibling test. `tokio::sync::Mutex` keeps
/// the guard hold-across-await safe — the std `Mutex` would trip
/// clippy's `await_holding_lock` lint.
static DB_BOOTSTRAP_GATE: Mutex<()> = Mutex::const_new(());

/// One-shot DB bootstrap against a tempdir + fresh SQLCipher key.
/// Returns the tempdir guard so the caller drops it after the test
/// (the DB file lives inside it).
async fn bootstrap_db_in_tempdir() -> tempfile::TempDir {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("test.db");
    // Mirror the Dart cold-start: pre-create an empty 0-byte file
    // before handing the path to `db_init` (sqlcipher then writes
    // the freshly-encrypted header on first open).
    std::fs::File::create(&path).expect("pre-create db file");
    let key = vec![0x42u8; 32];
    db_init(path.to_string_lossy().into_owned(), key)
        .await
        .expect("db_init");
    dir
}

/// Pre-register the test_server's host key in `known_hosts` so the
/// full `ssh_connect_password` path skips the TOFU prompt.
async fn pre_register_known_host(
    host: &str,
    port: u16,
    info: &lfs_frb::api::test_hooks::TestSshServerInfo,
) {
    db_known_hosts_upsert_by_host_port(
        host.into(),
        port as i64,
        info.host_pubkey_algorithm.clone(),
        info.host_pubkey_b64.clone(),
        0,
    )
    .await
    .expect("known_hosts upsert");
}

#[tokio::test]
async fn try_connect_password_succeeds_against_test_server_with_correct_password() {
    // The probe now runs read-only TOFU — it accepts only an
    // already-trusted host key — so bootstrap a DB and pre-register
    // the fixture's key before the probe reaches userauth.
    let _gate = DB_BOOTSTRAP_GATE.lock().await;
    let _ = lfs_core::app::init();
    let _dir = bootstrap_db_in_tempdir().await;
    let handle = lfs_frb::api::test_hooks::test_ssh_server_start()
        .await
        .expect("test_ssh_server_start");
    pre_register_known_host("127.0.0.1", handle.port, &handle).await;

    let res = ssh_try_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        TEST_PASSWORD.as_bytes().to_vec(),
    )
    .await;
    assert!(res.is_ok(), "expected Ok, got {res:?}");
    lfs_frb::api::test_hooks::test_ssh_server_stop_all();
}

#[tokio::test]
async fn try_connect_password_rejects_wrong_password_against_test_server() {
    // Pre-register the host key so the probe clears read-only TOFU and
    // the failure surfaces at userauth (not as a host-key rejection),
    // pinning the `kind=auth_failed` envelope.
    let _gate = DB_BOOTSTRAP_GATE.lock().await;
    let _ = lfs_core::app::init();
    let _dir = bootstrap_db_in_tempdir().await;
    let handle = lfs_frb::api::test_hooks::test_ssh_server_start()
        .await
        .expect("test_ssh_server_start");
    pre_register_known_host("127.0.0.1", handle.port, &handle).await;

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
    lfs_frb::api::test_hooks::test_ssh_server_stop_all();
}

#[tokio::test]
async fn try_connect_probe_rejects_unknown_host_key() {
    // Security regression: the probe must NOT auto-accept an
    // unverified host key — that would leak the credential to a MITM.
    // With no `known_hosts` entry, read-only TOFU rejects the
    // handshake before userauth even though the password is correct.
    let _gate = DB_BOOTSTRAP_GATE.lock().await;
    let _ = lfs_core::app::init();
    let _dir = bootstrap_db_in_tempdir().await;
    let handle = lfs_frb::api::test_hooks::test_ssh_server_start()
        .await
        .expect("test_ssh_server_start");
    // Deliberately skip `pre_register_known_host`.
    let res = ssh_try_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        TEST_PASSWORD.as_bytes().to_vec(),
    )
    .await;
    assert!(
        res.is_err(),
        "unknown host key must be rejected, not auto-accepted: {res:?}"
    );
    lfs_frb::api::test_hooks::test_ssh_server_stop_all();
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
async fn full_session_lifecycle_connects_lists_sftp_root_and_disconnects() {
    let _gate = DB_BOOTSTRAP_GATE.lock().await;
    let _ = lfs_core::app::init();
    let _dir = bootstrap_db_in_tempdir().await;

    let handle = lfs_frb::api::test_hooks::test_ssh_server_start()
        .await
        .expect("test_ssh_server_start");
    pre_register_known_host("127.0.0.1", handle.port, &handle).await;

    // Open a long-lived session against the fixture.
    let session = ssh_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        TEST_PASSWORD.as_bytes().to_vec(),
    )
    .await
    .expect("ssh_connect_password");

    // Pre-stage a file via the local filesystem (the test_server's
    // sftp_root tempdir is exposed in the handle). The russh_sftp
    // client's `write_file` shape doesn't set OPEN_CREATE — it
    // expects an existing file — so file creation lives outside
    // the SFTP path. Reads + lists then exercise the full SFTP
    // boundary round-trip.
    std::fs::write(format!("{}/hello.txt", &handle.sftp_root), b"world")
        .expect("pre-stage fixture file");

    let sftp = ssh_open_sftp(&session).await.expect("ssh_open_sftp");
    let entries = sftp.list("/".into()).await.expect("sftp list /");
    assert_eq!(entries.len(), 1, "expected one entry, got {entries:?}");
    assert_eq!(entries[0].name, "hello.txt");

    let bytes = sftp
        .read_file("/hello.txt".into())
        .await
        .expect("sftp read_file");
    assert_eq!(bytes, b"world");

    session.disconnect().await.expect("session disconnect");
    lfs_frb::api::test_hooks::test_ssh_server_stop_all();
}

#[tokio::test]
async fn direct_tcpip_channel_round_trips_bytes_through_proxied_endpoint() {
    // The test_server proxies direct-tcpip channels to localhost.
    // Spin up a local echo server, open a direct-tcpip channel
    // through the SSH session targeting the echo socket, and pin
    // that bytes flow round-trip through the FRB forward channel.
    let echo = TcpListener::bind("127.0.0.1:0").await.expect("echo bind");
    let echo_port = echo.local_addr().expect("echo addr").port();
    tokio::spawn(async move {
        // Single-shot echo: accept one connection, copy bytes back
        // until EOF / disconnect.
        if let Ok((mut sock, _)) = echo.accept().await {
            let mut buf = [0u8; 64];
            while let Ok(n) = sock.read(&mut buf).await {
                if n == 0 {
                    break;
                }
                if sock.write_all(&buf[..n]).await.is_err() {
                    break;
                }
            }
        }
    });

    let _gate = DB_BOOTSTRAP_GATE.lock().await;
    let _ = lfs_core::app::init();
    let _dir = bootstrap_db_in_tempdir().await;

    let handle = lfs_frb::api::test_hooks::test_ssh_server_start()
        .await
        .expect("test_ssh_server_start");
    pre_register_known_host("127.0.0.1", handle.port, &handle).await;

    let session = ssh_connect_password(
        "127.0.0.1".into(),
        handle.port,
        "tester".into(),
        TEST_PASSWORD.as_bytes().to_vec(),
    )
    .await
    .expect("ssh_connect_password");

    let channel = ssh_open_direct_tcpip(
        &session,
        "127.0.0.1".into(),
        u32::from(echo_port),
        "127.0.0.1".into(),
        0,
    )
    .await
    .expect("ssh_open_direct_tcpip");

    // Send a payload through the channel; expect the echo bytes
    // back. Bound the read with a tokio timeout so a regression
    // can't hang the suite.
    channel
        .write(b"ping".to_vec())
        .await
        .expect("forward channel write");
    let echoed = tokio::time::timeout(Duration::from_secs(5), channel.read())
        .await
        .expect("forward channel read timeout")
        .expect("forward channel read returned None");
    assert_eq!(&echoed[..], b"ping");

    channel.eof().await.expect("forward channel eof");
    session.disconnect().await.expect("session disconnect");
    lfs_frb::api::test_hooks::test_ssh_server_stop_all();
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
