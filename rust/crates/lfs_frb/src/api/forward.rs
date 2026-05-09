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
        self.inner
            .write(&data)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Wait for the next chunk of remote bytes. Returns `null` on
    /// the Dart side once the channel is fully closed.
    pub async fn read(&self) -> Option<Vec<u8>> {
        self.inner.read().await
    }

    /// Half-close the write side. Server typically interprets this
    /// as "client done sending" and closes its end after draining.
    pub async fn eof(&self) -> Result<(), String> {
        self.inner
            .eof()
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }
}

/// Start a Rust-driven `-L` local forward listener against the
/// supplied connection actor. Returns the actual bound port
/// (matters when the caller passes `0` to let the OS pick).
/// Status events flow onto the bus through the registered rule id.
///
/// All orchestration (resolve session, build factory, bind addr,
/// spawn listener, store handle) lives in
/// `lfs_core::portforward::driver::start_local`. The shim is a
/// pass-through so the adapter stays free of business logic.
pub async fn port_forward_start_local(
    rule_id: String,
    connection_id: String,
    bind_host: String,
    bind_port: u32,
    target_host: String,
    target_port: u32,
) -> Result<u32, String> {
    let bind_port = u16_port(bind_port, "bind_port")?;
    let target_port = u16_port(target_port, "target_port")?;
    lfs_core::portforward::driver::start_local(
        rule_id,
        connection_id,
        bind_host,
        u32::from(bind_port),
        target_host,
        target_port,
    )
    .await
    .map(|p| p as u32)
    .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Validate a wire-typed port (Dart `int` lands as `u32`) fits in
/// the canonical `u16` shape. The previous `as u16` cast would
/// silently truncate `100_000` to `34464` and dial the wrong port.
fn u16_port(value: u32, label: &str) -> Result<u16, String> {
    u16::try_from(value).map_err(|_| {
        crate::api::frb_err::wire(
            crate::api::frb_err::kind::GENERIC,
            &format!("{label} {value} exceeds u16::MAX (65535)"),
        )
    })
}

/// Stop a listener spawned by [`port_forward_start_local`].
/// Idempotent on a missing rule id — drops the stored handle
/// (which aborts the accept loop and closes the listener
/// socket). Returns `true` when a handle was actually stopped.
pub async fn port_forward_stop_local(rule_id: String) -> Result<bool, String> {
    Ok(lfs_core::portforward::driver::stop_listener(&rule_id))
}

/// Start a Rust-driven `-D` SOCKS5 dynamic-forward listener
/// against the supplied connection actor. Same shape as
/// [`port_forward_start_local`] minus the target tuple.
pub async fn port_forward_start_dynamic(
    rule_id: String,
    connection_id: String,
    bind_host: String,
    bind_port: u32,
) -> Result<u32, String> {
    let bind_port = u16_port(bind_port, "bind_port")?;
    lfs_core::portforward::driver::start_dynamic(
        rule_id,
        connection_id,
        bind_host,
        u32::from(bind_port),
    )
    .await
    .map(|p| p as u32)
    .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Stop a SOCKS5 listener spawned by
/// [`port_forward_start_dynamic`]. Same shape as
/// [`port_forward_stop_local`] — both share the registry's
/// listener handle slot.
pub async fn port_forward_stop_dynamic(rule_id: String) -> Result<bool, String> {
    Ok(lfs_core::portforward::driver::stop_listener(&rule_id))
}

/// Start a Rust-driven `-R` remote-forward against the supplied
/// connection actor. Returns the actual bound port the server
/// accepted (servers may substitute their own when the caller
/// asked for 0).
pub async fn port_forward_start_remote(
    rule_id: String,
    connection_id: String,
    bind_host: String,
    bind_port: u32,
    target_host: String,
    target_port: u32,
) -> Result<u32, String> {
    let bind_port = u16_port(bind_port, "bind_port")?;
    let target_port = u16_port(target_port, "target_port")?;
    lfs_core::portforward::driver::start_remote(
        rule_id,
        connection_id,
        bind_host,
        u32::from(bind_port),
        target_host,
        target_port,
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Stop a `-R` handle spawned by [`port_forward_start_remote`].
/// Drops the handle (which aborts the bridge task, withdraws the
/// session-level route, and asks the server to stop listening).
/// Idempotent on a missing rule id. The driver awaits the inline
/// `teardown` so the route withdraw + server-side cancel-tcpip
/// complete before this future resolves — no detached cleanup
/// task left racing the runtime shutdown.
pub async fn port_forward_stop_remote(rule_id: String) -> Result<bool, String> {
    Ok(lfs_core::portforward::driver::stop_remote(&rule_id).await)
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
        self.inner
            .write(&data)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Wait for the next chunk of bytes from the originator. `null`
    /// once the channel closes.
    pub async fn read(&self) -> Option<Vec<u8>> {
        self.inner.read().await
    }

    /// Half-close our write side of the channel.
    pub async fn eof(&self) -> Result<(), String> {
        self.inner
            .eof()
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
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

#[cfg(test)]
mod tests {
    use super::*;

    // The port-forward driver endpoints (`port_forward_start_local`
    // / `_stop_local` / `_dynamic` / `_remote` /
    // `ssh_open_direct_tcpip` / `ssh_request_remote_forward` /
    // `ssh_next_forwarded_connection`) drive listener accept loops +
    // russh tcpip channels against a live SSH session; covered by
    // the `tests/connection_lifecycle.rs` integration binary that
    // exercises the direct-tcpip channel path against the
    // `lfs_core::connection::test_server` fixture. The standalone
    // tests below pin the `u16_port` validator that every driver
    // entry point routes through before touching the registry — a
    // truncation regression here would silently dial the wrong port.

    #[test]
    fn u16_port_accepts_valid_port_range() {
        assert_eq!(u16_port(0, "p").expect("0 is valid"), 0);
        assert_eq!(u16_port(1, "p").expect("1 is valid"), 1);
        assert_eq!(u16_port(22, "p").expect("ssh default"), 22);
        assert_eq!(u16_port(65535, "p").expect("u16::MAX"), 65535);
    }

    #[test]
    fn u16_port_rejects_value_above_u16_max() {
        let res = u16_port(65536, "bind_port");
        assert!(res.is_err(), "65536 must surface as Err");
        let envelope = res.unwrap_err();
        // Pin the wire shape — the Dart caller's typed-error router
        // reads `kind` (not detail substring) so the routable cases
        // stay routable across reword.
        assert!(envelope.contains("generic"));
        assert!(
            envelope.contains("65536"),
            "envelope must carry the offending value, got {envelope}"
        );
        assert!(
            envelope.contains("bind_port"),
            "envelope must carry the field label, got {envelope}"
        );
    }

    #[test]
    fn u16_port_rejects_value_at_u32_max() {
        // The pre-audit shape silently truncated `0xFFFFFFFF as u16`
        // to `0xFFFF` and dialled the wrong port; pin the contract
        // that overflow surfaces as Err rather than truncating.
        let res = u16_port(u32::MAX, "target_port");
        assert!(res.is_err());
    }

    #[test]
    fn u16_port_rejects_arbitrary_overflow() {
        // A typical wire-shape overflow case: a Dart `int` overflowing
        // to a value past u16::MAX. The shim must reject rather than
        // truncate.
        let res = u16_port(100_000, "p");
        assert!(res.is_err());
        let envelope = res.unwrap_err();
        assert!(envelope.contains("100000"));
    }
}
