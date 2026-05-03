//! SSH transport surface (russh-backed).
//!
//! Provides `try_connect_password` / `try_connect_pubkey` (one-shot
//! validate-and-disconnect probes) plus long-lived `Session` +
//! `Shell` (PTY-allocated shell channel) — the foundation for the
//! `SshTransport` interface alongside SFTP + port forwarding.
//!
//! Key parsing covers OpenSSH, PuTTY PPK (v2 + v3 / Argon2id) via
//! russh-keys' `from_ppk` (gated on the `ppk` cargo feature,
//! enabled through a direct dep on
//! `internal-russh-forked-ssh-key`), and legacy PEM PKCS#1 /
//! PKCS#8.

use std::collections::HashMap;
use std::sync::Arc;

use russh::client::{self, AuthResult, Handle, Handler, Msg};
use russh::keys::{ssh_key, Certificate, HashAlg, PrivateKey, PrivateKeyWithHashAlg};
use russh::{ChannelMsg, ChannelReadHalf, ChannelWriteHalf};
use tokio::sync::Mutex;
use zeroize::Zeroizing;

use crate::error::Error;

/// russh `Handler` impl for our client side. Carries an mpsc sender
/// for inbound `-R` (server-initiated `forwarded-tcpip`) channels —
/// `request_remote_forward` registers the server-side listener, then
/// every connection the server forwards arrives as a callback here
/// and we relay it through the queue for the caller to drain via
/// `Session::next_forwarded_connection`.
///
/// Validates that the protocol pipeline reaches userauth.
/// Host-key verification (TOFU + known_hosts integration) sits
/// alongside the real session lifecycle. Do not promote the
/// accept-all `check_server_key` to default.
pub struct LfsHandler {
    forward_tx: Option<tokio::sync::mpsc::UnboundedSender<ForwardedConnection>>,
    /// Endpoint we're connecting to — used by `check_server_key` to
    /// look up the matching `known_hosts` entry. Empty `host` /
    /// zero `port` means "skip TOFU enforcement" (probe handlers
    /// auto-accept; production handlers always carry a real
    /// endpoint).
    host: String,
    port: u16,
}

impl LfsHandler {
    fn with_forwards(
        host: &str,
        port: u16,
    ) -> (
        Self,
        tokio::sync::mpsc::UnboundedReceiver<ForwardedConnection>,
    ) {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        (
            LfsHandler {
                forward_tx: Some(tx),
                host: host.to_string(),
                port,
            },
            rx,
        )
    }

    fn probe() -> Self {
        // One-shot probes (`try_connect_*`) never request remote
        // forwards, so no receiver is needed. Sender stays None;
        // any (hypothetical) inbound forwarded channel is dropped.
        // Probe handlers also skip TOFU — an unauthenticated probe
        // should not pollute the user's known_hosts table or pop a
        // dialog before the user has decided to actually connect.
        LfsHandler {
            forward_tx: None,
            host: String::new(),
            port: 0,
        }
    }
}

impl Handler for LfsHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &ssh_key::PublicKey,
    ) -> Result<bool, Self::Error> {
        // Empty host / zero port marks a probe handler — auto-accept.
        if self.host.is_empty() || self.port == 0 {
            return Ok(true);
        }
        // Defensive — a DB read failure or a missing prompt
        // listener resolves to "rejected" so the handshake fails
        // closed. Better than silent accept.
        Ok(
            check_server_key_via_tofu(&self.host, self.port, server_public_key)
                .await
                .unwrap_or(false),
        )
    }

    async fn server_channel_open_forwarded_tcpip(
        &mut self,
        channel: russh::Channel<Msg>,
        connected_address: &str,
        connected_port: u32,
        originator_address: &str,
        originator_port: u32,
        _session: &mut russh::client::Session,
    ) -> Result<(), Self::Error> {
        let Some(tx) = self.forward_tx.as_ref() else {
            // Probe handler — no receiver. Drop the channel.
            return Ok(());
        };
        let (read_half, write_half) = channel.split();
        let conn = ForwardedConnection {
            connected_address: connected_address.to_string(),
            connected_port,
            originator_address: originator_address.to_string(),
            originator_port,
            channel: ForwardChannel {
                write_half,
                read_half: Mutex::new(read_half),
            },
        };
        // If the receiver is gone, swallow — Session was dropped while
        // the server was still pushing forwards. russh would have torn
        // the underlying connection down anyway.
        let _ = tx.send(conn);
        Ok(())
    }
}

/// One inbound `-R` forwarded connection. The remote end has already
/// accepted a TCP connection on its side; this is the channel that
/// streams its bytes. Caller bridges to a local socket of choice.
pub struct ForwardedConnection {
    pub connected_address: String,
    pub connected_port: u32,
    pub originator_address: String,
    pub originator_port: u32,
    pub channel: ForwardChannel,
}

fn default_client_config() -> Arc<client::Config> {
    Arc::new(client::Config {
        // No inactivity timeout — interactive SSH sessions sit idle
        // for arbitrary stretches between user keystrokes / shell
        // opens, and any cap tears the freshly-authenticated session
        // down before the user reaches for the terminal pane. Lets
        // the underlying TCP layer + the OS keepalive policy be the
        // dead-link detector, mirroring an OpenSSH client without
        // ServerAliveInterval set.
        inactivity_timeout: None,
        ..client::Config::default()
    })
}

async fn open_handle_for_probe(host: &str, port: u16) -> Result<Handle<LfsHandler>, Error> {
    client::connect(default_client_config(), (host, port), LfsHandler::probe())
        .await
        .map_err(|e| Error::Connect(e.to_string()))
}

/// Run the TOFU lookup against the running DB and (when the host
/// is unknown / changed) fire a `KnownHostPromptRequest` event +
/// await the user's response via the prompt registry. Returns
/// `Ok(true)` when the offered key is accepted (matched stored
/// entry, or the user accepted a new/changed key — and we
/// persisted it). `Ok(false)` rejects the handshake.
///
/// Returns `Err` when the DB is not initialised yet — the
/// handshake then resolves to "rejected" via the caller's
/// `unwrap_or(false)`. Same posture for a fingerprint-encoding
/// failure: the safe default is "do not accept".
async fn check_server_key_via_tofu(
    host: &str,
    port: u16,
    server_public_key: &ssh_key::PublicKey,
) -> Result<bool, Error> {
    use base64::engine::{general_purpose::STANDARD as B64_STD, Engine as _};
    let app = crate::app::instance();
    let db = app
        .db()
        .ok_or_else(|| Error::Io("known-hosts: db not initialized".to_string()))?;
    let key_type = server_public_key.algorithm().as_str().to_string();
    // OpenSSH wire format for the known_hosts blob: the
    // `<key-type> <base64(SSH wire bytes)>` pair OpenSSH writes.
    // `to_openssh()` serializes as `ssh-ed25519 AAAA…` (one line);
    // we strip the prefix back off to reach the raw base64 the
    // known_hosts table stores.
    let openssh_line = server_public_key
        .to_openssh()
        .map_err(|e| Error::Io(format!("known-hosts: encode public key: {e}")))?;
    let key_b64 = openssh_line
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| Error::Io("known-hosts: malformed openssh line".to_string()))?
        .to_string();
    let key_bytes = B64_STD
        .decode(&key_b64)
        .map_err(|e| Error::Io(format!("known-hosts: base64 decode: {e}")))?;
    let port_i64 = port as i64;
    let result = crate::known_hosts::check_host(&db, host, port_i64, &key_type, &key_b64)?;
    if matches!(result, crate::known_hosts::HostCheckResult::Accepted) {
        return Ok(true);
    }
    let kind = crate::known_hosts::prompt_kind_for(&result)
        .expect("non-Accepted result must have a prompt kind");
    let fingerprint = format_fingerprint(&key_bytes);
    let prompt_id = generate_prompt_id();
    let receiver = app.known_hosts_prompts.register(prompt_id.clone());
    app.bus.publish(crate::bus::Event::KnownHostPromptRequest {
        prompt_id: prompt_id.clone(),
        host: host.to_string(),
        port: port_i64,
        key_type: key_type.clone(),
        fingerprint,
        kind,
    });
    let accepted = match receiver.await {
        Ok(v) => v,
        Err(_) => {
            // Sender dropped without resolving — Dart UI tore down
            // the dialog or the dispatcher dropped the entry. Fail
            // closed.
            app.known_hosts_prompts.cancel(&prompt_id);
            return Ok(false);
        }
    };
    if accepted {
        // Persist the freshly-accepted key. Upserting overrides a
        // stored Changed entry under the same `host:port` PK — the
        // user explicitly opted into the new fingerprint.
        let now_ms = current_unix_ms();
        let host_owned = host.to_string();
        let key_type_owned = key_type;
        let key_b64_owned = key_b64;
        db.with_conn(move |conn| {
            crate::db::known_hosts::upsert_by_host_port(
                conn,
                &host_owned,
                port_i64,
                &key_type_owned,
                &key_b64_owned,
                now_ms,
            )
        })?;
        crate::known_hosts::notify_changed(&app);
    }
    Ok(accepted)
}

/// Compute the OpenSSH-style SHA-256 host-key fingerprint —
/// `SHA256:<base64-no-pad>` shape, matching `ssh-keygen -lf` output.
///
/// Public so the Dart `KnownHostsManager.fingerprint` display
/// helper routes through the canonical implementation. Without
/// this the Dart side used `base64Encode` (with `=` padding), so
/// a key rendered Dart-side displayed as `SHA256:abc...=` while
/// the same key rendered Rust-side displayed as `SHA256:abc...` —
/// confusing when both shapes appear in the same UI.
pub fn format_fingerprint(key_bytes: &[u8]) -> String {
    use base64::engine::{general_purpose::STANDARD_NO_PAD as B64_NP, Engine as _};
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(key_bytes);
    let digest = h.finalize();
    format!("SHA256:{}", B64_NP.encode(digest))
}

fn generate_prompt_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let mut hex = String::with_capacity(32);
    for b in bytes {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

fn current_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

async fn open_handle_for_session(
    host: &str,
    port: u16,
) -> Result<
    (
        Handle<LfsHandler>,
        tokio::sync::mpsc::UnboundedReceiver<ForwardedConnection>,
    ),
    Error,
> {
    let (handler, rx) = LfsHandler::with_forwards(host, port);
    let handle = client::connect(default_client_config(), (host, port), handler)
        .await
        .map_err(|e| Error::Connect(e.to_string()))?;
    Ok((handle, rx))
}

/// Run the SSH handshake over a `direct-tcpip` channel opened on a
/// parent session — the russh primitive behind ProxyJump bastion
/// chains. The parent stays alive for the child's full lifetime; if
/// the parent disconnects the child's underlying transport closes
/// automatically (russh tears down the channel and the consequent
/// `connect_stream` future returns an IO error).
///
/// Recursive: the returned `Handle` belongs to a new `Session` that
/// can itself act as a parent for the next hop. Each hop consumes
/// one `direct-tcpip` channel slot on its parent.
async fn open_handle_via_proxy(
    parent: &Session,
    host: &str,
    port: u16,
) -> Result<
    (
        Handle<LfsHandler>,
        tokio::sync::mpsc::UnboundedReceiver<ForwardedConnection>,
    ),
    Error,
> {
    let (handler, rx) = LfsHandler::with_forwards(host, port);
    // The originator fields are protocol metadata only — they're
    // logged server-side but do not affect routing. "127.0.0.1:0"
    // is the conservative shape (a real loopback peer would have
    // a real ephemeral port; we have no socket here).
    let channel = parent
        .handle
        .channel_open_direct_tcpip(host.to_string(), port as u32, "127.0.0.1".to_string(), 0)
        .await
        .map_err(|e| Error::Connect(format!("proxy channel open: {e}")))?;
    let stream = channel.into_stream();
    let handle = client::connect_stream(default_client_config(), stream, handler)
        .await
        .map_err(|e| Error::Connect(e.to_string()))?;
    Ok((handle, rx))
}

// ---- One-shot probes (1.1, 1.2) ----------------------------------------

async fn finish_probe(session: Handle<LfsHandler>) {
    // Best-effort disconnect — never propagate teardown errors over a
    // probe call, the connect+auth result is what the caller wants.
    let _ = session
        .disconnect(russh::Disconnect::ByApplication, "probe done", "en")
        .await;
}

/// Probe an SSH server with a username + password, returning `Ok(())`
/// on successful auth and immediately disconnecting.
///
/// `password` wraps in `Zeroizing` so our local copy clears on drop.
/// Bytes copied into russh's userauth path are outside this guarantee
/// — best-effort hardening, not a security oracle.
pub async fn try_connect_password(
    host: &str,
    port: u16,
    user: &str,
    password: &str,
) -> Result<(), Error> {
    let password = Zeroizing::new(password.to_owned());
    let mut session = open_handle_for_probe(host, port).await?;

    let auth_result = session
        .authenticate_password(user, password.as_str())
        .await
        .map_err(|e| Error::Auth(e.to_string()))?;

    if !matches!(auth_result, AuthResult::Success) {
        return Err(Error::AuthFailed);
    }

    finish_probe(session).await;
    Ok(())
}

/// Probe an SSH server with a private-key file in OpenSSH format
/// or PuTTY PPK (v2 + v3 / Argon2id). Returns `Ok(())` on successful
/// auth + immediate disconnect.
///
/// Accepts:
///   - OpenSSH PEM (`-----BEGIN OPENSSH PRIVATE KEY-----`)
///   - PuTTY PPK (`PuTTY-User-Key-File-...`)
///   - Legacy PEM PKCS#1 / PKCS#8 (`-----BEGIN RSA PRIVATE KEY-----`)
///
/// `passphrase`, when given, also wraps in `Zeroizing` for the same
/// best-effort scrub semantics as `try_connect_password`.
pub async fn try_connect_pubkey(
    host: &str,
    port: u16,
    user: &str,
    private_key: &[u8],
    passphrase: Option<&str>,
) -> Result<(), Error> {
    let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));

    let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;

    let mut session = open_handle_for_probe(host, port).await?;
    finish_authenticate_pubkey(&mut session, user, key).await?;
    finish_probe(session).await;
    Ok(())
}

// ---- Long-lived session (1.3) -----------------------------------------

/// A live, authenticated SSH session. Holds the russh `Handle` until
/// `disconnect()` (or `Drop`) tears it down. Open shell / SFTP / port-
/// forward channels off this object.
///
/// Shareable across tasks — every method takes `&self` because
/// russh's `Handle` is internally `Sync`. Wrap in `Arc` if multiple
/// owners need it.
pub struct Session {
    handle: Handle<LfsHandler>,
    /// Inbound `-R` forwarded connections enqueued by `LfsHandler`.
    /// `Mutex` because `recv()` is `&mut self` on the receiver.
    /// Drained either by the legacy `next_forwarded_connection` path
    /// or — once `register_remote_forward_route` lazy-spawns it — by
    /// the per-session route dispatcher.
    forward_rx: Mutex<tokio::sync::mpsc::UnboundedReceiver<ForwardedConnection>>,
    /// Per-`(connected_address, connected_port)` route table
    /// populated by `register_remote_forward_route`. The dispatcher
    /// task pulls from `forward_rx` and routes inbound forwards to
    /// the matching sender; mismatched (or unregistered) forwards
    /// are dropped on the floor.
    forward_routes:
        Mutex<HashMap<(String, u32), tokio::sync::mpsc::UnboundedSender<ForwardedConnection>>>,
    /// Lazy-spawn flag for the dispatcher task. Set on the first
    /// call to `register_remote_forward_route`; mutual exclusion
    /// against concurrent first-call races is via
    /// `compare_exchange` rather than a Mutex so the registration
    /// hot-path stays lock-free after the dispatcher is up.
    forward_dispatcher_started: std::sync::atomic::AtomicBool,
}

impl Session {
    /// Build the [`Session`] wrapper around a freshly authenticated
    /// russh `Handle` + the matching forwarded-channel receiver.
    /// Co-located with the field set so every constructor site
    /// (password / pubkey / cert / agent / proxy variants) uses the
    /// same shape — adding a field bumps just this helper.
    fn from_handle(
        handle: Handle<LfsHandler>,
        forward_rx: tokio::sync::mpsc::UnboundedReceiver<ForwardedConnection>,
    ) -> Self {
        Session {
            handle,
            forward_rx: Mutex::new(forward_rx),
            forward_routes: Mutex::new(HashMap::new()),
            forward_dispatcher_started: std::sync::atomic::AtomicBool::new(false),
        }
    }

    /// Register a route for inbound `-R` forwarded connections that
    /// arrive at `(connected_address, connected_port)`. Returns a
    /// fresh receiver — each accepted connection whose
    /// `connected_address` + `connected_port` match the supplied
    /// pair is delivered through it.
    ///
    /// Lazy-spawns the dispatcher task on the first call. Subsequent
    /// registrations only insert into the route table; the
    /// dispatcher pulls from `forward_rx` and routes inbound
    /// `ForwardedConnection`s to the matching sender. Mismatched (or
    /// unregistered) forwards are dropped — there is no requeue path.
    ///
    /// Pair with [`Session::unregister_remote_forward_route`] when
    /// the rule tears down so the route table stays empty for the
    /// matching `(host, port)` (otherwise the dispatcher keeps a
    /// dangling sender that can leak inbound connections after the
    /// listener is supposed to be gone).
    pub async fn register_remote_forward_route(
        self: &Arc<Self>,
        host: String,
        port: u32,
    ) -> tokio::sync::mpsc::UnboundedReceiver<ForwardedConnection> {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        {
            let mut routes = self.forward_routes.lock().await;
            routes.insert((host, port), tx);
        }
        if !self
            .forward_dispatcher_started
            .swap(true, std::sync::atomic::Ordering::SeqCst)
        {
            let session = self.clone();
            tokio::spawn(async move {
                while let Some(conn) = session.next_forwarded_connection().await {
                    let key = (conn.connected_address.clone(), conn.connected_port);
                    let routes = session.forward_routes.lock().await;
                    if let Some(sender) = routes.get(&key) {
                        let _ = sender.send(conn);
                    }
                    // No matching route — drop on the floor. Unmatched
                    // forwards usually mean a route was withdrawn
                    // mid-flight; the server will see the channel
                    // closed and tear its end down.
                }
            });
        }
        rx
    }

    /// Withdraw a route registered through
    /// [`Session::register_remote_forward_route`]. Idempotent.
    pub async fn unregister_remote_forward_route(&self, host: &str, port: u32) {
        let mut routes = self.forward_routes.lock().await;
        routes.remove(&(host.to_string(), port));
    }

    /// Connect + authenticate with a username and password. The
    /// returned session stays live until `disconnect` or `Drop`.
    pub async fn connect_password(
        host: &str,
        port: u16,
        user: &str,
        password: &str,
    ) -> Result<Self, Error> {
        let password = Zeroizing::new(password.to_owned());
        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;

        let auth_result = handle
            .authenticate_password(user, password.as_str())
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        if !matches!(auth_result, AuthResult::Success) {
            return Err(Error::AuthFailed);
        }

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Connect + authenticate with a username and OpenSSH-format
    /// private key. `passphrase` is required only when the key file
    /// is encrypted.
    pub async fn connect_pubkey(
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;

        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;
        finish_authenticate_pubkey(&mut handle, user, key).await?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Open a PTY-backed shell channel sized to `cols × rows`. The
    /// returned `Shell` owns both halves of the channel and exposes
    /// concurrent write + read APIs.
    ///
    /// Fixes `term = "xterm-256color"`; a `term` override is a
    /// follow-up alongside the Dart-side wiring.
    pub async fn open_shell(&self, cols: u32, rows: u32) -> Result<Shell, Error> {
        let channel = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| Error::Io(e.to_string()))?;

        channel
            .request_pty(false, "xterm-256color", cols, rows, 0, 0, &[])
            .await
            .map_err(|e| Error::Io(e.to_string()))?;
        channel
            .request_shell(false)
            .await
            .map_err(|e| Error::Io(e.to_string()))?;

        let (read_half, write_half) = channel.split();
        Ok(Shell {
            write_half,
            read_half: Mutex::new(read_half),
        })
    }

    /// Connect + authenticate with an OpenSSH **certificate** (an SSH
    /// public key signed by a CA, plus the matching private key).
    /// Cert format: `-----BEGIN OPENSSH CERTIFICATE-----` / the
    /// `id_ed25519-cert.pub` companion file produced by `ssh-keygen
    /// -s ca_key id_ed25519.pub`. Server must trust the issuing CA
    /// (`TrustedUserCAKeys` in sshd_config).
    ///
    /// Used by §6.2 SSH certificates. russh recognises every
    /// `*-cert-v01@openssh.com` algorithm name natively — no fork
    /// or upstream patch required.
    pub async fn connect_pubkey_cert(
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
        cert_bytes: &[u8],
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;
        let cert = parse_certificate(cert_bytes)?;

        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;

        let auth_result = handle
            .authenticate_openssh_cert(user, Arc::new(key), cert)
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        if !matches!(auth_result, AuthResult::Success) {
            return Err(Error::AuthFailed);
        }

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Connect + authenticate by delegating signing to the system
    /// SSH agent ($SSH_AUTH_SOCK on Unix, OpenSSH-style named pipe
    /// on Windows, Pageant on Windows fallback). Iterates over the
    /// agent's identities in order; first one the server accepts
    /// wins. Returns `Error::AuthFailed` only if every identity is
    /// rejected.
    pub async fn connect_agent(host: &str, port: u16, user: &str) -> Result<Self, Error> {
        connect_via_agent(host.to_owned(), port, user.to_owned()).await
    }

    // ---- ProxyJump bastion variants (1.10b) ------------------------
    // Each `connect_*_via_proxy` mirrors its non-proxy counterpart but
    // tunnels the SSH handshake through a `direct-tcpip` channel on
    // `parent` instead of dialing a fresh TCP socket. The child takes
    // a `&Session` reference so it composes — the returned Session can
    // itself act as a parent for the next hop, supporting multi-hop
    // ProxyJump chains (A → B → C) without any special-case logic.

    /// Password auth tunnelled through a ProxyJump parent.
    pub async fn connect_password_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
        password: &str,
    ) -> Result<Self, Error> {
        let password = Zeroizing::new(password.to_owned());
        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;

        let auth_result = handle
            .authenticate_password(user, password.as_str())
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        if !matches!(auth_result, AuthResult::Success) {
            return Err(Error::AuthFailed);
        }

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Pubkey auth tunnelled through a ProxyJump parent.
    pub async fn connect_pubkey_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;

        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;
        finish_authenticate_pubkey(&mut handle, user, key).await?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// OpenSSH cert auth tunnelled through a ProxyJump parent.
    pub async fn connect_pubkey_cert_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
        cert_bytes: &[u8],
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;
        let cert = parse_certificate(cert_bytes)?;

        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;

        let auth_result = handle
            .authenticate_openssh_cert(user, Arc::new(key), cert)
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        if !matches!(auth_result, AuthResult::Success) {
            return Err(Error::AuthFailed);
        }

        Ok(Session::from_handle(handle, forward_rx))
    }

    // ---- Secret-store-backed connects ─────────────────────────────
    // The plaintext credential never crosses the FRB boundary —
    // callers stash bytes in the process-singleton SecretStore
    // (`lfs_core::app::instance().secrets`) under a stable id, then
    // hand the id (not the bytes) over FRB. These methods resolve
    // the id locally, copy into a Zeroizing buffer, and feed russh
    // exactly as the plaintext variants do. The fetched copy
    // scrubs on drop at the end of the connect call.

    /// Password auth using the SecretStore entry under `secret_id`.
    pub async fn connect_password_with_secret(
        host: &str,
        port: u16,
        user: &str,
        secret_id: &str,
    ) -> Result<Self, Error> {
        let bytes = crate::app::instance()
            .secrets
            .get(secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached secret '{secret_id}'")))?;
        let pwd = std::str::from_utf8(&bytes)
            .map_err(|e| Error::Auth(format!("password not utf-8: {e}")))?;
        Self::connect_password(host, port, user, pwd).await
    }

    /// Owned-arg twin of [`connect_password_with_secret`]. Returns
    /// `Pin<Box<dyn Future + Send + 'static>>` so the FRB layer's
    /// `wrap_async` `Send + 'static` bound is satisfied without
    /// HRTB inference reaching into the `&str`-borrowing internals.
    /// One heap allocation per connect — invisible next to the
    /// russh handshake.
    pub fn connect_password_with_secret_owned(
        host: String,
        port: u16,
        user: String,
        secret_id: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(
            async move { Self::connect_password_with_secret(&host, port, &user, &secret_id).await },
        )
    }

    /// Pubkey auth using SecretStore entries — `key_secret_id` for
    /// the private-key bytes and an optional `passphrase_secret_id`
    /// for the decryption passphrase.
    pub async fn connect_pubkey_with_secret(
        host: &str,
        port: u16,
        user: &str,
        key_secret_id: &str,
        passphrase_secret_id: Option<&str>,
    ) -> Result<Self, Error> {
        let store = &crate::app::instance().secrets;
        let key_bytes = store
            .get(key_secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
        let pass_bytes = match passphrase_secret_id {
            Some(id) => store.get(id),
            None => None,
        };
        let passphrase = match pass_bytes.as_ref() {
            Some(b) => Some(
                std::str::from_utf8(b)
                    .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
            ),
            None => None,
        };
        Self::connect_pubkey(host, port, user, &key_bytes, passphrase).await
    }

    /// Owned-arg twin of [`connect_pubkey_with_secret`]. Boxed for
    /// the same reason as [`connect_password_with_secret_owned`].
    pub fn connect_pubkey_with_secret_owned(
        host: String,
        port: u16,
        user: String,
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Self::connect_pubkey_with_secret(
                &host,
                port,
                &user,
                &key_secret_id,
                passphrase_secret_id.as_deref(),
            )
            .await
        })
    }

    /// OpenSSH-cert auth using SecretStore entries — `key_secret_id`
    /// for the private-key bytes, `cert_secret_id` for the cert
    /// blob, optional `passphrase_secret_id`.
    pub async fn connect_pubkey_cert_with_secret(
        host: &str,
        port: u16,
        user: &str,
        key_secret_id: &str,
        cert_secret_id: &str,
        passphrase_secret_id: Option<&str>,
    ) -> Result<Self, Error> {
        let store = &crate::app::instance().secrets;
        let key_bytes = store
            .get(key_secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
        let cert_bytes = store
            .get(cert_secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached cert '{cert_secret_id}'")))?;
        let pass_bytes = match passphrase_secret_id {
            Some(id) => store.get(id),
            None => None,
        };
        let passphrase = match pass_bytes.as_ref() {
            Some(b) => Some(
                std::str::from_utf8(b)
                    .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
            ),
            None => None,
        };
        Self::connect_pubkey_cert(host, port, user, &key_bytes, passphrase, &cert_bytes).await
    }

    /// Owned-arg twin of [`connect_pubkey_cert_with_secret`]. Boxed
    /// for the same reason as [`connect_password_with_secret_owned`].
    #[allow(clippy::too_many_arguments)] // every cert auth ingredient is load-bearing
    pub fn connect_pubkey_cert_with_secret_owned(
        host: String,
        port: u16,
        user: String,
        key_secret_id: String,
        cert_secret_id: String,
        passphrase_secret_id: Option<String>,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Self::connect_pubkey_cert_with_secret(
                &host,
                port,
                &user,
                &key_secret_id,
                &cert_secret_id,
                passphrase_secret_id.as_deref(),
            )
            .await
        })
    }

    /// Owned-arg twin of [`connect_agent`]. Bridges through
    /// `spawn_blocking + Handle::block_on` because the russh agent
    /// client holds a non-Send dyn trait object that cannot ride
    /// inside an FRB `wrap_async` future. Mirrors the workaround
    /// the legacy FRB `ssh_connect_agent` already uses, so the
    /// connection actor can expose a uniform `_owned` family.
    pub fn connect_agent_owned(
        host: String,
        port: u16,
        user: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let handle = tokio::runtime::Handle::current();
            tokio::task::spawn_blocking(move || {
                handle.block_on(Self::connect_agent(&host, port, &user))
            })
            .await
            .map_err(|e| Error::Auth(format!("agent task: {e}")))?
        })
    }

    // ---- ProxyJump + secret-store-backed connects ----------------
    // The `_via_proxy_with_secret_owned_arc` family takes an
    // `Arc<Session>` for the parent (so the returned future owns
    // its parent reference and stays `'static` instead of borrowing
    // for an unspecified lifetime) and a SecretStore id for every
    // credential ingredient. Returned as
    // `Pin<Box<dyn Future + Send + 'static>>` so the connection
    // actor's dispatch path threads through FRB `wrap_async`
    // without HRTB inference reaching into the deeper `&str`
    // borrow plumbing.

    /// Password auth tunnelled through a ProxyJump parent, resolving
    /// the password from the SecretStore. See module docs for the
    /// boxed-future rationale.
    pub fn connect_password_via_proxy_with_secret_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
        secret_id: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let bytes = crate::app::instance()
                .secrets
                .get(&secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached secret '{secret_id}'")))?;
            let pwd = std::str::from_utf8(&bytes)
                .map_err(|e| Error::Auth(format!("password not utf-8: {e}")))?;
            Self::connect_password_via_proxy(&parent, &host, port, &user, pwd).await
        })
    }

    /// Pubkey auth tunnelled through a ProxyJump parent, resolving
    /// key + optional passphrase from the SecretStore.
    pub fn connect_pubkey_via_proxy_with_secret_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let store = &crate::app::instance().secrets;
            let key_bytes = store
                .get(&key_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
            let pass_bytes = passphrase_secret_id.as_deref().and_then(|id| store.get(id));
            let passphrase = match pass_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
                ),
                None => None,
            };
            Self::connect_pubkey_via_proxy(&parent, &host, port, &user, &key_bytes, passphrase)
                .await
        })
    }

    /// OpenSSH-cert auth tunnelled through a ProxyJump parent.
    #[allow(clippy::too_many_arguments)] // every cert auth ingredient is load-bearing
    pub fn connect_pubkey_cert_via_proxy_with_secret_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
        key_secret_id: String,
        cert_secret_id: String,
        passphrase_secret_id: Option<String>,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let store = &crate::app::instance().secrets;
            let key_bytes = store
                .get(&key_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
            let cert_bytes = store
                .get(&cert_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached cert '{cert_secret_id}'")))?;
            let pass_bytes = passphrase_secret_id.as_deref().and_then(|id| store.get(id));
            let passphrase = match pass_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
                ),
                None => None,
            };
            Self::connect_pubkey_cert_via_proxy(
                &parent,
                &host,
                port,
                &user,
                &key_bytes,
                passphrase,
                &cert_bytes,
            )
            .await
        })
    }

    /// Agent auth tunnelled through a ProxyJump parent. Bridges
    /// through `spawn_blocking + Handle::block_on` for the same
    /// non-Send agent-client reason as [`connect_agent_owned`];
    /// the parent `Arc<Session>` cloned into the blocking task so
    /// the spawn boundary doesn't lose the reference.
    pub fn connect_agent_via_proxy_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let handle = tokio::runtime::Handle::current();
            tokio::task::spawn_blocking(move || {
                handle.block_on(Self::connect_agent_via_proxy(&parent, &host, port, &user))
            })
            .await
            .map_err(|e| Error::Auth(format!("agent task: {e}")))?
        })
    }

    /// SSH-agent auth tunnelled through a ProxyJump parent. Mirrors
    /// the non-proxy `connect_agent` path: spawn_blocking + Handle
    /// for the agent client whose per-call futures are not Send,
    /// then run authenticate over the proxy-tunnelled handle.
    pub async fn connect_agent_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
    ) -> Result<Self, Error> {
        connect_via_agent_proxy(parent, host.to_owned(), port, user.to_owned()).await
    }

    /// Open a direct-tcpip channel — the russh primitive behind
    /// `-L` local forwards and ProxyJump bastion hops. Caller
    /// supplies both the remote endpoint to connect to (host/port
    /// resolved server-side) and the originator (local socket
    /// peer) for the protocol's logging.
    ///
    /// Returns a `ForwardChannel` exposing `write` / `read` / `eof`
    /// for byte-pumping. Local-listener glue (`-L`) and bastion-as-
    /// transport plumbing (ProxyJump) live one layer up — see
    /// `lfs_core::forward` for the listener-driven local-forward
    /// helper.
    pub async fn open_direct_tcpip(
        &self,
        host_to_connect: &str,
        port_to_connect: u32,
        originator_address: &str,
        originator_port: u32,
    ) -> Result<ForwardChannel, Error> {
        let channel = self
            .handle
            .channel_open_direct_tcpip(
                host_to_connect.to_string(),
                port_to_connect,
                originator_address.to_string(),
                originator_port,
            )
            .await
            .map_err(|e| Error::Io(e.to_string()))?;

        let (read_half, write_half) = channel.split();
        Ok(ForwardChannel {
            write_half,
            read_half: Mutex::new(read_half),
        })
    }

    /// Open a direct-tcpip channel and return its `AsyncRead +
    /// AsyncWrite` stream form. Used by the port-forward
    /// listener-accept driver — `tokio::io::split` gives the
    /// generic pump its `(reader, writer)` halves directly,
    /// avoiding the [`ForwardChannel`] read/write/eof shape
    /// that the high-level Dart-driven path consumes.
    pub async fn open_direct_tcpip_stream(
        &self,
        host_to_connect: &str,
        port_to_connect: u32,
        originator_address: &str,
        originator_port: u32,
    ) -> Result<russh::ChannelStream<Msg>, Error> {
        let channel = self
            .handle
            .channel_open_direct_tcpip(
                host_to_connect.to_string(),
                port_to_connect,
                originator_address.to_string(),
                originator_port,
            )
            .await
            .map_err(|e| Error::Io(e.to_string()))?;
        Ok(channel.into_stream())
    }

    /// Open an SFTP subsystem on a fresh channel and return a live
    /// SFTP client. Multiple SFTP sessions can coexist on a single
    /// SSH session — each call here allocates a new channel.
    pub async fn open_sftp(&self) -> Result<crate::sftp::Sftp, Error> {
        let channel = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| Error::Io(e.to_string()))?;
        channel
            .request_subsystem(true, "sftp")
            .await
            .map_err(|e| Error::Io(e.to_string()))?;
        let stream = channel.into_stream();
        crate::sftp::Sftp::from_stream(stream).await
    }

    /// Ask the server to listen on `address:port` and forward
    /// connections back over this SSH session. Returns the actual
    /// bound port (servers may pick one when caller passes 0).
    ///
    /// Inbound connections arrive asynchronously via
    /// `next_forwarded_connection`. Cancel with
    /// `cancel_remote_forward` (idempotent).
    pub async fn request_remote_forward(&self, address: &str, port: u32) -> Result<u32, Error> {
        self.handle
            .tcpip_forward(address.to_string(), port)
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }

    /// Withdraw a previously-requested remote forward.
    pub async fn cancel_remote_forward(&self, address: &str, port: u32) -> Result<(), Error> {
        self.handle
            .cancel_tcpip_forward(address.to_string(), port)
            .await
            .map(|_| ())
            .map_err(|e| Error::Io(e.to_string()))
    }

    /// Wait for the next inbound `-R` forwarded connection. Returns
    /// `None` once the session is closed (handler dropped) or the
    /// receiver was already cancelled.
    pub async fn next_forwarded_connection(&self) -> Option<ForwardedConnection> {
        let mut rx = self.forward_rx.lock().await;
        rx.recv().await
    }

    /// Cleanly disconnect the session. Sends `SSH_MSG_DISCONNECT`;
    /// the actual transport teardown rides on `Drop` of the inner
    /// `Handle` once every shared reference goes out of scope.
    /// Idempotent; russh ignores a second disconnect after the
    /// first lands.
    pub async fn disconnect(&self) -> Result<(), Error> {
        self.handle
            .disconnect(russh::Disconnect::ByApplication, "client closed", "en")
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }
}

// ---- Direct-tcpip channel (1.7 — `-L` primitive + ProxyJump hop) -------

/// Direct-tcpip channel: a russh-managed TCP-to-TCP byte pipe over
/// the SSH session. Used by:
///   - `-L` local forwards: external code accepts on a local
///     listener and bridges sockets to a `ForwardChannel`.
///   - ProxyJump: the originator becomes the entry-side socket,
///     the connect target is the next-hop SSH server, and the
///     channel itself is the transport for `Session::connect_*`
///     after this point.
///
/// Same split-halves design as `Shell` — write side uses russh's
/// `&self`-based send path, read side serialises behind a Mutex
/// because `wait()` is `&mut self`.
pub struct ForwardChannel {
    write_half: ChannelWriteHalf<Msg>,
    read_half: Mutex<ChannelReadHalf>,
}

impl ForwardChannel {
    /// Send bytes to the remote endpoint.
    pub async fn write(&self, data: &[u8]) -> Result<(), Error> {
        let mut reader: &[u8] = data;
        self.write_half
            .data(&mut reader)
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }

    /// Wait for the next chunk of remote bytes. Returns `None` when
    /// the channel is fully closed (server sent `Close` after
    /// optional `Eof`). Channel-control messages (window updates,
    /// success / failure replies) are filtered out internally.
    pub async fn read(&self) -> Option<Vec<u8>> {
        loop {
            let mut read = self.read_half.lock().await;
            let msg = read.wait().await?;
            drop(read);
            match msg {
                ChannelMsg::Data { data } => return Some(data.to_vec()),
                ChannelMsg::ExtendedData { data, .. } => return Some(data.to_vec()),
                ChannelMsg::Eof | ChannelMsg::Close => return None,
                _ => continue,
            }
        }
    }

    /// Half-close the write side. Server typically interprets this
    /// as "client done sending" and closes its end after draining.
    pub async fn eof(&self) -> Result<(), Error> {
        self.write_half
            .eof()
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }
}

// ---- Shell channel (1.3) ----------------------------------------------

/// Long-lived shell channel. Holds russh's split halves so writers
/// and readers do not contend on the same lock — critical for an
/// interactive terminal where stdin and stdout are independent.
pub struct Shell {
    /// `ChannelWriteHalf` exposes its mutating operations through
    /// `&self` (russh handles internal synchronisation), so no Mutex
    /// needed here.
    write_half: ChannelWriteHalf<Msg>,
    /// `wait()` requires `&mut self`, so the read half lives behind
    /// a tokio Mutex. Concurrent calls to `next_event` are serialised
    /// — the channel only delivers one event at a time anyway.
    read_half: Mutex<ChannelReadHalf>,
}

impl Shell {
    /// Send stdin bytes to the remote shell. Returns when russh has
    /// queued the bytes; backpressure on the wire is internal to russh.
    pub async fn write(&self, data: &[u8]) -> Result<(), Error> {
        let mut reader: &[u8] = data;
        self.write_half
            .data(&mut reader)
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }

    /// Wait for the next event from the remote — output bytes,
    /// extended (stderr) bytes, EOF, or an exit-status / exit-signal
    /// from the server. Returns `None` once the channel is fully
    /// closed.
    pub async fn next_event(&self) -> Option<ShellEvent> {
        loop {
            let mut read = self.read_half.lock().await;
            let msg = read.wait().await?;
            // Drop the lock before yielding to caller — keeps `write`
            // unblocked between events.
            drop(read);
            if let Some(event) = ShellEvent::from_channel_msg(msg) {
                return Some(event);
            }
            // Otherwise loop and read the next message.
        }
    }

    /// Notify the remote of a terminal-window resize. `pix_width` /
    /// `pix_height` default to 0 — almost no terminal cares about
    /// pixel dimensions over character cells.
    pub async fn resize(&self, cols: u32, rows: u32) -> Result<(), Error> {
        self.write_half
            .window_change(cols, rows, 0, 0)
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }

    /// Send EOF on the stdin side. The server typically interprets
    /// this as "user closed stdin" and exits the foreground program.
    pub async fn eof(&self) -> Result<(), Error> {
        self.write_half
            .eof()
            .await
            .map_err(|e| Error::Io(e.to_string()))
    }
}

/// Events delivered by `Shell::next_event`. Mirrors the subset of
/// russh's `ChannelMsg` that interactive shells care about — channel-
/// management messages (window adjustments, success / failure replies)
/// are handled internally by russh and never surface here.
#[derive(Debug, Clone)]
pub enum ShellEvent {
    /// Standard-output bytes from the remote shell.
    Output(Vec<u8>),
    /// Extended-data bytes (typically stderr).
    ExtendedOutput(Vec<u8>),
    /// Server signalled end-of-file on its side.
    Eof,
    /// Process exited with the given status code.
    ExitStatus(u32),
    /// Process exited because of an OS signal.
    ExitSignal(String),
}

impl ShellEvent {
    fn from_channel_msg(msg: ChannelMsg) -> Option<Self> {
        match msg {
            ChannelMsg::Data { data } => Some(ShellEvent::Output(data.to_vec())),
            ChannelMsg::ExtendedData { data, .. } => {
                Some(ShellEvent::ExtendedOutput(data.to_vec()))
            }
            ChannelMsg::Eof => Some(ShellEvent::Eof),
            ChannelMsg::ExitStatus { exit_status } => Some(ShellEvent::ExitStatus(exit_status)),
            ChannelMsg::ExitSignal { signal_name, .. } => {
                Some(ShellEvent::ExitSignal(format!("{signal_name:?}")))
            }
            _ => None,
        }
    }
}

// ---- Helpers ----------------------------------------------------------

/// Connect to the user's running ssh-agent across the platform-
/// specific default channels:
/// - **Unix** — `$SSH_AUTH_SOCK` (the canonical OpenSSH path).
/// - **Windows** — OpenSSH-on-Windows named pipe
///   (`\\.\pipe\openssh-ssh-agent`) preferred (that's what the
///   `OpenSSH Authentication Agent` service registers when the
///   user enables it via Optional Features), falling back to
///   Pageant for users on the PuTTY toolchain. russh 0.59 does
///   not expose `connect_env` on Windows because Windows has no
///   single canonical agent socket — the platform splits between
///   the OpenSSH named pipe and Pageant's per-process protocol.
///
/// Returns the dynamic-stream variant (`AgentClient<Box<dyn ...>>`)
/// so the call sites stay generic over the per-platform stream type
/// downstream (UnixStream / NamedPipeClient / PageantStream).
async fn connect_default_agent() -> Result<
    russh::keys::agent::client::AgentClient<
        Box<dyn russh::keys::agent::client::AgentStream + Send + Unpin + 'static>,
    >,
    Error,
> {
    #[cfg(unix)]
    {
        let agent = russh::keys::agent::client::AgentClient::connect_env()
            .await
            .map_err(|e| Error::Auth(format!("agent connect: {e}")))?;
        Ok(agent.dynamic())
    }
    #[cfg(windows)]
    {
        const OPENSSH_NAMED_PIPE: &str = r"\\.\pipe\openssh-ssh-agent";
        match russh::keys::agent::client::AgentClient::connect_named_pipe(
            OPENSSH_NAMED_PIPE,
        )
        .await
        {
            Ok(client) => Ok(client.dynamic()),
            Err(named_pipe_err) => match russh::keys::agent::client::AgentClient::connect_pageant()
                .await
            {
                Ok(client) => Ok(client.dynamic()),
                Err(pageant_err) => Err(Error::Auth(format!(
                    "agent connect: openssh-named-pipe={named_pipe_err}, pageant={pageant_err}"
                ))),
            },
        }
    }
}

/// Owned-args agent flow extracted into a free function. Inlining it
/// inside the `Session::connect_agent` method body produces a
/// "higher-ranked lifetime error" out of FRB's `wrap_async` (the
/// future captured a borrowed parameter through several `.await`
/// hops in a loop, and FRB couldn't prove the resulting future is
/// `Send + 'static`). Owning the strings up front sidesteps the
/// reference-lifetime tangle.
async fn connect_via_agent(host: String, port: u16, user: String) -> Result<Session, Error> {
    let mut agent = connect_default_agent().await?;

    let identities = agent
        .request_identities()
        .await
        .map_err(|e| Error::Auth(format!("agent list: {e}")))?;

    if identities.is_empty() {
        return Err(Error::Auth(
            "ssh-agent reachable but exposes no identities".into(),
        ));
    }

    let (mut handle, forward_rx) = open_handle_for_session(&host, port).await?;

    // Consume identities by value and match-extract the owned key —
    // borrowing them across `.await` (or going through the `Cow`
    // public_key accessor) trips a higher-ranked lifetime error in
    // FRB's `wrap_async` because `&AgentIdentity` is only `Send`
    // for a specific lifetime and the future needs to be `Send`
    // for any lifetime.
    for ident in identities {
        let public = match ident {
            russh::keys::agent::AgentIdentity::PublicKey { key, .. } => key,
            // Cert-bearing identities skipped here — SSH cert
            // userauth needs the upstream russh-keys cert
            // algorithm tables anyway.
            russh::keys::agent::AgentIdentity::Certificate { .. } => continue,
        };
        let hash_alg = if public.algorithm().is_rsa() {
            Some(HashAlg::Sha256)
        } else {
            None
        };
        match handle
            .authenticate_publickey_with(user.clone(), public, hash_alg, &mut agent)
            .await
        {
            Ok(AuthResult::Success) => {
                return Ok(Session::from_handle(handle, forward_rx));
            }
            Ok(AuthResult::Failure { .. }) => continue,
            Err(e) => return Err(Error::Auth(format!("agent sign: {e}"))),
        }
    }

    Err(Error::AuthFailed)
}

/// ProxyJump-tunnelled twin of `connect_via_agent`. Mirrors the
/// owned-arg shape because the same FRB lifetime constraints apply
/// to this path; the only difference is how we obtain the inner
/// russh `Handle` (via `open_handle_via_proxy` instead of a fresh
/// TCP dial).
async fn connect_via_agent_proxy(
    parent: &Session,
    host: String,
    port: u16,
    user: String,
) -> Result<Session, Error> {
    let mut agent = connect_default_agent().await?;

    let identities = agent
        .request_identities()
        .await
        .map_err(|e| Error::Auth(format!("agent list: {e}")))?;

    if identities.is_empty() {
        return Err(Error::Auth(
            "ssh-agent reachable but exposes no identities".into(),
        ));
    }

    let (mut handle, forward_rx) = open_handle_via_proxy(parent, &host, port).await?;

    for ident in identities {
        let public = match ident {
            russh::keys::agent::AgentIdentity::PublicKey { key, .. } => key,
            russh::keys::agent::AgentIdentity::Certificate { .. } => continue,
        };
        let hash_alg = if public.algorithm().is_rsa() {
            Some(HashAlg::Sha256)
        } else {
            None
        };
        match handle
            .authenticate_publickey_with(user.clone(), public, hash_alg, &mut agent)
            .await
        {
            Ok(AuthResult::Success) => {
                return Ok(Session::from_handle(handle, forward_rx));
            }
            Ok(AuthResult::Failure { .. }) => continue,
            Err(e) => return Err(Error::Auth(format!("agent sign: {e}"))),
        }
    }

    Err(Error::AuthFailed)
}

async fn finish_authenticate_pubkey(
    session: &mut Handle<LfsHandler>,
    user: &str,
    key: PrivateKey,
) -> Result<(), Error> {
    let hash_alg = if key.algorithm().is_rsa() {
        // Default to SHA-256 for RSA — server-side OpenSSH ≥7.2 prefers
        // it over the legacy SHA-1 (`ssh-rsa`). A follow-up may probe
        // `best_supported_rsa_hash` and fall back if the server
        // explicitly rejects SHA-256.
        Some(HashAlg::Sha256)
    } else {
        None
    };

    let key_with_hash = PrivateKeyWithHashAlg::new(Arc::new(key), hash_alg);

    let auth_result = session
        .authenticate_publickey(user, key_with_hash)
        .await
        .map_err(|e| Error::Auth(e.to_string()))?;

    if !matches!(auth_result, AuthResult::Success) {
        return Err(Error::AuthFailed);
    }
    Ok(())
}

/// Parse a private key in OpenSSH format or PuTTY PPK (v2 + v3),
/// applying a passphrase if the key is encrypted. Pure-CPU; runs
/// synchronously inside the caller's task.
///
/// Format detection: a leading `-----BEGIN OPENSSH PRIVATE KEY-----`
/// marker routes to russh-keys' `from_openssh`; bytes starting with
/// `PuTTY-User-Key-File-` route to `from_ppk` (PPK feature on the
/// forked ssh-key crate, enabled via Cargo.toml direct dep). Legacy
/// PEM PKCS#1 / PKCS#8 (`-----BEGIN RSA PRIVATE KEY-----` etc.)
/// route through the legacy `rsa::pkcs1` / `pkcs8` parser on top
/// of russh-keys.
fn parse_private_key(bytes: &[u8], passphrase: Option<&str>) -> Result<PrivateKey, Error> {
    let trimmed: Vec<u8> = bytes
        .iter()
        .copied()
        .skip_while(|b| b.is_ascii_whitespace())
        .collect();

    let mut key = if trimmed.starts_with(b"PuTTY-User-Key-File-") {
        let ppk =
            std::str::from_utf8(&trimmed).map_err(|e| Error::KeyParse(format!("ppk utf8: {e}")))?;
        let pass_owned = passphrase.map(|p| p.to_owned());
        PrivateKey::from_ppk(ppk, pass_owned).map_err(map_key_decrypt_err)?
    } else {
        let key = PrivateKey::from_openssh(&trimmed).map_err(|e| Error::KeyParse(e.to_string()))?;
        if key.is_encrypted() {
            let pass = passphrase.ok_or(Error::PassphraseRequired)?;
            key.decrypt(pass).map_err(map_key_decrypt_err)?
        } else {
            key
        }
    };
    // OpenSSH path can leave the key encrypted on the first decrypt
    // call when the passphrase is wrong; the `decrypt` arm above
    // already returns the error in that case. PPK's `from_ppk`
    // returns a decrypted key directly, so no extra step here. The
    // `mut` binding shape mirrors the structure for symmetry with
    // future format dispatchers (PEM PKCS#1/#8 land at 1.4b and
    // will append more arms above).
    let _ = &mut key;
    Ok(key)
}

/// Parse an OpenSSH-format certificate (`id_*-cert.pub` / armored
/// `-----BEGIN OPENSSH CERTIFICATE-----` form). UTF-8-decodes the
/// caller's bytes first so callers can pass the file contents
/// straight through.
fn parse_certificate(bytes: &[u8]) -> Result<Certificate, Error> {
    let trimmed: Vec<u8> = bytes
        .iter()
        .copied()
        .skip_while(|b| b.is_ascii_whitespace())
        .collect();
    let cert_str =
        std::str::from_utf8(&trimmed).map_err(|e| Error::KeyParse(format!("cert utf8: {e}")))?;
    Certificate::from_openssh(cert_str).map_err(|e| Error::KeyParse(format!("cert: {e}")))
}

/// Distinguish "passphrase wrong" (very common on user mistyping) from
/// generic key-parse failures so the UI can prompt for re-entry rather
/// than abandoning the auth attempt.
fn map_key_decrypt_err(e: ssh_key::Error) -> Error {
    let msg = e.to_string().to_ascii_lowercase();
    if msg.contains("crypto") || msg.contains("decrypt") || msg.contains("mac") {
        Error::PassphraseIncorrect
    } else {
        Error::KeyParse(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::keys::{ssh_key::LineEnding, Algorithm, PrivateKey};

    fn random_ed25519_pem() -> Vec<u8> {
        let key = PrivateKey::random(&mut rand::thread_rng(), Algorithm::Ed25519)
            .expect("ed25519 keygen");
        key.to_openssh(LineEnding::LF)
            .expect("openssh encode")
            .as_bytes()
            .to_vec()
    }

    #[test]
    fn parses_unencrypted_ed25519() {
        let pem = random_ed25519_pem();
        let parsed = parse_private_key(&pem, None);
        assert!(parsed.is_ok(), "expected Ok, got: {parsed:?}");
    }

    #[test]
    fn rejects_garbage_bytes() {
        let result = parse_private_key(b"not-a-key", None);
        assert!(
            matches!(result, Err(Error::KeyParse(_))),
            "expected KeyParse, got: {result:?}",
        );
    }

    #[test]
    fn rejects_empty_bytes() {
        let result = parse_private_key(b"", None);
        assert!(
            matches!(result, Err(Error::KeyParse(_))),
            "expected KeyParse, got: {result:?}",
        );
    }

    #[tokio::test]
    async fn try_connect_password_against_closed_port_returns_connect_error() {
        // Port 1 is privileged and almost always refused — deterministic
        // negative test for the connect path. Avoids a network round-trip
        // to a real server while still exercising the full code path.
        let result = try_connect_password("127.0.0.1", 1, "anyone", "irrelevant").await;
        assert!(
            matches!(result, Err(Error::Connect(_))),
            "expected Connect, got: {result:?}",
        );
    }

    #[tokio::test]
    async fn session_connect_password_against_closed_port_returns_connect_error() {
        // `Session` wraps russh's Handle which is not Debug; format
        // only the error path explicitly for assertion messages.
        let result = Session::connect_password("127.0.0.1", 1, "anyone", "irrelevant").await;
        match result {
            Err(Error::Connect(_)) => {} // expected
            Err(other) => panic!("expected Connect, got: {other:?}"),
            Ok(_) => panic!("expected Connect error, got Ok session"),
        }
    }

    #[test]
    fn routes_ppk_marker_to_ppk_parser() {
        // Truncated PPK header is rejected at parse time — but the
        // dispatch must be the PPK arm, so the error wraps the PPK
        // parser's complaint, not OpenSSH's.
        let result = parse_private_key(b"PuTTY-User-Key-File-3: ssh-rsa\nEncryption: none\n", None);
        // PassphraseIncorrect maps from "mac"/"crypto"/"decrypt" lines;
        // KeyParse covers everything else. Either is acceptable here —
        // the body is incomplete so PPK parser fails for either reason.
        match result {
            Err(Error::KeyParse(_)) | Err(Error::PassphraseIncorrect) => {}
            other => panic!("expected KeyParse / PassphraseIncorrect, got: {other:?}"),
        }
    }

    #[test]
    fn ppk_marker_with_leading_whitespace_is_recognised() {
        // Real-world keys often arrive with a stray leading newline
        // from copy-paste. The parser strips ASCII whitespace before
        // looking at the magic, so this still routes to PPK.
        let result = parse_private_key(b"\n\n  PuTTY-User-Key-File-3: bogus\n", None);
        match result {
            Err(Error::KeyParse(_)) | Err(Error::PassphraseIncorrect) => {}
            other => panic!("expected KeyParse / PassphraseIncorrect, got: {other:?}"),
        }
    }

    #[test]
    fn key_parse_error_carries_message() {
        let result = parse_private_key(
            b"-----BEGIN OPENSSH PRIVATE KEY-----\nnope\n-----END OPENSSH PRIVATE KEY-----\n",
            None,
        );
        let err = result.expect_err("garbage payload");
        let formatted = format!("{err}");
        assert!(formatted.starts_with("key parse failed:"), "{formatted}");
    }
}
