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
mod tests {
    use super::*;
    use crate::security::capabilities::{KeyringProbeResult, SecurityCapabilities};
    use std::sync::{Arc, Mutex};

    fn sample(probe: KeyringProbeResult) -> SecurityCapabilities {
        SecurityCapabilities {
            keychain_available: matches!(probe, KeyringProbeResult::Available),
            hardware_vault_available: false,
            biometric_available: false,
            fprintd_available: false,
            is_linux_host: true,
            keychain_probe: probe,
            hardware_probe_code: "available".into(),
        }
    }

    /// In-memory sink used by the persister tests to capture
    /// every snapshot the loop forwards.
    struct VecSink {
        log: Arc<Mutex<Vec<Option<SecurityCapabilities>>>>,
    }

    impl CapabilitiesSink for VecSink {
        fn apply(&self, caps: Option<SecurityCapabilities>) {
            self.log.lock().unwrap().push(caps);
        }
    }

    /// Wait until the sink has accumulated at least `count`
    /// entries or the bounded deadline expires. Polling instead
    /// of relying on `tokio::task::yield_now` keeps the test
    /// deterministic across the broadcast channel's internal
    /// scheduling — a missed event surfaces as a timeout panic
    /// rather than a flaky pass.
    async fn await_entries(log: &Arc<Mutex<Vec<Option<SecurityCapabilities>>>>, count: usize) {
        let deadline = std::time::Duration::from_secs(2);
        tokio::time::timeout(deadline, async {
            loop {
                if log.lock().unwrap().len() >= count {
                    return;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("sink did not reach expected entry count before timeout");
    }

    /// Pin the canonical "snapshot in → snapshot out" path. The
    /// orchestrator publishes a `SecurityCapabilitiesChanged`
    /// event with the JSON-encoded snapshot; the persister
    /// decodes it through the canonical
    /// `SecurityCapabilities::from_json_value` and lands the
    /// typed struct on the sink.
    #[tokio::test]
    async fn forwards_fresh_snapshot_to_sink() {
        let (tx, rx) = tokio::sync::broadcast::channel::<Event>(8);
        let log = Arc::new(Mutex::new(Vec::new()));
        let sink = VecSink { log: log.clone() };

        let handle = tokio::spawn(async move { run_loop_for_tests(rx, sink).await });

        let snapshot = sample(KeyringProbeResult::Available);
        let json = snapshot.to_json_value().to_string();
        tx.send(Event::SecurityCapabilitiesChanged { json })
            .expect("send");
        await_entries(&log, 1).await;
        drop(tx);
        let _ = handle.await;

        let entries = log.lock().unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0], Some(snapshot));
    }

    /// Empty-string payload is the wizard's "Recheck" path —
    /// `Cache::clear` publishes `SecurityCapabilitiesChanged { json: "" }`
    /// and the persister translates it to a `None` sink write
    /// (clearing the persisted slot).
    #[tokio::test]
    async fn empty_payload_clears_via_sink() {
        let (tx, rx) = tokio::sync::broadcast::channel::<Event>(8);
        let log = Arc::new(Mutex::new(Vec::new()));
        let sink = VecSink { log: log.clone() };

        let handle = tokio::spawn(async move { run_loop_for_tests(rx, sink).await });

        tx.send(Event::SecurityCapabilitiesChanged {
            json: String::new(),
        })
        .expect("send");
        await_entries(&log, 1).await;
        drop(tx);
        let _ = handle.await;

        let entries = log.lock().unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0], None);
    }

    /// Malformed JSON / wire shape rejected by
    /// `SecurityCapabilities::from_json_value` must NOT clear the
    /// persisted slot — clearing on a contract drift would surface
    /// as a wizard rerun where the user expected cached values.
    /// The loop logs + skips; the next legitimate publish lands
    /// on the sink.
    #[tokio::test]
    async fn malformed_payload_skipped_not_cleared() {
        let (tx, rx) = tokio::sync::broadcast::channel::<Event>(8);
        let log = Arc::new(Mutex::new(Vec::new()));
        let sink = VecSink { log: log.clone() };

        let handle = tokio::spawn(async move { run_loop_for_tests(rx, sink).await });

        // Not JSON at all.
        tx.send(Event::SecurityCapabilitiesChanged {
            json: "{not json".into(),
        })
        .expect("send-1");
        // Valid JSON but missing the required `keychain_probe`
        // field — the canonical `from_json_value` returns None,
        // not a defaulted snapshot.
        tx.send(Event::SecurityCapabilitiesChanged {
            json: r#"{"hardware_probe_code":"x"}"#.into(),
        })
        .expect("send-2");
        // Trailing well-formed publish so we can synchronise on
        // "loop has drained everything"; without it the test
        // would have no observable signal for "skipped".
        let snapshot = sample(KeyringProbeResult::Available);
        tx.send(Event::SecurityCapabilitiesChanged {
            json: snapshot.to_json_value().to_string(),
        })
        .expect("send-3");
        await_entries(&log, 1).await;
        drop(tx);
        let _ = handle.await;

        let entries = log.lock().unwrap();
        assert_eq!(entries.len(), 1, "malformed publishes must be skipped");
        assert_eq!(entries[0], Some(snapshot));
    }

    /// Cross-check with the singleton config store — the
    /// production wiring (ApplyToSingleton) lands the snapshot in
    /// `config_store::instance().get_app_config().security_probe_cache`.
    /// This test pre-init's the singleton against a tempdir so
    /// the update lands somewhere observable; left in despite
    /// the singleton-contention risk because a future refactor
    /// that drops the seam still needs this contract pinned.
    /// Marked `#[ignore]` to keep the regular `cargo test` run
    /// hermetic — opt in via `cargo test -- --ignored` when
    /// hand-verifying the end-to-end path.
    #[tokio::test]
    #[ignore = "writes to process-global config_store singleton; opt in via --ignored"]
    async fn end_to_end_through_singleton() {
        let dir = tempfile::TempDir::new().unwrap();
        config_store::instance()
            .init(dir.path().to_path_buf())
            .unwrap();

        let (tx, rx) = tokio::sync::broadcast::channel::<Event>(8);
        let handle = tokio::spawn(async move { run_loop_for_tests(rx, ApplyToSingleton).await });

        let snapshot = sample(KeyringProbeResult::Available);
        let json = snapshot.to_json_value().to_string();
        tx.send(Event::SecurityCapabilitiesChanged { json })
            .expect("send");
        // Poll the singleton until the loop has drained.
        let deadline = std::time::Duration::from_secs(2);
        tokio::time::timeout(deadline, async {
            loop {
                if let Some(cfg) = config_store::instance().get_app_config() {
                    if cfg.security_probe_cache == Some(snapshot.clone()) {
                        return;
                    }
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .expect("singleton did not adopt the snapshot before timeout");
        drop(tx);
        let _ = handle.await;

        let cfg = config_store::instance().get_app_config().unwrap();
        assert_eq!(cfg.security_probe_cache, Some(snapshot));
    }
}
