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
//! Once an actor reaches `Connected`, [`run_transport_monitor`] is
//! spawned to watch the russh handle and flip the actor back to
//! `Disconnected` if the transport dies *without* an explicit
//! teardown — the sleeping-laptop case, where the socket is dead but
//! nothing called [`disconnect`]. Without it the actor sat
//! `Connected` over a corpse and the next channel open surfaced a raw
//! `channel closed`; the proactive flip lets the UI render the
//! session as dropped (and offer reconnect) on its own.
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
    // Bind the connection id around the auth future so any russh `log`
    // records emitted during the handshake / userauth land in the
    // verbose file log attributed to this session (no-op unless the
    // user enabled the verbose connection log).
    let result = match run_with_pause_aware_timeout(
        std::time::Duration::from_secs(timeout_secs),
        move || {
            app_for_pause.known_hosts_prompts.pending_count() > 0
                || crate::security::credential_prompt::instance().pending_count() > 0
        },
        crate::ssh::verbose_log::scoped(
            id.clone(),
            run_auth_with_credential_prompts(id.clone(), args),
        ),
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
            let monitored_session = {
                let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
                let s = Arc::new(session);
                a.session = Some(s.clone());
                a.state = ConnectionState::Connected;
                s
            };
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
            // Watch the freshly connected transport so a silent death
            // (host sleep, keepalive timeout, peer reset) flips the
            // actor to `Disconnected` proactively — see
            // `run_transport_monitor`.
            tokio::spawn(run_transport_monitor(
                id.clone(),
                handle.clone(),
                Arc::downgrade(&monitored_session),
            ));
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

/// Upper bound on interactive credential re-prompts for one connect
/// attempt — stops a user who keeps mistyping the passphrase from
/// looping forever; after the cap the last `PassphraseIncorrect`
/// propagates as the connect failure.
const MAX_CREDENTIAL_PROMPTS: u8 = 3;

/// Upper bound on how long one connect waits for the user to answer a
/// credential overlay. The connect driver's outer `ssh_timeout_sec`
/// is *suspended* while a `credential_prompt` is pending (so typing
/// time isn't counted as network time), which means this is the only
/// bound on a prompt that is never answered — a headless context with
/// no UI listener degrades to "connect fails after this window"
/// rather than hanging the actor forever.
const CREDENTIAL_PROMPT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(300);

/// Run [`run_auth`], and when it fails because a private-key
/// passphrase is missing or wrong, fire a `CredentialPromptRequest`,
/// await the passphrase the user types into the overlay, stage it,
/// and retry — the interactive passphrase overlay that lets an
/// encrypted-key session whose passphrase was never saved connect
/// without a round-trip through the session editor.
///
/// Only `PassphraseRequired` / `PassphraseIncorrect` on a pubkey auth
/// are recoverable this way; every other failure (wrong password,
/// network, host-key reject) and a user `Cancel` propagate unchanged.
/// The wait is covered by the connect driver's pause-aware timeout
/// (it suspends while `credential_prompt` has a pending request), so
/// the user's typing time is not counted against `ssh_timeout_sec`.
async fn run_auth_with_credential_prompts(
    id: ConnId,
    mut args: ConnectArgs,
) -> Result<Session, Error> {
    use crate::security::credential_prompt::CredentialPromptKind;
    let app = crate::app::instance();
    // The dialog caption keys off the session id; quick-connect has
    // none, so fall back to the connection id for a stable label.
    let session_id = args.session_id.clone().unwrap_or_else(|| id.clone());

    // Password auth with no stored secret → prompt once up front. An
    // empty password just bounces off the server, and a *wrong* typed
    // password comes back as a generic `AuthFailed` with no reliable
    // re-prompt signal (unlike the key passphrase's typed
    // `PassphraseIncorrect`), so this is a single proactive prompt, not
    // a retry loop. A cancel falls through and the as-is attempt
    // surfaces the auth error.
    if let ConnectAuthRef::Password { secret_id } = &args.auth {
        let empty = app
            .secrets
            .get(secret_id)
            .map(|b| b.is_empty())
            .unwrap_or(true);
        if empty {
            if let Some(secret) =
                prompt_credential(&session_id, CredentialPromptKind::Password).await
            {
                app.secrets.put(secret_id, &secret);
            }
        }
    }

    let mut attempts: u8 = 0;
    loop {
        let err = match run_auth(args.clone()).await {
            Ok(session) => return Ok(session),
            Err(e) => e,
        };
        let recoverable = matches!(err, Error::PassphraseRequired | Error::PassphraseIncorrect)
            && matches!(
                args.auth,
                ConnectAuthRef::Pubkey { .. } | ConnectAuthRef::PubkeyCert { .. }
            );
        if !recoverable || attempts >= MAX_CREDENTIAL_PROMPTS {
            return Err(err);
        }
        attempts += 1;
        match prompt_credential(&session_id, CredentialPromptKind::Passphrase).await {
            Some(secret) => {
                // Stage the typed passphrase into the pubkey's
                // passphrase slot (minting a transient id when the row
                // carried no stored passphrase) and retry the dispatch.
                let slot = ensure_passphrase_slot(&mut args.auth);
                app.secrets.put(&slot, &secret);
            }
            // Cancel / timeout / dropped sender end the attempt with
            // the original error.
            None => return Err(err),
        }
    }
}

/// Fire a `CredentialPromptRequest` of `kind` and await the user's
/// answer, bounded by [`CREDENTIAL_PROMPT_TIMEOUT`]. Returns the typed
/// secret bytes on Submit; `None` on Cancel, timeout, or a dropped
/// sender (registry cleared on lock / teardown).
async fn prompt_credential(
    session_id: &str,
    kind: crate::security::credential_prompt::CredentialPromptKind,
) -> Option<Vec<u8>> {
    use crate::security::credential_prompt::{self, CredentialResponse};
    let app = crate::app::instance();
    let prompt_id = crate::id::random_uuid_v4();
    let receiver = credential_prompt::instance().register(prompt_id.clone());
    app.bus.publish(crate::bus::Event::CredentialPromptRequest {
        prompt_id,
        session_id: session_id.to_string(),
        kind_wire_name: kind.wire_name().to_string(),
    });
    match tokio::time::timeout(CREDENTIAL_PROMPT_TIMEOUT, receiver).await {
        Ok(Ok(CredentialResponse::Submit { secret, .. })) => Some(secret),
        _ => None,
    }
}

/// Return the passphrase SecretStore slot for a pubkey auth, minting
/// a fresh transient id when the row carried no stored passphrase.
fn ensure_passphrase_slot(auth: &mut ConnectAuthRef) -> String {
    let slot = match auth {
        ConnectAuthRef::Pubkey {
            passphrase_secret_id,
            ..
        }
        | ConnectAuthRef::PubkeyCert {
            passphrase_secret_id,
            ..
        } => passphrase_secret_id,
        _ => unreachable!("ensure_passphrase_slot called on non-pubkey auth"),
    };
    if slot.is_none() {
        *slot = Some(format!("conn.passphrase.{}", crate::id::random_uuid_v4()));
    }
    slot.clone().expect("passphrase slot set above")
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

    let bastion_session = resolve_bastion_session(bastion_id.as_deref()).await?;

    dispatch_connect(host, port, user, auth, bastion_session).await
}

/// Resolve the ProxyJump bastion's live `Arc<Session>` for a child
/// connect, or `None` when this connect has no bastion.
///
/// Looks up the parent actor and grabs its live session. If the
/// parent is still `Connecting`, waits for it to settle (Connected
/// → proceed; Disconnected → fail the child) up to
/// [`PARENT_READY_TIMEOUT`]. The wait lives Rust-side so the FRB
/// call surfaces the wait + the parent-failed branch in one place
/// rather than splitting it across the Dart connect orchestrator.
async fn resolve_bastion_session(bastion_id: Option<&str>) -> Result<Option<Arc<Session>>, Error> {
    let Some(id) = bastion_id else {
        return Ok(None);
    };
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
    Ok(Some(actor.clone_session().ok_or_else(|| {
        Error::Transport(format!("ProxyJump parent '{id}' has no live session"))
    })?))
}

/// Dispatch the connect to the matching `Session::connect_*` entry
/// point, choosing the bastion (`_via_proxy`) or direct variant
/// based on `bastion_session`.
async fn dispatch_connect(
    host: String,
    port: u16,
    user: String,
    auth: ConnectAuthRef,
    bastion_session: Option<Arc<Session>>,
) -> Result<Session, Error> {
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
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::Sk,
                Session::connect_pubkey_sk_owned(crate::ssh::ConnectPubkeySkOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    credential_id,
                    application,
                    pin_secret_id,
                }),
            )
            .await
        }
        ConnectAuthRef::PubkeySkCert {
            public_openssh,
            credential_id,
            application,
            cert_secret_id,
            pin_secret_id,
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::SkCert,
                Session::connect_pubkey_sk_cert_owned(crate::ssh::ConnectPubkeySkCertOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    credential_id,
                    application,
                    cert_secret_id,
                    pin_secret_id,
                }),
            )
            .await
        }
        ConnectAuthRef::PubkeyPkcs11 {
            public_openssh,
            module_path,
            token_serial,
            cka_id,
            key_type,
            pin_secret_id,
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::Pkcs11,
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
                }),
            )
            .await
        }
        ConnectAuthRef::PubkeyEnclave {
            public_openssh,
            application_tag,
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::Enclave,
                Session::connect_pubkey_enclave_owned(crate::ssh::ConnectPubkeyEnclaveOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    application_tag,
                }),
            )
            .await
        }
        ConnectAuthRef::PubkeyHello {
            public_openssh,
            credential_name,
            key_type,
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::Hello,
                Session::connect_pubkey_hello_owned(crate::ssh::ConnectPubkeyHelloOwnedArgs {
                    host,
                    port,
                    user,
                    public_openssh,
                    credential_name,
                    key_type,
                }),
            )
            .await
        }
        ConnectAuthRef::PubkeyTpm {
            public_openssh,
            provider,
            blob,
            cng_key_name,
            key_type,
            pin_secret_id,
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::Tpm,
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
                }),
            )
            .await
        }
        ConnectAuthRef::PubkeyKeystore {
            public_openssh,
            keystore_alias,
            key_type,
        } => {
            direct_or_reject_hardware(
                bastion_session,
                HardwareSigner::Keystore,
                Session::connect_pubkey_keystore_owned(
                    crate::ssh::ConnectPubkeyKeystoreOwnedArgs {
                        host,
                        port,
                        user,
                        public_openssh,
                        keystore_alias,
                        key_type,
                    },
                ),
            )
            .await
        }
        ConnectAuthRef::Agent => match bastion_session {
            None => Session::connect_agent_owned(host, port, user).await,
            Some(parent) => Session::connect_agent_via_proxy_owned(parent, host, port, user).await,
        },
    }
}

/// Route a hardware-bound signer: run the direct-connect future when
/// there is no bastion, else reject with the signer-specific
/// "ProxyJump unsupported" error. The `direct` future is built eagerly
/// by the caller (constructing an async future runs no code) and is
/// simply dropped unrun on the bastion path.
async fn direct_or_reject_hardware(
    bastion_session: Option<Arc<Session>>,
    signer: HardwareSigner,
    direct: impl std::future::Future<Output = Result<Session, Error>>,
) -> Result<Session, Error> {
    match bastion_session {
        None => direct.await,
        Some(_) => Err(hardware_over_proxyjump_unsupported(signer)),
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
        | Error::AuthFailed(_)
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

/// How often [`run_transport_monitor`] polls a connected actor's
/// russh handle for a silent death. The check is a cheap
/// `is_closed()` (mpsc sender state, no I/O), so a few-second cadence
/// catches a dropped link promptly — within one interval of the OS
/// reporting the dead socket on wake — without measurable overhead.
const TRANSPORT_MONITOR_INTERVAL: std::time::Duration = std::time::Duration::from_secs(3);

/// Watch a connected actor's russh transport and flip it to
/// `Disconnected` the instant the underlying session dies without an
/// explicit teardown — the sleeping-laptop case, where the socket is
/// dead but nothing has called [`disconnect`]. Without this the actor
/// stays `Connected` over a corpse and the next channel open surfaces
/// a raw `channel closed` to the user; the proactive flip lets the UI
/// render the session as dropped (and offer reconnect) on its own.
///
/// Lifecycle is anchored on two facts the monitor captures up front
/// — the exact `Arc<Mutex<ConnectionActor>>` it was spawned for and a
/// `Weak` ref to that connect's session — rather than on the actor's
/// reconnect `generation` (which `run_connect_driver` owns for a
/// different purpose). Each tick the monitor exits unless the registry
/// still maps `id` to *its* handle AND its session Arc is still alive.
/// That covers every teardown shape: manual `disconnect` removes the
/// row (identity check fails); a reconnect that inserts a fresh actor
/// replaces the row (identity check fails); a reconnect that reuses
/// the actor with a new session drops the old session Arc (the `Weak`
/// upgrade fails). So a stale monitor can neither keep a dead
/// transport alive nor clobber a newer connection's state.
async fn run_transport_monitor(
    id: ConnId,
    handle: Arc<Mutex<ConnectionActor>>,
    session: std::sync::Weak<Session>,
) {
    let app = crate::app::instance();
    loop {
        tokio::time::sleep(TRANSPORT_MONITOR_INTERVAL).await;

        // Still the registry's current actor for this id? If the row
        // was removed (disconnect) or replaced (reconnect), this
        // monitor is stale — exit without touching anything.
        match app.connections.get(&id) {
            Some(cur) if Arc::ptr_eq(&cur, &handle) => {}
            _ => return,
        }

        // Transport Arc already gone — nothing left to watch.
        let Some(session) = session.upgrade() else {
            return;
        };
        if !session.is_closed() {
            continue;
        }

        // Dead transport. Flip Connected → Disconnected exactly once
        // and publish the same transition the connect-failure path
        // emits, which the Dart side already renders as a dropped
        // session.
        let flipped = {
            let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
            if a.state == ConnectionState::Connected {
                a.state = ConnectionState::Disconnected;
                a.session = None;
                true
            } else {
                false
            }
        };
        if flipped {
            crate::app_log_warn!(
                "CoreConnect",
                "transport monitor flipped a connection to Disconnected (link died without teardown)"
            );
            app.bus.publish(crate::bus::Event::ConnectionStateChanged {
                id: id.clone(),
                state: ConnectionState::Disconnected,
            });
            publish_active_count(&app);
        }
        return;
    }
}

#[cfg(test)]
mod tests;
