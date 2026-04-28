//! Port-forward listener / accept-loop pump.
//!
//! Generic over a channel-factory closure so tests can inject a
//! plain in-process pipe pair (or a TCP echo server) instead of
//! a real `russh` `direct-tcpip` channel. The same pump body
//! production uses runs against any `(AsyncRead + AsyncWrite)`
//! pair the factory returns.
//!
//! Lifecycle: [`spawn_listener`] returns a [`ListenerHandle`]
//! whose `Drop` aborts the inner task. Status events
//! (`Listening` / `Error`) flow through the supplied
//! [`StatusReporter`] — production wires it onto the
//! `EventBus`; tests collect events into a `Vec`.
//!
//! Out of scope here: a single-shot connect loop (the russh
//! direct-tcpip channel returns one stream pair per accepted
//! socket, so the production driver wires the factory to call
//! `Session::open_direct_tcpip` per accept).

use std::future::Future;
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::Arc;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;

use crate::error::Error;
use crate::portforward::RuleStatus;

/// Status event reporter. Production threads to the event bus
/// (publish `PortForwardStatus`); tests buffer into a `Vec`.
pub trait StatusReporter: Send + Sync {
    fn report(&self, status: RuleStatus, detail: Option<String>);
}

/// Production reporter — owns a rule id + an `Arc` to the
/// running `AppState` and routes every status event through
/// `PortForwardRegistry::set_status` so subscribers receive
/// the bus event for free.
pub struct AppStatusReporter {
    rule_id: String,
}

impl AppStatusReporter {
    pub fn new(rule_id: impl Into<String>) -> Self {
        Self {
            rule_id: rule_id.into(),
        }
    }
}

impl StatusReporter for AppStatusReporter {
    fn report(&self, status: RuleStatus, detail: Option<String>) {
        let app = crate::app::instance();
        app.port_forwards
            .set_status(&self.rule_id, status, detail, &app.bus);
    }
}

/// Reader half handed back from a [`ChannelFactory`] open. A
/// trait object wrapper keeps the API monomorphisation-free
/// — production wraps russh `ChannelReadHalf`, tests wrap
/// `tokio::io::DuplexStream`.
pub type ReaderHalf = Pin<Box<dyn AsyncRead + Send + 'static>>;
/// Writer half handed back from a [`ChannelFactory`] open.
pub type WriterHalf = Pin<Box<dyn AsyncWrite + Send + 'static>>;

/// Future the [`ChannelFactory::open`] call returns. Aliased
/// out of the trait so the type stays readable inline.
pub type OpenFuture =
    Pin<Box<dyn Future<Output = Result<(ReaderHalf, WriterHalf), Error>> + Send + 'static>>;

/// Open a fresh upstream channel for one accepted socket. The
/// production wiring calls `Session::open_direct_tcpip_stream`
/// and splits the result; tests return `tokio::io::duplex`
/// halves.
pub trait ChannelFactory: Send + Sync + 'static {
    fn open(&self, peer: SocketAddr) -> OpenFuture;
}

/// Production [`ChannelFactory`] impl that resolves each accept
/// to a fresh russh `direct-tcpip` channel against the supplied
/// session. `target_host` / `target_port` are the remote
/// endpoint russh asks the server to connect to; the originator
/// address + port carry the local peer's tuple for the SSH
/// protocol's logging field.
pub struct DirectTcpipFactory {
    session: std::sync::Arc<crate::ssh::Session>,
    target_host: String,
    target_port: u16,
}

impl DirectTcpipFactory {
    pub fn new(
        session: std::sync::Arc<crate::ssh::Session>,
        target_host: String,
        target_port: u16,
    ) -> Self {
        Self {
            session,
            target_host,
            target_port,
        }
    }
}

impl ChannelFactory for DirectTcpipFactory {
    fn open(&self, peer: SocketAddr) -> OpenFuture {
        let session = self.session.clone();
        let host = self.target_host.clone();
        let port = self.target_port as u32;
        Box::pin(async move {
            let stream = session
                .open_direct_tcpip_stream(&host, port, &peer.ip().to_string(), peer.port() as u32)
                .await?;
            let (r, w) = tokio::io::split(stream);
            let reader: ReaderHalf = Box::pin(r);
            let writer: WriterHalf = Box::pin(w);
            Ok((reader, writer))
        })
    }
}

/// Handle owning the spawned listener task. Dropping aborts
/// the task — the OS frees the listening socket as soon as
/// the task's `TcpListener` drops.
pub struct ListenerHandle {
    inner: JoinHandle<()>,
    bound: SocketAddr,
}

impl ListenerHandle {
    pub fn bound_addr(&self) -> SocketAddr {
        self.bound
    }

    pub fn abort(&self) {
        self.inner.abort();
    }
}

impl Drop for ListenerHandle {
    fn drop(&mut self) {
        self.inner.abort();
    }
}

/// Bind a [`TcpListener`] and spawn the accept loop. Each
/// accepted socket dispatches a background task that:
///   1. Calls `factory.open(peer)` for an upstream channel.
///   2. Pumps bytes bidirectionally between socket and channel
///      until either side closes.
///
/// Returns once the listener is bound (or fails to bind);
/// the accept loop runs in the background. `bind_addr` of
/// `0.0.0.0:0` (or `[::]:0`) lets the OS pick a port — the
/// returned [`ListenerHandle::bound_addr`] reports the actual
/// port for tests / UI.
pub async fn spawn_listener(
    bind_addr: SocketAddr,
    factory: Arc<dyn ChannelFactory>,
    reporter: Arc<dyn StatusReporter>,
) -> Result<ListenerHandle, Error> {
    let listener = match TcpListener::bind(bind_addr).await {
        Ok(l) => l,
        Err(e) => {
            reporter.report(RuleStatus::Error, Some(e.to_string()));
            return Err(Error::Io(format!("bind {bind_addr}: {e}")));
        }
    };
    let bound = listener
        .local_addr()
        .map_err(|e| Error::Io(format!("local_addr: {e}")))?;
    reporter.report(RuleStatus::Listening, None);

    let task = tokio::spawn(accept_loop(listener, factory, reporter));
    Ok(ListenerHandle { inner: task, bound })
}

async fn accept_loop(
    listener: TcpListener,
    factory: Arc<dyn ChannelFactory>,
    reporter: Arc<dyn StatusReporter>,
) {
    loop {
        let (socket, peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(e) => {
                reporter.report(RuleStatus::Error, Some(e.to_string()));
                continue;
            }
        };
        let f = factory.clone();
        tokio::spawn(async move {
            match f.open(peer).await {
                Ok((reader, writer)) => {
                    let _ = pump(socket, reader, writer).await;
                }
                Err(_) => {
                    // Per-accept failure is logged through the
                    // reporter at the registry level; here we
                    // just drop the socket so the client sees
                    // a connection-refused on read.
                }
            }
        });
    }
}

/// Bind a SOCKS5 dynamic-forward listener (`-D`). Each accepted
/// socket runs the SOCKS5 CONNECT handshake (RFC 1928, NO_AUTH
/// only — same shape the Dart-side path enforced) and on success
/// opens a fresh `direct-tcpip` channel to the target the client
/// asked for, then pumps bytes bidirectionally.
///
/// Bind contract matches [`spawn_listener`]: returns once the
/// listener is bound (or fails to bind); the accept loop runs
/// in the background. `bind_addr` of `127.0.0.1:0` lets the OS
/// pick a port — the returned [`ListenerHandle::bound_addr`]
/// reports the actual port for the UI.
pub async fn spawn_socks5_listener(
    bind_addr: SocketAddr,
    session: Arc<crate::ssh::Session>,
    reporter: Arc<dyn StatusReporter>,
) -> Result<ListenerHandle, Error> {
    let listener = match TcpListener::bind(bind_addr).await {
        Ok(l) => l,
        Err(e) => {
            reporter.report(RuleStatus::Error, Some(e.to_string()));
            return Err(Error::Io(format!("bind {bind_addr}: {e}")));
        }
    };
    let bound = listener
        .local_addr()
        .map_err(|e| Error::Io(format!("local_addr: {e}")))?;
    reporter.report(RuleStatus::Listening, None);

    let task = tokio::spawn(socks5_accept_loop(listener, session, reporter));
    Ok(ListenerHandle { inner: task, bound })
}

async fn socks5_accept_loop(
    listener: TcpListener,
    session: Arc<crate::ssh::Session>,
    reporter: Arc<dyn StatusReporter>,
) {
    loop {
        let (socket, peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(e) => {
                reporter.report(RuleStatus::Error, Some(e.to_string()));
                continue;
            }
        };
        let session = session.clone();
        tokio::spawn(async move {
            let _ = handle_socks5_client(socket, peer, session).await;
        });
    }
}

async fn handle_socks5_client(
    mut socket: TcpStream,
    peer: SocketAddr,
    session: Arc<crate::ssh::Session>,
) -> Result<(), Error> {
    // Greeting: [VER=0x05][NMETHODS][methods…]
    let mut greeting = [0u8; 2];
    socket
        .read_exact(&mut greeting)
        .await
        .map_err(|e| Error::Io(format!("socks5 greeting: {e}")))?;
    if greeting[0] != 0x05 {
        let _ = socks5_fail(&mut socket, 0x07).await;
        return Err(Error::Io("socks5: bad version in greeting".into()));
    }
    let n_methods = greeting[1] as usize;
    let mut methods = vec![0u8; n_methods];
    socket
        .read_exact(&mut methods)
        .await
        .map_err(|e| Error::Io(format!("socks5 methods: {e}")))?;
    // Always pick NO_AUTH (0x00). If the client didn't offer it,
    // the connect will fail at the request stage; auth selection
    // is fixed at the Dart-era behaviour.
    socket
        .write_all(&[0x05, 0x00])
        .await
        .map_err(|e| Error::Io(format!("socks5 method ack: {e}")))?;

    // Request: [VER=0x05][CMD=0x01 CONNECT][RSV=0x00][ATYP][…]
    let mut head = [0u8; 4];
    socket
        .read_exact(&mut head)
        .await
        .map_err(|e| Error::Io(format!("socks5 req head: {e}")))?;
    if head[0] != 0x05 {
        let _ = socks5_fail(&mut socket, 0x07).await;
        return Err(Error::Io("socks5: bad version in request".into()));
    }
    if head[1] != 0x01 {
        let _ = socks5_fail(&mut socket, 0x07).await;
        return Err(Error::Io("socks5: only CONNECT supported".into()));
    }
    let host = match head[3] {
        0x01 => {
            let mut addr = [0u8; 4];
            socket
                .read_exact(&mut addr)
                .await
                .map_err(|e| Error::Io(format!("socks5 ipv4: {e}")))?;
            format!("{}.{}.{}.{}", addr[0], addr[1], addr[2], addr[3])
        }
        0x03 => {
            let mut len = [0u8; 1];
            socket
                .read_exact(&mut len)
                .await
                .map_err(|e| Error::Io(format!("socks5 domain len: {e}")))?;
            let mut domain = vec![0u8; len[0] as usize];
            socket
                .read_exact(&mut domain)
                .await
                .map_err(|e| Error::Io(format!("socks5 domain: {e}")))?;
            String::from_utf8(domain).map_err(|_| Error::Io("socks5: domain not utf-8".into()))?
        }
        0x04 => {
            let mut addr = [0u8; 16];
            socket
                .read_exact(&mut addr)
                .await
                .map_err(|e| Error::Io(format!("socks5 ipv6: {e}")))?;
            format_ipv6(&addr)
        }
        _ => {
            let _ = socks5_fail(&mut socket, 0x08).await;
            return Err(Error::Io("socks5: unsupported address type".into()));
        }
    };
    let mut port_bytes = [0u8; 2];
    socket
        .read_exact(&mut port_bytes)
        .await
        .map_err(|e| Error::Io(format!("socks5 port: {e}")))?;
    let port = ((port_bytes[0] as u16) << 8) | port_bytes[1] as u16;

    // Open direct-tcpip channel to the target.
    let stream = match session
        .open_direct_tcpip_stream(
            &host,
            port as u32,
            &peer.ip().to_string(),
            peer.port() as u32,
        )
        .await
    {
        Ok(s) => s,
        Err(e) => {
            let _ = socks5_fail(&mut socket, 0x05).await;
            return Err(e);
        }
    };

    // Reply: success. BND values are zero — clients ignore them
    // for CONNECT against a SOCKS5 over SSH.
    socket
        .write_all(&[0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        .await
        .map_err(|e| Error::Io(format!("socks5 reply: {e}")))?;

    let (r, w) = tokio::io::split(stream);
    let reader: ReaderHalf = Box::pin(r);
    let writer: WriterHalf = Box::pin(w);
    pump(socket, reader, writer).await
}

async fn socks5_fail(socket: &mut TcpStream, rep: u8) -> std::io::Result<()> {
    socket
        .write_all(&[0x05, rep, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        .await?;
    socket.flush().await
}

fn format_ipv6(bytes: &[u8; 16]) -> String {
    let mut groups = Vec::with_capacity(8);
    for i in (0..16).step_by(2) {
        let word = ((bytes[i] as u16) << 8) | bytes[i + 1] as u16;
        groups.push(format!("{word:x}"));
    }
    groups.join(":")
}

/// Handle owning the spawned `-R` dispatcher task plus the
/// session-side route registration. Dropping aborts the bridge
/// task, withdraws the route from the session's dispatcher, and
/// asks the server to stop listening on the bound port.
///
/// The post-Drop teardown is fire-and-forget — the unregister +
/// cancel run on a detached tokio task because `Drop` cannot be
/// async itself. The handle goes away promptly; the network-side
/// withdrawal lands a moment later.
pub struct RemoteForwardHandle {
    inner: JoinHandle<()>,
    session: Arc<crate::ssh::Session>,
    bind_host: String,
    bound_port: u32,
}

impl RemoteForwardHandle {
    pub fn bound_port(&self) -> u32 {
        self.bound_port
    }

    pub fn abort(&self) {
        self.inner.abort();
    }
}

impl Drop for RemoteForwardHandle {
    fn drop(&mut self) {
        self.inner.abort();
        let session = self.session.clone();
        let host = self.bind_host.clone();
        let port = self.bound_port;
        tokio::spawn(async move {
            session.unregister_remote_forward_route(&host, port).await;
            // Best-effort — the channel may already be torn down.
            let _ = session.cancel_remote_forward(&host, port).await;
        });
    }
}

/// Start a Rust-driven `-R` remote-forward against the supplied
/// session. Asks the server to listen on
/// `bind_host:bind_port` (passing 0 lets the server pick), then
/// registers a route through the session-level dispatcher and
/// spawns a bridge task that, per inbound forwarded connection,
/// opens a local TCP connection to `target_host:target_port` and
/// pumps bytes bidirectionally.
///
/// Status events (`Listening` / `Error`) flow onto the bus
/// through the supplied [`StatusReporter`]. Bridge teardown is
/// driven by [`RemoteForwardHandle`]'s `Drop` impl.
pub async fn spawn_remote_forward(
    session: Arc<crate::ssh::Session>,
    bind_host: String,
    bind_port: u32,
    target_host: String,
    target_port: u16,
    reporter: Arc<dyn StatusReporter>,
) -> Result<RemoteForwardHandle, Error> {
    let bound_port = match session.request_remote_forward(&bind_host, bind_port).await {
        Ok(p) => p,
        Err(e) => {
            reporter.report(RuleStatus::Error, Some(e.to_string()));
            return Err(e);
        }
    };
    let mut rx = session
        .register_remote_forward_route(bind_host.clone(), bound_port)
        .await;
    reporter.report(RuleStatus::Listening, None);

    let target_host_inner = target_host.clone();
    let task = tokio::spawn(async move {
        while let Some(conn) = rx.recv().await {
            let target_host = target_host_inner.clone();
            tokio::spawn(async move {
                let _ = bridge_forward_to_local_tcp(conn.channel, &target_host, target_port).await;
            });
        }
    });

    Ok(RemoteForwardHandle {
        inner: task,
        session,
        bind_host,
        bound_port,
    })
}

/// Bridge one inbound `-R` `ForwardChannel` to a fresh local TCP
/// connection at `(target_host, target_port)`. Each direction
/// runs to completion in its own task; either side closing tears
/// down the counterpart.
async fn bridge_forward_to_local_tcp(
    channel: crate::ssh::ForwardChannel,
    target_host: &str,
    target_port: u16,
) -> Result<(), Error> {
    let socket = TcpStream::connect((target_host, target_port))
        .await
        .map_err(|e| Error::Io(format!("connect {target_host}:{target_port}: {e}")))?;
    let (mut sock_r, mut sock_w) = socket.into_split();
    let channel = Arc::new(channel);

    let chan_to_sock = {
        let channel = channel.clone();
        tokio::spawn(async move {
            while let Some(bytes) = channel.read().await {
                if sock_w.write_all(&bytes).await.is_err() {
                    break;
                }
            }
            let _ = sock_w.shutdown().await;
        })
    };

    let sock_to_chan = {
        let channel = channel.clone();
        tokio::spawn(async move {
            let mut buf = vec![0u8; 16 * 1024];
            loop {
                let n = match sock_r.read(&mut buf).await {
                    Ok(0) | Err(_) => break,
                    Ok(n) => n,
                };
                if channel.write(&buf[..n]).await.is_err() {
                    break;
                }
            }
            let _ = channel.eof().await;
        })
    };

    let _ = chan_to_sock.await;
    let _ = sock_to_chan.await;
    Ok(())
}

/// Bidirectional copy between an accepted [`TcpStream`] and an
/// upstream channel reader / writer pair. Each direction runs
/// to completion: client shutting down the write side
/// propagates an EOF + writer-shutdown into the channel, the
/// peer drains, and the channel reader returns its final
/// bytes before the downstream side closes the socket.
pub async fn pump(socket: TcpStream, reader: ReaderHalf, writer: WriterHalf) -> Result<(), Error> {
    let (sock_r, sock_w) = socket.into_split();

    let upstream = tokio::spawn(copy_one_way_owned(sock_r, writer));
    let downstream = tokio::spawn(copy_one_way_owned(reader, sock_w));

    let _ = upstream.await;
    let _ = downstream.await;
    Ok(())
}

async fn copy_one_way_owned<R, W>(reader: R, writer: W)
where
    R: AsyncRead + Unpin + Send + 'static,
    W: AsyncWrite + Unpin + Send + 'static,
{
    copy_one_way(reader, writer).await
}

async fn copy_one_way<R, W>(mut reader: R, mut writer: W)
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut buf = vec![0u8; 16 * 1024];
    loop {
        let n = match reader.read(&mut buf).await {
            Ok(0) => break,
            Ok(n) => n,
            Err(_) => break,
        };
        if writer.write_all(&buf[..n]).await.is_err() {
            break;
        }
    }
    let _ = writer.shutdown().await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};

    struct VecReporter {
        events: Mutex<Vec<(RuleStatus, Option<String>)>>,
    }

    impl VecReporter {
        fn new() -> Self {
            Self {
                events: Mutex::new(Vec::new()),
            }
        }
        fn snapshot(&self) -> Vec<(RuleStatus, Option<String>)> {
            self.events.lock().unwrap().clone()
        }
    }

    impl StatusReporter for VecReporter {
        fn report(&self, status: RuleStatus, detail: Option<String>) {
            self.events.lock().unwrap().push((status, detail));
        }
    }

    /// Echo factory — every `open` returns a fresh duplex pair
    /// where the "remote" side echoes whatever the pump writes
    /// upstream back to the downstream reader. Lets us exercise
    /// the full bidirectional path with no russh / TCP peer.
    struct EchoFactory;

    impl ChannelFactory for EchoFactory {
        fn open(&self, _peer: SocketAddr) -> OpenFuture {
            Box::pin(async move {
                // Two duplex pairs: (a, b) is the channel
                // visible to the pump; we keep the other end
                // alive on a spawned task that echoes.
                let (a, mut b) = duplex(8192);
                tokio::spawn(async move {
                    let mut buf = [0u8; 1024];
                    loop {
                        match b.read(&mut buf).await {
                            Ok(0) | Err(_) => break,
                            Ok(n) => {
                                if b.write_all(&buf[..n]).await.is_err() {
                                    break;
                                }
                            }
                        }
                    }
                });
                let (reader, writer) = tokio::io::split(a);
                let r: ReaderHalf = Box::pin(reader);
                let w: WriterHalf = Box::pin(writer);
                Ok((r, w))
            })
        }
    }

    #[tokio::test]
    async fn spawn_listener_reports_listening_and_picks_port() {
        let factory: Arc<dyn ChannelFactory> = Arc::new(EchoFactory);
        let reporter = Arc::new(VecReporter::new());
        let handle = spawn_listener(
            "127.0.0.1:0".parse().unwrap(),
            factory.clone(),
            reporter.clone(),
        )
        .await
        .expect("bind");
        assert_ne!(handle.bound_addr().port(), 0);
        let events = reporter.snapshot();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].0, RuleStatus::Listening);
    }

    #[tokio::test]
    async fn round_trip_through_echo_factory() {
        let factory: Arc<dyn ChannelFactory> = Arc::new(EchoFactory);
        let reporter = Arc::new(VecReporter::new());
        let handle = spawn_listener(
            "127.0.0.1:0".parse().unwrap(),
            factory.clone(),
            reporter.clone(),
        )
        .await
        .expect("bind");

        let mut client = TcpStream::connect(handle.bound_addr())
            .await
            .expect("connect");
        client.write_all(b"ping").await.expect("write");
        client.shutdown().await.expect("shutdown write");
        let mut got = Vec::new();
        client.read_to_end(&mut got).await.expect("read");
        assert_eq!(&got, b"ping");
    }

    #[tokio::test]
    async fn drop_handle_aborts_listener() {
        let factory: Arc<dyn ChannelFactory> = Arc::new(EchoFactory);
        let reporter = Arc::new(VecReporter::new());
        let handle = spawn_listener(
            "127.0.0.1:0".parse().unwrap(),
            factory.clone(),
            reporter.clone(),
        )
        .await
        .expect("bind");
        let bound = handle.bound_addr();
        drop(handle);
        // Give the abort a tick to land.
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        // New connect should fail because the listener socket
        // is gone.
        let result = tokio::time::timeout(
            std::time::Duration::from_millis(200),
            TcpStream::connect(bound),
        )
        .await;
        assert!(
            matches!(result, Ok(Err(_)) | Err(_)),
            "expected connect failure after listener drop, got {result:?}"
        );
    }

    #[tokio::test]
    async fn bind_failure_reports_error_status() {
        // Bind once successfully on an OS-assigned port, then
        // try to bind again on the same address — second bind
        // must fail and surface `RuleStatus::Error`.
        let factory: Arc<dyn ChannelFactory> = Arc::new(EchoFactory);
        let reporter = Arc::new(VecReporter::new());
        let first = spawn_listener(
            "127.0.0.1:0".parse().unwrap(),
            factory.clone(),
            reporter.clone(),
        )
        .await
        .expect("first bind");
        let bound = first.bound_addr();
        let second = spawn_listener(bound, factory, reporter.clone()).await;
        assert!(second.is_err());
        let events = reporter.snapshot();
        assert!(events.iter().any(|(s, _)| *s == RuleStatus::Error));
    }
}
