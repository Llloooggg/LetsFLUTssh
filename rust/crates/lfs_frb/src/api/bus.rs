//! FRB adapter for `lfs_core::bus` — typed Command / Event bus
//! that turns Dart into a thin renderer subscribed to Rust state.
//! New variants extend the enums in lockstep with the actor
//! moves.

use crate::frb_generated::StreamSink;

/// Topic tag the Dart subscriber picks. The FRB-visible mirror of
/// `lfs_core::bus::EventTopic` — bumped in lockstep when new
/// domains are added.
#[derive(Debug, Clone, Copy)]
pub enum BusTopic {
    Diagnostics,
    Connection,
    PortForward,
    Transfer,
    Recorder,
    AutoLock,
    Import,
    Update,
    KnownHosts,
    Sessions,
    Config,
    Tier,
    SecurityPrompt,
    SecurityCapabilities,
}

impl From<BusTopic> for lfs_core::bus::EventTopic {
    fn from(t: BusTopic) -> Self {
        match t {
            BusTopic::Diagnostics => lfs_core::bus::EventTopic::Diagnostics,
            BusTopic::Connection => lfs_core::bus::EventTopic::Connection,
            BusTopic::PortForward => lfs_core::bus::EventTopic::PortForward,
            BusTopic::Transfer => lfs_core::bus::EventTopic::Transfer,
            BusTopic::Recorder => lfs_core::bus::EventTopic::Recorder,
            BusTopic::AutoLock => lfs_core::bus::EventTopic::AutoLock,
            BusTopic::Import => lfs_core::bus::EventTopic::Import,
            BusTopic::Update => lfs_core::bus::EventTopic::Update,
            BusTopic::KnownHosts => lfs_core::bus::EventTopic::KnownHosts,
            BusTopic::Sessions => lfs_core::bus::EventTopic::Sessions,
            BusTopic::Config => lfs_core::bus::EventTopic::Config,
            BusTopic::Tier => lfs_core::bus::EventTopic::Tier,
            BusTopic::SecurityPrompt => lfs_core::bus::EventTopic::SecurityPrompt,
            BusTopic::SecurityCapabilities => lfs_core::bus::EventTopic::SecurityCapabilities,
        }
    }
}

/// Connection lifecycle state — FRB mirror of
/// `lfs_core::connection::ConnectionState`.
#[derive(Debug, Clone, Copy)]
pub enum BusConnectionState {
    Disconnected,
    Connecting,
    Connected,
}

impl From<lfs_core::connection::ConnectionState> for BusConnectionState {
    fn from(s: lfs_core::connection::ConnectionState) -> Self {
        match s {
            lfs_core::connection::ConnectionState::Disconnected => BusConnectionState::Disconnected,
            lfs_core::connection::ConnectionState::Connecting => BusConnectionState::Connecting,
            lfs_core::connection::ConnectionState::Connected => BusConnectionState::Connected,
        }
    }
}

/// Connection progress phase — FRB mirror of
/// `lfs_core::connection::ConnectionPhase`.
#[derive(Debug, Clone, Copy)]
pub enum BusConnectionPhase {
    SocketConnect,
    HostKeyVerify,
    Authenticate,
    OpenChannel,
}

impl From<lfs_core::connection::ConnectionPhase> for BusConnectionPhase {
    fn from(p: lfs_core::connection::ConnectionPhase) -> Self {
        match p {
            lfs_core::connection::ConnectionPhase::SocketConnect => {
                BusConnectionPhase::SocketConnect
            }
            lfs_core::connection::ConnectionPhase::HostKeyVerify => {
                BusConnectionPhase::HostKeyVerify
            }
            lfs_core::connection::ConnectionPhase::Authenticate => BusConnectionPhase::Authenticate,
            lfs_core::connection::ConnectionPhase::OpenChannel => BusConnectionPhase::OpenChannel,
        }
    }
}

/// Step status — FRB mirror of `lfs_core::connection::StepStatus`.
#[derive(Debug, Clone, Copy)]
pub enum BusStepStatus {
    InProgress,
    Success,
    Failed,
}

impl From<lfs_core::connection::StepStatus> for BusStepStatus {
    fn from(s: lfs_core::connection::StepStatus) -> Self {
        match s {
            lfs_core::connection::StepStatus::InProgress => BusStepStatus::InProgress,
            lfs_core::connection::StepStatus::Success => BusStepStatus::Success,
            lfs_core::connection::StepStatus::Failed => BusStepStatus::Failed,
        }
    }
}

/// Connection progress step — FRB mirror of
/// `lfs_core::connection::ProgressStep`.
#[derive(Debug, Clone)]
pub struct BusProgressStep {
    pub phase: BusConnectionPhase,
    pub status: BusStepStatus,
    pub detail: Option<String>,
}

impl From<lfs_core::connection::ProgressStep> for BusProgressStep {
    fn from(s: lfs_core::connection::ProgressStep) -> Self {
        BusProgressStep {
            phase: s.phase.into(),
            status: s.status.into(),
            detail: s.detail,
        }
    }
}

/// State change envelope delivered to subscribers. Mirrors
/// `lfs_core::bus::Event` — variants accrete as actor lifts land.
#[derive(Debug, Clone)]
pub enum BusEvent {
    /// Smoke event. Foundation plumbing test only — no domain
    /// state behind it.
    Echoed { payload: String },
    /// Connection state machine transitioned.
    ConnectionStateChanged {
        id: String,
        state: BusConnectionState,
    },
    /// Per-step progress fan-out during connect / reconnect.
    ConnectionProgress { id: String, step: BusProgressStep },
    /// Connect-time error recorded against an actor.
    ConnectionError { id: String, detail: String },
    /// Actor removed from the registry (manual disconnect or
    /// parent of a disconnected bastion chain).
    ConnectionRemoved { id: String },
    /// User-visible Connected count changed. Excludes internal
    /// bastion hops. Foreground-service binding consumes this to
    /// gate the Android persistent-notification service.
    ConnectionActiveCountChanged { count: i64 },

    /// Auto-lock — fired when the idle timer expires, the app
    /// backgrounds with a non-zero timeout, or the user explicitly
    /// requests a lock.
    AutoLockLocked,
    /// Auto-lock — fired after the Dart unlock dialog supplies
    /// a fresh key + reopens the DB.
    AutoLockUnlocked,
    /// Auto-lock — fired when the configured idle timeout
    /// changes. Carries the new value in minutes (0 = off).
    AutoLockTimeoutChanged { minutes: i64 },

    /// Recorder — recording actor entered the registry.
    RecorderStarted { id: String, path: String },
    /// Recorder — recording actor left the registry.
    RecorderStopped { id: String },
    /// Recorder — chunk written; carries running byte total.
    RecorderBytesWritten { id: String, total_bytes: u64 },
    /// Recorder — running total crossed the per-file cap; the
    /// Dart shim subscribes, prepares a fresh path, and fires
    /// `recorder_queue_enqueue_rotate` to roll the recording over.
    RecorderRotateRequested { id: String, bytes_written: u64 },

    /// Transfer queue — task entered the queue.
    TransferTaskAdded { id: String },
    /// Transfer queue — task transitioned to a new state.
    TransferTaskState { id: String, state: BusTaskState },
    /// Transfer queue — bytes-done counter advanced.
    TransferTaskProgress {
        id: String,
        bytes_done: u64,
        bytes_total: u64,
    },
    /// Transfer queue — terminal failure on a task.
    TransferTaskError { id: String, detail: String },

    /// Port forward — rule actor entered the registry.
    PortForwardRegistered { id: String },
    /// Port forward — rule status transitioned.
    PortForwardStatus {
        id: String,
        status: BusRuleStatus,
        detail: Option<String>,
    },
    /// Port forward — rule actor left the registry.
    PortForwardRemoved { id: String },

    /// Auto-update — bytes-written tick during a streaming
    /// download. `total_bytes` is `None` when the server did not
    /// declare a `Content-Length`.
    UpdateDownloadProgress {
        url: String,
        written_bytes: u64,
        total_bytes: Option<u64>,
    },
    /// Auto-update — HTTP done; verifying SHA + signed manifest.
    UpdateVerifyingStarted { url: String },
    /// Auto-update — verification passed; asset is on disk at
    /// `path` ready for the install step.
    UpdateDownloadCompleted { url: String, path: String },
    /// Known-hosts table mutated.
    KnownHostsChanged,
    /// Sessions / folders tables mutated.
    SessionsChanged,
    /// `config.json` save landed — carries the freshly-written
    /// JSON so subscribers swap in the canonical state without
    /// a follow-up `config_store_get_json` round-trip.
    ConfigChanged { json: String },
    /// Tier state machine transitioned. `state_wire_name` is
    /// `locked` / `unlocking` / `unlocked` / `wiping`.
    TierStateChanged { state_wire_name: String },
    /// Connection actor needs a password / passphrase for the
    /// saved session — Dart subscriber renders the dialog,
    /// dispatches the response command back. `kind_wire_name`
    /// is `password` or `passphrase`.
    CredentialPromptRequest {
        prompt_id: String,
        session_id: String,
        kind_wire_name: String,
    },
    /// Capabilities orchestrator needs the OS-keychain
    /// reachability answer. Dart subscriber pings the platform
    /// keychain and dispatches the `KeyringProbeResult` wire
    /// name (`"available"` / `"linuxNoSecretService"` /
    /// `"probeFailed"`).
    KeychainProbePromptRequest { prompt_id: String },
    /// Capabilities orchestrator needs the hardware-vault
    /// probe code on Apple / Android / Windows. Dart
    /// subscriber calls
    /// `MethodChannel('com.letsflutssh/hardware_vault')
    /// .invokeMethod('probeDetail')` and dispatches the
    /// platform reason code verbatim.
    HardwareVaultProbePromptRequest { prompt_id: String },
    /// L3 tier-unlock orchestrator needs the hardware vault
    /// to unseal the DB key. Dart subscriber calls
    /// `HardwareTierVault.read(pin)` which fans out to
    /// `tpm2-tools` on Linux or the platform method channel
    /// elsewhere; resolves with the unsealed bytes / wrong-
    /// PIN signal / plugin error via the
    /// `hardware_vault_unlock_prompt_resolve*` shims. `pin`
    /// is `None` for the passwordless variant.
    HardwareVaultUnlockPromptRequest {
        prompt_id: String,
        pin: Option<String>,
    },
    /// Hardware-vault seal — fired by the L3 first-launch
    /// orchestrator. Dart subscriber takes the staged bytes via
    /// `secrets_take(db_key_secret_id)` and (when present)
    /// `secrets_take(pin_secret_id)`, wraps them via
    /// `HardwareTierVault.store(dbKey: bytes, pin: pin)`;
    /// resolves via `hardware_vault_seal_prompt_resolve*` shims.
    /// `pin_secret_id` is `None` for the passwordless variant.
    /// The plaintext DB key + PIN never enter the broadcast channel
    /// or cross the FRB boundary inline — only opaque ids do.
    HardwareVaultSealPromptRequest {
        prompt_id: String,
        db_key_secret_id: String,
        pin_secret_id: Option<String>,
    },
    /// Security capabilities cache snapshot updated. `json` is
    /// the freshly-cached snapshot in the `lfs_core::security::
    /// capabilities` snake_case JSON shape; an empty string
    /// signals an explicit `clear` (Dart subscriber flips back
    /// to the neutral "probing…" state).
    SecurityCapabilitiesChanged { json: String },
    /// TOFU prompt — russh saw an unknown / changed host key.
    /// Subscribers (Dart UI) surface the host-key dialog and
    /// dispatch [`BusCommand::KnownHostPromptResponse`] back.
    KnownHostPromptRequest {
        prompt_id: String,
        host: String,
        port: i64,
        key_type: String,
        fingerprint: String,
        kind: BusKnownHostPromptKind,
    },
    /// TOFU prompt resolved — fired after the dispatcher wakes the
    /// awaiting handler. Diagnostic only (the matching handler
    /// already woke); UI may use it to dismiss any lingering toast.
    KnownHostPromptResolved { prompt_id: String, accepted: bool },
}

/// FRB mirror of `lfs_core::bus::KnownHostPromptKind`.
#[derive(Debug, Clone, Copy)]
pub enum BusKnownHostPromptKind {
    NewHost,
    KeyChanged,
}

impl From<lfs_core::bus::KnownHostPromptKind> for BusKnownHostPromptKind {
    fn from(k: lfs_core::bus::KnownHostPromptKind) -> Self {
        match k {
            lfs_core::bus::KnownHostPromptKind::NewHost => BusKnownHostPromptKind::NewHost,
            lfs_core::bus::KnownHostPromptKind::KeyChanged => BusKnownHostPromptKind::KeyChanged,
        }
    }
}

/// Rule status — FRB mirror of `lfs_core::portforward::RuleStatus`.
#[derive(Debug, Clone, Copy)]
pub enum BusRuleStatus {
    Idle,
    Listening,
    Error,
}

impl From<lfs_core::portforward::RuleStatus> for BusRuleStatus {
    fn from(s: lfs_core::portforward::RuleStatus) -> Self {
        match s {
            lfs_core::portforward::RuleStatus::Idle => BusRuleStatus::Idle,
            lfs_core::portforward::RuleStatus::Listening => BusRuleStatus::Listening,
            lfs_core::portforward::RuleStatus::Error => BusRuleStatus::Error,
        }
    }
}

/// Task state — FRB mirror of `lfs_core::transfer::TaskState`.
#[derive(Debug, Clone, Copy)]
pub enum BusTaskState {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl From<lfs_core::transfer::TaskState> for BusTaskState {
    fn from(s: lfs_core::transfer::TaskState) -> Self {
        match s {
            lfs_core::transfer::TaskState::Queued => BusTaskState::Queued,
            lfs_core::transfer::TaskState::Running => BusTaskState::Running,
            lfs_core::transfer::TaskState::Completed => BusTaskState::Completed,
            lfs_core::transfer::TaskState::Failed => BusTaskState::Failed,
            lfs_core::transfer::TaskState::Cancelled => BusTaskState::Cancelled,
        }
    }
}

impl BusEvent {
    fn from_core(e: lfs_core::bus::Event) -> Self {
        match e {
            lfs_core::bus::Event::Echoed { payload } => BusEvent::Echoed { payload },
            lfs_core::bus::Event::ConnectionStateChanged { id, state } => {
                BusEvent::ConnectionStateChanged {
                    id,
                    state: state.into(),
                }
            }
            lfs_core::bus::Event::ConnectionProgress { id, step } => BusEvent::ConnectionProgress {
                id,
                step: step.into(),
            },
            lfs_core::bus::Event::ConnectionError { id, detail } => {
                BusEvent::ConnectionError { id, detail }
            }
            lfs_core::bus::Event::ConnectionRemoved { id } => BusEvent::ConnectionRemoved { id },
            lfs_core::bus::Event::ConnectionActiveCountChanged { count } => {
                BusEvent::ConnectionActiveCountChanged { count }
            }
            lfs_core::bus::Event::AutoLockLocked => BusEvent::AutoLockLocked,
            lfs_core::bus::Event::AutoLockUnlocked => BusEvent::AutoLockUnlocked,
            lfs_core::bus::Event::AutoLockTimeoutChanged { minutes } => {
                BusEvent::AutoLockTimeoutChanged { minutes }
            }
            lfs_core::bus::Event::RecorderStarted { id, path } => {
                BusEvent::RecorderStarted { id, path }
            }
            lfs_core::bus::Event::RecorderStopped { id } => BusEvent::RecorderStopped { id },
            lfs_core::bus::Event::RecorderBytesWritten { id, total_bytes } => {
                BusEvent::RecorderBytesWritten { id, total_bytes }
            }
            lfs_core::bus::Event::RecorderRotateRequested { id, bytes_written } => {
                BusEvent::RecorderRotateRequested { id, bytes_written }
            }
            lfs_core::bus::Event::TransferTaskAdded { id } => BusEvent::TransferTaskAdded { id },
            lfs_core::bus::Event::TransferTaskState { id, state } => BusEvent::TransferTaskState {
                id,
                state: state.into(),
            },
            lfs_core::bus::Event::TransferTaskProgress {
                id,
                bytes_done,
                bytes_total,
            } => BusEvent::TransferTaskProgress {
                id,
                bytes_done,
                bytes_total,
            },
            lfs_core::bus::Event::TransferTaskError { id, detail } => {
                BusEvent::TransferTaskError { id, detail }
            }
            lfs_core::bus::Event::PortForwardRegistered { id } => {
                BusEvent::PortForwardRegistered { id }
            }
            lfs_core::bus::Event::PortForwardStatus { id, status, detail } => {
                BusEvent::PortForwardStatus {
                    id,
                    status: status.into(),
                    detail,
                }
            }
            lfs_core::bus::Event::PortForwardRemoved { id } => BusEvent::PortForwardRemoved { id },
            lfs_core::bus::Event::UpdateDownloadProgress {
                url,
                written_bytes,
                total_bytes,
            } => BusEvent::UpdateDownloadProgress {
                url,
                written_bytes,
                total_bytes,
            },
            lfs_core::bus::Event::UpdateVerifyingStarted { url } => {
                BusEvent::UpdateVerifyingStarted { url }
            }
            lfs_core::bus::Event::UpdateDownloadCompleted { url, path } => {
                BusEvent::UpdateDownloadCompleted { url, path }
            }
            lfs_core::bus::Event::KnownHostsChanged => BusEvent::KnownHostsChanged,
            lfs_core::bus::Event::SessionsChanged => BusEvent::SessionsChanged,
            lfs_core::bus::Event::ConfigChanged { json } => BusEvent::ConfigChanged { json },
            lfs_core::bus::Event::TierStateChanged { state_wire_name } => {
                BusEvent::TierStateChanged { state_wire_name }
            }
            lfs_core::bus::Event::CredentialPromptRequest {
                prompt_id,
                session_id,
                kind_wire_name,
            } => BusEvent::CredentialPromptRequest {
                prompt_id,
                session_id,
                kind_wire_name,
            },
            lfs_core::bus::Event::KeychainProbePromptRequest { prompt_id } => {
                BusEvent::KeychainProbePromptRequest { prompt_id }
            }
            lfs_core::bus::Event::HardwareVaultProbePromptRequest { prompt_id } => {
                BusEvent::HardwareVaultProbePromptRequest { prompt_id }
            }
            lfs_core::bus::Event::HardwareVaultUnlockPromptRequest { prompt_id, pin } => {
                BusEvent::HardwareVaultUnlockPromptRequest { prompt_id, pin }
            }
            lfs_core::bus::Event::HardwareVaultSealPromptRequest {
                prompt_id,
                db_key_secret_id,
                pin_secret_id,
            } => BusEvent::HardwareVaultSealPromptRequest {
                prompt_id,
                db_key_secret_id,
                pin_secret_id,
            },
            lfs_core::bus::Event::SecurityCapabilitiesChanged { json } => {
                BusEvent::SecurityCapabilitiesChanged { json }
            }
            lfs_core::bus::Event::KnownHostPromptRequest {
                prompt_id,
                host,
                port,
                key_type,
                fingerprint,
                kind,
            } => BusEvent::KnownHostPromptRequest {
                prompt_id,
                host,
                port,
                key_type,
                fingerprint,
                kind: kind.into(),
            },
            lfs_core::bus::Event::KnownHostPromptResolved {
                prompt_id,
                accepted,
            } => BusEvent::KnownHostPromptResolved {
                prompt_id,
                accepted,
            },
        }
    }
}

/// Auth method reference — FRB mirror of
/// `lfs_core::connection::ConnectAuthRef`. Carries SecretStore ids,
/// not bytes.
#[derive(Debug, Clone)]
pub enum BusConnectAuthRef {
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

impl From<BusConnectAuthRef> for lfs_core::connection::ConnectAuthRef {
    fn from(a: BusConnectAuthRef) -> Self {
        match a {
            BusConnectAuthRef::Password { secret_id } => {
                lfs_core::connection::ConnectAuthRef::Password { secret_id }
            }
            BusConnectAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } => lfs_core::connection::ConnectAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            },
            BusConnectAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            } => lfs_core::connection::ConnectAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            },
            BusConnectAuthRef::Agent => lfs_core::connection::ConnectAuthRef::Agent,
        }
    }
}

/// Inputs to a connect command — FRB mirror of
/// `lfs_core::connection::ConnectArgs`.
#[derive(Debug, Clone)]
pub struct BusConnectArgs {
    pub label: String,
    pub session_id: Option<String>,
    pub host: String,
    pub port: u16,
    pub user: String,
    pub auth: BusConnectAuthRef,
    pub bastion_id: Option<String>,
    pub internal: bool,
}

impl From<BusConnectArgs> for lfs_core::connection::ConnectArgs {
    fn from(a: BusConnectArgs) -> Self {
        lfs_core::connection::ConnectArgs {
            label: a.label,
            session_id: a.session_id,
            host: a.host,
            port: a.port,
            user: a.user,
            auth: a.auth.into(),
            bastion_id: a.bastion_id,
            internal: a.internal,
        }
    }
}

/// Operation envelope dispatched by the Dart side. Mirrors
/// `lfs_core::bus::Command`.
///
/// `ConnectAsync` is **not** a bus command — connect is a request /
/// response shape (Dart awaits a Result, not just side-effect
/// events). It lives at [`connection_connect`] alongside its
/// dedicated FRB entry.
#[derive(Debug, Clone)]
pub enum BusCommand {
    /// Smoke command — emits `Echoed` with the same payload.
    NoopEcho { payload: String },
    /// Remove an actor from the registry. Idempotent on a
    /// missing id.
    ConnectionDisconnect { id: String },
    /// Tear down every active connection actor.
    ConnectionDisconnectAll,

    /// Auto-lock — pointer activity ping.
    AutoLockOnPointerActivity,
    /// Auto-lock — lifecycle change.
    AutoLockOnLifecycleChange { background: bool },
    /// Auto-lock — set the idle timeout in minutes (0 = off).
    AutoLockSetTimeout { minutes: i64 },
    /// Auto-lock — explicit lock request.
    AutoLockRequestLock,
    /// Auto-lock — unlock signal from the Dart-side dialog.
    AutoLockUnlock,
    /// TOFU prompt response — Dart UI's host-key dialog resolved.
    /// Wakes the russh handler that fired the matching request.
    KnownHostPromptResponse { prompt_id: String, accepted: bool },
}

impl From<BusCommand> for lfs_core::bus::Command {
    fn from(c: BusCommand) -> Self {
        match c {
            BusCommand::NoopEcho { payload } => lfs_core::bus::Command::NoopEcho { payload },
            BusCommand::ConnectionDisconnect { id } => {
                lfs_core::bus::Command::ConnectionDisconnect { id }
            }
            BusCommand::ConnectionDisconnectAll => lfs_core::bus::Command::ConnectionDisconnectAll,
            BusCommand::AutoLockOnPointerActivity => {
                lfs_core::bus::Command::AutoLockOnPointerActivity
            }
            BusCommand::AutoLockOnLifecycleChange { background } => {
                lfs_core::bus::Command::AutoLockOnLifecycleChange { background }
            }
            BusCommand::AutoLockSetTimeout { minutes } => {
                lfs_core::bus::Command::AutoLockSetTimeout { minutes }
            }
            BusCommand::AutoLockRequestLock => lfs_core::bus::Command::AutoLockRequestLock,
            BusCommand::AutoLockUnlock => lfs_core::bus::Command::AutoLockUnlock,
            BusCommand::KnownHostPromptResponse {
                prompt_id,
                accepted,
            } => lfs_core::bus::Command::KnownHostPromptResponse {
                prompt_id,
                accepted,
            },
        }
    }
}

/// Direct connect entry point. Bypasses the bus because connect is
/// a request/response operation: the Dart caller awaits the result
/// to learn whether the actor reached `Connected`. Lifecycle events
/// (`ConnectionStateChanged`, `ConnectionProgress`) still fan out
/// over the bus for any subscribed view.
///
/// The driver inside `lfs_core::connection` dispatches onto the
/// `connect_*_with_secret_owned` family so the entire future chain
/// (`wrap_async → connect_async → Session::connect_*_with_secret_owned`)
/// keeps an unambiguous `Send + 'static` shape — no `&str` HRTB
/// auto-trait propagation between the layers.
pub async fn connection_connect(id: String, args: BusConnectArgs) -> Result<(), String> {
    lfs_core::connection::connect_async(id, args.into())
        .await
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Pull the live `SshSession` handle off a connected actor. Returns
/// `Ok(None)` when the actor is missing or hasn't reached the
/// `Connected` state yet — the caller can subscribe to
/// `ConnectionStateChanged` events to learn when to retry. The
/// returned wrapper shares the underlying `Arc<Session>` with the
/// actor so channel ops (`open_shell`, `open_sftp`, …) drive the
/// same russh session the actor parked on `Connected`. Callers
/// must NOT call `disconnect()` on the returned wrapper — that
/// would only clear the wrapper's own slot, leaving the actor's
/// session live but no longer reachable through this handle.
/// Tear-down belongs to the actor (`bus_dispatch(ConnectionDisconnect)`).
pub async fn connection_get_session(
    id: String,
) -> Result<Option<crate::api::ssh::SshSession>, String> {
    Ok(lfs_core::app::instance()
        .connections
        .connected_session(&id)
        .map(crate::api::ssh::SshSession::from_arc))
}

/// Dispatch a typed command. Single entry point Dart calls for
/// every operation; the Rust side routes by command variant.
pub async fn bus_dispatch(command: BusCommand) -> Result<(), String> {
    let core = lfs_core::bus::Command::from(command);
    lfs_core::bus::dispatch(core)
        .await
        .map_err(|e| e.to_string())
}

/// Subscribe to events filtered by [`BusTopic`]. Yields the matching
/// events to the Dart `StreamSink` until the sink rejects an
/// `add` (Dart side cancelled the subscription).
///
/// Drop semantics: when the Dart subscription is cancelled, the
/// returned future returns from `sink.add` with `Err`, the loop
/// exits, the `broadcast::Receiver` drops, and the broker
/// auto-detaches. No explicit unsubscribe is needed.
pub async fn bus_subscribe(topic: BusTopic, sink: StreamSink<BusEvent>) -> Result<(), String> {
    let app = lfs_core::app::instance();
    let mut rx = app.bus.subscribe();
    let want_topic: lfs_core::bus::EventTopic = topic.into();
    loop {
        match rx.recv().await {
            Ok(event) => {
                if event.topic() != want_topic {
                    continue;
                }
                if sink.add(BusEvent::from_core(event)).is_err() {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                // Subscriber fell behind; drop intermediate events
                // (the bus is a notification surface, not a queue —
                // see `lfs_core::bus` doc) and keep listening so
                // the next event still arrives.
                continue;
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                break;
            }
        }
    }
    Ok(())
}
