//! Typed Command / Event bus — Rust-core foundation.
//!
//! Frontend dispatches `Command`s (operation envelopes); domain
//! actors mutate state and publish `Event`s onto the bus broker.
//! Subscribers receive an `Event` stream filtered by topic, so a
//! per-screen view picks up only the events that affect it.
//!
//! The foundation surface defines just the scaffolding: a
//! `NoopEcho` command + an `Echoed` event used as smoke test for
//! the FRB plumbing. Concrete domain enums (`Connection*`,
//! `PortForward*`, `Transfer*`, ...) extend in lockstep with the
//! actor moves below.
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
    /// Smoke / debug events — foundation echo, future bus self-tests.
    Diagnostics,
    /// Connection lifecycle.
    Connection,
    /// Port forward rule status.
    PortForward,
    /// Transfer queue task progress.
    Transfer,
    /// Recorder lifecycle.
    Recorder,
    /// Auto-lock state machine.
    AutoLock,
    /// `.lfs` import handle progress.
    Import,
    /// Auto-update channel — fetch / download progress.
    Update,
    /// Known-hosts table — refresh notification for the
    /// settings panel + any cached snapshot mirrors.
    KnownHosts,
    /// Sessions / folders tables — refresh notification for the
    /// session-store cache mirror. Fires after every write
    /// (upsert / delete / move / folder rename / collapsed-flag
    /// toggle) so the Dart shim can re-fetch in one
    /// microtask-coalesced refresh rather than per-call.
    Sessions,
    /// `config.json` actor — fires after a debounced save lands
    /// on disk. Subscribers re-snapshot the canonical state
    /// without polling. Decision 5 / D5 in
    /// `docs/RUST_MIGRATION_REMAINING.md`.
    Config,
    /// Tier state machine — Locked / Unlocking / Unlocked /
    /// Wiping transitions. Subscribers (Dart unlock dialog,
    /// auto-lock path, lock indicator) react to state changes
    /// without polling. Decision 4 / C9 in
    /// `docs/RUST_MIGRATION_REMAINING.md`.
    Tier,
    /// Per-prompt-type request channels (Decision 1 / Decision
    /// 2). Today: keychain pepper read; future arcs add
    /// credential / biometric prompt channels under the same
    /// topic so the Dart subscriber can multiplex them.
    SecurityPrompt,
}

/// State change envelope published onto the bus. Variants accrete
/// as actor lifts land.
#[derive(Debug, Clone)]
pub enum Event {
    /// Foundation smoke event. `bus_dispatch(NoopEcho)` publishes
    /// this with the same payload so the FRB plumbing can be
    /// verified end-to-end before any real domain command lands.
    Echoed { payload: String },

    /// Connection lifecycle — emitted whenever an actor
    /// transitions between `Disconnected / Connecting / Connected`.
    /// Subscribers re-snapshot their connection-level views off
    /// this signal; the snapshot itself is fetched via a separate
    /// `ConnectionSnapshot` command (cheap copy of the actor's
    /// plain-data view).
    ConnectionStateChanged {
        id: crate::connection::ConnId,
        state: crate::connection::ConnectionState,
    },

    /// Connection lifecycle — fan-out per progress step
    /// (`socketConnect / hostKeyVerify / authenticate / openChannel`
    /// at `inProgress / success / failed`). The Dart-era
    /// `Connection.progressStream` retires in favour of subscribing
    /// here and filtering by id.
    ConnectionProgress {
        id: crate::connection::ConnId,
        step: crate::connection::ProgressStep,
    },

    /// Connection lifecycle — emitted when an actor records a
    /// fresh connect-time error. Detail is the localised /
    /// sanitised message; subscribers pair this with the matching
    /// `ConnectionStateChanged(Disconnected)` for UI feedback.
    ConnectionError {
        id: crate::connection::ConnId,
        detail: String,
    },

    /// Connection lifecycle — emitted when an actor is
    /// removed from the registry (manual disconnect, parent of a
    /// disconnected bastion chain).
    ConnectionRemoved { id: crate::connection::ConnId },

    /// Connection lifecycle — count of user-visible Connected
    /// actors changed (excludes internal bastion hops). The
    /// Android foreground-service binding subscribes here to
    /// start / stop the persistent service. Re-published after
    /// every state transition that flips at least one actor's
    /// `Connected` predicate; coalesced inside the publisher so
    /// repeated emits with the same count don't fan out.
    ConnectionActiveCountChanged { count: i64 },

    /// Auto-lock — fired when the idle timer expires, when
    /// the app backgrounds with a non-zero timeout, or when the
    /// user explicitly requests a lock. The payload is empty —
    /// subscribers re-fetch any state they need from the
    /// machine snapshot or the DB.
    AutoLockLocked,
    /// Auto-lock — fired after the Dart unlock dialog
    /// supplies a fresh key + reopens the DB.
    AutoLockUnlocked,
    /// Auto-lock — fired when the configured idle timeout
    /// changes. Carries the new value in minutes (0 = off).
    AutoLockTimeoutChanged { minutes: i64 },

    /// Config — fired by `lfs_core::config_store::Store` after
    /// a debounced atomic write of `config.json` lands on disk.
    /// Carries the freshly-written JSON so subscribers can swap
    /// in the snapshot without a follow-up `get_json` round-trip.
    /// Decision 5 / D5 in `docs/RUST_MIGRATION_REMAINING.md`.
    ConfigChanged { json: String },

    /// Tier state machine — fired by
    /// `lfs_core::security::tier_machine::Machine` on every
    /// successful state transition. Carries the new state's wire
    /// name (`locked` / `unlocking` / `unlocked` / `wiping`) so
    /// subscribers branch without parsing an enum across FRB.
    /// Decision 4 / C9 in `docs/RUST_MIGRATION_REMAINING.md`.
    TierStateChanged { state_wire_name: String },

    /// Keychain pepper read request — fired by the L2 gate actor
    /// when it needs the `letsflutssh_l2_pepper` value from
    /// flutter_secure_storage. Dart subscriber executes the
    /// keychain read, then dispatches the response command which
    /// resolves the awaiting Rust handler through
    /// `lfs_core::security::keychain_pepper_prompt::PromptRegistry`.
    /// Decision 1 + Decision 2 in
    /// `docs/RUST_MIGRATION_REMAINING.md`.
    KeychainPepperPromptRequest { prompt_id: String },

    /// Recorder — fired when a fresh recording actor enters
    /// the registry.
    RecorderStarted { id: String, path: String },
    /// Recorder — fired when an actor leaves the registry
    /// (close / shutdown / file rotation).
    RecorderStopped { id: String },
    /// Recorder — fired after the frame-write driver records
    /// a chunk of bytes. Carries the running total so subscribers
    /// can render progress without polling.
    RecorderBytesWritten { id: String, total_bytes: u64 },
    /// Recorder — fired by the per-id worker when the running
    /// total crosses [`crate::recorder::MAX_FILE_BYTES`]. The
    /// Dart shim subscribes, prepares a fresh path under the
    /// session's recording dir, and enqueues a
    /// [`crate::recorder::queue::QueueEntry::Rotate`]. The
    /// worker latches the request flag so a single overflow
    /// emits one event regardless of how many writes follow
    /// before the rotate enqueue arrives.
    RecorderRotateRequested { id: String, bytes_written: u64 },

    /// Transfer queue — task entered the queue.
    TransferTaskAdded { id: String },
    /// Transfer queue — task transitioned to a new state.
    TransferTaskState {
        id: String,
        state: crate::transfer::TaskState,
    },
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
        status: crate::portforward::RuleStatus,
        detail: Option<String>,
    },
    /// Port forward — rule actor left the registry.
    PortForwardRemoved { id: String },

    /// Auto-update — bytes-written tick during a streaming
    /// download. `total_bytes` is `None` when the server did not
    /// declare a `Content-Length`. Subscribers tick the progress
    /// bar; the URL identifies the active download for UIs that
    /// drive multiple in parallel.
    UpdateDownloadProgress {
        url: String,
        written_bytes: u64,
        total_bytes: Option<u64>,
    },
    /// Auto-update — HTTP bytes are on disk; the orchestrator
    /// is now hashing + fetching the signed manifest + verifying
    /// the Ed25519 signature. UI swaps the determinate progress
    /// bar for an indeterminate "Verifying…" caption.
    UpdateVerifyingStarted { url: String },
    /// Auto-update — every verification step passed; the asset
    /// is at `path` ready to install.
    UpdateDownloadCompleted { url: String, path: String },

    /// Known-hosts table mutated (upsert / delete / clear /
    /// import). No detail — Dart subscribers re-fetch the full
    /// list via `db_known_hosts_list_all`. One coalesced event
    /// per write; bulk imports emit a single event for the whole
    /// batch.
    KnownHostsChanged,
    /// Sessions / folders tables mutated. No detail — Dart
    /// subscribers re-fetch the full list via the session DAOs.
    /// One event per write covers both session-row changes and
    /// folder-cascade ripples (rename / move / delete / collapsed
    /// toggle) — the cache mirror picks the canonical state up
    /// from the DB after the FRB layer publishes here.
    SessionsChanged,

    /// TOFU prompt — russh's `check_server_key` saw a host key
    /// that does not match a stored entry. The prompt id is
    /// caller-allocated (UUIDv4 from the Dart shim that subscribes
    /// to this topic); the response command echoes the same id so
    /// concurrent prompts (parallel reconnect storm) don't
    /// cross-wire. `kind` distinguishes "first time we've seen
    /// this host" from "host key changed under us — possible
    /// MITM" so the UI picks the matching dialog wording.
    KnownHostPromptRequest {
        prompt_id: String,
        host: String,
        port: i64,
        key_type: String,
        fingerprint: String,
        kind: KnownHostPromptKind,
    },
    /// TOFU prompt result — published after the dispatcher resolves
    /// the user's choice from the bus command back into the
    /// awaiting handler. Subscribers (the russh handler that fired
    /// the request) match on `prompt_id`.
    KnownHostPromptResolved { prompt_id: String, accepted: bool },
}

/// Distinguish the two TOFU prompt shapes:
/// - `NewHost` — first time we've seen this `host:port`. The dialog
///   shows the new fingerprint with a "trust this server?" prompt.
/// - `KeyChanged` — we have a stored entry for this `host:port` but
///   the offered key does not match. The dialog warns about
///   possible MITM and shows both fingerprints; accepting overwrites
///   the stored entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KnownHostPromptKind {
    NewHost,
    KeyChanged,
}

impl Event {
    pub fn topic(&self) -> EventTopic {
        match self {
            Event::Echoed { .. } => EventTopic::Diagnostics,
            Event::ConnectionStateChanged { .. }
            | Event::ConnectionProgress { .. }
            | Event::ConnectionError { .. }
            | Event::ConnectionRemoved { .. }
            | Event::ConnectionActiveCountChanged { .. } => EventTopic::Connection,
            Event::AutoLockLocked
            | Event::AutoLockUnlocked
            | Event::AutoLockTimeoutChanged { .. } => EventTopic::AutoLock,
            Event::RecorderStarted { .. }
            | Event::RecorderStopped { .. }
            | Event::RecorderBytesWritten { .. }
            | Event::RecorderRotateRequested { .. } => EventTopic::Recorder,
            Event::TransferTaskAdded { .. }
            | Event::TransferTaskState { .. }
            | Event::TransferTaskProgress { .. }
            | Event::TransferTaskError { .. } => EventTopic::Transfer,
            Event::PortForwardRegistered { .. }
            | Event::PortForwardStatus { .. }
            | Event::PortForwardRemoved { .. } => EventTopic::PortForward,
            Event::UpdateDownloadProgress { .. }
            | Event::UpdateVerifyingStarted { .. }
            | Event::UpdateDownloadCompleted { .. } => EventTopic::Update,
            Event::KnownHostsChanged => EventTopic::KnownHosts,
            Event::SessionsChanged => EventTopic::Sessions,
            Event::ConfigChanged { .. } => EventTopic::Config,
            Event::TierStateChanged { .. } => EventTopic::Tier,
            Event::KeychainPepperPromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::KnownHostPromptRequest { .. } | Event::KnownHostPromptResolved { .. } => {
                EventTopic::KnownHosts
            }
        }
    }
}

/// Operation envelope dispatched by the frontend. New variants
/// extend this enum with concrete domain commands.
#[derive(Debug, Clone)]
pub enum Command {
    /// Foundation smoke command — emits `Event::Echoed` with the
    /// same payload. No state mutation; use only for FRB plumbing
    /// tests.
    NoopEcho { payload: String },

    /// Remove an actor from the registry. Idempotent on a
    /// missing id. Drops the held russh handle (which sends
    /// `SSH_MSG_DISCONNECT` on Drop) before clearing the row.
    ConnectionDisconnect { id: crate::connection::ConnId },

    /// Tear down every active connection actor. Convenience for
    /// "lock now" / shutdown paths — emits `ConnectionRemoved`
    /// per actor as it walks the registry.
    ConnectionDisconnectAll,

    /// Auto-lock — pointer activity ping. Resets the idle
    /// timer; the Dart side fires this once per significant
    /// pointer event so the lock doesn't trip mid-typing.
    AutoLockOnPointerActivity,
    /// Auto-lock — lifecycle change. `background = true` is
    /// the Dart-era `paused / inactive / hidden` umbrella;
    /// `background = false` is `resumed`.
    AutoLockOnLifecycleChange { background: bool },
    /// Auto-lock — configure the idle timeout in minutes
    /// (0 disables the timer). Mirrors the Settings → Auto-lock
    /// preset list.
    AutoLockSetTimeout { minutes: i64 },
    /// Auto-lock — explicit lock request (Settings →
    /// "Lock now", deeplink, etc).
    AutoLockRequestLock,
    /// Auto-lock — unlock signal from the Dart-side unlock
    /// dialog. The dialog has already supplied the master key +
    /// reopened the DB; the machine just resets its activity
    /// clock and emits the matching event.
    AutoLockUnlock,

    /// TOFU prompt response — the Dart UI's host-key dialog
    /// resolved (user tapped Accept / Reject). `prompt_id` echoes
    /// the id from the matching [`Event::KnownHostPromptRequest`]
    /// so the awaiting russh handler matches the right pending
    /// prompt. `accepted` is the user's choice; the dispatcher
    /// persists the new entry into `known_hosts` when accepted.
    KnownHostPromptResponse { prompt_id: String, accepted: bool },
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
/// variant. New variants extend the match arms in lockstep with
/// each actor move.
///
/// Async because command handlers touch tokio mutexes
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
        Command::ConnectionDisconnectAll => {
            crate::connection::disconnect_all().await;
            Ok(())
        }
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
        Command::KnownHostPromptResponse {
            prompt_id,
            accepted,
        } => {
            let resolved = app.known_hosts_prompts.resolve(&prompt_id, accepted);
            if resolved {
                app.bus.publish(Event::KnownHostPromptResolved {
                    prompt_id,
                    accepted,
                });
            }
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
