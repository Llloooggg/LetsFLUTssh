//! Test-only FRB surface — drives the in-process russh-server
//! fixture under [`lfs_core::connection::test_server`].
//!
//! Always compiled in; see the `test_server` module docstring for
//! why the previous Cargo-feature-gated approach was abandoned. The
//! fixture binds 127.0.0.1 only, no production code path calls
//! [`test_ssh_server_start`], and the hard-coded test password is
//! meaningless to anyone who isn't already on the loopback
//! interface AND running the test suite.
//!
//! Usage from `flutter test` is in
//! `test/integration/connection_lifecycle_test.dart`:
//!
//! ```dart
//! setUpAll(() async {
//!   await requireFrbLoaded();
//!   await dbInit(...);            // for connectionPrepareAuth + known_hosts
//!   final info = await testSshServerStart();
//!   await knownHostsUpsertByHostPort(
//!     host: '127.0.0.1',
//!     port: info.port,
//!     keyType: info.hostPubkeyAlgorithm,
//!     keyBase64: info.hostPubkeyB64,
//!   );
//! });
//!
//! tearDownAll(() {
//!   testSshServerStopAll();
//! });
//! ```
//!
//! Concurrent fixtures: each [`test_ssh_server_start`] adds a new
//! handle to the running set without disturbing the others, so a
//! ProxyJump-style test can stand up two endpoints (bastion + final
//! target) on disjoint ports and shut them all down with one
//! [`test_ssh_server_stop_all`] call in `tearDownAll`.

use std::sync::{Mutex, OnceLock};

use lfs_core::connection::test_server::{self, TestServerHandle, TEST_PASSWORD};

/// Bundle returned to the Dart test caller. Carries everything a
/// test needs to drive a connect against the fixture: the bound
/// localhost port, the host-key shape (so the test can pre-seed
/// `known_hosts` and avoid the prompt round-trip), the fixed
/// password the fixture's `auth_password` handler accepts, and the
/// absolute filesystem path the SFTP subsystem is rooted at (tests
/// can drop fixture files there with `dart:io` before the SFTP
/// flow reads them, or assert against the same path after a PUT).
#[derive(Debug, Clone)]
pub struct TestSshServerInfo {
    pub port: u16,
    pub host_pubkey_algorithm: String,
    pub host_pubkey_b64: String,
    pub password: String,
    pub sftp_root: String,
}

/// Multiple-instance slot. Each [`test_ssh_server_start`] pushes a
/// fresh handle so a ProxyJump test can stand up two endpoints on
/// disjoint ports without one start tearing the other down.
fn slot() -> &'static Mutex<Vec<TestServerHandle>> {
    static SLOT: OnceLock<Mutex<Vec<TestServerHandle>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(Vec::new()))
}

/// Start an additional in-process russh-server fixture. Returns the
/// bound port + the OpenSSH-shaped public-key blob the caller seeds
/// into `known_hosts`. Each call generates a fresh Ed25519 host
/// keypair + a fresh SFTP-root tempdir, so multiple concurrent
/// fixtures stay independent.
pub async fn test_ssh_server_start() -> Result<TestSshServerInfo, String> {
    let handle = test_server::start().await.map_err(|e| e.to_string())?;
    let info = TestSshServerInfo {
        port: handle.port,
        host_pubkey_algorithm: handle.host_pubkey_algorithm.clone(),
        host_pubkey_b64: handle.host_pubkey_b64.clone(),
        password: TEST_PASSWORD.to_string(),
        sftp_root: handle.sftp_root.to_string_lossy().into_owned(),
    };
    slot()
        .lock()
        .expect("test_server slot poisoned")
        .push(handle);
    Ok(info)
}

/// Stop every running fixture. Safe to call multiple times — each
/// `shutdown()` on the underlying handle is idempotent.
#[flutter_rust_bridge::frb(sync)]
pub fn test_ssh_server_stop_all() {
    let handles: Vec<TestServerHandle> = slot()
        .lock()
        .expect("test_server slot poisoned")
        .drain(..)
        .collect();
    for h in &handles {
        h.shutdown();
    }
}
