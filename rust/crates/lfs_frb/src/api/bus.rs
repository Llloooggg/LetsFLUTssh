//! FRB adapter for `lfs_core::bus`. Phase 5.0 surface — typed
//! Command / Event bus that turns Dart into a thin renderer
//! subscribed to Rust state. Sub-phases extend the enum variants in
//! lockstep with the actor moves.

use crate::frb_generated::StreamSink;

/// Topic tag the Dart subscriber picks. The FRB-visible mirror of
/// `lfs_core::bus::EventTopic` — bumped in lockstep when sub-phases
/// add new domains.
#[derive(Debug, Clone, Copy)]
pub enum BusTopic {
    Diagnostics,
    Connection,
    PortForward,
    Transfer,
    Recorder,
    AutoLock,
    Import,
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
/// `lfs_core::bus::Event` — variants accrete as Phase 5 sub-phases
/// land.
#[derive(Debug, Clone)]
pub enum BusEvent {
    /// 5.0 smoke event. Foundation plumbing test only — no domain
    /// state behind it.
    Echoed { payload: String },
    /// 5.1 — connection state machine transitioned.
    ConnectionStateChanged {
        id: String,
        state: BusConnectionState,
    },
    /// 5.1 — per-step progress fan-out during connect / reconnect.
    ConnectionProgress { id: String, step: BusProgressStep },
    /// 5.1 — connect-time error recorded against an actor.
    ConnectionError { id: String, detail: String },
    /// 5.1 — actor removed from the registry (manual disconnect or
    /// parent of a disconnected bastion chain).
    ConnectionRemoved { id: String },
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
        }
    }
}

/// Operation envelope dispatched by the Dart side. Mirrors
/// `lfs_core::bus::Command`.
#[derive(Debug, Clone)]
pub enum BusCommand {
    /// 5.0 smoke command — emits `Echoed` with the same payload.
    NoopEcho { payload: String },
    /// 5.1 — remove an actor from the registry. Idempotent on a
    /// missing id.
    ConnectionDisconnect { id: String },
}

impl From<BusCommand> for lfs_core::bus::Command {
    fn from(c: BusCommand) -> Self {
        match c {
            BusCommand::NoopEcho { payload } => lfs_core::bus::Command::NoopEcho { payload },
            BusCommand::ConnectionDisconnect { id } => {
                lfs_core::bus::Command::ConnectionDisconnect { id }
            }
        }
    }
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
