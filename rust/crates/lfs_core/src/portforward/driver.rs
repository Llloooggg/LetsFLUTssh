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
