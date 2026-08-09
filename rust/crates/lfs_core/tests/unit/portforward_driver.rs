/// Unit tests extracted from portforward/driver.rs
/// Declared via `#[path] mod tests;` in the source file.
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

#[test]
fn parse_bind_addr_accepts_localhost_and_ip_literals() {
    // The editor validator accepts any non-empty bind host, so the
    // bind path must resolve `localhost` (loopback) as well as IP
    // literals — not only bare `SocketAddr` strings.
    let loopback = parse_bind_addr("localhost", 8022).expect("localhost resolves");
    assert!(loopback.ip().is_loopback());
    assert_eq!(loopback.port(), 8022);

    let v4 = parse_bind_addr("0.0.0.0", 9000).expect("ipv4 literal");
    assert_eq!(v4.port(), 9000);
    assert!(v4.ip().is_unspecified());

    // Out-of-range port is rejected before resolution.
    assert!(parse_bind_addr("127.0.0.1", 70000).is_err());
}
