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
/// as Phase 5 sub-phases land; today the enum carries only the 5.0
/// smoke variant.
#[derive(Debug, Clone)]
pub enum Event {
    /// Foundation smoke event. `bus_dispatch(NoopEcho)` publishes
    /// this with the same payload so the FRB plumbing can be
    /// verified end-to-end before any real domain command lands.
    Echoed { payload: String },
}

impl Event {
    pub fn topic(&self) -> EventTopic {
        match self {
            Event::Echoed { .. } => EventTopic::Diagnostics,
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
/// variant; the 5.0 surface only handles `NoopEcho`. Sub-phases
/// extend the match arms in lockstep with the actor moves.
pub fn dispatch(cmd: Command) -> Result<(), Error> {
    let app = crate::app::instance();
    match cmd {
        Command::NoopEcho { payload } => {
            app.bus.publish(Event::Echoed { payload });
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
