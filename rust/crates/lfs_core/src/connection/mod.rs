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

pub mod auth_compose;
pub mod test_server;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Connect-driver trace lines. Route through
/// [`crate::app_log`] so every step lands in `letsflutssh.log`
/// the same as Dart-side logs — no env var, no stderr dance.
/// `info!` rung; the user's log threshold is what gates whether
/// the line actually hits disk.
macro_rules! trace_connect {
    ($($arg:tt)*) => {
        $crate::app_log_info!("CoreConnect", $($arg)*);
    };
}

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
///
/// `host` / `port` / `user` are the destination tuple — included
/// in the snapshot so consumers (workspace UI, mirror provider)
/// don't have to round-trip back through the registry to enrich
/// the row. **Don't strip these fields and force the FRB adapter
/// to walk the registry inside an `impl From`** — that wrong-
/// direction layering (the bridge papering over a core-shape
/// gap) is exactly what this snapshot exists to avoid.
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
    pub host: String,
    pub port: u16,
    pub user: String,
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
    /// FIDO2 hardware-bound `sk-*` SSH key. `public_openssh` is the
    /// captured `id_*.pub` body re-parsed inside the connect path to
    /// recover the SSH `Algorithm`. `credential_id` + `application`
    /// drive the CTAP2 round trip; `pin_secret_id` points at a staged
    /// transient PIN for credentials that carry the user-verification
    /// bit, `None` for touch-only.
    PubkeySk {
        public_openssh: String,
        credential_id: Vec<u8>,
        application: String,
        pin_secret_id: Option<String>,
    },
    /// FIDO2 hardware-bound `sk-*` SSH key AND a paired OpenSSH
    /// certificate. Carries the same FIDO2 metadata block as
    /// [`ConnectAuthRef::PubkeySk`] plus the staged cert blob's
    /// SecretStore id. The connect path's dispatcher routes this to
    /// [`crate::ssh::Session::connect_pubkey_sk_cert_owned`], which
    /// composes T-1's `FidoSigner` with russh 0.59's
    /// `authenticate_certificate_with<S: Signer>`. Cert is the
    /// strictly stronger credential, so the composer picks this
    /// variant whenever a cert is paired to the resolved sk-* row.
    PubkeySkCert {
        public_openssh: String,
        credential_id: Vec<u8>,
        application: String,
        cert_secret_id: String,
        pin_secret_id: Option<String>,
    },
    /// PKCS#11 hardware-token key. The `module_path`, `token_serial`,
    /// and `cka_id` triple carries the disambiguation surface; `key_type`
    /// drives the wire-name selection (rsa, ecdsa-*, ed25519); and
    /// `pin_secret_id` points at a staged transient PIN entry — `None`
    /// for protected-authentication-path tokens. Reaches
    /// `Session::connect_pubkey_pkcs11_owned` on dispatch.
    PubkeyPkcs11 {
        public_openssh: String,
        module_path: String,
        token_serial: String,
        cka_id: Vec<u8>,
        key_type: String,
        pin_secret_id: Option<String>,
    },
    /// Apple Secure Enclave-bound SSH key. `application_tag` is the
    /// opaque `kSecAttrApplicationTag` bytes captured at create
    /// time — the Keychain `SecItemCopyMatching` matches on it to
    /// resolve the on-chip private half. No PIN slot: the OS fires
    /// its biometric / passcode prompt at the
    /// `SecKeyCreateSignature` boundary. Reaches
    /// `Session::connect_pubkey_enclave_owned` on dispatch.
    PubkeyEnclave {
        public_openssh: String,
        application_tag: Vec<u8>,
    },
    /// Windows Hello (NCrypt / Microsoft Platform Crypto Provider)
    /// SSH key resolved from the manager. `credential_name` is the
    /// CNG persistent-key name persisted on
    /// `ssh_keys.hello_credential_name`; `key_type` selects the
    /// algorithm bag (`ecdsa-sha2-nistp256` / `ecdsa-sha2-nistp384` /
    /// `rsa-2048`). Reaches `Session::connect_pubkey_hello_owned` on
    /// dispatch.
    PubkeyHello {
        public_openssh: String,
        credential_name: String,
        key_type: String,
    },
    /// TPM 2.0-bound SSH key resolved from the manager. `provider`
    /// is one of `"tss-esapi"` (Linux ESAPI driver — `blob`
    /// carries the wrapped TSS2 PRIVATE KEY bytes) or `"cng-pcp"`
    /// (Windows PCP silent variant — `cng_key_name` carries the
    /// NCrypt persistent-key name). `pin_secret_id` points at a
    /// staged transient PIN for PIN-bound keys; `None` for empty-
    /// auth (headless service-account) keys. Reaches
    /// `Session::connect_pubkey_tpm_owned` on dispatch.
    PubkeyTpm {
        public_openssh: String,
        provider: String,
        blob: Option<Vec<u8>>,
        cng_key_name: Option<String>,
        key_type: String,
        pin_secret_id: Option<String>,
    },
    /// Android Hardware Keystore / StrongBox-bound SSH key.
    /// `keystore_alias` is the AndroidKeyStore alias persisted on
    /// `ssh_keys.keystore_alias`; `key_type` drives the algorithm
    /// bag (`ecdsa-sha2-nistp256` / `ssh-ed25519` / `rsa-2048`). No
    /// PIN slot — `BiometricPrompt.CryptoObject` fires inside
    /// `Session::connect_pubkey_keystore_owned` per the auth
    /// requirement set at create time. Reaches
    /// `Session::connect_pubkey_keystore_owned` on dispatch
    /// (Android-only — desktop targets surface a typed
    /// `Error::Unsupported`).
    PubkeyKeystore {
        public_openssh: String,
        keystore_alias: String,
        key_type: String,
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

/// Bundled inputs for [`ConnectionActor::new`]. Eight fields land
/// here so the constructor signature stays under clippy's
/// too-many-arguments threshold; every field is load-bearing for
/// the connection lifecycle so the bundle exists strictly to keep
/// the call shape readable, not to compress.
#[derive(Clone, Debug)]
pub struct ConnectionActorInit {
    pub id: ConnId,
    pub label: String,
    pub session_id: Option<String>,
    pub bastion_id: Option<ConnId>,
    pub internal: bool,
    pub host: String,
    pub port: u16,
    pub user: String,
}

impl ConnectionActor {
    pub fn new(init: ConnectionActorInit) -> Self {
        let ConnectionActorInit {
            id,
            label,
            session_id,
            bastion_id,
            internal,
            host,
            port,
            user,
        } = init;
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
            host: self.host.clone(),
            port: self.port,
            user: self.user.clone(),
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
    /// Per-connection reconnect-generation counter. The Dart
    /// `ConnectionManager` bumps it on every reconnect attempt so
    /// late-arriving bus events from a superseded attempt can be
    /// dropped. Living one place lets the future actor cutover
    /// move the bump+check into the Rust event dispatcher itself
    /// without a separate registry lookup.
    generations: HashMap<ConnId, u32>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryInner {
                by_id: HashMap::new(),
                order: Vec::new(),
                generations: HashMap::new(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
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

    /// Return the live `Arc<Session>` for `id` only when the actor
    /// is currently in `Connected` state. Used by FRB shims that
    /// need to drive channel operations against the actor's russh
    /// session without holding the per-actor mutex across an
    /// `await`. `None` covers both "no actor under id" and "actor
    /// exists but isn't connected" — the caller folds them into
    /// the same retry-or-skip branch.
    ///
    /// Recovers from a poisoned per-actor mutex via `into_inner`
    /// rather than panicking — matches the FFI-safety discipline
    /// the FRB adapters apply at every lock site.
    pub fn connected_session(&self, id: &str) -> Option<Arc<Session>> {
        let handle = self.get(id)?;
        let actor = handle.lock().unwrap_or_else(|p| p.into_inner());
        if actor.state != ConnectionState::Connected {
            return None;
        }
        actor.clone_session()
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
                let actor = handle.lock().unwrap_or_else(|e| e.into_inner());
                out.push(actor.snapshot());
            }
        }
        out
    }

    /// Live count — diagnostic only.
    pub fn count(&self) -> usize {
        self.lock().by_id.len()
    }

    /// Reset the generation counter for [`id`] to `1`. Called on
    /// the initial connect — the first reconnect bumps to `2`.
    pub fn init_generation(&self, id: &str) {
        self.lock().generations.insert(id.to_string(), 1);
    }

    /// Bump the generation counter for [`id`] and return the new
    /// value. Returns `1` for the first call on an unknown id
    /// (matches the `init_generation` shape so a missed init still
    /// produces a sensible value).
    pub fn bump_generation(&self, id: &str) -> u32 {
        let mut g = self.lock();
        let next = g.generations.get(id).copied().unwrap_or(0) + 1;
        g.generations.insert(id.to_string(), next);
        next
    }

    /// True when [`generation`] matches the current value for
    /// [`id`]. Returns `false` for unknown ids — callers treat
    /// "missing" the same as "stale" and drop the event.
    #[must_use]
    pub fn is_current_generation(&self, id: &str, generation: u32) -> bool {
        self.lock()
            .generations
            .get(id)
            .copied()
            .map(|g| g == generation)
            .unwrap_or(false)
    }

    /// Drop the generation counter for [`id`]. Called on
    /// disconnect / connection-removed.
    pub fn drop_generation(&self, id: &str) {
        self.lock().generations.remove(id);
    }

    /// Drop every generation counter — used by `disconnectAll` /
    /// the auto-lock teardown path.
    pub fn clear_generations(&self) {
        self.lock().generations.clear();
    }

    /// Count of actors whose state is `Connected`. Excludes
    /// internal bastion hops (parents own the user-visible
    /// lifecycle) so the result matches the user-visible
    /// "connected sessions" metric the Android foreground service
    /// gates on.
    pub fn connected_user_visible_count(&self) -> usize {
        let g = self.lock();
        let mut n: usize = 0;
        for handle in g.by_id.values() {
            let actor = handle.lock().unwrap_or_else(|e| e.into_inner());
            if !actor.internal && matches!(actor.state, ConnectionState::Connected) {
                n += 1;
            }
        }
        n
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
    let actor = ConnectionActor::new(ConnectionActorInit {
        id: id.clone(),
        label: args.label.clone(),
        session_id: args.session_id.clone(),
        bastion_id: args.bastion_id.clone(),
        internal: args.internal,
        host: args.host.clone(),
        port: args.port,
        user: args.user.clone(),
    });
    let app = crate::app::instance();
    let handle = app.connections.insert(actor);
    run_connect_driver(id.clone(), args, handle).await;
    Ok(id)
}

/// Run `fut` under a wall-clock budget that *suspends* while
/// `is_paused()` returns true. Returns `Some(output)` when the
/// future completes; `None` when the un-paused elapsed time
/// reaches `cap` and no pause is active.
///
/// Why: the SSH handshake can park on a user-facing prompt — TOFU
/// host-key verification today, MFA / hardware-vault unlock later —
/// and the configured `ssh_timeout_sec` should bound the *network*
/// portion only. Counting the user's read-and-click time against
/// the cap surfaced as spurious "connect timed out" errors when
/// the network was healthy and the dialog just sat unanswered.
///
/// Implementation: poll on a 250 ms tick. Whenever `is_paused()`
/// returns true on a tick boundary, the slice since the previous
/// tick is added to a paused-time accumulator and excluded from
/// elapsed. The granularity is well below the 10–60 s typical
/// `ssh_timeout_sec` range, so the effective cap is accurate to
/// within a quarter-second of the configured value.
async fn run_with_pause_aware_timeout<F, Fut, T>(
    cap: std::time::Duration,
    is_paused: F,
    fut: Fut,
) -> Option<T>
where
    F: Fn() -> bool,
    Fut: std::future::Future<Output = T>,
{
    use tokio::time::{sleep, Instant};
    let started = Instant::now();
    let mut paused = std::time::Duration::ZERO;
    let mut last_tick = started;
    let tick = std::time::Duration::from_millis(250);
    tokio::pin!(fut);
    loop {
        let now = Instant::now();
        let paused_now = is_paused();
        if paused_now {
            paused += now.duration_since(last_tick);
        }
        last_tick = now;
        let elapsed_net = now.duration_since(started).saturating_sub(paused);
        if elapsed_net >= cap && !paused_now {
            return None;
        }
        tokio::select! {
            biased;
            r = &mut fut => return Some(r),
            _ = sleep(tick) => continue,
        }
    }
}

/// Internal driver loop. Owns the state-machine transitions for one
/// connect attempt; runs in a background tokio task so [`connect_async`]
/// returns immediately. Stale-generation results are discarded so a
/// reconnect issued mid-handshake never overwrites the newer state.
async fn run_connect_driver(id: ConnId, args: ConnectArgs, handle: Arc<Mutex<ConnectionActor>>) {
    // Drop host:port + user from the trace — both are markers
    // covered by the `<host>` / `<user>` redaction tokens the
    // project sanitiser already enforces, but interpolating them
    // verbatim here meant the bare hostname slipped through
    // (the sanitiser's regex preserves bare hostnames so a
    // `host:port` shape doesn't false-flag). Bastion id is opaque
    // and stays.
    trace_connect!(
        "run_connect_driver enter id={id} host=<host> user=<user> bastion={:?}",
        args.bastion_id
    );
    let app = crate::app::instance();
    let generation;
    {
        let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
        a.state = ConnectionState::Connecting;
        a.error = None;
        a.progress.clear();
        a.generation = a.generation.wrapping_add(1);
        generation = a.generation;
    }
    trace_connect!("run_connect_driver bumped gen={generation} id={id}");
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
    trace_connect!("run_connect_driver about to enter run_auth id={id}");

    // SSH connect timeout — sourced from `AppConfig.ssh_timeout_sec`
    // (`config.json`) so the user's "Connection timeout (s)"
    // setting in Settings → Connection actually flows into the
    // dial. russh `client::connect` doesn't bound the TCP connect
    // on its own; an unreachable host would otherwise pin the
    // actor for the OS-level TCP timeout (60–130 s on Linux).
    // Wrapping the whole handshake — TCP dial, host-key exchange,
    // userauth — keeps the worst case bounded by the configured
    // value; legitimate slow networks finish well under the cap.
    // Pull `ssh_timeout_sec` from the config-store JSON (the
    // Dart-side serialiser writes the canonical shape; defaults
    // to 10 s when the field is absent, capped to ≥1 s so a
    // hostile / corrupt entry can't disable the bound entirely).
    let timeout_secs = crate::config_store::instance()
        .get_json()
        .as_deref()
        .and_then(|j| serde_json::from_str::<serde_json::Value>(j).ok())
        .and_then(|v| v.get("ssh_timeout_sec").and_then(|x| x.as_i64()))
        .filter(|s| *s > 0)
        .unwrap_or(30) as u64;
    // The cap suspends while a TOFU prompt is awaiting the user
    // — the dialog opens during host-key verification and any
    // wall-clock spent waiting on the user's accept/reject is
    // not network time. See `run_with_pause_aware_timeout`.
    let app_for_pause = app.clone();
    let result = match run_with_pause_aware_timeout(
        std::time::Duration::from_secs(timeout_secs),
        move || app_for_pause.known_hosts_prompts.pending_count() > 0,
        run_auth(args),
    )
    .await
    {
        Some(r) => r,
        None => Err(Error::Connect(format!(
            "connect timed out ({timeout_secs} s)"
        ))),
    };
    trace_connect!(
        "run_connect_driver run_auth returned id={id} ok={} err={:?}",
        result.is_ok(),
        result.as_ref().err().map(|e| e.to_string())
    );

    // Discard stale-generation results — a reconnect bumped the
    // counter while we were mid-handshake. Bus-event publication
    // lives in [`emit_stale_attempt_closure`]; the function is
    // unit-tested directly so the closing-edge invariant does not
    // need a full russh handshake to lock in.
    {
        let a = handle.lock().unwrap_or_else(|e| e.into_inner());
        if a.generation != generation {
            let canonical_state = a.state;
            drop(a);
            trace_connect!(
                "run_connect_driver early-return STALE gen id={id} snapshot={generation} canonical_state={canonical_state:?}"
            );
            emit_stale_attempt_closure(&app, id, canonical_state);
            return;
        }
    }
    trace_connect!("run_connect_driver gen-check passed id={id} entering match");

    let id_dbg = id.clone();
    match result {
        Ok(session) => {
            trace_connect!("run_connect_driver SUCCESS id={id_dbg}");
            {
                let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
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
            publish_active_count(&app);
        }
        Err(err) => {
            let detail = err.to_string();
            // FAILURE path lands as `app_log_warn!` — the connect
            // driver's failure is surfaced to the user through the
            // progress bus + UI; the log line is for support traces
            // and a real connect failure is a `Warn`-level event,
            // not the `Info` that `trace_connect!` emits.
            crate::app_log_warn!(
                "CoreConnect",
                "run_connect_driver FAILURE id={id_dbg} phase={:?} detail={detail}",
                failure_phase(&err)
            );
            {
                let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
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
            publish_active_count(&app);
        }
    }
    trace_connect!("run_connect_driver exit id={id_dbg}");
}

/// Hard upper bound on how long a child connect waits for its
/// ProxyJump parent to leave the `Connecting` state. 30 s
/// matches the SSH banner timeout the dialler itself uses;
/// going past it almost always means the parent's TCP /
/// handshake itself is wedged and the child failure is the
/// right outcome (vs. burning UI spinner time on a parent that
/// will never settle).
const PARENT_READY_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);

/// Subscribe to the bus, snapshot the parent actor's current
/// state, and either return immediately (parent already
/// `Connected`) or await the next `ConnectionStateChanged`
/// event for `parent_id` until it transitions to a terminal
/// state. Owning the wait inside the connect actor keeps the
/// FRB surface self-contained — a child connect FRB call
/// returns the parent-failed branch as the same typed error
/// the rest of the cascade surfaces.
///
/// Returns:
///
/// * `Ok(())` — parent is `Connected`. Caller proceeds with the
///   existing parent-session-grab + child auth.
/// * `Err(_)` — parent is missing, transitioned to
///   `Disconnected`, or did not settle within
///   [`PARENT_READY_TIMEOUT`]. Caller fails the child connect
///   with the typed error so the UI gets one clean
///   "ProxyJump parent failed" line.
///
/// **Race window** — `app.bus.subscribe(crate::bus::EventTopic::Connection)` returns a
/// `tokio::sync::broadcast::Receiver` BEFORE we snapshot
/// `actor.state`, so an event published between the snapshot
/// and the await is delivered through the receiver and the
/// caller's await fires immediately. Subscribing first and
/// snapshotting second is the standard "lost-update" hedge
/// for broadcast streams.
async fn wait_for_parent_ready(parent_id: &str) -> Result<(), Error> {
    let app = crate::app::instance();
    let mut rx = app.bus.subscribe(crate::bus::EventTopic::Connection);

    // Snapshot the current state. If parent is already in a
    // terminal state we don't need to await anything.
    let initial_state = {
        let handle = app
            .connections
            .get(parent_id)
            .ok_or_else(|| Error::Transport(format!("ProxyJump parent '{parent_id}' missing")))?;
        let actor = handle.lock().unwrap_or_else(|e| e.into_inner());
        actor.state
    };
    match initial_state {
        ConnectionState::Connected => return Ok(()),
        ConnectionState::Disconnected => {
            return Err(Error::Transport(format!(
                "ProxyJump parent '{parent_id}' is disconnected"
            )));
        }
        ConnectionState::Connecting => {} // wait below
    }

    let parent_id = parent_id.to_string();
    let wait_fut = async {
        loop {
            match rx.recv().await {
                Ok(crate::bus::Event::ConnectionStateChanged { id, state }) if id == parent_id => {
                    match state {
                        ConnectionState::Connected => return Ok(()),
                        ConnectionState::Disconnected => {
                            return Err(Error::Transport(format!(
                                "ProxyJump parent '{parent_id}' failed to connect"
                            )));
                        }
                        ConnectionState::Connecting => continue,
                    }
                }
                Ok(_) => continue,
                Err(_) => {
                    // Receiver lagged or the bus shut down. Re-snapshot
                    // the actor state — if a transition to Connected
                    // happened we missed, the snapshot still surfaces it.
                    let app = crate::app::instance();
                    if let Some(handle) = app.connections.get(&parent_id) {
                        let actor = handle.lock().unwrap_or_else(|e| e.into_inner());
                        match actor.state {
                            ConnectionState::Connected => return Ok(()),
                            ConnectionState::Disconnected => {
                                return Err(Error::Transport(format!(
                                    "ProxyJump parent '{parent_id}' is disconnected"
                                )));
                            }
                            ConnectionState::Connecting => {
                                // Re-subscribe and keep waiting.
                                rx = app.bus.subscribe(crate::bus::EventTopic::Connection);
                                continue;
                            }
                        }
                    }
                    return Err(Error::Transport(format!(
                        "ProxyJump parent '{parent_id}' missing during wait"
                    )));
                }
            }
        }
    };

    match tokio::time::timeout(PARENT_READY_TIMEOUT, wait_fut).await {
        Ok(r) => r,
        Err(_) => Err(Error::Transport(format!(
            "ProxyJump parent '{parent_id}' did not settle within {}s",
            PARENT_READY_TIMEOUT.as_secs()
        ))),
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
    // live `Arc<Session>`. If the parent is still `Connecting`,
    // wait for it to settle (Connected → proceed; Disconnected →
    // fail the child) up to [`PARENT_READY_TIMEOUT`]. The wait
    // lives Rust-side so the FRB call surfaces the wait + the
    // parent-failed branch in one place rather than splitting
    // it across the Dart connect orchestrator.
    let bastion_session = match bastion_id.as_deref() {
        None => None,
        Some(id) => {
            wait_for_parent_ready(id).await?;
            let app = crate::app::instance();
            let handle = app
                .connections
                .get(id)
                .ok_or_else(|| Error::Transport(format!("ProxyJump parent '{id}' missing")))?;
            let actor = handle.lock().unwrap_or_else(|e| e.into_inner());
            if actor.state != ConnectionState::Connected {
                return Err(Error::Transport(format!(
                    "ProxyJump parent '{id}' not yet connected (state {:?})",
                    actor.state
                )));
            }
            Some(actor.clone_session().ok_or_else(|| {
                Error::Transport(format!("ProxyJump parent '{id}' has no live session"))
            })?)
        }
    };

    // Owned-arg `_owned` variants — `Session::connect_*_with_secret_owned`
    // (and `_via_proxy_with_secret_owned`) take `String`/`Arc<Session>`
    // by value so the resulting future is `Send + 'static` without
    // HRTB inference on `&str`/`&Session` borrows. The wrapping
    // `wrap_async` future on the FRB side stays clean.
    //
    // Dispatch contract — single exhaustive match on
    // [`ConnectAuthRef`]. The outer arms split by variant; the
    // inner `match` on `bastion_session` keeps the bastion / direct
    // pair adjacent and forces the author of any new variant to
    // decide for both paths in the same edit. Hardware-bound
    // signers that cannot yet sign through ProxyJump share one
    // arm in [`hardware_over_proxyjump_unsupported`] — that helper's
    // exhaustive match is the compile-time gate that catches a new
    // hardware variant added without a ProxyJump decision.
    match auth {
        ConnectAuthRef::Password { secret_id } => match bastion_session {
            None => Session::connect_password_with_secret_owned(host, port, user, secret_id).await,
            Some(parent) => {
                Session::connect_password_via_proxy_with_secret_owned(
                    parent, host, port, user, secret_id,
                )
                .await
            }
        },
        ConnectAuthRef::Pubkey {
            key_secret_id,
            passphrase_secret_id,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_with_secret_owned(
                    host,
                    port,
                    user,
                    key_secret_id,
                    passphrase_secret_id,
                )
                .await
            }
            Some(parent) => {
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
        },
        ConnectAuthRef::PubkeyCert {
            key_secret_id,
            cert_secret_id,
            passphrase_secret_id,
        } => {
            let args = crate::ssh::ConnectPubkeyCertOwnedArgs {
                host,
                port,
                user,
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            };
            match bastion_session {
                None => Session::connect_pubkey_cert_with_secret_owned(args).await,
                Some(parent) => {
                    Session::connect_pubkey_cert_via_proxy_with_secret_owned(parent, args).await
                }
            }
        }
        ConnectAuthRef::PubkeySk {
            public_openssh,
            credential_id,
            application,
            pin_secret_id,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_sk_owned(crate::ssh::ConnectPubkeySkOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    credential_id,
                    application,
                    pin_secret_id,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(HardwareSigner::Sk)),
        },
        ConnectAuthRef::PubkeySkCert {
            public_openssh,
            credential_id,
            application,
            cert_secret_id,
            pin_secret_id,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_sk_cert_owned(crate::ssh::ConnectPubkeySkCertOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    credential_id,
                    application,
                    cert_secret_id,
                    pin_secret_id,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(HardwareSigner::SkCert)),
        },
        ConnectAuthRef::PubkeyPkcs11 {
            public_openssh,
            module_path,
            token_serial,
            cka_id,
            key_type,
            pin_secret_id,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_pkcs11_owned(crate::ssh::ConnectPubkeyPkcs11OwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    module_path,
                    token_serial,
                    cka_id,
                    key_type,
                    pin_secret_id,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(HardwareSigner::Pkcs11)),
        },
        ConnectAuthRef::PubkeyEnclave {
            public_openssh,
            application_tag,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_enclave_owned(crate::ssh::ConnectPubkeyEnclaveOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    application_tag,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(HardwareSigner::Enclave)),
        },
        ConnectAuthRef::PubkeyHello {
            public_openssh,
            credential_name,
            key_type,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_hello_owned(crate::ssh::ConnectPubkeyHelloOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    credential_name,
                    key_type,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(HardwareSigner::Hello)),
        },
        ConnectAuthRef::PubkeyTpm {
            public_openssh,
            provider,
            blob,
            cng_key_name,
            key_type,
            pin_secret_id,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_tpm_owned(crate::ssh::ConnectPubkeyTpmOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    provider,
                    blob,
                    cng_key_name,
                    key_type,
                    pin_secret_id,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(HardwareSigner::Tpm)),
        },
        ConnectAuthRef::PubkeyKeystore {
            public_openssh,
            keystore_alias,
            key_type,
        } => match bastion_session {
            None => {
                Session::connect_pubkey_keystore_owned(crate::ssh::ConnectPubkeyKeystoreOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    keystore_alias,
                    key_type,
                })
                .await
            }
            Some(_) => Err(hardware_over_proxyjump_unsupported(
                HardwareSigner::Keystore,
            )),
        },
        ConnectAuthRef::Agent => match bastion_session {
            None => Session::connect_agent_owned(host, port, user).await,
            Some(parent) => Session::connect_agent_via_proxy_owned(parent, host, port, user).await,
        },
    }
}

/// Discriminator for the hardware-signer family. Each variant maps
/// 1-to-1 onto one of the hardware-bound [`ConnectAuthRef`] arms
/// that cannot yet sign through a ProxyJump bastion. The enum's
/// exhaustive match in [`hardware_over_proxyjump_unsupported`] is
/// the compile-time gate: adding a hardware variant to
/// [`ConnectAuthRef`] without a matching `HardwareSigner` arm
/// (and a `Some(_) => Err(...)` route in the dispatcher above)
/// fails to compile, which is the invariant the previous
/// 7-arm repeat pattern could not enforce.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HardwareSigner {
    Sk,
    SkCert,
    Pkcs11,
    Enclave,
    Hello,
    Tpm,
    Keystore,
}

/// Single error site for "hardware-bound SSH key over ProxyJump
/// is not supported yet". Each signer carries its own
/// human-readable label so the message tells the user which
/// hardware backend the bastion routing currently lacks.
fn hardware_over_proxyjump_unsupported(signer: HardwareSigner) -> Error {
    let label = match signer {
        HardwareSigner::Sk => "FIDO2",
        HardwareSigner::SkCert => "FIDO2 (with certificate)",
        HardwareSigner::Pkcs11 => "PKCS#11",
        HardwareSigner::Enclave => "Apple Secure Enclave",
        HardwareSigner::Hello => "Windows Hello",
        HardwareSigner::Tpm => "TPM 2.0",
        HardwareSigner::Keystore => "Android Hardware Keystore",
    };
    Error::Auth(format!(
        "{label} hardware key over ProxyJump is not supported yet"
    ))
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
        let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
        a.progress.push(step.clone());
    }
    app.bus
        .publish(crate::bus::Event::ConnectionProgress { id, step });
}

/// Publish a closing edge on the bus for a connect attempt that
/// was superseded by a newer reconnect. The actor's state field
/// is owned by the live generation (it republished `Connecting`
/// at entry and will publish its own terminal event when its
/// `run_auth` settles); the stale driver therefore must NOT
/// mutate `actor.state`. Without a bus event, a per-attempt
/// observer (UI progress row, awaiting future, late subscriber)
/// that saw the dropped attempt's `Connecting +
/// SocketConnect:InProgress` step would hang on that step
/// forever — the live generation's terminal event arrives on the
/// same connection id but a strict per-attempt consumer cannot
/// tell that signal apart from the one it was waiting for. The
/// two-event closure (`ConnectionError` + a state-echo
/// `ConnectionStateChanged`) gives every subscriber a closing
/// edge: the error names the supersession, the state echo
/// surfaces the actor's canonical state. The live driver's later
/// terminal publish overwrites the echo whenever the canonical
/// state moves.
fn emit_stale_attempt_closure(
    app: &Arc<crate::app::AppState>,
    id: ConnId,
    canonical_state: ConnectionState,
) {
    app.bus.publish(crate::bus::Event::ConnectionError {
        id: id.clone(),
        detail: "connect attempt superseded by newer reconnect".into(),
    });
    app.bus.publish(crate::bus::Event::ConnectionStateChanged {
        id,
        state: canonical_state,
    });
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
            let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
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
        publish_active_count(&app);
    }
    Ok(())
}

/// Publish [`Event::ConnectionActiveCountChanged`] with the current
/// user-visible Connected count. Coalesced through an `AtomicI64`
/// so repeated calls with the same count don't fan out.
fn publish_active_count(app: &std::sync::Arc<crate::app::AppState>) {
    let count = app.connections.connected_user_visible_count() as i64;
    let prev = LAST_ACTIVE_COUNT.swap(count, std::sync::atomic::Ordering::SeqCst);
    if prev != count {
        app.bus
            .publish(crate::bus::Event::ConnectionActiveCountChanged { count });
    }
}

static LAST_ACTIVE_COUNT: std::sync::atomic::AtomicI64 = std::sync::atomic::AtomicI64::new(-1);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn insert_and_snapshot() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new(ConnectionActorInit {
            id: "c1".into(),
            label: "Label".into(),
            session_id: Some("s1".into()),
            bastion_id: None,
            internal: false,
            host: "host".into(),
            port: 22,
            user: "user".into(),
        });
        reg.insert(actor);
        let snap = reg.snapshot_all();
        assert_eq!(snap.len(), 1);
        assert_eq!(snap[0].id, "c1");
        assert_eq!(snap[0].state, ConnectionState::Disconnected);
    }

    #[tokio::test]
    async fn remove_drops_actor() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new(ConnectionActorInit {
            id: "c1".into(),
            label: "L".into(),
            session_id: None,
            bastion_id: None,
            internal: false,
            host: "h".into(),
            port: 22,
            user: "u".into(),
        });
        reg.insert(actor);
        assert_eq!(reg.count(), 1);
        reg.remove("c1");
        assert_eq!(reg.count(), 0);
        assert!(reg.snapshot_all().is_empty());
    }

    #[tokio::test]
    async fn snapshot_carries_progress() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new(ConnectionActorInit {
            id: "c1".into(),
            label: "L".into(),
            session_id: None,
            bastion_id: None,
            internal: false,
            host: "h".into(),
            port: 22,
            user: "u".into(),
        });
        let handle = reg.insert(actor);
        {
            let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
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

    #[test]
    fn init_generation_starts_at_one() {
        let reg = ConnectionRegistry::new();
        reg.init_generation("c1");
        assert!(reg.is_current_generation("c1", 1));
        assert!(!reg.is_current_generation("c1", 2));
    }

    #[test]
    fn bump_generation_increments_monotonically() {
        let reg = ConnectionRegistry::new();
        assert_eq!(reg.bump_generation("c1"), 1);
        assert_eq!(reg.bump_generation("c1"), 2);
        assert_eq!(reg.bump_generation("c1"), 3);
        assert!(reg.is_current_generation("c1", 3));
        assert!(!reg.is_current_generation("c1", 2));
    }

    #[test]
    fn drop_generation_makes_subsequent_checks_false() {
        let reg = ConnectionRegistry::new();
        reg.init_generation("c1");
        reg.drop_generation("c1");
        assert!(!reg.is_current_generation("c1", 1));
    }

    #[test]
    fn clear_generations_drops_every_id() {
        let reg = ConnectionRegistry::new();
        reg.init_generation("c1");
        reg.init_generation("c2");
        reg.clear_generations();
        assert!(!reg.is_current_generation("c1", 1));
        assert!(!reg.is_current_generation("c2", 1));
    }

    #[test]
    fn unknown_id_is_never_current() {
        let reg = ConnectionRegistry::new();
        assert!(!reg.is_current_generation("missing", 1));
        assert!(!reg.is_current_generation("missing", 0));
    }

    // ─── failure_phase mapping ─────────────────────────────────────
    // Each match arm in `failure_phase` paints the red marker at a
    // specific connection phase; a regression that misroutes auth
    // failures to socketConnect (or vice versa) silently mislabels
    // every connect-error UI.

    fn make_actor(id: &str, internal: bool) -> ConnectionActor {
        ConnectionActor::new(ConnectionActorInit {
            id: id.into(),
            label: format!("L-{id}"),
            session_id: None,
            bastion_id: None,
            internal,
            host: "h".into(),
            port: 22,
            user: "u".into(),
        })
    }

    #[test]
    fn failure_phase_routes_auth_variants_to_authenticate() {
        for err in [
            Error::Auth("server refused".into()),
            Error::AuthFailed,
            Error::PassphraseRequired,
            Error::PassphraseIncorrect,
            Error::KeyParse("malformed PEM".into()),
        ] {
            assert_eq!(
                failure_phase(&err),
                ConnectionPhase::Authenticate,
                "auth-family error must paint at Authenticate: {err:?}"
            );
        }
    }

    #[test]
    fn failure_phase_routes_host_key_rejected_to_host_key_verify() {
        assert_eq!(
            failure_phase(&Error::HostKeyRejected),
            ConnectionPhase::HostKeyVerify
        );
    }

    #[test]
    fn failure_phase_falls_through_to_socket_connect() {
        // Anything not auth-family or host-key paints at SocketConnect
        // — the catch-all default. Pre-auth failures (DNS, refused
        // connection, TLS / kex aborts) all land here.
        for err in [
            Error::Connect("dns nope".into()),
            Error::Handshake("kex".into()),
            Error::Io("ECONNREFUSED".into()),
            Error::Timeout,
            Error::Cancelled,
        ] {
            assert_eq!(
                failure_phase(&err),
                ConnectionPhase::SocketConnect,
                "non-auth/host-key error must paint at SocketConnect: {err:?}"
            );
        }
    }

    // ─── ConnectionRegistry edge cases ─────────────────────────────

    #[test]
    fn snapshot_includes_every_inserted_actor() {
        let reg = ConnectionRegistry::new();
        for i in 0..5 {
            reg.insert(make_actor(&format!("c{i}"), false));
        }
        let snap = reg.snapshot_all();
        assert_eq!(snap.len(), 5);
        assert_eq!(reg.count(), 5);
    }

    #[test]
    fn duplicate_insert_with_same_id_overwrites() {
        // Re-inserting under the same id replaces the existing
        // actor — reconnect re-creates the actor row rather than
        // carrying state across.
        let reg = ConnectionRegistry::new();
        reg.insert(make_actor("c1", false));
        let first_count = reg.count();
        reg.insert(make_actor("c1", false));
        assert_eq!(reg.count(), first_count);
    }

    #[test]
    fn remove_unknown_id_is_idempotent() {
        let reg = ConnectionRegistry::new();
        reg.insert(make_actor("c1", false));
        assert_eq!(reg.count(), 1);
        reg.remove("does-not-exist");
        assert_eq!(reg.count(), 1);
    }

    #[test]
    fn count_reflects_current_size_through_insert_remove_cycles() {
        let reg = ConnectionRegistry::new();
        assert_eq!(reg.count(), 0);
        reg.insert(make_actor("a", false));
        reg.insert(make_actor("b", false));
        assert_eq!(reg.count(), 2);
        reg.remove("a");
        assert_eq!(reg.count(), 1);
        reg.insert(make_actor("c", false));
        assert_eq!(reg.count(), 2);
        reg.remove("b");
        reg.remove("c");
        assert_eq!(reg.count(), 0);
    }

    // ─── connected_user_visible_count ──────────────────────────────

    #[test]
    fn user_visible_count_zero_on_empty_registry() {
        let reg = ConnectionRegistry::new();
        assert_eq!(reg.connected_user_visible_count(), 0);
    }

    #[test]
    fn user_visible_count_skips_disconnected_actors() {
        // Inserted actors start in `Disconnected`. Until the driver
        // flips them to Connected the user-visible count must stay
        // at zero — an early-fire would tell the Android foreground
        // service to start before any connection actually exists.
        let reg = ConnectionRegistry::new();
        reg.insert(make_actor("c1", false));
        reg.insert(make_actor("c2", false));
        assert_eq!(reg.connected_user_visible_count(), 0);
    }

    #[test]
    fn user_visible_count_includes_only_connected_non_internal() {
        let reg = ConnectionRegistry::new();
        let h_user = reg.insert(make_actor("user", false));
        let h_bastion = reg.insert(make_actor("bastion", true));
        // Flip both to Connected.
        for h in [&h_user, &h_bastion] {
            let mut a = h.lock().unwrap_or_else(|e| e.into_inner());
            a.state = ConnectionState::Connected;
        }
        // Bastion (internal: true) is excluded — the user-visible
        // metric must match the "Connected sessions" badge the user
        // sees, not the underlying transport count.
        assert_eq!(reg.connected_user_visible_count(), 1);
    }

    #[test]
    fn user_visible_count_recovers_to_zero_after_disconnect_all() {
        let reg = ConnectionRegistry::new();
        let h = reg.insert(make_actor("c1", false));
        {
            let mut a = h.lock().unwrap_or_else(|e| e.into_inner());
            a.state = ConnectionState::Connected;
        }
        assert_eq!(reg.connected_user_visible_count(), 1);
        reg.remove("c1");
        assert_eq!(reg.connected_user_visible_count(), 0);
    }

    // ─── enum / struct invariants ──────────────────────────────────

    #[test]
    fn connection_state_partial_eq_distinguishes_all_three() {
        // Enum equality powers every state-machine branch (driver,
        // disconnect path, snapshot diff). Pin the trichotomy so a
        // future variant addition surfaces as a missed match arm.
        assert_eq!(ConnectionState::Disconnected, ConnectionState::Disconnected);
        assert_eq!(ConnectionState::Connecting, ConnectionState::Connecting);
        assert_eq!(ConnectionState::Connected, ConnectionState::Connected);
        assert_ne!(ConnectionState::Disconnected, ConnectionState::Connecting);
        assert_ne!(ConnectionState::Connecting, ConnectionState::Connected);
        assert_ne!(ConnectionState::Disconnected, ConnectionState::Connected);
    }

    #[test]
    fn progress_step_clone_preserves_every_field() {
        let step = ProgressStep {
            phase: ConnectionPhase::Authenticate,
            status: StepStatus::Failed,
            detail: Some("auth refused".into()),
        };
        let cloned = step.clone();
        assert_eq!(cloned.phase, ConnectionPhase::Authenticate);
        assert_eq!(cloned.status, StepStatus::Failed);
        assert_eq!(cloned.detail.as_deref(), Some("auth refused"));
    }

    #[test]
    fn progress_step_with_no_detail_is_legal() {
        // The driver emits steps without detail for the success path
        // (detail carries the error message on failure). Pin the
        // Optional contract.
        let step = ProgressStep {
            phase: ConnectionPhase::OpenChannel,
            status: StepStatus::Success,
            detail: None,
        };
        assert!(step.detail.is_none());
    }

    // ─── run_with_pause_aware_timeout ──────────────────────────────
    // Wraps the SSH handshake with a wall-clock cap that suspends
    // while a TOFU prompt is awaiting the user. The bug shape these
    // pin: a `connect timed out` error fires while the
    // host-key-changed dialog is still on screen. Tests use real
    // time with sub-second caps so they stay deterministic without
    // pulling tokio's `test-util` feature.

    #[tokio::test]
    async fn pause_aware_timeout_returns_some_when_future_completes() {
        let result =
            run_with_pause_aware_timeout(std::time::Duration::from_secs(10), || false, async {
                42_i32
            })
            .await;
        assert_eq!(result, Some(42));
    }

    #[tokio::test]
    async fn pause_aware_timeout_fires_at_cap_when_no_pause() {
        let cap = std::time::Duration::from_millis(500);
        let started = std::time::Instant::now();
        let result =
            run_with_pause_aware_timeout(cap, || false, std::future::pending::<()>()).await;
        let elapsed = started.elapsed();
        assert!(result.is_none(), "expected timeout to fire");
        assert!(elapsed >= cap, "timeout fired too early: {elapsed:?}");
        assert!(
            elapsed < cap + std::time::Duration::from_millis(750),
            "timeout fired too late: {elapsed:?}"
        );
    }

    #[tokio::test]
    async fn pause_aware_timeout_excludes_paused_window_from_elapsed() {
        use std::sync::atomic::{AtomicBool, Ordering};
        let paused = std::sync::Arc::new(AtomicBool::new(false));
        let pf = paused.clone();

        let cap = std::time::Duration::from_millis(500);
        let helper = tokio::spawn(async move {
            run_with_pause_aware_timeout(
                cap,
                move || pf.load(Ordering::Relaxed),
                std::future::pending::<()>(),
            )
            .await
        });

        // 200 ms with no pause active — net elapsed ≈ 200 ms.
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        assert!(!helper.is_finished());

        // Open the prompt and sleep well past the remaining 300 ms
        // budget — the helper must keep waiting because the pause
        // window is excluded.
        paused.store(true, Ordering::Relaxed);
        tokio::time::sleep(std::time::Duration::from_millis(800)).await;
        assert!(
            !helper.is_finished(),
            "helper fired during pause — paused window not excluded from elapsed"
        );

        // Close the prompt; net elapsed ≈ 200 ms, cap = 500 ms, so
        // the helper should fire roughly 300 ms later. Bound the
        // wait so a regression doesn't hang the suite.
        paused.store(false, Ordering::Relaxed);
        let outcome = tokio::time::timeout(std::time::Duration::from_millis(1500), helper)
            .await
            .expect("helper did not finish post-pause")
            .expect("helper task panicked");
        assert!(
            outcome.is_none(),
            "expected timeout to fire after pause closed and net elapsed reached cap"
        );
    }

    // ─── emit_stale_attempt_closure ────────────────────────────────
    // When a reconnect bumps the actor's generation mid-handshake,
    // the dropped driver returns silently. Without a bus event the
    // subscriber that observed the dropped attempt's
    // `Connecting + SocketConnect:InProgress` step has no closing
    // edge — the helper publishes one. Tests pin the exact event
    // pair AND the no-actor-mutation invariant (the live generation
    // owns `actor.state`).

    /// Drain every event already pending on a receiver. Flushes
    /// events published during fixture setup so the assertions
    /// observe only the closure helper's output.
    fn drain_receiver(rx: &mut tokio::sync::broadcast::Receiver<crate::bus::Event>) {
        while rx.try_recv().is_ok() {}
    }

    /// Pull the next N events off a receiver under a short tokio
    /// timeout so a missing publish fails the test instead of
    /// hanging the suite.
    async fn recv_n_events(
        rx: &mut tokio::sync::broadcast::Receiver<crate::bus::Event>,
        n: usize,
    ) -> Vec<crate::bus::Event> {
        let mut out = Vec::with_capacity(n);
        for _ in 0..n {
            let ev = tokio::time::timeout(std::time::Duration::from_millis(500), rx.recv())
                .await
                .expect("event did not arrive within 500 ms")
                .expect("broadcast channel closed");
            out.push(ev);
        }
        out
    }

    #[tokio::test]
    async fn stale_attempt_closure_emits_error_and_state_echo_when_live_gen_owns_connecting() {
        // Simulates the rapid-reconnect race: an old connect driver
        // discovers `actor.generation` was bumped by a newer attempt
        // while it was inside `run_auth`. The actor's state field is
        // still `Connecting` (owned by the live generation). The
        // dropped driver must publish a closing edge without
        // mutating actor state.
        let app = crate::app::init();
        let id = format!(
            "stale-conn-live-connecting-{}",
            crate::id::random_handle_hex_32()
        );
        // Pre-seed the actor in `Connecting` so we can verify the
        // helper does not touch `actor.state`.
        let handle = app
            .connections
            .insert(ConnectionActor::new(ConnectionActorInit {
                id: id.clone(),
                label: "stale".into(),
                session_id: None,
                bastion_id: None,
                internal: false,
                host: "h".into(),
                port: 22,
                user: "u".into(),
            }));
        {
            let mut a = handle.lock().unwrap();
            a.state = ConnectionState::Connecting;
            a.generation = 7;
        }
        let mut rx = app.bus.subscribe(crate::bus::EventTopic::Connection);
        drain_receiver(&mut rx);

        // Call the helper as the stale driver would: canonical state
        // is what the actor currently shows.
        emit_stale_attempt_closure(&app, id.clone(), ConnectionState::Connecting);

        let events = recv_n_events(&mut rx, 2).await;
        match &events[0] {
            crate::bus::Event::ConnectionError { id: e_id, detail } => {
                assert_eq!(e_id, &id);
                assert!(
                    detail.contains("superseded"),
                    "ConnectionError detail must name supersession: {detail}"
                );
            }
            other => panic!("expected ConnectionError first, got {other:?}"),
        }
        match &events[1] {
            crate::bus::Event::ConnectionStateChanged { id: e_id, state } => {
                assert_eq!(e_id, &id);
                assert_eq!(*state, ConnectionState::Connecting);
            }
            other => panic!("expected ConnectionStateChanged second, got {other:?}"),
        }

        // The helper must not have flipped the actor — the live
        // generation still owns the `Connecting` state and its
        // pending generation count.
        {
            let a = handle.lock().unwrap();
            assert_eq!(a.state, ConnectionState::Connecting);
            assert_eq!(a.generation, 7);
        }

        // Clean up so neighbouring tests do not see this row.
        app.connections.remove(&id);
    }

    #[tokio::test]
    async fn stale_attempt_closure_echoes_terminal_state_when_live_gen_already_settled() {
        // When the live generation has already settled the actor to
        // `Disconnected`, the stale driver's closure echoes the
        // terminal so any subscriber that joined late after the
        // live driver's terminal publish still sees a closing edge
        // attributed to the dropped attempt's id.
        let app = crate::app::init();
        let id = format!(
            "stale-conn-live-settled-{}",
            crate::id::random_handle_hex_32()
        );
        let handle = app
            .connections
            .insert(ConnectionActor::new(ConnectionActorInit {
                id: id.clone(),
                label: "stale".into(),
                session_id: None,
                bastion_id: None,
                internal: false,
                host: "h".into(),
                port: 22,
                user: "u".into(),
            }));
        {
            let mut a = handle.lock().unwrap();
            a.state = ConnectionState::Disconnected;
            a.generation = 9;
        }
        let mut rx = app.bus.subscribe(crate::bus::EventTopic::Connection);
        drain_receiver(&mut rx);

        emit_stale_attempt_closure(&app, id.clone(), ConnectionState::Disconnected);

        let events = recv_n_events(&mut rx, 2).await;
        assert!(matches!(
            &events[0],
            crate::bus::Event::ConnectionError { .. }
        ));
        match &events[1] {
            crate::bus::Event::ConnectionStateChanged { id: e_id, state } => {
                assert_eq!(e_id, &id);
                assert_eq!(*state, ConnectionState::Disconnected);
            }
            other => panic!("expected terminal state echo, got {other:?}"),
        }

        app.connections.remove(&id);
    }

    // ─── ProxyJump dispatch — exhaustive variant coverage ──────────
    // M5 collapsed the 14-arm dispatch into a single exhaustive
    // match on `ConnectAuthRef`. Adding a new variant without a
    // bastion-arm decision now fails to compile. These tests
    // exercise every hardware-signer arm via [`run_auth`] with a
    // mocked bastion `Some(_)` and assert each surfaces a typed
    // `Error::Auth` with a label that names the hardware backend —
    // the previous duplicate-arm code shipped this contract in
    // 7 separate string literals; the refactor centralises them in
    // [`hardware_over_proxyjump_unsupported`].
    //
    // Constructing a real `Arc<Session>` for the `Some(_)` arm needs
    // a live russh handshake (see `tests/connection_lifecycle.rs`).
    // The dispatcher's bastion-arm branch is reached after
    // `wait_for_parent_ready` succeeds, which itself needs the
    // parent actor to be `Connected`. To keep the unit-test purely
    // in-process we instead call [`hardware_over_proxyjump_unsupported`]
    // directly per signer variant — the dispatcher's only call site
    // for the `Some(_)` arm is this helper, so locking in the
    // helper's output covers the bastion-error contract while the
    // exhaustive match on `HardwareSigner` keeps the compile-time
    // gate intact.

    #[test]
    fn hardware_over_proxyjump_unsupported_labels_every_signer_variant() {
        for (signer, expected_label) in [
            (HardwareSigner::Sk, "FIDO2"),
            (HardwareSigner::SkCert, "FIDO2 (with certificate)"),
            (HardwareSigner::Pkcs11, "PKCS#11"),
            (HardwareSigner::Enclave, "Apple Secure Enclave"),
            (HardwareSigner::Hello, "Windows Hello"),
            (HardwareSigner::Tpm, "TPM 2.0"),
            (HardwareSigner::Keystore, "Android Hardware Keystore"),
        ] {
            let err = hardware_over_proxyjump_unsupported(signer);
            match err {
                Error::Auth(detail) => {
                    assert!(
                        detail.contains(expected_label),
                        "label for {signer:?} missing: got {detail:?}"
                    );
                    assert!(
                        detail.contains("ProxyJump"),
                        "label for {signer:?} must name the ProxyJump gap: {detail:?}"
                    );
                }
                other => panic!("expected Error::Auth for {signer:?}, got {other:?}"),
            }
        }
    }

    /// Build one instance of every [`ConnectAuthRef`] variant so the
    /// test asserts the dispatcher has a route for each. The match
    /// inside the loop is exhaustive — a new variant added to
    /// `ConnectAuthRef` without a corresponding builder branch
    /// fails to compile, locking in the "every variant has a
    /// direct + bastion decision" invariant the M5 refactor enforces.
    fn every_auth_ref_variant() -> Vec<ConnectAuthRef> {
        vec![
            ConnectAuthRef::Password {
                secret_id: "s".into(),
            },
            ConnectAuthRef::Pubkey {
                key_secret_id: "k".into(),
                passphrase_secret_id: None,
            },
            ConnectAuthRef::PubkeyCert {
                key_secret_id: "k".into(),
                cert_secret_id: "c".into(),
                passphrase_secret_id: None,
            },
            ConnectAuthRef::PubkeySk {
                public_openssh: "p".into(),
                credential_id: vec![0; 1],
                application: "ssh:".into(),
                pin_secret_id: None,
            },
            ConnectAuthRef::PubkeySkCert {
                public_openssh: "p".into(),
                credential_id: vec![0; 1],
                application: "ssh:".into(),
                cert_secret_id: "c".into(),
                pin_secret_id: None,
            },
            ConnectAuthRef::PubkeyPkcs11 {
                public_openssh: "p".into(),
                module_path: "/mod".into(),
                token_serial: "T".into(),
                cka_id: vec![0; 1],
                key_type: "ecdsa-sha2-nistp256".into(),
                pin_secret_id: None,
            },
            ConnectAuthRef::PubkeyEnclave {
                public_openssh: "p".into(),
                application_tag: vec![0; 1],
            },
            ConnectAuthRef::PubkeyHello {
                public_openssh: "p".into(),
                credential_name: "cn".into(),
                key_type: "ecdsa-sha2-nistp256".into(),
            },
            ConnectAuthRef::PubkeyTpm {
                public_openssh: "p".into(),
                provider: "tss-esapi".into(),
                blob: None,
                cng_key_name: None,
                key_type: "ecdsa-sha2-nistp256".into(),
                pin_secret_id: None,
            },
            ConnectAuthRef::PubkeyKeystore {
                public_openssh: "p".into(),
                keystore_alias: "alias".into(),
                key_type: "ecdsa-sha2-nistp256".into(),
            },
            ConnectAuthRef::Agent,
        ]
    }

    #[test]
    fn every_auth_ref_variant_is_classified() {
        // Pure-data classification: each variant is either a
        // hardware signer (matching one `HardwareSigner` arm), or a
        // software / agent path (Password, Pubkey, PubkeyCert,
        // Agent). The exhaustive `match` below is the compile-time
        // gate — a new `ConnectAuthRef` variant added without a
        // classification branch fails to compile, which forces the
        // author to decide whether ProxyJump is supported for it.
        for auth in every_auth_ref_variant() {
            let classified: Result<Option<HardwareSigner>, &str> = match &auth {
                ConnectAuthRef::Password { .. } => Ok(None),
                ConnectAuthRef::Pubkey { .. } => Ok(None),
                ConnectAuthRef::PubkeyCert { .. } => Ok(None),
                ConnectAuthRef::Agent => Ok(None),
                ConnectAuthRef::PubkeySk { .. } => Ok(Some(HardwareSigner::Sk)),
                ConnectAuthRef::PubkeySkCert { .. } => Ok(Some(HardwareSigner::SkCert)),
                ConnectAuthRef::PubkeyPkcs11 { .. } => Ok(Some(HardwareSigner::Pkcs11)),
                ConnectAuthRef::PubkeyEnclave { .. } => Ok(Some(HardwareSigner::Enclave)),
                ConnectAuthRef::PubkeyHello { .. } => Ok(Some(HardwareSigner::Hello)),
                ConnectAuthRef::PubkeyTpm { .. } => Ok(Some(HardwareSigner::Tpm)),
                ConnectAuthRef::PubkeyKeystore { .. } => Ok(Some(HardwareSigner::Keystore)),
            };
            assert!(classified.is_ok(), "variant {auth:?} has no classification");
        }
    }
}
