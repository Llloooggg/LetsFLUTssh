//! FRB adapter for `lfs_core` direct-tcpip channels (`-L` primitive
//! and ProxyJump hops).
//!
//! Sub-phase 1.7a — exposes the russh primitive. Local-listener
//! glue (`-L` accept loop) and bastion-as-transport plumbing
//! (ProxyJump) live higher up — Dart drives the listener for now;
//! 1.7b/1.10 may move that into `lfs_core::forward` once the
//! bastion-chain shape is clearer.

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
