//! FRB adapter for `lfs_core` direct-tcpip channels (`-L` primitive
//! and ProxyJump hops).
//!
//! Exposes the russh primitive. Local-listener glue (`-L` accept
//! loop) and bastion-as-transport plumbing (ProxyJump) live
//! higher up — Dart drives the listener for now; a follow-up may
//! move that into `lfs_core::forward` once the bastion-chain
//! shape is clearer.

use std::sync::Arc;

use flutter_rust_bridge::frb;

use crate::api::ssh::SshSession;

/// Direct-tcpip channel: a TCP-to-TCP byte pipe over the SSH
/// session. Created by `ssh_open_direct_tcpip`. Drop on the Dart
/// side closes it; russh tears the channel down even without an
/// explicit `eof`.
#[frb(opaque)]
pub struct SshForwardChannel {
    inner: Arc<lfs_core::ssh::ForwardChannel>,
}

impl SshForwardChannel {
    /// Send bytes to the remote endpoint.
    pub async fn write(&self, data: Vec<u8>) -> Result<(), String> {
        self.inner.write(&data).await.map_err(|e| e.to_string())
    }

    /// Wait for the next chunk of remote bytes. Returns `null` on
    /// the Dart side once the channel is fully closed.
    pub async fn read(&self) -> Option<Vec<u8>> {
        self.inner.read().await
    }

    /// Half-close the write side. Server typically interprets this
    /// as "client done sending" and closes its end after draining.
    pub async fn eof(&self) -> Result<(), String> {
        self.inner.eof().await.map_err(|e| e.to_string())
    }
}

/// Start a Rust-driven `-L` local forward listener against the
/// supplied connection actor. Binds `bind_host:bind_port`,
/// resolves the active russh `Session` via the connection
/// registry, and spawns the accept loop that relays each accepted
/// socket through a fresh `direct-tcpip` channel to
/// `target_host:target_port`.
///
/// Returns the actual bound port (matters when the caller passes
/// `0` to let the OS pick). Status events (`Listening` / `Error`)
/// flow onto the bus through the registered rule id; the Dart UI
/// subscribes there as usual.
///
/// `connection_id` must point at a `Connected` actor — without
/// a live session the russh handle is gone and the listener task
/// would fail every accept.
pub async fn port_forward_start_local(
    rule_id: String,
    connection_id: String,
    bind_host: String,
    bind_port: u32,
    target_host: String,
    target_port: u32,
) -> Result<u32, String> {
    use std::net::SocketAddr;

    let app = lfs_core::app::instance();
    let actor_handle = app
        .connections
        .get(&connection_id)
        .ok_or_else(|| format!("connection {connection_id} not registered"))?;
    let session = {
        let actor = actor_handle
            .lock()
            .map_err(|_| "connection actor mutex poisoned".to_string())?;
        actor
            .clone_session()
            .ok_or_else(|| format!("connection {connection_id} has no live session"))?
    };

    let bind_str = format!("{bind_host}:{bind_port}");
    let bind_addr: SocketAddr = bind_str
        .parse()
        .map_err(|e| format!("invalid bind address {bind_str}: {e}"))?;

    let factory: std::sync::Arc<dyn lfs_core::portforward::driver::ChannelFactory> =
        std::sync::Arc::new(lfs_core::portforward::driver::DirectTcpipFactory::new(
            session,
            target_host,
            target_port as u16,
        ));
    let reporter: std::sync::Arc<dyn lfs_core::portforward::driver::StatusReporter> =
        std::sync::Arc::new(lfs_core::portforward::driver::AppStatusReporter::new(
            rule_id.clone(),
        ));

    let handle = lfs_core::portforward::driver::spawn_listener(bind_addr, factory, reporter)
        .await
        .map_err(|e| e.to_string())?;
    let bound_port = handle.bound_addr().port() as u32;
    app.port_forwards.store_listener(&rule_id, handle);
    Ok(bound_port)
}

/// Stop a listener spawned by [`port_forward_start_local`].
/// Idempotent on a missing rule id — drops the stored handle
/// (which aborts the accept loop and closes the listener
/// socket). Returns `true` when a handle was actually stopped.
pub async fn port_forward_stop_local(rule_id: String) -> Result<bool, String> {
    let app = lfs_core::app::instance();
    Ok(app.port_forwards.stop_listener(&rule_id).is_some())
}

/// Start a Rust-driven `-D` SOCKS5 dynamic-forward listener
/// against the supplied connection actor. Binds
/// `bind_host:bind_port`, resolves the active russh `Session`
/// via the connection registry, and spawns the accept loop that
/// runs the SOCKS5 CONNECT handshake (RFC 1928, NO_AUTH only)
/// per accepted socket and bridges it through a fresh
/// `direct-tcpip` channel to the target the client asked for.
///
/// Returns the actual bound port (matters when the caller
/// passes `0` to let the OS pick). Status events (`Listening` /
/// `Error`) flow onto the bus through the registered rule id;
/// the Dart UI subscribes there as usual.
pub async fn port_forward_start_dynamic(
    rule_id: String,
    connection_id: String,
    bind_host: String,
    bind_port: u32,
) -> Result<u32, String> {
    use std::net::SocketAddr;

    let app = lfs_core::app::instance();
    let actor_handle = app
        .connections
        .get(&connection_id)
        .ok_or_else(|| format!("connection {connection_id} not registered"))?;
    let session = {
        let actor = actor_handle
            .lock()
            .map_err(|_| "connection actor mutex poisoned".to_string())?;
        actor
            .clone_session()
            .ok_or_else(|| format!("connection {connection_id} has no live session"))?
    };

    let bind_str = format!("{bind_host}:{bind_port}");
    let bind_addr: SocketAddr = bind_str
        .parse()
        .map_err(|e| format!("invalid bind address {bind_str}: {e}"))?;

    let reporter: std::sync::Arc<dyn lfs_core::portforward::driver::StatusReporter> =
        std::sync::Arc::new(lfs_core::portforward::driver::AppStatusReporter::new(
            rule_id.clone(),
        ));

    let handle =
        lfs_core::portforward::driver::spawn_socks5_listener(bind_addr, session, reporter)
            .await
            .map_err(|e| e.to_string())?;
    let bound_port = handle.bound_addr().port() as u32;
    app.port_forwards.store_listener(&rule_id, handle);
    Ok(bound_port)
}

/// Stop a SOCKS5 listener spawned by
/// [`port_forward_start_dynamic`]. Same shape as
/// [`port_forward_stop_local`] — both share the registry's
/// listener handle slot.
pub async fn port_forward_stop_dynamic(rule_id: String) -> Result<bool, String> {
    let app = lfs_core::app::instance();
    Ok(app.port_forwards.stop_listener(&rule_id).is_some())
}

/// Start a Rust-driven `-R` remote-forward against the supplied
/// connection actor. Asks the server to listen on
/// `bind_host:bind_port` (pass `0` to let the server pick),
/// registers a route through the session-level dispatcher, and
/// spawns the bridge task that opens a fresh local TCP connection
/// to `target_host:target_port` per inbound forwarded connection.
///
/// Returns the actual bound port the server accepted (servers may
/// substitute their own when the caller asked for 0). Status
/// events (`Listening` / `Error`) flow onto the bus through the
/// registered rule id; the Dart UI subscribes there as usual.
pub async fn port_forward_start_remote(
    rule_id: String,
    connection_id: String,
    bind_host: String,
    bind_port: u32,
    target_host: String,
    target_port: u32,
) -> Result<u32, String> {
    let app = lfs_core::app::instance();
    let actor_handle = app
        .connections
        .get(&connection_id)
        .ok_or_else(|| format!("connection {connection_id} not registered"))?;
    let session = {
        let actor = actor_handle
            .lock()
            .map_err(|_| "connection actor mutex poisoned".to_string())?;
        actor
            .clone_session()
            .ok_or_else(|| format!("connection {connection_id} has no live session"))?
    };

    let reporter: std::sync::Arc<dyn lfs_core::portforward::driver::StatusReporter> =
        std::sync::Arc::new(lfs_core::portforward::driver::AppStatusReporter::new(
            rule_id.clone(),
        ));

    let handle = lfs_core::portforward::driver::spawn_remote_forward(
        session,
        bind_host,
        bind_port,
        target_host,
        target_port as u16,
        reporter,
    )
    .await
    .map_err(|e| e.to_string())?;
    let bound_port = handle.bound_port();
    app.port_forwards.store_remote_forward(&rule_id, handle);
    Ok(bound_port)
}

/// Stop a `-R` handle spawned by [`port_forward_start_remote`].
/// Drops the handle (which aborts the bridge task, withdraws the
/// session-level route, and asks the server to stop listening).
/// Idempotent on a missing rule id.
pub async fn port_forward_stop_remote(rule_id: String) -> Result<bool, String> {
    let app = lfs_core::app::instance();
    Ok(app.port_forwards.stop_remote_forward(&rule_id))
}

/// Open a direct-tcpip channel. `host_to_connect` / `port_to_connect`
/// is the remote endpoint reached server-side; `originator_address`
/// / `originator_port` is the local socket peer (used only by the
/// SSH protocol's logging — pass `127.0.0.1` / 0 if absent).
pub async fn ssh_open_direct_tcpip(
    session: &SshSession,
    host_to_connect: String,
    port_to_connect: u32,
    originator_address: String,
    originator_port: u32,
) -> Result<SshForwardChannel, String> {
    let channel = session
        .open_direct_tcpip_inner(
            &host_to_connect,
            port_to_connect,
            &originator_address,
            originator_port,
        )
        .await?;
    Ok(SshForwardChannel {
        inner: Arc::new(channel),
    })
}

// ---- `-R` remote forward (1.8a) --------------------------------------

/// One inbound connection delivered by `ssh_next_forwarded_connection`
/// after a successful `ssh_request_remote_forward`. Caller bridges
/// the `channel` to wherever the local user wanted the connection to
/// land (typically a localhost TCP service).
#[frb(opaque)]
pub struct SshForwardedConnection {
    /// Address the server-side listener was registered on (echoes
    /// the `ssh_request_remote_forward` argument).
    pub connected_address: String,
    /// Port the server-side listener was registered on.
    pub connected_port: u32,
    /// Originator socket peer address — informational only, comes
    /// straight from the SSH protocol's logging.
    pub originator_address: String,
    /// Originator socket peer port.
    pub originator_port: u32,
    /// Bidirectional byte channel to the originator. Same surface
    /// as `SshForwardChannel`.
    inner: Arc<lfs_core::ssh::ForwardChannel>,
}

impl SshForwardedConnection {
    #[flutter_rust_bridge::frb(ignore)]
    pub(crate) fn from_core(conn: lfs_core::ssh::ForwardedConnection) -> Self {
        SshForwardedConnection {
            connected_address: conn.connected_address,
            connected_port: conn.connected_port,
            originator_address: conn.originator_address,
            originator_port: conn.originator_port,
            inner: Arc::new(conn.channel),
        }
    }

    /// Send bytes to the originator (to whoever connected to the
    /// server-side listener).
    pub async fn write(&self, data: Vec<u8>) -> Result<(), String> {
        self.inner.write(&data).await.map_err(|e| e.to_string())
    }

    /// Wait for the next chunk of bytes from the originator. `null`
    /// once the channel closes.
    pub async fn read(&self) -> Option<Vec<u8>> {
        self.inner.read().await
    }

    /// Half-close our write side of the channel.
    pub async fn eof(&self) -> Result<(), String> {
        self.inner.eof().await.map_err(|e| e.to_string())
    }
}

/// Ask the server to listen on `address:port` and forward all
/// incoming connections back over this SSH session. Returns the
/// actual bound port — when the caller passes 0, the server picks
/// one and the returned value reports it.
pub async fn ssh_request_remote_forward(
    session: &SshSession,
    address: String,
    port: u32,
) -> Result<u32, String> {
    session.request_remote_forward_inner(&address, port).await
}

/// Withdraw a previously-requested remote forward. Idempotent on
/// the server side (sending CANCEL after the listener is gone is
/// a no-op).
pub async fn ssh_cancel_remote_forward(
    session: &SshSession,
    address: String,
    port: u32,
) -> Result<(), String> {
    session.cancel_remote_forward_inner(&address, port).await
}

/// Wait for the next inbound `-R` forwarded connection. `null` once
/// the session is closed or the receiver was already cancelled.
pub async fn ssh_next_forwarded_connection(session: &SshSession) -> Option<SshForwardedConnection> {
    session.next_forwarded_connection_inner().await
}
