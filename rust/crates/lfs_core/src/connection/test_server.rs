//! In-process russh-server fixture for end-to-end connection tests.
//!
//! Always compiled into the .so. Feature-gating it behind a Cargo
//! flag broke the FRB-generated bindings story: `frb_generated.rs`
//! is committed to git and reflects a single `--rust-features` set,
//! so test-only modules either pollute the working tree on every
//! `make test` (test codegen rewrites the committed file) or break
//! the production build (production codegen drops references the
//! test build expects). Shipping the fixture unconditionally costs
//! ~50 KB of dead code in the release `.so` — production callers
//! never invoke [`start`], the listener only ever binds 127.0.0.1,
//! and the hard-coded test password is meaningless to anyone who
//! isn't already on the loopback interface AND running the test
//! suite. The cost is well below the price of keeping the build
//! bifurcated.
//!
//! # Why an embedded server (vs. a static-event-driver fake)
//!
//! The four race conditions this scaffolding exists to catch
//! ([`docs/_audit/G03.md`] missed all of them) live at the bus
//! delivery boundary between the real Rust connect actor and the
//! Dart-side observation pipeline. Fake event emitters reproduce
//! the *shape* of the bus traffic but not the *timing* — the bug
//! window is the gap between when `connection_connect` resolves
//! and when the post-success events drain Dart's microtask queue,
//! and only a real handshake against a real listener exercises
//! that window deterministically. The fixture has zero system
//! dependencies (pure-Rust russh server, no `apt install
//! openssh-server`), accepts a fixed password for any user, and
//! generates a fresh Ed25519 host keypair on each [`start`] so
//! repeated test runs do not need to flush a known_hosts row.
//!
//! # Lifecycle
//!
//! [`start`] binds 127.0.0.1:0 (random ephemeral port), spawns
//! the accept loop on the current tokio runtime, and returns the
//! port + the OpenSSH-shaped host pubkey blob. The test then
//! seeds the running app's `known_hosts` table with that key
//! before calling `connectAsync`. [`TestServerHandle::shutdown`]
//! triggers a notify, the accept loop drops the listener, all
//! in-flight per-connection tasks finish naturally on the next
//! disconnect.

use std::sync::Arc;

use base64::Engine as _;
use russh::keys::ssh_key::rand_core::OsRng;
use russh::keys::{Algorithm, PrivateKey};
use russh::server::{Auth, Config, Handler, Msg, Server, Session};
use russh::{Channel, ChannelId};
use tokio::net::TcpListener;
use tokio::sync::Notify;

use crate::error::Error;

/// Password the fixture accepts for every user. Hard-coded — tests
/// do not care which password works, they care that *some* known
/// password completes the auth phase deterministically.
pub const TEST_PASSWORD: &str = "letsflutssh-test";

/// Handle returned to the caller. Drop without calling
/// [`shutdown`] still terminates the server eventually (the
/// `Arc<Notify>` count drops to zero and the spawned task's
/// listener is dropped on the next iteration), but tests should
/// always invoke `shutdown()` in `tearDown` so the listening
/// socket is released before the next group runs.
pub struct TestServerHandle {
    /// Bound localhost port — the test passes this to
    /// `connectAsync(host: '127.0.0.1', port: ...)`.
    pub port: u16,
    /// `"ssh-ed25519"` — the value the `known_hosts` row's
    /// `key_type` column expects.
    pub host_pubkey_algorithm: String,
    /// Base64 blob of the SSH wire-format public key. Matches
    /// what `lfs_core::known_hosts` stores in `key_base64` after
    /// stripping the `"ssh-ed25519 "` prefix from a normal
    /// OpenSSH public-key line.
    pub host_pubkey_b64: String,
    shutdown: Arc<Notify>,
}

impl TestServerHandle {
    /// Signal the accept loop to stop. Safe to call multiple
    /// times; subsequent notifies are no-ops once the loop has
    /// observed the first one.
    pub fn shutdown(&self) {
        self.shutdown.notify_waiters();
    }
}

/// Start the in-process SSH fixture. Must be called from inside a
/// tokio runtime — uses `tokio::spawn` for the accept loop.
pub async fn start() -> Result<TestServerHandle, Error> {
    let host_key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519)
        .map_err(|e| Error::Io(format!("test_server: host key gen: {e}")))?;

    let host_pub = host_key.public_key();
    let host_pubkey_algorithm = host_pub.algorithm().as_str().to_string();
    // SSH wire format = the same bytes that show up base64-encoded
    // after the algorithm tag in a standard OpenSSH `authorized_keys`
    // / `known_hosts` line. `ssh-key`'s `to_bytes()` produces exactly
    // that wire encoding for the public-key body.
    let host_pubkey_wire = host_pub
        .to_bytes()
        .map_err(|e| Error::Io(format!("test_server: pubkey wire: {e}")))?;
    let host_pubkey_b64 = base64::engine::general_purpose::STANDARD.encode(&host_pubkey_wire);

    let listener = TcpListener::bind(("127.0.0.1", 0u16))
        .await
        .map_err(|e| Error::Io(format!("test_server: bind: {e}")))?;
    let port = listener
        .local_addr()
        .map_err(|e| Error::Io(format!("test_server: local_addr: {e}")))?
        .port();

    let config = Arc::new(Config {
        inactivity_timeout: Some(std::time::Duration::from_secs(60)),
        auth_rejection_time: std::time::Duration::from_millis(50),
        auth_rejection_time_initial: Some(std::time::Duration::from_millis(0)),
        keys: vec![host_key],
        ..Config::default()
    });

    let shutdown = Arc::new(Notify::new());
    let shutdown_for_loop = shutdown.clone();
    let mut server = TestSshServer;

    // Custom accept loop instead of `Server::run_on_socket` so the
    // listener + per-connection tasks live entirely inside one
    // owned tokio task — `run_on_socket` borrows the listener for
    // the lifetime of its returned future, which is awkward to
    // spawn into a 'static background task.
    tokio::spawn(async move {
        loop {
            tokio::select! {
                biased;
                _ = shutdown_for_loop.notified() => break,
                accept = listener.accept() => {
                    match accept {
                        Ok((stream, _peer)) => {
                            let cfg = config.clone();
                            let handler = server.new_client(None);
                            tokio::spawn(async move {
                                let _ = russh::server::run_stream(cfg, stream, handler).await;
                            });
                        }
                        Err(_) => break,
                    }
                }
            }
        }
    });

    Ok(TestServerHandle {
        port,
        host_pubkey_algorithm,
        host_pubkey_b64,
        shutdown,
    })
}

/// Per-process server template. Russh constructs one `Handler` per
/// inbound TCP socket via [`Server::new_client`]; the template
/// itself carries no state because per-handler initialisation is
/// what kept stateful in the upstream echoserver pattern.
#[derive(Clone)]
struct TestSshServer;

impl Server for TestSshServer {
    type Handler = TestSshHandler;
    fn new_client(&mut self, _peer_addr: Option<std::net::SocketAddr>) -> Self::Handler {
        TestSshHandler
    }
}

#[derive(Default)]
struct TestSshHandler;

impl Handler for TestSshHandler {
    type Error = russh::Error;

    /// Accept the fixed test password for any user; reject every
    /// other input with `Auth::reject` so a misconfigured test
    /// surfaces an Authenticate-phase failure immediately rather
    /// than hanging.
    async fn auth_password(
        &mut self,
        _user: &str,
        password: &str,
    ) -> Result<Auth, Self::Error> {
        if password == TEST_PASSWORD {
            Ok(Auth::Accept)
        } else {
            Ok(Auth::reject())
        }
    }

    /// Accept any pubkey for any user — public-key tests do not
    /// care about the cryptographic identity, only that the auth
    /// phase succeeds.
    async fn auth_publickey(
        &mut self,
        _user: &str,
        _key: &russh::keys::ssh_key::PublicKey,
    ) -> Result<Auth, Self::Error> {
        Ok(Auth::Accept)
    }

    /// Accept session-channel opens — needed for tests that exercise
    /// `openShell` after the connect has settled. The bare-connect
    /// lifecycle test never gets here, but having the handler in
    /// place keeps the fixture useful for the next consumer.
    async fn channel_open_session(
        &mut self,
        _channel: Channel<Msg>,
        _session: &mut Session,
    ) -> Result<bool, Self::Error> {
        Ok(true)
    }

    /// Accept pty + shell so an `openShell` consumer can drive a
    /// `Channel`. The fixture does not actually run a shell — the
    /// channel sits idle until the client closes it.
    async fn pty_request(
        &mut self,
        _channel: ChannelId,
        _term: &str,
        _col_width: u32,
        _row_height: u32,
        _pix_width: u32,
        _pix_height: u32,
        _modes: &[(russh::Pty, u32)],
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn shell_request(
        &mut self,
        _channel: ChannelId,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        Ok(())
    }
}
