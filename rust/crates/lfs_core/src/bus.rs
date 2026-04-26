//! Typed Command / Event bus — Phase 5 foundation.
//!
//! Frontend dispatches `Command`s (operation envelopes); domain
//! actors mutate state and publish `Event`s onto the bus broker.
//! Subscribers receive an `Event` stream filtered by topic, so a
//! per-screen view picks up only the events that affect it.
//!
//! The 5.0 surface defines just the scaffolding: a `NoopEcho`
//! command + an `Echoed` event used as smoke test for the FRB
//! plumbing. Sub-phases 5.1+ extend the enums in lockstep with the
//! actor moves (`Connection*`, `PortForward*`, `Transfer*`, ...).
//!
//! # Design choices
//!
//! - `tokio::sync::broadcast` for the broker: multi-subscriber
//!   fan-out, drops the slowest receiver on overflow rather than
//!   stalling the publisher. Capacity is generous (256) since
//!   most domains emit at most a handful of events per user
//!   action; the recorder / transfer paths post per-frame /
//!   per-chunk events but those have their own coalescing inside
//!   the actor before reaching the bus.
//! - Subscribers receive a *clone* of every event (the broadcast
//!   channel handles that). Filtering happens in the subscriber
//!   loop — cheap per-event topic match keeps the hot path
//!   lock-free.
//! - Drop-on-overflow is intentional: the bus is a notification
//!   surface, not a queue. Authoritative state lives in the
//!   actors; if a subscriber lags badly enough to lose events it
//!   re-syncs through a snapshot command rather than replaying.

use tokio::sync::broadcast;

use crate::error::Error;

/// Generous capacity. Domain actors emit a handful of events per
/// user action; per-frame / per-chunk traffic coalesces inside the
/// actor before reaching the bus.
const EVENT_CHANNEL_CAPACITY: usize = 256;

/// Topic tag attached to every event. Subscribers filter by the
/// topic they care about; a per-screen view typically subscribes
/// to one or two topics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventTopic {
    /// Smoke / debug events — Phase 5.0 echo, future bus self-tests.
    Diagnostics,
    /// Connection lifecycle (Phase 5.1).
    Connection,
    /// Port forward rule status (Phase 5.2).
    PortForward,
    /// Transfer queue task progress (Phase 5.3).
    Transfer,
    /// Recorder lifecycle (Phase 5.4).
    Recorder,
    /// Auto-lock state machine (Phase 5.5).
    AutoLock,
    /// `.lfs` import handle progress (Phase 5.6).
    Import,
}

/// State change envelope published onto the bus. Variants accrete
/// as Phase 5 sub-phases land.
#[derive(Debug, Clone)]
pub enum Event {
    /// Foundation smoke event. `bus_dispatch(NoopEcho)` publishes
    /// this with the same payload so the FRB plumbing can be
    /// verified end-to-end before any real domain command lands.
    Echoed { payload: String },

    /// 5.1 connection lifecycle — emitted whenever an actor
    /// transitions between `Disconnected / Connecting / Connected`.
    /// Subscribers re-snapshot their connection-level views off
    /// this signal; the snapshot itself is fetched via a separate
    /// `ConnectionSnapshot` command (cheap copy of the actor's
    /// plain-data view).
    ConnectionStateChanged {
        id: crate::connection::ConnId,
        state: crate::connection::ConnectionState,
    },

    /// 5.1 connection lifecycle — fan-out per progress step
    /// (`socketConnect / hostKeyVerify / authenticate / openChannel`
    /// at `inProgress / success / failed`). The Dart-era
    /// `Connection.progressStream` retires in favour of subscribing
    /// here and filtering by id.
    ConnectionProgress {
        id: crate::connection::ConnId,
        step: crate::connection::ProgressStep,
    },

    /// 5.1 connection lifecycle — emitted when an actor records a
    /// fresh connect-time error. Detail is the localised /
    /// sanitised message; subscribers pair this with the matching
    /// `ConnectionStateChanged(Disconnected)` for UI feedback.
    ConnectionError {
        id: crate::connection::ConnId,
        detail: String,
    },

    /// 5.1 connection lifecycle — emitted when an actor is
    /// removed from the registry (manual disconnect, parent of a
    /// disconnected bastion chain).
    ConnectionRemoved { id: crate::connection::ConnId },

    /// 5.5 auto-lock — fired when the idle timer expires, when
    /// the app backgrounds with a non-zero timeout, or when the
    /// user explicitly requests a lock. The payload is empty —
    /// subscribers re-fetch any state they need from the
    /// machine snapshot or the DB.
    AutoLockLocked,
    /// 5.5 auto-lock — fired after the Dart unlock dialog
    /// supplies a fresh key + reopens the DB.
    AutoLockUnlocked,
    /// 5.5 auto-lock — fired when the configured idle timeout
    /// changes. Carries the new value in minutes (0 = off).
    AutoLockTimeoutChanged { minutes: i64 },

    /// 5.4 recorder — fired when a fresh recording actor enters
    /// the registry.
    RecorderStarted { id: String, path: String },
    /// 5.4 recorder — fired when an actor leaves the registry
    /// (close / shutdown / file rotation).
    RecorderStopped { id: String },
    /// 5.4 recorder — fired after the frame-write driver records
    /// a chunk of bytes. Carries the running total so subscribers
    /// can render progress without polling.
    RecorderBytesWritten { id: String, total_bytes: u64 },

    /// 5.3 transfer queue — task entered the queue.
    TransferTaskAdded { id: String },
    /// 5.3 transfer queue — task transitioned to a new state.
    TransferTaskState {
        id: String,
        state: crate::transfer::TaskState,
    },
    /// 5.3 transfer queue — bytes-done counter advanced.
    TransferTaskProgress {
        id: String,
        bytes_done: u64,
        bytes_total: u64,
    },
    /// 5.3 transfer queue — terminal failure on a task.
    TransferTaskError { id: String, detail: String },

    /// 5.2 port forward — rule actor entered the registry.
    PortForwardRegistered { id: String },
    /// 5.2 port forward — rule status transitioned.
    PortForwardStatus {
        id: String,
        status: crate::portforward::RuleStatus,
        detail: Option<String>,
    },
    /// 5.2 port forward — rule actor left the registry.
    PortForwardRemoved { id: String },
}

impl Event {
    pub fn topic(&self) -> EventTopic {
        match self {
            Event::Echoed { .. } => EventTopic::Diagnostics,
            Event::ConnectionStateChanged { .. }
            | Event::ConnectionProgress { .. }
            | Event::ConnectionError { .. }
            | Event::ConnectionRemoved { .. } => EventTopic::Connection,
            Event::AutoLockLocked
            | Event::AutoLockUnlocked
            | Event::AutoLockTimeoutChanged { .. } => EventTopic::AutoLock,
            Event::RecorderStarted { .. }
            | Event::RecorderStopped { .. }
            | Event::RecorderBytesWritten { .. } => EventTopic::Recorder,
            Event::TransferTaskAdded { .. }
            | Event::TransferTaskState { .. }
            | Event::TransferTaskProgress { .. }
            | Event::TransferTaskError { .. } => EventTopic::Transfer,
            Event::PortForwardRegistered { .. }
            | Event::PortForwardStatus { .. }
            | Event::PortForwardRemoved { .. } => EventTopic::PortForward,
        }
    }
}

/// Operation envelope dispatched by the frontend. Sub-phases
/// extend this enum with concrete domain commands.
#[derive(Debug, Clone)]
pub enum Command {
    /// Foundation smoke command — emits `Event::Echoed` with the
    /// same payload. No state mutation; use only for FRB plumbing
    /// tests.
    NoopEcho { payload: String },

    /// 5.1 — remove an actor from the registry. Idempotent on a
    /// missing id. Drops the held russh handle (which sends
    /// `SSH_MSG_DISCONNECT` on Drop) before clearing the row.
    ConnectionDisconnect { id: crate::connection::ConnId },

    /// 5.5 auto-lock — pointer activity ping. Resets the idle
    /// timer; the Dart side fires this once per significant
    /// pointer event so the lock doesn't trip mid-typing.
    AutoLockOnPointerActivity,
    /// 5.5 auto-lock — lifecycle change. `background = true` is
    /// the Dart-era `paused / inactive / hidden` umbrella;
    /// `background = false` is `resumed`.
    AutoLockOnLifecycleChange { background: bool },
    /// 5.5 auto-lock — configure the idle timeout in minutes
    /// (0 disables the timer). Mirrors the Settings → Auto-lock
    /// preset list.
    AutoLockSetTimeout { minutes: i64 },
    /// 5.5 auto-lock — explicit lock request (Settings →
    /// "Lock now", deeplink, etc).
    AutoLockRequestLock,
    /// 5.5 auto-lock — unlock signal from the Dart-side unlock
    /// dialog. The dialog has already supplied the master key +
    /// reopened the DB; the machine just resets its activity
    /// clock and emits the matching event.
    AutoLockUnlock,
}

/// Broadcast-backed event broker. Owned by `AppState` (process
/// singleton); domain actors hold references and call `publish`,
/// FRB subscribers call `subscribe` to get a fresh `Receiver`.
pub struct EventBus {
    sender: broadcast::Sender<Event>,
}

impl EventBus {
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        Self { sender }
    }

    /// Publish an event. Returns `Ok(receiver_count)` so callers
    /// that care can log "no subscribers" cases; the most common
    /// shape is fire-and-forget.
    pub fn publish(&self, event: Event) -> usize {
        // `broadcast::send` returns Err only when there are no
        // subscribers — that's not an error condition for a
        // notification bus, the event simply has no listener and
        // evaporates.
        self.sender.send(event).unwrap_or(0)
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.sender.subscribe()
    }

    /// Live receiver count. Diagnostic only — callers MUST NOT gate
    /// publish on subscriber presence (a late subscriber would
    /// then miss the bootstrap event).
    pub fn subscriber_count(&self) -> usize {
        self.sender.receiver_count()
    }
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new()
    }
}

/// Dispatch a typed command. Domain handlers route by command
/// variant. Sub-phases extend the match arms in lockstep with each
/// actor move.
///
/// Async because 5.1+ command handlers touch tokio mutexes
/// (registry lookups, per-actor locks). Synchronous-leaf commands
/// like `NoopEcho` keep the same await shape so the FRB caller
/// never has to branch.
pub async fn dispatch(cmd: Command) -> Result<(), Error> {
    let app = crate::app::instance();
    match cmd {
        Command::NoopEcho { payload } => {
            app.bus.publish(Event::Echoed { payload });
            Ok(())
        }
        Command::ConnectionDisconnect { id } => crate::connection::disconnect(&id).await,
        Command::AutoLockOnPointerActivity => {
            app.autolock.on_pointer_activity();
            Ok(())
        }
        Command::AutoLockOnLifecycleChange { background } => {
            app.autolock.on_lifecycle_change(
                if background {
                    crate::autolock::LifecycleState::Background
                } else {
                    crate::autolock::LifecycleState::Foreground
                },
                &app.bus,
            );
            Ok(())
        }
        Command::AutoLockSetTimeout { minutes } => {
            app.autolock.set_timeout_minutes(minutes, &app.bus);
            Ok(())
        }
        Command::AutoLockRequestLock => {
            app.autolock.request_lock(&app.bus);
            Ok(())
        }
        Command::AutoLockUnlock => {
            app.autolock.unlock(&app.bus);
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn echo_round_trip() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
        bus.publish(Event::Echoed {
            payload: "hello".into(),
        });
        let event = rx.recv().await.expect("event");
        match event {
            Event::Echoed { payload } => assert_eq!(payload, "hello"),
            other => panic!("unexpected event: {other:?}"),
        }
    }

    #[tokio::test]
    async fn topic_filter() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
        bus.publish(Event::Echoed {
            payload: "x".into(),
        });
        let event = rx.recv().await.expect("event");
        assert_eq!(event.topic(), EventTopic::Diagnostics);
    }

    #[test]
    fn publish_without_subscribers_returns_zero() {
        let bus = EventBus::new();
        assert_eq!(
            bus.publish(Event::Echoed {
                payload: "noop".into()
            }),
            0
        );
    }
}
