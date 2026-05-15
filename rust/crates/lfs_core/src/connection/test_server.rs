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
//! (`docs/_audit/G03.md` missed all of them) live at the bus
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
//! [`start`] binds 127.0.0.1:0 (random ephemeral port), generates
//! a fresh tempdir under `std::env::temp_dir()` for the SFTP
//! subsystem to back its filesystem ops against, spawns the
//! accept loop on the current tokio runtime, and returns the
//! port + the OpenSSH-shaped host pubkey blob + the absolute
//! path of the SFTP root. The test seeds the running app's
//! `known_hosts` table with the key before calling
//! `connectAsync`, and uses normal `dart:io` to drop fixture
//! files into the SFTP root before the SFTP-side test
//! sequences run. [`TestServerHandle::shutdown`] triggers the
//! notify, the accept loop drops the listener, all in-flight
//! per-connection tasks finish naturally on the next
//! disconnect, and the SFTP root is removed best-effort from
//! disk.

use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use base64::Engine as _;
use russh::keys::ssh_key::rand_core::OsRng;
use russh::keys::{Algorithm, PrivateKey};
use russh::server::{Auth, Config, Handle as ServerHandle, Handler, Msg, Server, Session};
use russh::{Channel, ChannelId};
use russh_sftp::protocol::{
    Attrs, Data, File as SftpFile, FileAttributes, Handle as SftpHandle, Name, OpenFlags, Status,
    StatusCode, Version,
};
use tokio::io::AsyncWriteExt as _;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{Mutex, Notify};
use tokio::task::JoinHandle;

use crate::error::Error;

/// Password the fixture accepts for every user. Hard-coded — tests
/// do not care which password works, they care that *some* known
/// password completes the auth phase deterministically.
pub const TEST_PASSWORD: &str = "letsflutssh-test";

/// Process-wide SFTP-write artificial delay, in milliseconds. The
/// transfer-cancel-mid-flight integration test sets this to widen
/// the cancel race window — without the delay the loopback +
/// per-chunk-open SFTP write completes faster than the cancel can
/// be dispatched from the test process, and the cancel never wins.
/// Sentinel `0` (default) means no delay.
///
/// Read once per `write` call; safe to mutate at any point because
/// every read is `Relaxed`. Tests should reset to 0 in their
/// teardown so a delay set by one test does not bleed into the
/// next.
static SFTP_WRITE_DELAY_MS: AtomicU64 = AtomicU64::new(0);

/// Set the artificial per-`write` SFTP delay. Pass 0 to clear.
/// Any active SFTP write picks up the new value on its next call.
pub fn set_sftp_write_delay_ms(delay_ms: u64) {
    SFTP_WRITE_DELAY_MS.store(delay_ms, Ordering::Relaxed);
}

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
    /// Absolute filesystem path the SFTP subsystem treats as `/`.
    /// Tests can read / write here directly with `dart:io` to
    /// pre-seed fixtures or assert on what an SFTP put landed.
    pub sftp_root: PathBuf,
    shutdown: Arc<Notify>,
}

impl TestServerHandle {
    /// Signal the accept loop to stop and remove the SFTP-root
    /// tempdir. Safe to call multiple times; the tempdir-remove
    /// is best-effort (an in-flight SFTP operation might still
    /// hold a handle, in which case the OS releases the path on
    /// the next sweep).
    pub fn shutdown(&self) {
        self.shutdown.notify_waiters();
        let _ = std::fs::remove_dir_all(&self.sftp_root);
    }
}

/// Start the in-process SSH fixture. Must be called from inside a
/// tokio runtime — uses `tokio::spawn` for the accept loop.
pub async fn start() -> Result<TestServerHandle, Error> {
    let host_key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519)
        .map_err(|e| Error::Transport(format!("test_server: host key gen: {e}")))?;

    let host_pub = host_key.public_key();
    let host_pubkey_algorithm = host_pub.algorithm().as_str().to_string();
    // SSH wire format = the same bytes that show up base64-encoded
    // after the algorithm tag in a standard OpenSSH `authorized_keys`
    // / `known_hosts` line. `ssh-key`'s `to_bytes()` produces exactly
    // that wire encoding for the public-key body.
    let host_pubkey_wire = host_pub
        .to_bytes()
        .map_err(|e| Error::Transport(format!("test_server: pubkey wire: {e}")))?;
    let host_pubkey_b64 = base64::engine::general_purpose::STANDARD.encode(&host_pubkey_wire);

    let sftp_root = std::env::temp_dir().join(format!(
        "letsflutssh-sftp-{}",
        crate::id::random_handle_hex_32()
    ));
    std::fs::create_dir_all(&sftp_root)
        .map_err(|e| Error::Transport(format!("test_server: sftp root mkdir: {e}")))?;

    let listener = TcpListener::bind(("127.0.0.1", 0u16))
        .await
        .map_err(|e| Error::Transport(format!("test_server: bind: {e}")))?;
    let port = listener
        .local_addr()
        .map_err(|e| Error::Transport(format!("test_server: local_addr: {e}")))?
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
    let server_template = TestSshServer {
        sftp_root: Arc::new(sftp_root.clone()),
    };

    // Custom accept loop instead of `Server::run_on_socket` so the
    // listener + per-connection tasks live entirely inside one
    // owned tokio task — `run_on_socket` borrows the listener for
    // the lifetime of its returned future, which is awkward to
    // spawn into a 'static background task.
    tokio::spawn(async move {
        let mut server = server_template;
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
        sftp_root,
        shutdown,
    })
}

/// Per-process server template. The single `Arc<PathBuf>` is the
/// SFTP root every spawned handler shares — every SSH session
/// served by this fixture is rooted at the same tempdir, so a
/// test that wrote to the directory through dart:io and then
/// connected sees the same files as a test that wrote via SFTP
/// PUT and asserted via dart:io read.
#[derive(Clone)]
struct TestSshServer {
    sftp_root: Arc<PathBuf>,
}

impl Server for TestSshServer {
    type Handler = TestSshHandler;
    fn new_client(&mut self, _peer_addr: Option<std::net::SocketAddr>) -> Self::Handler {
        TestSshHandler {
            sftp_root: self.sftp_root.clone(),
            channels: Arc::new(Mutex::new(HashMap::new())),
            remote_forwards: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

/// Active `tcpip_forward` listeners keyed by `(bind_addr, port)`.
/// Dropping the [`JoinHandle`] aborts the accept loop, which drops
/// its `TcpListener` and frees the OS port.
type RemoteForwardMap = Arc<Mutex<HashMap<(String, u32), JoinHandle<()>>>>;

/// Per-SSH-session handler. Holds the channels the SSH side opens
/// so `subsystem_request("sftp")` can pull the matching `Channel`
/// out and feed it into `russh_sftp::server::run`. Also tracks any
/// active server-side `-R` listeners spawned by `tcpip_forward` so
/// `cancel_tcpip_forward` can shut them down.
struct TestSshHandler {
    sftp_root: Arc<PathBuf>,
    channels: Arc<Mutex<HashMap<ChannelId, Channel<Msg>>>>,
    remote_forwards: RemoteForwardMap,
}

impl Handler for TestSshHandler {
    type Error = russh::Error;

    /// Accept the fixed test password for any user; reject every
    /// other input with `Auth::reject` so a misconfigured test
    /// surfaces an Authenticate-phase failure immediately rather
    /// than hanging.
    async fn auth_password(&mut self, _user: &str, password: &str) -> Result<Auth, Self::Error> {
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

    /// Stash the channel by id so a later `subsystem_request("sftp")`
    /// or shell command can fetch it. Necessary because `russh_sftp::
    /// server::run` consumes the `Channel<Msg>` value, but
    /// `subsystem_request` only sees `ChannelId`.
    async fn channel_open_session(
        &mut self,
        channel: Channel<Msg>,
        _session: &mut Session,
    ) -> Result<bool, Self::Error> {
        self.channels.lock().await.insert(channel.id(), channel);
        Ok(true)
    }

    async fn subsystem_request(
        &mut self,
        channel_id: ChannelId,
        name: &str,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        if name == "sftp" {
            let Some(channel) = self.channels.lock().await.remove(&channel_id) else {
                session.channel_failure(channel_id)?;
                return Ok(());
            };
            session.channel_success(channel_id)?;
            let sftp = TestSftpHandler::new(self.sftp_root.clone());
            // run() owns the channel for the rest of the SFTP
            // session; spawn so the handler returns and the SSH
            // side can keep multiplexing other channels.
            tokio::spawn(async move {
                russh_sftp::server::run(channel.into_stream(), sftp).await;
            });
        } else {
            session.channel_failure(channel_id)?;
        }
        Ok(())
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

    /// ProxyJump's `direct-tcpip` channel: a client speaking SSH
    /// to *us* asks us to forward bytes onward to
    /// `host_to_connect:port_to_connect`. The fixture proxies
    /// loopback addresses only — every test target is also a
    /// fixture on 127.0.0.1, so this is sufficient for the
    /// bastion-routed connect path. Non-loopback requests get
    /// rejected (returning `false` makes russh reply
    /// `AdministrativelyProhibited`), which keeps the fixture
    /// from accidentally opening sockets to user-supplied hosts.
    async fn channel_open_direct_tcpip(
        &mut self,
        channel: Channel<Msg>,
        host_to_connect: &str,
        port_to_connect: u32,
        _originator_address: &str,
        _originator_port: u32,
        _session: &mut Session,
    ) -> Result<bool, Self::Error> {
        if host_to_connect != "127.0.0.1" && host_to_connect != "localhost" {
            // Surface the rejection so a CI run using this fixture
            // has a breadcrumb when a test accidentally asks the
            // bastion to dial a non-loopback hop. Stays on stderr
            // (test code, not production); production paths use
            // `app_log_warn!`.
            eprintln!(
                "test_server: refused direct-tcpip to {host_to_connect}:{port_to_connect} \
                 (fixture only proxies loopback)"
            );
            return Ok(false);
        }
        let target = format!("127.0.0.1:{port_to_connect}");
        let tcp = match TcpStream::connect(&target).await {
            Ok(s) => s,
            Err(_) => return Ok(false),
        };
        tokio::spawn(proxy_channel_to_tcp(channel, tcp));
        Ok(true)
    }

    /// `-R` remote forward request: the client asks us to listen
    /// on `address:port` and forward every inbound TCP connection
    /// back over a fresh `forwarded-tcpip` channel. The fixture
    /// binds 127.0.0.1 only — the SSH protocol's `address` value
    /// is informational; ignoring it keeps the fixture from
    /// listening on a non-loopback interface. When `*port` is 0
    /// the OS picks one and we mutate the slot so russh sends the
    /// real number back to the client.
    ///
    /// The accept loop runs as a tokio task; its [`JoinHandle`] is
    /// stored in `remote_forwards` so a later `cancel_tcpip_forward`
    /// can abort it. Each accepted socket spawns its own
    /// `forwarded-tcpip` open-and-proxy task, mirroring how a real
    /// OpenSSH server multiplexes inbound connections onto a single
    /// `tcpip_forward` request.
    async fn tcpip_forward(
        &mut self,
        address: &str,
        port: &mut u32,
        session: &mut Session,
    ) -> Result<bool, Self::Error> {
        let bind_addr = ("127.0.0.1", *port as u16);
        let listener = match TcpListener::bind(bind_addr).await {
            Ok(l) => l,
            Err(_) => return Ok(false),
        };
        let bound = match listener.local_addr() {
            Ok(a) => a,
            Err(_) => return Ok(false),
        };
        let bound_port = bound.port() as u32;
        *port = bound_port;
        let advertised_address = address.to_string();
        let session_handle: ServerHandle = session.handle();

        let key = (advertised_address.clone(), bound_port);
        let forwards = self.remote_forwards.clone();
        // If a slot under the same (addr, port) already exists,
        // abort + replace. Real servers reject overlapping requests
        // with a SUCCESS-vs-FAILURE mismatch; the fixture keeps
        // teardown deterministic instead.
        if let Some(prev) = forwards.lock().await.remove(&key) {
            prev.abort();
        }

        let task = tokio::spawn(remote_forward_accept_loop(
            listener,
            session_handle,
            advertised_address,
            bound_port,
        ));
        forwards.lock().await.insert(key, task);
        Ok(true)
    }

    /// `-R` remote forward cancel: drop the listener handle so the
    /// accept loop aborts and the OS releases the port. Idempotent
    /// on a missing key — returning `Ok(true)` lets the client's
    /// `cancel_tcpip_forward` await resolve cleanly even when the
    /// listener was already torn down (e.g. by a prior test).
    async fn cancel_tcpip_forward(
        &mut self,
        address: &str,
        port: u32,
        _session: &mut Session,
    ) -> Result<bool, Self::Error> {
        if let Some(task) = self
            .remote_forwards
            .lock()
            .await
            .remove(&(address.to_string(), port))
        {
            task.abort();
        }
        Ok(true)
    }
}

/// Per-`tcpip_forward` accept loop. For every inbound TCP socket
/// that lands on `listener`, open a fresh `forwarded-tcpip` channel
/// back to the client through `session_handle` and proxy bytes
/// bidirectionally. Aborts when the parent handler drops the
/// stored `JoinHandle`.
async fn remote_forward_accept_loop(
    listener: TcpListener,
    session_handle: ServerHandle,
    advertised_address: String,
    bound_port: u32,
) {
    loop {
        let (socket, peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(_) => break,
        };
        let session_handle = session_handle.clone();
        let connected_address = advertised_address.clone();
        let originator_address = peer.ip().to_string();
        let originator_port = peer.port() as u32;
        tokio::spawn(async move {
            let channel = match session_handle
                .channel_open_forwarded_tcpip(
                    connected_address,
                    bound_port,
                    originator_address,
                    originator_port,
                )
                .await
            {
                Ok(c) => c,
                Err(_) => return,
            };
            proxy_channel_to_tcp(channel, socket).await;
        });
    }
}

/// Bidirectional pipe between an SSH channel (used as an
/// `AsyncRead + AsyncWrite` stream) and a downstream TCP socket.
/// Used by [`TestSshHandler::channel_open_direct_tcpip`] to wire
/// a ProxyJump child handshake through the bastion fixture.
async fn proxy_channel_to_tcp(channel: Channel<Msg>, tcp: TcpStream) {
    let mut stream = channel.into_stream();
    let (mut tcp_read, mut tcp_write) = tcp.into_split();
    let (mut stream_read, mut stream_write) = tokio::io::split(&mut stream);
    let upstream = async {
        let _ = tokio::io::copy(&mut stream_read, &mut tcp_write).await;
        let _ = tcp_write.shutdown().await;
    };
    let downstream = async {
        let _ = tokio::io::copy(&mut tcp_read, &mut stream_write).await;
        let _ = stream_write.shutdown().await;
    };
    tokio::join!(upstream, downstream);
}

// ─── SFTP subsystem ────────────────────────────────────────────────

/// Filesystem-backed SFTP handler. Every operation resolves the
/// SFTP-absolute path against [`Self::root`] (which is the
/// per-fixture tempdir), and `..` traversal that would escape
/// `root` is rejected with [`StatusCode::PermissionDenied`].
struct TestSftpHandler {
    root: Arc<PathBuf>,
    /// Active dir handles → resolved on-disk path + readdir done flag.
    dir_handles: HashMap<String, DirState>,
    /// Active file handles → resolved on-disk path + open mode.
    file_handles: HashMap<String, FileState>,
    /// Monotonic id assigned to each handle string. Keeps the
    /// strings short and unambiguous.
    next_handle_id: u64,
    version: Option<u32>,
}

struct DirState {
    path: PathBuf,
    done: bool,
}

struct FileState {
    path: PathBuf,
    /// True if the handle was opened with WRITE / APPEND. Used to
    /// skip the metadata-only path for the read-only handle.
    writable: bool,
}

impl TestSftpHandler {
    fn new(root: Arc<PathBuf>) -> Self {
        Self {
            root,
            dir_handles: HashMap::new(),
            file_handles: HashMap::new(),
            next_handle_id: 0,
            version: None,
        }
    }

    fn alloc_handle(&mut self, kind: &str) -> String {
        let id = self.next_handle_id;
        self.next_handle_id = self.next_handle_id.wrapping_add(1);
        format!("{kind}-{id}")
    }

    /// Map an SFTP-absolute path to the on-disk path inside
    /// [`Self::root`]. Reject `..` segments that would escape the
    /// root with [`StatusCode::PermissionDenied`].
    fn resolve(&self, sftp_path: &str) -> Result<PathBuf, StatusCode> {
        let trimmed = sftp_path.trim_start_matches('/');
        let candidate = Path::new(trimmed);
        for c in candidate.components() {
            match c {
                Component::Normal(_) | Component::CurDir => {}
                _ => return Err(StatusCode::PermissionDenied),
            }
        }
        Ok(self.root.join(candidate))
    }

    fn attrs_from_metadata(meta: &std::fs::Metadata) -> FileAttributes {
        FileAttributes {
            size: Some(meta.len()),
            permissions: Some(if meta.is_dir() { 0o040755 } else { 0o100644 }),
            ..FileAttributes::default()
        }
    }
}

impl russh_sftp::server::Handler for TestSftpHandler {
    type Error = StatusCode;

    fn unimplemented(&self) -> Self::Error {
        StatusCode::OpUnsupported
    }

    async fn init(
        &mut self,
        version: u32,
        _extensions: HashMap<String, String>,
    ) -> Result<Version, Self::Error> {
        if self.version.is_some() {
            return Err(StatusCode::ConnectionLost);
        }
        self.version = Some(version);
        Ok(Version::new())
    }

    async fn realpath(&mut self, id: u32, path: String) -> Result<Name, Self::Error> {
        // The russh-sftp client's `canonicalize` issues a realpath
        // for "." right after init. Always anchor at "/" — the
        // fixture's tempdir is the SFTP root, paths above it are
        // not addressable.
        let display = if path == "." || path.is_empty() {
            "/".to_string()
        } else {
            let normalised = path.replace("//", "/");
            let trimmed = normalised.trim_end_matches('/');
            if trimmed.is_empty() {
                "/".to_string()
            } else {
                trimmed.to_string()
            }
        };
        Ok(Name {
            id,
            files: vec![SftpFile::dummy(display)],
        })
    }

    async fn opendir(&mut self, id: u32, path: String) -> Result<SftpHandle, Self::Error> {
        let on_disk = self.resolve(&path)?;
        let meta = std::fs::metadata(&on_disk).map_err(io_to_status)?;
        if !meta.is_dir() {
            return Err(StatusCode::NoSuchFile);
        }
        let handle = self.alloc_handle("dir");
        self.dir_handles.insert(
            handle.clone(),
            DirState {
                path: on_disk,
                done: false,
            },
        );
        Ok(SftpHandle { id, handle })
    }

    async fn readdir(&mut self, id: u32, handle: String) -> Result<Name, Self::Error> {
        let state = self
            .dir_handles
            .get_mut(&handle)
            .ok_or(StatusCode::NoSuchFile)?;
        if state.done {
            return Err(StatusCode::Eof);
        }
        let mut files: Vec<SftpFile> = Vec::new();
        let read_dir = std::fs::read_dir(&state.path).map_err(io_to_status)?;
        for entry in read_dir {
            let entry = entry.map_err(io_to_status)?;
            let name = entry.file_name().to_string_lossy().into_owned();
            let meta = entry.metadata().map_err(io_to_status)?;
            files.push(SftpFile::new(
                name,
                TestSftpHandler::attrs_from_metadata(&meta),
            ));
        }
        state.done = true;
        Ok(Name { id, files })
    }

    async fn close(&mut self, id: u32, handle: String) -> Result<Status, Self::Error> {
        self.dir_handles.remove(&handle);
        self.file_handles.remove(&handle);
        Ok(ok_status(id))
    }

    async fn open(
        &mut self,
        id: u32,
        filename: String,
        pflags: OpenFlags,
        _attrs: FileAttributes,
    ) -> Result<SftpHandle, Self::Error> {
        let on_disk = self.resolve(&filename)?;
        let mut opts = std::fs::OpenOptions::new();
        let writable = pflags.contains(OpenFlags::WRITE) || pflags.contains(OpenFlags::APPEND);
        opts.read(pflags.contains(OpenFlags::READ));
        opts.write(writable);
        opts.append(pflags.contains(OpenFlags::APPEND));
        opts.create(pflags.contains(OpenFlags::CREATE));
        opts.truncate(pflags.contains(OpenFlags::TRUNCATE));
        // Probe-open just to surface ENOENT / EPERM through the
        // SFTP error channel — we re-open per read/write so the
        // handler can remain `Send + Sync` without holding a
        // `std::fs::File`.
        let _probe = opts.open(&on_disk).map_err(io_to_status)?;
        let handle = self.alloc_handle("file");
        self.file_handles.insert(
            handle.clone(),
            FileState {
                path: on_disk,
                writable,
            },
        );
        Ok(SftpHandle { id, handle })
    }

    async fn read(
        &mut self,
        id: u32,
        handle: String,
        offset: u64,
        len: u32,
    ) -> Result<Data, Self::Error> {
        use std::io::{Read as _, Seek as _, SeekFrom};
        let state = self
            .file_handles
            .get(&handle)
            .ok_or(StatusCode::NoSuchFile)?;
        let mut file = std::fs::OpenOptions::new()
            .read(true)
            .open(&state.path)
            .map_err(io_to_status)?;
        file.seek(SeekFrom::Start(offset)).map_err(io_to_status)?;
        let mut buf = vec![0u8; len as usize];
        let n = file.read(&mut buf).map_err(io_to_status)?;
        if n == 0 {
            return Err(StatusCode::Eof);
        }
        buf.truncate(n);
        Ok(Data { id, data: buf })
    }

    async fn write(
        &mut self,
        id: u32,
        handle: String,
        offset: u64,
        data: Vec<u8>,
    ) -> Result<Status, Self::Error> {
        use std::io::{Seek as _, SeekFrom, Write as _};
        // Honor the process-wide write delay knob — the
        // transfer-cancel-mid-flight integration test sets this so
        // the cancel race window is wide enough to hit reliably on
        // localhost loopback. Sentinel 0 means no delay.
        let delay_ms = SFTP_WRITE_DELAY_MS.load(Ordering::Relaxed);
        if delay_ms > 0 {
            tokio::time::sleep(Duration::from_millis(delay_ms)).await;
        }
        let state = self
            .file_handles
            .get(&handle)
            .ok_or(StatusCode::NoSuchFile)?;
        if !state.writable {
            return Err(StatusCode::PermissionDenied);
        }
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .open(&state.path)
            .map_err(io_to_status)?;
        file.seek(SeekFrom::Start(offset)).map_err(io_to_status)?;
        file.write_all(&data).map_err(io_to_status)?;
        Ok(ok_status(id))
    }

    async fn stat(&mut self, id: u32, path: String) -> Result<Attrs, Self::Error> {
        let on_disk = self.resolve(&path)?;
        let meta = std::fs::metadata(&on_disk).map_err(io_to_status)?;
        Ok(Attrs {
            id,
            attrs: TestSftpHandler::attrs_from_metadata(&meta),
        })
    }

    async fn lstat(&mut self, id: u32, path: String) -> Result<Attrs, Self::Error> {
        let on_disk = self.resolve(&path)?;
        let meta = std::fs::symlink_metadata(&on_disk).map_err(io_to_status)?;
        Ok(Attrs {
            id,
            attrs: TestSftpHandler::attrs_from_metadata(&meta),
        })
    }

    async fn fstat(&mut self, id: u32, handle: String) -> Result<Attrs, Self::Error> {
        let state = self
            .file_handles
            .get(&handle)
            .ok_or(StatusCode::NoSuchFile)?;
        let meta = std::fs::metadata(&state.path).map_err(io_to_status)?;
        Ok(Attrs {
            id,
            attrs: TestSftpHandler::attrs_from_metadata(&meta),
        })
    }

    async fn remove(&mut self, id: u32, filename: String) -> Result<Status, Self::Error> {
        let on_disk = self.resolve(&filename)?;
        std::fs::remove_file(&on_disk).map_err(io_to_status)?;
        Ok(ok_status(id))
    }

    async fn mkdir(
        &mut self,
        id: u32,
        path: String,
        _attrs: FileAttributes,
    ) -> Result<Status, Self::Error> {
        let on_disk = self.resolve(&path)?;
        std::fs::create_dir(&on_disk).map_err(io_to_status)?;
        Ok(ok_status(id))
    }

    async fn rmdir(&mut self, id: u32, path: String) -> Result<Status, Self::Error> {
        let on_disk = self.resolve(&path)?;
        std::fs::remove_dir(&on_disk).map_err(io_to_status)?;
        Ok(ok_status(id))
    }

    async fn rename(
        &mut self,
        id: u32,
        oldpath: String,
        newpath: String,
    ) -> Result<Status, Self::Error> {
        let from = self.resolve(&oldpath)?;
        let to = self.resolve(&newpath)?;
        std::fs::rename(&from, &to).map_err(io_to_status)?;
        Ok(ok_status(id))
    }

    async fn setstat(
        &mut self,
        id: u32,
        _path: String,
        _attrs: FileAttributes,
    ) -> Result<Status, Self::Error> {
        // Tests do not assert on chmod; ignore + return Ok so a
        // client-side `setstat(644)` after upload doesn't trip
        // the SFTP-error path.
        Ok(ok_status(id))
    }

    async fn fsetstat(
        &mut self,
        id: u32,
        _handle: String,
        _attrs: FileAttributes,
    ) -> Result<Status, Self::Error> {
        Ok(ok_status(id))
    }
}

fn ok_status(id: u32) -> Status {
    Status {
        id,
        status_code: StatusCode::Ok,
        error_message: "Ok".to_string(),
        language_tag: "en-US".to_string(),
    }
}

fn io_to_status(err: std::io::Error) -> StatusCode {
    match err.kind() {
        std::io::ErrorKind::NotFound => StatusCode::NoSuchFile,
        std::io::ErrorKind::PermissionDenied => StatusCode::PermissionDenied,
        std::io::ErrorKind::AlreadyExists => StatusCode::Failure,
        std::io::ErrorKind::UnexpectedEof => StatusCode::Eof,
        _ => StatusCode::Failure,
    }
}
