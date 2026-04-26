//! Connection lifecycle actor.
//!
//! Owns the canonical state for every active SSH connection. Dart
//! drives operations by dispatching `ConnectionCommand`s through the
//! bus; widgets observe `ConnectionEvent`s via per-screen view
//! streams. The Dart-side `Connection` class becomes a thin view
//! that mirrors the Rust state — no FSM machinery left in the UI
//! layer.
//!
//! # State model
//!
//! Each `ConnectionActor` carries its own state machine
//! (`Disconnected → Connecting → Connected → Disconnected`) plus a
//! generation counter that protects against stale reconnect results
//! overwriting newer ones. The actor also holds the progress-step
//! history so a subscriber that joins late can replay every step
//! through a snapshot command.
//!
//! Bastion refs (`bastion_id`) point at another actor in the same
//! registry; the connect driver looks the parent up, grabs its
//! live `Arc<Session>`, and routes the child handshake through the
//! `connect_*_via_proxy_with_secret_owned` family. The `internal`
//! flag gates the user-visible connection list so the workspace UI
//! never paints a tab for a hop the user did not explicitly open.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::error::Error;
use crate::ssh::Session;

/// Stable identifier for an active connection. Allocated by the
/// registry on `ConnectAsync`; used as the key in every subsequent
/// command + event so subscribers can demux per-connection traffic.
pub type ConnId = String;

/// Mirrors the Dart-era `SSHConnectionState` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
}

/// Mirrors `ConnectionPhase` in Dart `connection_step.dart`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionPhase {
    SocketConnect,
    HostKeyVerify,
    Authenticate,
    OpenChannel,
}

/// Mirrors `StepStatus` in Dart `connection_step.dart`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepStatus {
    InProgress,
    Success,
    Failed,
}

/// Single progress step. Mirrors Dart `ConnectionStep`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgressStep {
    pub phase: ConnectionPhase,
    pub status: StepStatus,
    pub detail: Option<String>,
}

/// Snapshot view of an actor — what the FRB layer hands over to a
/// late subscriber as the initial state, and what a `Snapshot`
/// command returns. Designed to carry no plaintext: credentials
/// stay in the SecretStore, bastion linkage is by id only.
#[derive(Debug, Clone)]
pub struct ConnectionSnapshot {
    pub id: ConnId,
    pub label: String,
    pub session_id: Option<String>,
    pub bastion_id: Option<ConnId>,
    pub internal: bool,
    pub state: ConnectionState,
    pub error: Option<String>,
    pub progress: Vec<ProgressStep>,
}

/// Reference to a SecretStore-backed credential. The actor's
/// connect driver dispatches by variant onto the matching
/// `lfs_core::ssh::Session::connect_*_with_secret` constructor;
/// secret bytes never cross outbound from `lfs_core`.
///
/// Mirrors the Dart-side `SshAuthMethod` family but only the Ref
/// variants — quick-connect / inline plaintext is the Dart-side
/// concern and gets normalised into a transient SecretStore entry
/// before the dispatch.
#[derive(Debug, Clone)]
pub enum ConnectAuthRef {
    Password {
        secret_id: String,
    },
    Pubkey {
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    },
    PubkeyCert {
        key_secret_id: String,
        cert_secret_id: String,
        passphrase_secret_id: Option<String>,
    },
    Agent,
}

/// Inputs to [`connect_async`]. Carries the destination + typed
/// auth ref + bookkeeping fields the actor needs for its lifecycle.
#[derive(Debug, Clone)]
pub struct ConnectArgs {
    pub label: String,
    pub session_id: Option<String>,
    pub host: String,
    pub port: u16,
    pub user: String,
    pub auth: ConnectAuthRef,
    /// Parent actor id for ProxyJump bastion tunnelling. `None` =
    /// direct connect. Bastion-aware driver path lands in the
    /// next 5.1 commit; the field is here so the FRB surface
    /// stabilises now.
    pub bastion_id: Option<ConnId>,
    /// True for connections the manager creates on behalf of a
    /// ProxyJump chain. Hidden from the user-visible workspace
    /// list — the parent owns the lifecycle, internal hops have
    /// no tab.
    pub internal: bool,
}

/// Per-connection actor. The registry owns these inside an
/// `Arc<Mutex<...>>` so commands serialise per-id while the Tokio
/// runtime drives the actual transport work concurrently.
///
/// `session` holds the live russh handle once the connect driver
/// transitions the actor into `Connected`; channel-opening
/// commands look it up via [`ConnectionActor::clone_session`] and
/// drive russh directly.
pub struct ConnectionActor {
    pub id: ConnId,
    pub label: String,
    pub session_id: Option<String>,
    pub bastion_id: Option<ConnId>,
    pub internal: bool,
    pub state: ConnectionState,
    pub generation: u64,
    pub error: Option<String>,
    pub progress: Vec<ProgressStep>,
    pub host: String,
    pub port: u16,
    pub user: String,
    /// Live russh handle. `None` until the connect driver records a
    /// successful handshake; reset to `None` on disconnect so the
    /// actor can be reconnected without leaking the old handle.
    session: Option<Arc<Session>>,
}

impl ConnectionActor {
    #[allow(clippy::too_many_arguments)] // every field is load-bearing for the lifecycle
    pub fn new(
        id: ConnId,
        label: String,
        session_id: Option<String>,
        bastion_id: Option<ConnId>,
        internal: bool,
        host: String,
        port: u16,
        user: String,
    ) -> Self {
        Self {
            id,
            label,
            session_id,
            bastion_id,
            internal,
            state: ConnectionState::Disconnected,
            generation: 0,
            error: None,
            progress: Vec::new(),
            host,
            port,
            user,
            session: None,
        }
    }

    pub fn snapshot(&self) -> ConnectionSnapshot {
        ConnectionSnapshot {
            id: self.id.clone(),
            label: self.label.clone(),
            session_id: self.session_id.clone(),
            bastion_id: self.bastion_id.clone(),
            internal: self.internal,
            state: self.state,
            error: self.error.clone(),
            progress: self.progress.clone(),
        }
    }

    /// Clone the live russh handle for channel-opening callers.
    /// Returns `None` when the actor is not in the `Connected`
    /// state.
    pub fn clone_session(&self) -> Option<Arc<Session>> {
        self.session.clone()
    }
}

/// Process-singleton registry of active connections. Guards the
/// id-to-actor map under one lock; state mutations stay short-
/// lived (one transition then one bus event per call) so global
/// mutex contention is bounded.
///
/// Long-running transport work (connect handshake, keep-alive)
/// runs outside the lock — the driver loops clone the `Arc` and
/// re-acquire the lock only for state-change writes.
pub struct ConnectionRegistry {
    inner: Mutex<RegistryInner>,
}

struct RegistryInner {
    by_id: HashMap<ConnId, Arc<Mutex<ConnectionActor>>>,
    /// Live insertion order — preserved for the Dart-side workspace
    /// view that paints connections in the order the user opened
    /// them.
    order: Vec<ConnId>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryInner {
                by_id: HashMap::new(),
                order: Vec::new(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryInner> {
        self.inner.lock().expect("registry mutex poisoned")
    }

    /// Insert a freshly-built actor. Returns its handle so the
    /// caller can spin up the connect driver against the same
    /// `Arc<Mutex<ConnectionActor>>` the registry now holds.
    pub fn insert(&self, actor: ConnectionActor) -> Arc<Mutex<ConnectionActor>> {
        let id = actor.id.clone();
        let handle = Arc::new(Mutex::new(actor));
        let mut g = self.lock();
        g.by_id.insert(id.clone(), handle.clone());
        g.order.push(id);
        handle
    }

    pub fn get(&self, id: &str) -> Option<Arc<Mutex<ConnectionActor>>> {
        self.lock().by_id.get(id).cloned()
    }

    pub fn remove(&self, id: &str) -> Option<Arc<Mutex<ConnectionActor>>> {
        let mut g = self.lock();
        let handle = g.by_id.remove(id);
        if handle.is_some() {
            g.order.retain(|x| x != id);
        }
        handle
    }

    /// Snapshot every actor (in insertion order) for a workspace
    /// view rebuild. Cloning each snapshot under the lock keeps the
    /// caller off any per-actor mutex; the snapshot itself is
    /// plain-data so subsequent reads can outlive any state
    /// transition.
    pub fn snapshot_all(&self) -> Vec<ConnectionSnapshot> {
        let g = self.lock();
        let mut out = Vec::with_capacity(g.order.len());
        for id in &g.order {
            if let Some(handle) = g.by_id.get(id) {
                let actor = handle.lock().expect("actor mutex poisoned");
                out.push(actor.snapshot());
            }
        }
        out
    }

    /// Live count — diagnostic only.
    pub fn count(&self) -> usize {
        self.lock().by_id.len()
    }
}

impl Default for ConnectionRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Kick off a connect attempt under a caller-supplied `id`. The
/// caller — today the Dart-side `ConnectionManager` — generates the
/// id via `Uuid().v4()` so it can plumb the same string through
/// Riverpod / widget ownership before the Rust side has finished
/// its handshake.
///
/// Inserts the fresh actor into the registry, spawns the driver
/// task, and returns once the actor row exists so the caller can
/// safely subscribe to per-id events. The driver itself runs in
/// the background; subscribers learn about `Connecting → Connected`
/// / `Connecting → Disconnected` plus per-phase progress steps as
/// they arrive on the bus.
/// Allocate the actor row and run the connect driver to completion.
/// Returns the new `ConnId` once the actor has settled into either
/// `Connected` or `Disconnected`. Subscribers observe every
/// transition through the bus, so a Dart caller wishing to "fire
/// and forget" simply doesn't await the dispatch result.
///
/// The async-but-not-spawned shape is deliberate: tokio's HRTB
/// inference misfires when an async-fn future capturing short-lived
/// `&str` borrows is shipped through `tokio::spawn`'s `Send + 'static`
/// bound. Awaiting in-place lets the FRB worker thread own the
/// future without erasing the auto-trait constraint.
pub async fn connect_async(id: ConnId, args: ConnectArgs) -> Result<ConnId, Error> {
    let actor = ConnectionActor::new(
        id.clone(),
        args.label.clone(),
        args.session_id.clone(),
        args.bastion_id.clone(),
        args.internal,
        args.host.clone(),
        args.port,
        args.user.clone(),
    );
    let app = crate::app::instance();
    let handle = app.connections.insert(actor);
    run_connect_driver(id.clone(), args, handle).await;
    Ok(id)
}

/// Internal driver loop. Owns the state-machine transitions for one
/// connect attempt; runs in a background tokio task so [`connect_async`]
/// returns immediately. Stale-generation results are discarded so a
/// reconnect issued mid-handshake never overwrites the newer state.
async fn run_connect_driver(id: ConnId, args: ConnectArgs, handle: Arc<Mutex<ConnectionActor>>) {
    let app = crate::app::instance();
    let generation;
    {
        let mut a = handle.lock().expect("actor mutex poisoned");
        a.state = ConnectionState::Connecting;
        a.error = None;
        a.progress.clear();
        a.generation = a.generation.wrapping_add(1);
        generation = a.generation;
    }
    app.bus.publish(crate::bus::Event::ConnectionStateChanged {
        id: id.clone(),
        state: ConnectionState::Connecting,
    });
    record_progress(
        handle.clone(),
        id.clone(),
        ProgressStep {
            phase: ConnectionPhase::SocketConnect,
            status: StepStatus::InProgress,
            detail: None,
        },
    )
    .await;

    let result = run_auth(args).await;
    let _ = &result; // silence unused if future arms add early returns

    // Discard stale-generation results — a reconnect bumped the
    // counter while we were mid-handshake.
    {
        let a = handle.lock().expect("actor mutex poisoned");
        if a.generation != generation {
            return;
        }
    }

    match result {
        Ok(session) => {
            {
                let mut a = handle.lock().expect("actor mutex poisoned");
                a.session = Some(Arc::new(session));
                a.state = ConnectionState::Connected;
            }
            for phase in [
                ConnectionPhase::SocketConnect,
                ConnectionPhase::HostKeyVerify,
                ConnectionPhase::Authenticate,
            ] {
                record_progress(
                    handle.clone(),
                    id.clone(),
                    ProgressStep {
                        phase,
                        status: StepStatus::Success,
                        detail: None,
                    },
                )
                .await;
            }
            app.bus.publish(crate::bus::Event::ConnectionStateChanged {
                id,
                state: ConnectionState::Connected,
            });
        }
        Err(err) => {
            let detail = err.to_string();
            {
                let mut a = handle.lock().expect("actor mutex poisoned");
                a.state = ConnectionState::Disconnected;
                a.error = Some(detail.clone());
            }
            record_progress(
                handle.clone(),
                id.clone(),
                ProgressStep {
                    phase: failure_phase(&err),
                    status: StepStatus::Failed,
                    detail: Some(detail.clone()),
                },
            )
            .await;
            app.bus.publish(crate::bus::Event::ConnectionError {
                id: id.clone(),
                detail,
            });
            app.bus.publish(crate::bus::Event::ConnectionStateChanged {
                id,
                state: ConnectionState::Disconnected,
            });
        }
    }
}

async fn run_auth(args: ConnectArgs) -> Result<Session, Error> {
    let ConnectArgs {
        host,
        user,
        port,
        auth,
        bastion_id,
        ..
    } = args;

    // ProxyJump bastion path — look up parent actor and grab its
    // live `Arc<Session>`. If the parent is missing or not in the
    // `Connected` state, fail the child with a typed error rather
    // than silently dialing direct. Dart-side orchestrator is
    // responsible for awaiting the parent before triggering the
    // child connect (the actor's bus events provide the hook).
    let bastion_session =
        match bastion_id.as_deref() {
            None => None,
            Some(id) => {
                let app = crate::app::instance();
                let handle = app
                    .connections
                    .get(id)
                    .ok_or_else(|| Error::Io(format!("ProxyJump parent '{id}' missing")))?;
                let actor = handle.lock().expect("actor mutex poisoned");
                if actor.state != ConnectionState::Connected {
                    return Err(Error::Io(format!(
                        "ProxyJump parent '{id}' not yet connected (state {:?})",
                        actor.state
                    )));
                }
                Some(actor.clone_session().ok_or_else(|| {
                    Error::Io(format!("ProxyJump parent '{id}' has no live session"))
                })?)
            }
        };

    // Owned-arg `_owned` variants — `Session::connect_*_with_secret_owned`
    // (and `_via_proxy_with_secret_owned`) take `String`/`Arc<Session>`
    // by value so the resulting future is `Send + 'static` without
    // HRTB inference on `&str`/`&Session` borrows. The wrapping
    // `wrap_async` future on the FRB side stays clean.
    match (auth, bastion_session) {
        (ConnectAuthRef::Password { secret_id }, None) => {
            Session::connect_password_with_secret_owned(host, port, user, secret_id).await
        }
        (ConnectAuthRef::Password { secret_id }, Some(parent)) => {
            Session::connect_password_via_proxy_with_secret_owned(
                parent, host, port, user, secret_id,
            )
            .await
        }
        (
            ConnectAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            },
            None,
        ) => {
            Session::connect_pubkey_with_secret_owned(
                host,
                port,
                user,
                key_secret_id,
                passphrase_secret_id,
            )
            .await
        }
        (
            ConnectAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            },
            Some(parent),
        ) => {
            Session::connect_pubkey_via_proxy_with_secret_owned(
                parent,
                host,
                port,
                user,
                key_secret_id,
                passphrase_secret_id,
            )
            .await
        }
        (
            ConnectAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            },
            None,
        ) => {
            Session::connect_pubkey_cert_with_secret_owned(
                host,
                port,
                user,
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            )
            .await
        }
        (
            ConnectAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            },
            Some(parent),
        ) => {
            Session::connect_pubkey_cert_via_proxy_with_secret_owned(
                parent,
                host,
                port,
                user,
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            )
            .await
        }
        (ConnectAuthRef::Agent, None) => Session::connect_agent_owned(host, port, user).await,
        (ConnectAuthRef::Agent, Some(parent)) => {
            Session::connect_agent_via_proxy_owned(parent, host, port, user).await
        }
    }
}

/// Map a connect error onto the most-likely phase that broke. Lets
/// the progress writer paint the red marker next to the right line
/// — auth failure → authenticate, host-key change → hostKeyVerify,
/// otherwise socketConnect.
fn failure_phase(err: &Error) -> ConnectionPhase {
    match err {
        Error::Auth(_)
        | Error::AuthFailed
        | Error::PassphraseRequired
        | Error::PassphraseIncorrect
        | Error::KeyParse(_) => ConnectionPhase::Authenticate,
        Error::HostKeyRejected => ConnectionPhase::HostKeyVerify,
        _ => ConnectionPhase::SocketConnect,
    }
}

async fn record_progress(handle: Arc<Mutex<ConnectionActor>>, id: ConnId, step: ProgressStep) {
    let app = crate::app::instance();
    {
        let mut a = handle.lock().expect("actor mutex poisoned");
        a.progress.push(step.clone());
    }
    app.bus
        .publish(crate::bus::Event::ConnectionProgress { id, step });
}

/// Tear down every active connection actor. Convenience for
/// "lock now" / shutdown paths — walks the current registry
/// snapshot in insertion order and dispatches [`disconnect`]
/// against each. Returns the number of actors that were torn
/// down. Best-effort: per-actor protocol-level disconnect errors
/// surface through the bus, not the return value.
pub async fn disconnect_all() -> usize {
    let app = crate::app::instance();
    // Snapshot the id list under the registry lock first so the
    // iteration doesn't hold the registry's mutex across the
    // per-actor `disconnect` (which itself takes the lock again
    // to remove the row).
    let ids: Vec<String> = app
        .connections
        .snapshot_all()
        .into_iter()
        .map(|s| s.id)
        .collect();
    let mut torn_down = 0;
    for id in ids {
        if disconnect(&id).await.is_ok() {
            torn_down += 1;
        }
    }
    torn_down
}

/// Tear down a connection actor. Idempotent on a missing id.
/// Drops the held russh handle (which sends `SSH_MSG_DISCONNECT`
/// on Drop) and removes the actor from the registry; subscribers
/// observe the teardown via [`crate::bus::Event::ConnectionRemoved`].
pub async fn disconnect(id: &str) -> Result<(), Error> {
    let app = crate::app::instance();
    if let Some(handle) = app.connections.remove(id) {
        let session = {
            let mut a = handle.lock().expect("actor mutex poisoned");
            a.state = ConnectionState::Disconnected;
            a.session.take()
        };
        if let Some(s) = session {
            // Best-effort tear-down; any error during the
            // protocol-level disconnect is logged through the bus
            // but doesn't block the actor removal.
            if let Err(e) = s.disconnect().await {
                app.bus.publish(crate::bus::Event::ConnectionError {
                    id: id.to_string(),
                    detail: format!("disconnect: {e}"),
                });
            }
        }
        app.bus
            .publish(crate::bus::Event::ConnectionRemoved { id: id.to_string() });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn insert_and_snapshot() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new(
            "c1".into(),
            "Label".into(),
            Some("s1".into()),
            None,
            false,
            "host".into(),
            22,
            "user".into(),
        );
        reg.insert(actor);
        let snap = reg.snapshot_all();
        assert_eq!(snap.len(), 1);
        assert_eq!(snap[0].id, "c1");
        assert_eq!(snap[0].state, ConnectionState::Disconnected);
    }

    #[tokio::test]
    async fn remove_drops_actor() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new(
            "c1".into(),
            "L".into(),
            None,
            None,
            false,
            "h".into(),
            22,
            "u".into(),
        );
        reg.insert(actor);
        assert_eq!(reg.count(), 1);
        reg.remove("c1");
        assert_eq!(reg.count(), 0);
        assert!(reg.snapshot_all().is_empty());
    }

    #[tokio::test]
    async fn snapshot_carries_progress() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new(
            "c1".into(),
            "L".into(),
            None,
            None,
            false,
            "h".into(),
            22,
            "u".into(),
        );
        let handle = reg.insert(actor);
        {
            let mut a = handle.lock().expect("actor mutex poisoned");
            a.progress.push(ProgressStep {
                phase: ConnectionPhase::SocketConnect,
                status: StepStatus::Success,
                detail: None,
            });
        }
        let snap = reg.snapshot_all();
        assert_eq!(snap[0].progress.len(), 1);
        assert_eq!(snap[0].progress[0].phase, ConnectionPhase::SocketConnect);
    }
}
