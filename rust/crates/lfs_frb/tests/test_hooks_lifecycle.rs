//! Integration tests for the `lfs_frb::api::test_hooks` shim — the
//! Dart-callable wrapper around `lfs_core::connection::test_server`.
//!
//! Why a separate integration binary: `test_hooks::test_ssh_server_start`
//! pushes onto a process-singleton handle list. Running the lifecycle
//! tests in the main `cargo test --lib` binary would leak fixture
//! state into other tests sharing the same process. Each integration
//! binary gets its own process, so the singleton starts empty.

use lfs_core::connection::test_server::TEST_PASSWORD;
use lfs_frb::api::test_hooks::{
    test_ssh_server_set_sftp_write_delay_ms, test_ssh_server_start, test_ssh_server_stop_all,
};

#[tokio::test]
async fn start_returns_a_handle_with_a_bound_port_and_a_known_password() {
    let info = test_ssh_server_start()
        .await
        .expect("test_ssh_server_start must succeed");
    assert!(info.port > 0, "bound port must be non-zero");
    assert_eq!(
        info.password, TEST_PASSWORD,
        "password must mirror the canonical fixture constant"
    );
    assert!(
        !info.host_pubkey_b64.is_empty(),
        "host pubkey base64 must not be empty"
    );
    assert!(
        info.host_pubkey_algorithm.starts_with("ssh-"),
        "expected ssh-* algorithm, got {}",
        info.host_pubkey_algorithm
    );
    assert!(
        !info.sftp_root.is_empty(),
        "sftp_root path must not be empty"
    );
    test_ssh_server_stop_all();
}

#[tokio::test]
async fn start_then_start_again_yields_two_distinct_endpoints() {
    // Pin the documented contract — concurrent fixtures (e.g.
    // ProxyJump tests standing up bastion + final target) must
    // get distinct ports + tempdirs without one start tearing the
    // other down.
    let a = test_ssh_server_start().await.expect("first start");
    let b = test_ssh_server_start().await.expect("second start");
    assert_ne!(
        a.port, b.port,
        "concurrent fixtures must bind disjoint ports"
    );
    assert_ne!(
        a.sftp_root, b.sftp_root,
        "concurrent fixtures must use disjoint sftp_root tempdirs"
    );
    test_ssh_server_stop_all();
}

#[tokio::test]
async fn stop_all_is_idempotent_on_an_empty_slot() {
    // Pin the no-panic contract — `tearDownAll` runs unconditionally
    // even when `setUpAll` failed to start any fixture. Two calls
    // in a row must also stay clean.
    test_ssh_server_stop_all();
    test_ssh_server_stop_all();
}

#[tokio::test]
async fn set_sftp_write_delay_ms_does_not_panic_for_any_value() {
    // The shim must accept zero (clear), small positive (typical
    // race-window widening for cancel-mid-flight tests), and large
    // (defensive — no caller passes huge values today, but the
    // wire shape is u32).
    test_ssh_server_set_sftp_write_delay_ms(0);
    test_ssh_server_set_sftp_write_delay_ms(1);
    test_ssh_server_set_sftp_write_delay_ms(50);
    test_ssh_server_set_sftp_write_delay_ms(u32::MAX);
    // Reset for sibling tests that share the binary.
    test_ssh_server_set_sftp_write_delay_ms(0);
}
