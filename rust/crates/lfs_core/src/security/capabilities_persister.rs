//! Capabilities-probe-cache persister — Rust-side subscriber that
//! mirrors every [`Event::SecurityCapabilitiesChanged`] back into
//! the `security_probe_cache` slot of `config.json`.
//!
//! Sits between the orchestrator (which publishes after every
//! [`crate::security::capabilities_cache::Cache::set`]) and the
//! config store (which owns the debounced atomic write). Keeps
//! the persistence side-effect Rust-side so the Dart layer no
//! longer needs a `ref.listen` provider on the capabilities
//! stream.
//!
//! ## Ordering invariant
//!
//! [`start`] MUST run after [`crate::config_store::Store::init`]
//! returns — otherwise the persister's update calls hit the
//! "not initialised" branch and the first published snapshot is
//! lost. The FRB entry point [`crate::config_store::start_background_ticker`]
//! is the canonical predecessor; `lfs_frb::api::config::config_store_init`
//! wires both in the documented order.
//!
//! The persister also attaches **before** the orchestrator runs
//! its first probe — `EventBus` is a `tokio::sync::broadcast`
//! channel; subscribers that join after a publish never see that
//! event. The FRB orchestrator endpoint is only reachable from
//! Dart bootstrap code that runs strictly after `config_store_init`,
//! so the production cold-start path already satisfies this.
//!
//! ## Lag handling
//!
//! `tokio::sync::broadcast::Receiver` returns `RecvError::Lagged`
//! when a slow subscriber falls behind the channel's capacity. The
//! loop logs once and continues — the next [`Cache::set`] /
//! [`Cache::clear`] publishes the canonical state, and the
//! capabilities snapshot is always idempotent (a missed delta is
//! re-published the next time the orchestrator runs). `Closed`
//! means the singleton bus is shutting down (process exit) — the
//! loop breaks cleanly.

use std::sync::OnceLock;

use tokio::sync::broadcast::error::RecvError;

use crate::bus::{Event, EventTopic};
use crate::config_store;
use crate::security::capabilities::SecurityCapabilities;

/// Production entry point — spawn the persister once against the
/// singleton config store + capabilities cache. Idempotent;
/// repeated calls after the first are no-ops. Returns early when
/// no Tokio runtime is reachable from the calling thread —
/// mirrors the same guard
/// [`crate::config_store::start_background_ticker`] uses so the
/// FRB sync init path on a non-runtime thread (or a unit test
/// outside `#[tokio::test]`) does not panic.
///
/// Subscribes to [`EventTopic::SecurityCapabilities`] and writes
/// every [`Event::SecurityCapabilitiesChanged`] through
/// [`config_store::Store::update_security_probe_cache`].
pub fn start() {
    static STARTED: OnceLock<()> = OnceLock::new();
    if tokio::runtime::Handle::try_current().is_err() {
        return;
    }
    if STARTED.set(()).is_err() {
        return;
    }
    let rx = crate::app::instance()
        .bus
        .subscribe(EventTopic::SecurityCapabilities);
    tokio::spawn(async move {
        run_loop(rx, ApplyToSingleton).await;
    });
}

/// Test seam — the persister loop accepts any sink that lands a
/// [`SecurityCapabilities`] update somewhere. Production wires
/// [`ApplyToSingleton`]; unit tests substitute a fresh
/// [`config_store::Store`] to keep `cargo test` runs from
/// scribbling on the process-global state.
pub trait CapabilitiesSink: Send + 'static {
    fn apply(&self, caps: Option<SecurityCapabilities>);
}

/// Production sink — forwards to the process-singleton
/// [`config_store::Store`].
pub struct ApplyToSingleton;

impl CapabilitiesSink for ApplyToSingleton {
    fn apply(&self, caps: Option<SecurityCapabilities>) {
        if let Err(e) = config_store::instance().update_security_probe_cache(caps) {
            // The store has a documented "not initialised" error
            // when `start_background_ticker` runs ahead of
            // `Store::init` — surfacing it via warn keeps the
            // miswiring debuggable without flooding logs on a
            // missing-config-store cold start.
            crate::app_log_warn!(
                "CapabilitiesPersister",
                "update_security_probe_cache failed: {}",
                e
            );
        }
    }
}

/// Receive-loop body. Public to the crate so the unit test in
/// this module can drive it against a custom sink + an
/// independently-published bus event.
async fn run_loop<S: CapabilitiesSink>(mut rx: tokio::sync::broadcast::Receiver<Event>, sink: S) {
    loop {
        match rx.recv().await {
            Ok(Event::SecurityCapabilitiesChanged { json }) => {
                match decode_capabilities_snapshot(&json) {
                    Ok(caps) => sink.apply(caps),
                    // Rejected snapshot already logged — skip rather
                    // than clear the persisted slot.
                    Err(()) => continue,
                }
            }
            // Some other event landed on the same topic — ignore;
            // capabilities is the only variant on this topic
            // today, but a future extra event variant should not
            // crash the loop.
            Ok(_) => continue,
            Err(RecvError::Lagged(n)) => {
                crate::app_log_warn!(
                    "CapabilitiesPersister",
                    "broadcast lagged by {} events; next publish reconciles",
                    n
                );
                continue;
            }
            Err(RecvError::Closed) => break,
        }
    }
}

/// Decode a `SecurityCapabilitiesChanged` payload into the value to
/// persist. An empty `json` clears the slot (`Ok(None)`); a valid
/// snapshot yields `Ok(Some(caps))`. `Err(())` means the snapshot
/// was rejected (unparsable JSON or a shape the wire-format decoder
/// rejects — a contract drift between `Cache::set` and the JSON
/// shape) and the caller should skip without clearing the slot,
/// which would be a false negative. Logs the rejection reason here.
fn decode_capabilities_snapshot(json: &str) -> Result<Option<SecurityCapabilities>, ()> {
    if json.is_empty() {
        return Ok(None);
    }
    let value = serde_json::from_str::<serde_json::Value>(json).map_err(|e| {
        crate::app_log_warn!("CapabilitiesPersister", "rejected snapshot: parse: {}", e);
    })?;
    match SecurityCapabilities::from_json_value(&value) {
        Some(caps) => Ok(Some(caps)),
        None => {
            crate::app_log_warn!(
                "CapabilitiesPersister",
                "rejected snapshot: SecurityCapabilities::from_json_value returned None"
            );
            Err(())
        }
    }
}

/// Test-only convenience that drives [`run_loop`] against a
/// custom sink. The integration test in this file uses it; the
/// production `start()` path goes through the singleton config
/// store via [`ApplyToSingleton`].
#[cfg(test)]
pub(crate) async fn run_loop_for_tests<S: CapabilitiesSink>(
    rx: tokio::sync::broadcast::Receiver<Event>,
    sink: S,
) {
    run_loop(rx, sink).await;
}
#[cfg(test)]
#[path = "../../tests/unit/security_capabilities_persister.rs"]
mod tests;
