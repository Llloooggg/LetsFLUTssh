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

/// State change envelope delivered to subscribers. Mirrors
/// `lfs_core::bus::Event` — variants accrete as Phase 5 sub-phases
/// land.
#[derive(Debug, Clone)]
pub enum BusEvent {
    /// 5.0 smoke event. Foundation plumbing test only — no domain
    /// state behind it.
    Echoed { payload: String },
}

impl BusEvent {
    fn from_core(e: lfs_core::bus::Event) -> Self {
        match e {
            lfs_core::bus::Event::Echoed { payload } => BusEvent::Echoed { payload },
        }
    }
}

/// Operation envelope dispatched by the Dart side. Mirrors
/// `lfs_core::bus::Command`.
#[derive(Debug, Clone)]
pub enum BusCommand {
    /// 5.0 smoke command — emits `Echoed` with the same payload.
    NoopEcho { payload: String },
}

impl From<BusCommand> for lfs_core::bus::Command {
    fn from(c: BusCommand) -> Self {
        match c {
            BusCommand::NoopEcho { payload } => lfs_core::bus::Command::NoopEcho { payload },
        }
    }
}

/// Dispatch a typed command. Single entry point Dart calls for
/// every operation; the Rust side routes by command variant.
pub async fn bus_dispatch(command: BusCommand) -> Result<(), String> {
    let core = lfs_core::bus::Command::from(command);
    lfs_core::bus::dispatch(core).map_err(|e| e.to_string())
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
