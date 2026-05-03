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
//!   testSshServerStop();
//! });
//! ```

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

/// Single-instance slot. Tests that re-call [`test_ssh_server_start`]
/// while a previous server is still running stop the old one first
/// — keeps the API forgiving for `setUpAll` retries.
fn slot() -> &'static Mutex<Option<TestServerHandle>> {
    static SLOT: OnceLock<Mutex<Option<TestServerHandle>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(None))
}

/// Start the in-process russh-server fixture. Returns the bound
/// port + the OpenSSH-shaped public-key blob the caller seeds
/// into `known_hosts`. Idempotent in the sense that a re-call
/// stops the previous server before starting a fresh one (a fresh
/// host keypair is generated on every call — tests that share a
/// `known_hosts` table across `start` invocations must re-seed
/// the row).
pub async fn test_ssh_server_start() -> Result<TestSshServerInfo, String> {
    if let Some(prev) = slot().lock().expect("test_server slot poisoned").take() {
        prev.shutdown();
    }
    let handle = test_server::start().await.map_err(|e| e.to_string())?;
    let info = TestSshServerInfo {
        port: handle.port,
        host_pubkey_algorithm: handle.host_pubkey_algorithm.clone(),
        host_pubkey_b64: handle.host_pubkey_b64.clone(),
        password: TEST_PASSWORD.to_string(),
        sftp_root: handle.sftp_root.to_string_lossy().into_owned(),
    };
    *slot().lock().expect("test_server slot poisoned") = Some(handle);
    Ok(info)
}

/// Stop the running fixture (no-op if none is running). Safe to
/// call multiple times.
#[flutter_rust_bridge::frb(sync)]
pub fn test_ssh_server_stop() {
    if let Some(handle) = slot().lock().expect("test_server slot poisoned").take() {
        handle.shutdown();
    }
}
