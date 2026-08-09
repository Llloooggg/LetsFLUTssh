/// Unit tests extracted from security/capabilities_persister.rs
/// Declared via `#[path] mod tests;` in the source file.
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
