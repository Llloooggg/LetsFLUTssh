//! FRB adapter for `lfs_core::ssh`.
//!
//! Two surfaces today:
//!   - One-shot probes (`ssh_try_connect_password`,
//!     `ssh_try_connect_pubkey`) — validate credentials and
//!     disconnect.
//!   - Long-lived session + shell (`SshSession`, `SshShell`) —
//!     opens an interactive PTY-backed shell channel and exposes
//!     write / read / resize / eof.
//!
//! Session / shell are exposed as FRB opaque types — Dart receives
//! handle objects whose `dispose()` triggers Rust `Drop` and tears
//! the channel / connection down. `disconnect()` exposes the explicit
//! teardown path that sends `SSH_MSG_DISCONNECT`; preferred over
//! relying on Drop for graceful shutdown.

use std::sync::Arc;

use tokio::sync::Mutex;

use flutter_rust_bridge::frb;

// `StreamSink<T>` is generated into our own `frb_generated` module by
// the FRB codegen macro at build time — it expands to a small wrapper
// over `flutter_rust_bridge::for_generated::StreamSinkBase`. Importing
// it here keeps the user-facing surface in this file readable and lets
// codegen recognise the parameter as a Rust→Dart Stream channel.
use crate::frb_generated::StreamSink;

// ---- Pure helpers -----------------------------------------------------

/// Compute the OpenSSH `SHA256:<base64-no-pad>` host-key
/// fingerprint. Sync — one SHA-256 + one base64 encode, runs in
/// microseconds. Used by the `known_hosts` settings UI when
/// rendering a key the user is about to confirm.
#[flutter_rust_bridge::frb(sync)]
pub fn ssh_format_host_key_fingerprint(key_bytes: Vec<u8>) -> String {
    lfs_core::ssh::format_fingerprint(&key_bytes)
}

// ---- Probes (1.1, 1.2) ------------------------------------------------

/// Probe an SSH server with username + password.
///
/// Returns `Ok(())` on successful auth (server immediately
/// disconnected after); throws a typed Dart exception on connect
/// failure, host-key rejection, or auth failure.
///
/// One-shot probe surface — the long-lived session handle plus
/// the full `SshTransport` interface live on `SshSession`.
pub async fn ssh_try_connect_password(
    host: String,
    port: u16,
    user: String,
    password: Vec<u8>,
) -> Result<(), String> {
    // RFC 4252 §8 specifies the SSH password field as UTF-8.
    // russh enforces this at its `auth_password(&str)` boundary,
    // so we surface non-UTF-8 input as a typed FRB envelope
    // (`kind=auth_failed`) rather than the previous plain-string
    // error that the Dart router degraded to "generic". A user
    // pasting a Latin-1-encoded password from a legacy tool now
    // lands on the localised "password rejected" path.
    let pw = std::str::from_utf8(&password).map_err(|_| {
        crate::api::frb_err::wire(
            crate::api::frb_err::kind::AUTH_FAILED,
            "password is not valid UTF-8",
        )
    })?;
    lfs_core::ssh::try_connect_password(&host, port, &user, pw)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Probe an SSH server with username + private key.
///
/// Accepts OpenSSH PEM (`-----BEGIN OPENSSH PRIVATE KEY-----`) and
/// PuTTY PPK (v2 + v3 / Argon2id, `PuTTY-User-Key-File-...`).
/// `passphrase` is required only when the key file is encrypted.
///
/// Legacy PEM PKCS#1 / PKCS#8 (`-----BEGIN RSA PRIVATE KEY-----`
/// etc.) routes through the same parser.
pub async fn ssh_try_connect_pubkey(
    host: String,
    port: u16,
    user: String,
    private_key: Vec<u8>,
    passphrase: Option<String>,
) -> Result<(), String> {
    lfs_core::ssh::try_connect_pubkey(&host, port, &user, &private_key, passphrase.as_deref())
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

// ---- Long-lived session (1.3) -----------------------------------------

/// Live, authenticated SSH session. Drop-safe: when Dart releases the
/// handle, Rust drops the inner `Session` and russh tears the TCP
/// connection down. Call `disconnect()` first for a graceful
/// `SSH_MSG_DISCONNECT`.
///
/// Inner is `Mutex<Option<Arc<Session>>>` — every method clones the
/// `Arc` under the lock and immediately releases it before awaiting
/// any per-channel work. Concurrent operations (open_shell while a
/// forward pump is parked on `next_forwarded_connection`) therefore
/// never serialise on the outer mutex; russh handles the per-channel
/// concurrency itself. Holding the lock across an `await` previously
/// produced an infinite deadlock against the long-lived forward
/// pump.
#[frb(opaque)]
pub struct SshSession {
    inner: Mutex<Option<Arc<lfs_core::ssh::Session>>>,
}

impl SshSession {
    /// Construct a fresh `SshSession` wrapper around an `Arc`-shared
    /// core `Session`. Connect helpers below funnel through here so
    /// the Arc shape stays consistent.
    fn from_core(session: lfs_core::ssh::Session) -> Self {
        Self {
            inner: Mutex::new(Some(Arc::new(session))),
        }
    }

    /// Construct a wrapper around an already-shared `Arc<Session>`.
    /// Used by `connection_get_session` so the FRB layer can hand
    /// the Dart side a handle that points at the same russh session
    /// the connection actor holds. Both wrappers share the
    /// underlying `Arc`, so a `disconnect()` call on either drops
    /// only its own slot — the actor's session lives until the
    /// actor itself is removed from the registry.
    pub(crate) fn from_arc(session: Arc<lfs_core::ssh::Session>) -> Self {
        Self {
            inner: Mutex::new(Some(session)),
        }
    }

    /// Pull the live `Arc<Session>` out from under the outer mutex,
    /// then drop the lock before the caller awaits anything. Returns
    /// "session disconnected" once `disconnect()` has cleared the
    /// slot. The Arc lets the underlying `Session` outlive the lock
    /// for as long as the operation needs it — concurrent operations
    /// share the same `Session` without serialising at the FRB
    /// boundary.
    async fn snapshot(&self) -> Result<Arc<lfs_core::ssh::Session>, String> {
        let guard = self.inner.lock().await;
        guard
            .as_ref()
            .cloned()
            .ok_or_else(|| "session disconnected".to_string())
    }

    /// Open a PTY-backed shell channel sized to `cols × rows`.
    /// Returned `SshShell` lives independently of the session — the
    /// session can be dropped while the shell is still in use; russh
    /// then errors out the next read / write.
    pub async fn open_shell(&self, cols: u32, rows: u32) -> Result<SshShell, String> {
        let session = self.snapshot().await?;
        let shell = session
            .open_shell(cols, rows)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
        Ok(SshShell {
            inner: Arc::new(shell),
        })
    }

    /// Internal helper for `api::sftp::ssh_open_sftp` — keeps the
    /// `lfs_core::sftp::Sftp` constructor private to the adapter
    /// crate while still letting siblings reach in.
    #[frb(ignore)]
    pub(crate) async fn open_sftp_inner(&self) -> Result<lfs_core::sftp::Sftp, String> {
        let session = self.snapshot().await?;
        session
            .open_sftp()
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    #[frb(ignore)]
    pub(crate) async fn request_remote_forward_inner(
        &self,
        address: &str,
        port: u32,
    ) -> Result<u32, String> {
        let session = self.snapshot().await?;
        session
            .request_remote_forward(address, port)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    #[frb(ignore)]
    pub(crate) async fn cancel_remote_forward_inner(
        &self,
        address: &str,
        port: u32,
    ) -> Result<(), String> {
        let session = self.snapshot().await?;
        session
            .cancel_remote_forward(address, port)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    #[frb(ignore)]
    pub(crate) async fn next_forwarded_connection_inner(
        &self,
    ) -> Option<crate::api::forward::SshForwardedConnection> {
        let session = self.snapshot().await.ok()?;
        let conn = session.next_forwarded_connection().await?;
        Some(crate::api::forward::SshForwardedConnection::from_core(conn))
    }

    #[frb(ignore)]
    pub(crate) async fn open_direct_tcpip_inner(
        &self,
        host_to_connect: &str,
        port_to_connect: u32,
        originator_address: &str,
        originator_port: u32,
    ) -> Result<lfs_core::ssh::ForwardChannel, String> {
        let session = self.snapshot().await?;
        session
            .open_direct_tcpip(
                host_to_connect,
                port_to_connect,
                originator_address,
                originator_port,
            )
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Send `SSH_MSG_DISCONNECT`. Idempotent — clearing the slot
    /// stops new operations; russh's underlying `Handle` drops once
    /// the last cloned `Arc` goes out of scope, which tears the TCP
    /// connection down. The forward-pump loop holding the last live
    /// clone exits naturally on the next `recv()` returning `None`.
    pub async fn disconnect(&self) -> Result<(), String> {
        let session = {
            let mut guard = self.inner.lock().await;
            guard.take()
        };
        match session {
            Some(arc) => arc
                .disconnect()
                .await
                .map_err(|e| crate::api::frb_err::from_core(&e)),
            None => Ok(()),
        }
    }
}

/// Connect + authenticate with username + password. Returns a live
/// `SshSession` ready for `open_shell` / future SFTP / port-forward
/// methods.
pub async fn ssh_connect_password(
    host: String,
    port: u16,
    user: String,
    password: Vec<u8>,
) -> Result<SshSession, String> {
    let pw =
        std::str::from_utf8(&password).map_err(|_| "password is not valid UTF-8".to_string())?;
    let session = lfs_core::ssh::Session::connect_password(&host, port, &user, pw)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// Connect + authenticate by delegating signing to the system SSH
/// agent ($SSH_AUTH_SOCK on Unix, OpenSSH-style named pipe on Windows,
/// Pageant on Windows fallback). Iterates over the agent's identities
/// in order; first identity the server accepts wins. Errors with
/// `auth failed` only if every identity is rejected (the typical
/// remediation is `ssh-add` of the desired key, then retry).
///
/// **FIDO2 sk-* keys go through this path** — when the agent has
/// security-key identities registered (`ssh-add -K`), the agent
/// itself drives the CTAP2 user-presence prompt; russh just relays
/// the resulting signature. So this function also covers §6.3
/// hardware-token auth without any local FIDO2 stack.
///
/// Implementation: russh's `AgentClient` produces per-method futures
/// that are not `Send` — the all-identities iteration in
/// `Session::connect_agent` therefore can't run inside FRB's
/// `Send + 'static`-bounded async wrapper. We dispatch the work on
/// `tokio::task::spawn_blocking` and drive the future with a fresh
/// runtime handle's `block_on`, keeping the non-Send future on a
/// dedicated blocking-pool thread that never crosses thread
/// boundaries.
pub async fn ssh_connect_agent(
    host: String,
    port: u16,
    user: String,
) -> Result<SshSession, String> {
    let handle = tokio::runtime::Handle::current();
    let session = tokio::task::spawn_blocking(move || {
        handle
            .block_on(lfs_core::ssh::Session::connect_agent(&host, port, &user))
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("agent task: {e}"))??;
    Ok(SshSession::from_core(session))
}

/// Connect + authenticate with an OpenSSH **certificate** (an SSH
/// public key signed by a CA, plus the matching private key).
///
/// `private_key` accepts either OpenSSH PEM (`-----BEGIN OPENSSH
/// PRIVATE KEY-----`) or PuTTY PPK formats (same dispatch as
/// `ssh_connect_pubkey`); `cert` accepts the OpenSSH cert blob (the
/// `-cert.pub` companion file produced by `ssh-keygen -s ca_key
/// id_*.pub`). Server must trust the issuing CA via
/// `TrustedUserCAKeys`.
///
/// SSH certificate auth surface (see ARCHITECTURE §6.2).
pub async fn ssh_connect_pubkey_cert(
    host: String,
    port: u16,
    user: String,
    private_key: Vec<u8>,
    passphrase: Option<String>,
    cert: Vec<u8>,
) -> Result<SshSession, String> {
    // Direct in-line `await` — sibling `ssh_connect_password` /
    // `ssh_connect_pubkey` already use this shape. The previous
    // `tokio::spawn` detached the connect future from the FRB
    // task's cancellation: a Dart-side `dispose` on the dial-in-
    // progress controller could not abort the spawned task, which
    // kept holding the russh session through to handshake
    // completion before noticing nobody wanted the result.
    let session = lfs_core::ssh::Session::connect_pubkey_cert(
        &host,
        port,
        &user,
        &private_key,
        passphrase.as_deref(),
        &cert,
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// Connect + authenticate with a FIDO2 hardware-bound `sk-*` SSH
/// key. Private key material never crosses this boundary: russh
/// asks the device to sign every userauth challenge through
/// `lfs_core::fido2::get_assertion`, the touch / PIN prompt fires
/// inside the device firmware, and only the resulting signature
/// blob reaches the process.
///
/// `public_openssh` is the single-line `id_*.pub` body. `credential_id`
/// is the opaque CTAP2 blob captured at import. `application` is the
/// SSH `application` string (typically `ssh:`). `pin` is forwarded
/// to the device when the credential carries the user-verification
/// bit; touch-only credentials should pass `None`.
pub async fn ssh_connect_pubkey_sk(
    host: String,
    port: u16,
    user: String,
    public_openssh: String,
    credential_id: Vec<u8>,
    application: String,
    pin: Option<String>,
) -> Result<SshSession, String> {
    let session = lfs_core::ssh::Session::connect_pubkey_sk(
        &host,
        port,
        &user,
        &public_openssh,
        &credential_id,
        &application,
        pin.as_deref(),
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// Connect + authenticate with username + private key. Accepts both
/// OpenSSH PEM and PuTTY PPK formats (see `ssh_try_connect_pubkey`
/// for the format list). `passphrase` is required only when the key
/// file is encrypted.
pub async fn ssh_connect_pubkey(
    host: String,
    port: u16,
    user: String,
    private_key: Vec<u8>,
    passphrase: Option<String>,
) -> Result<SshSession, String> {
    let session = lfs_core::ssh::Session::connect_pubkey(
        &host,
        port,
        &user,
        &private_key,
        passphrase.as_deref(),
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

// ---- Secret-store-backed variants -------------------------------------
//
// These take secret IDs instead of plaintext bytes. The Dart side
// is expected to push credentials into the SecretStore via the
// `app::secrets_put` FRB call, then hand the IDs to these connect
// functions. Plaintext does not cross the FRB boundary at connect
// time. The `Session::connect_*_with_secret` family resolves the
// IDs against the process-singleton SecretStore.

/// Password auth using a SecretStore-stored password.
pub async fn ssh_connect_password_with_secret(
    host: String,
    port: u16,
    user: String,
    password_secret_id: String,
) -> Result<SshSession, String> {
    let session = lfs_core::ssh::Session::connect_password_with_secret(
        &host,
        port,
        &user,
        &password_secret_id,
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// Pubkey auth using SecretStore-stored bytes. `passphrase_secret_id`
/// is optional — pass `None` for unencrypted keys.
pub async fn ssh_connect_pubkey_with_secret(
    host: String,
    port: u16,
    user: String,
    key_secret_id: String,
    passphrase_secret_id: Option<String>,
) -> Result<SshSession, String> {
    let session = lfs_core::ssh::Session::connect_pubkey_with_secret(
        &host,
        port,
        &user,
        &key_secret_id,
        passphrase_secret_id.as_deref(),
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// OpenSSH-cert auth using SecretStore-stored bytes.
pub async fn ssh_connect_pubkey_cert_with_secret(
    host: String,
    port: u16,
    user: String,
    key_secret_id: String,
    cert_secret_id: String,
    passphrase_secret_id: Option<String>,
) -> Result<SshSession, String> {
    let session = lfs_core::ssh::Session::connect_pubkey_cert_with_secret(
        &host,
        port,
        &user,
        &key_secret_id,
        &cert_secret_id,
        passphrase_secret_id.as_deref(),
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

// ---- ProxyJump bastion variants (1.10b) -------------------------------
//
// Each `ssh_connect_*_via_proxy` mirrors its non-proxy counterpart
// but tunnels the SSH handshake through a `direct-tcpip` channel on
// the supplied parent session. The parent stays live for the child's
// full lifetime; tearing the parent down ends the child's transport
// at the next read / write.
//
// Composability: the returned child is itself an `SshSession`, so it
// can serve as the parent for the next hop. ConnectionManager.dart
// walks the chain from the outermost bastion inward.

/// Password auth tunnelled through `parent`.
pub async fn ssh_connect_password_via_proxy(
    parent: &SshSession,
    host: String,
    port: u16,
    user: String,
    password: Vec<u8>,
) -> Result<SshSession, String> {
    let pw =
        std::str::from_utf8(&password).map_err(|_| "password is not valid UTF-8".to_string())?;
    // Drop the parent's mutex before awaiting the handshake — clone
    // the Arc out via `snapshot()` so concurrent `*_via_proxy` calls
    // against the same parent never serialise behind one mutex.
    let parent_session = parent.snapshot().await?;
    let session =
        lfs_core::ssh::Session::connect_password_via_proxy(&parent_session, &host, port, &user, pw)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// Pubkey auth tunnelled through `parent`.
pub async fn ssh_connect_pubkey_via_proxy(
    parent: &SshSession,
    host: String,
    port: u16,
    user: String,
    private_key: Vec<u8>,
    passphrase: Option<String>,
) -> Result<SshSession, String> {
    let parent_session = parent.snapshot().await?;
    let session = lfs_core::ssh::Session::connect_pubkey_via_proxy(
        &parent_session,
        &host,
        port,
        &user,
        &private_key,
        passphrase.as_deref(),
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

/// OpenSSH cert auth tunnelled through `parent`.
pub async fn ssh_connect_pubkey_cert_via_proxy(
    parent: &SshSession,
    host: String,
    port: u16,
    user: String,
    private_key: Vec<u8>,
    passphrase: Option<String>,
    cert: Vec<u8>,
) -> Result<SshSession, String> {
    let parent_session = parent.snapshot().await?;
    let session = lfs_core::ssh::Session::connect_pubkey_cert_via_proxy(
        &parent_session,
        &host,
        port,
        &user,
        &private_key,
        passphrase.as_deref(),
        &cert,
    )
    .await
    .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(SshSession::from_core(session))
}

// `ssh_connect_agent_via_proxy` intentionally NOT exposed: russh's
// `AgentClient` per-method futures are not `Send`, so the FRB
// `wrap_async`'s `Send + 'static` bound rejects the inner call. The
// non-proxy `ssh_connect_agent` works around it with
// `spawn_blocking + Handle::block_on`, but the proxy variant takes
// `parent: &SshSession` — that reference can't cross the
// `spawn_blocking` thread boundary. Agent + ProxyJump is rare in
// practice (users typically run the agent at the bastion or use a
// pubkey for the inner hop); leaving this gap until a future
// SshSession redesign that wraps `lfs_core::ssh::Session` in `Arc`
// and lets the proxy variant clone the Arc into `spawn_blocking`.

// ---- Shell channel (1.3) ----------------------------------------------

/// PTY-backed interactive shell channel. Wraps `lfs_core::ssh::Shell`
/// behind an `Arc` so multiple Dart objects (e.g. a writer and a
/// reader running in parallel isolates) can share access.
#[frb(opaque)]
pub struct SshShell {
    inner: Arc<lfs_core::ssh::Shell>,
}

impl SshShell {
    /// Send stdin bytes to the remote shell.
    pub async fn write(&self, data: Vec<u8>) -> Result<(), String> {
        self.inner
            .write(&data)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Wait for the next event from the remote — output bytes,
    /// extended (stderr) bytes, EOF, or an exit-status / exit-signal.
    /// Returns `null` on the Dart side once the channel is fully
    /// closed.
    pub async fn next_event(&self) -> Option<SshShellEvent> {
        self.inner.next_event().await.map(SshShellEvent::from_core)
    }

    /// Notify the remote of a terminal-window resize. `pix_width` /
    /// `pix_height` default to 0 internally — almost no terminal
    /// cares about pixel dimensions over character cells.
    pub async fn resize(&self, cols: u32, rows: u32) -> Result<(), String> {
        self.inner
            .resize(cols, rows)
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Send EOF on stdin. The server typically interprets this as
    /// "user closed stdin" and exits the foreground program.
    pub async fn eof(&self) -> Result<(), String> {
        self.inner
            .eof()
            .await
            .map_err(|e| crate::api::frb_err::from_core(&e))
    }

    /// Long-running task that pumps shell events into a Dart-side
    /// `Stream<SshShellEvent>`. Returns when the channel closes (the
    /// remote sent `Close` / `Eof`) or when the Dart subscription is
    /// cancelled (sink rejects further `add`s).
    ///
    /// The Dart-side terminal widget binds
    /// `terminal.write(...)` to the `Output` / `ExtendedOutput`
    /// variants and surfaces `ExitStatus` / `ExitSignal` to the
    /// connection-state UI. Since `SshShell::next_event` already
    /// serialises the read half through a tokio `Mutex`, calling
    /// this method twice on the same shell would deadlock — caller
    /// must ensure a single subscriber per shell.
    pub async fn events_stream(&self, sink: StreamSink<SshShellEvent>) -> Result<(), String> {
        while let Some(event) = self.inner.next_event().await {
            let mapped = SshShellEvent::from_core(event);
            if sink.add(mapped).is_err() {
                // Dart side closed the stream — exit cleanly.
                break;
            }
        }
        Ok(())
    }
}

/// Event delivered by `SshShell::next_event` — output bytes, extended
/// (stderr) bytes, EOF, exit status, or exit signal. Mirrors the
/// `lfs_core` enum so FRB can codegen a tagged Dart sealed class.
#[derive(Debug, Clone)]
pub enum SshShellEvent {
    Output(Vec<u8>),
    ExtendedOutput(Vec<u8>),
    Eof,
    ExitStatus(u32),
    ExitSignal(String),
}

impl SshShellEvent {
    fn from_core(event: lfs_core::ssh::ShellEvent) -> Self {
        match event {
            lfs_core::ssh::ShellEvent::Output(data) => SshShellEvent::Output(data),
            lfs_core::ssh::ShellEvent::ExtendedOutput(data) => SshShellEvent::ExtendedOutput(data),
            lfs_core::ssh::ShellEvent::Eof => SshShellEvent::Eof,
            lfs_core::ssh::ShellEvent::ExitStatus(code) => SshShellEvent::ExitStatus(code),
            lfs_core::ssh::ShellEvent::ExitSignal(name) => SshShellEvent::ExitSignal(name),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The connect / shell / forward / sftp surfaces (`ssh_connect_*`,
    // `SshSession`, `SshShell`, `ssh_open_direct_tcpip`) need a live
    // russh peer; the `tests/connection_lifecycle.rs` integration
    // binary spins up `lfs_core::connection::test_server` and drives
    // them end-to-end. The standalone tests below pin the pure
    // helpers + the SshShellEvent variant mapping that crosses the
    // FRB boundary on every shell event.

    #[test]
    fn format_host_key_fingerprint_emits_openssh_sha256_shape() {
        // Pin the wire shape — the known_hosts settings UI renders
        // the returned string verbatim. `SHA256:<base64-no-pad>`
        // is the OpenSSH canonical form.
        let key = vec![0xAA; 32];
        let fp = ssh_format_host_key_fingerprint(key);
        assert!(
            fp.starts_with("SHA256:"),
            "expected SHA256: prefix, got {fp}"
        );
        assert!(
            !fp.ends_with('='),
            "OpenSSH fingerprint is base64-no-pad — trailing '=' is a regression"
        );
    }

    #[test]
    fn format_host_key_fingerprint_is_deterministic() {
        let key = vec![0xBB; 16];
        let a = ssh_format_host_key_fingerprint(key.clone());
        let b = ssh_format_host_key_fingerprint(key);
        assert_eq!(a, b, "same input must produce same fingerprint");
    }

    #[test]
    fn format_host_key_fingerprint_changes_with_key_bytes() {
        let a = ssh_format_host_key_fingerprint(vec![0xAA; 32]);
        let b = ssh_format_host_key_fingerprint(vec![0xBB; 32]);
        assert_ne!(a, b, "different keys must produce different fingerprints");
    }

    #[test]
    fn ssh_shell_event_maps_each_variant() {
        let cases = [
            lfs_core::ssh::ShellEvent::Output(b"hello".to_vec()),
            lfs_core::ssh::ShellEvent::ExtendedOutput(b"err".to_vec()),
            lfs_core::ssh::ShellEvent::Eof,
            lfs_core::ssh::ShellEvent::ExitStatus(0),
            lfs_core::ssh::ShellEvent::ExitSignal("TERM".into()),
        ];
        for core in cases {
            let db = SshShellEvent::from_core(core);
            // Pin via exhaustive match so a future variant addition
            // forces a compile error here.
            match db {
                SshShellEvent::Output(_)
                | SshShellEvent::ExtendedOutput(_)
                | SshShellEvent::Eof
                | SshShellEvent::ExitStatus(_)
                | SshShellEvent::ExitSignal(_) => (),
            }
        }
    }

    #[test]
    fn ssh_shell_event_carries_payload_through() {
        let out = SshShellEvent::from_core(lfs_core::ssh::ShellEvent::Output(b"hi".to_vec()));
        match out {
            SshShellEvent::Output(bytes) => assert_eq!(bytes, b"hi"),
            _ => panic!("expected Output"),
        }
        let err = SshShellEvent::from_core(lfs_core::ssh::ShellEvent::ExitStatus(42));
        match err {
            SshShellEvent::ExitStatus(code) => assert_eq!(code, 42),
            _ => panic!("expected ExitStatus"),
        }
        let sig = SshShellEvent::from_core(lfs_core::ssh::ShellEvent::ExitSignal("HUP".into()));
        match sig {
            SshShellEvent::ExitSignal(name) => assert_eq!(name, "HUP"),
            _ => panic!("expected ExitSignal"),
        }
    }

    #[tokio::test]
    async fn try_connect_password_rejects_non_utf8_password() {
        // Pin the post-audit contract — RFC 4252 §8 specifies UTF-8
        // for the password field; the shim must surface a clean
        // typed error rather than panic / generic-string degrade.
        let invalid_utf8 = vec![0xFF, 0xFE, 0xFD];
        let res =
            ssh_try_connect_password("127.0.0.1".into(), 65535, "u".into(), invalid_utf8).await;
        assert!(res.is_err());
        let envelope = res.unwrap_err();
        assert!(
            envelope.contains("auth_failed"),
            "expected typed kind=auth_failed envelope, got {envelope}"
        );
    }
}
