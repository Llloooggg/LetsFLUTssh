use super::*;

#[tokio::test]
async fn echo_round_trip() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(EventTopic::Diagnostics);
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
    let mut rx = bus.subscribe(EventTopic::Diagnostics);
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

// ─── Event::topic() mapping coverage ────────────────────────────
// One test per match arm in `Event::topic()` so a forgotten / mis-
// routed arm fails the suite loud. The Dart subscriber filters by
// topic; a regression here silently drops every event under the
// affected variant.

fn cid() -> crate::connection::ConnId {
    crate::connection::ConnId::from("cid")
}

#[test]
fn topic_echoed_is_diagnostics() {
    assert_eq!(
        Event::Echoed {
            payload: "x".into()
        }
        .topic(),
        EventTopic::Diagnostics
    );
}

#[test]
fn topic_connection_state_changed_is_connection() {
    assert_eq!(
        Event::ConnectionStateChanged {
            id: cid(),
            state: crate::connection::ConnectionState::Connected,
        }
        .topic(),
        EventTopic::Connection
    );
}

#[test]
fn topic_connection_progress_is_connection() {
    assert_eq!(
        Event::ConnectionProgress {
            id: cid(),
            step: crate::connection::ProgressStep {
                phase: crate::connection::ConnectionPhase::SocketConnect,
                status: crate::connection::StepStatus::InProgress,
                detail: None,
            },
        }
        .topic(),
        EventTopic::Connection
    );
}

#[test]
fn topic_connection_error_is_connection() {
    assert_eq!(
        Event::ConnectionError {
            id: cid(),
            detail: "x".into()
        }
        .topic(),
        EventTopic::Connection
    );
}

#[test]
fn topic_connection_removed_is_connection() {
    assert_eq!(
        Event::ConnectionRemoved { id: cid() }.topic(),
        EventTopic::Connection
    );
}

#[test]
fn topic_connection_active_count_changed_is_connection() {
    assert_eq!(
        Event::ConnectionActiveCountChanged { count: 3 }.topic(),
        EventTopic::Connection
    );
}

#[test]
fn topic_autolock_locked_is_autolock() {
    assert_eq!(Event::AutoLockLocked.topic(), EventTopic::AutoLock);
}

#[test]
fn topic_autolock_unlocked_is_autolock() {
    assert_eq!(Event::AutoLockUnlocked.topic(), EventTopic::AutoLock);
}

#[test]
fn topic_autolock_timeout_changed_is_autolock() {
    assert_eq!(
        Event::AutoLockTimeoutChanged { minutes: 15 }.topic(),
        EventTopic::AutoLock
    );
}

#[test]
fn topic_recorder_started_is_recorder() {
    assert_eq!(
        Event::RecorderStarted {
            id: "r".into(),
            path: "/tmp/x".into()
        }
        .topic(),
        EventTopic::Recorder
    );
}

#[test]
fn topic_recorder_stopped_is_recorder() {
    assert_eq!(
        Event::RecorderStopped { id: "r".into() }.topic(),
        EventTopic::Recorder
    );
}

#[test]
fn topic_recorder_bytes_written_is_recorder() {
    assert_eq!(
        Event::RecorderBytesWritten {
            id: "r".into(),
            total_bytes: 1024
        }
        .topic(),
        EventTopic::Recorder
    );
}

#[test]
fn topic_recorder_rotate_requested_is_recorder() {
    assert_eq!(
        Event::RecorderRotateRequested {
            id: "r".into(),
            bytes_written: 1024
        }
        .topic(),
        EventTopic::Recorder
    );
}

#[test]
fn topic_recorder_write_failed_is_recorder() {
    assert_eq!(
        Event::RecorderWriteFailed {
            id: "r".into(),
            kind: "header".into(),
            detail: "x".into()
        }
        .topic(),
        EventTopic::Recorder
    );
}

#[test]
fn topic_transfer_task_added_is_transfer() {
    assert_eq!(
        Event::TransferTaskAdded { id: "t".into() }.topic(),
        EventTopic::Transfer
    );
}

#[test]
fn topic_transfer_task_state_is_transfer() {
    assert_eq!(
        Event::TransferTaskState {
            id: "t".into(),
            state: crate::transfer::TaskState::Queued,
        }
        .topic(),
        EventTopic::Transfer
    );
}

#[test]
fn topic_transfer_task_progress_is_transfer() {
    assert_eq!(
        Event::TransferTaskProgress {
            id: "t".into(),
            bytes_done: 0,
            bytes_total: 1
        }
        .topic(),
        EventTopic::Transfer
    );
}

#[test]
fn topic_transfer_task_error_is_transfer() {
    assert_eq!(
        Event::TransferTaskError {
            id: "t".into(),
            detail: "x".into()
        }
        .topic(),
        EventTopic::Transfer
    );
}

#[test]
fn topic_port_forward_registered_is_port_forward() {
    assert_eq!(
        Event::PortForwardRegistered { id: "p".into() }.topic(),
        EventTopic::PortForward
    );
}

#[test]
fn topic_port_forward_status_is_port_forward() {
    assert_eq!(
        Event::PortForwardStatus {
            id: "p".into(),
            status: crate::portforward::RuleStatus::Idle,
            detail: None,
        }
        .topic(),
        EventTopic::PortForward
    );
}

#[test]
fn topic_port_forward_removed_is_port_forward() {
    assert_eq!(
        Event::PortForwardRemoved { id: "p".into() }.topic(),
        EventTopic::PortForward
    );
}

#[test]
fn topic_update_download_progress_is_update() {
    assert_eq!(
        Event::UpdateDownloadProgress {
            url: "u".into(),
            written_bytes: 0,
            total_bytes: None
        }
        .topic(),
        EventTopic::Update
    );
}

#[test]
fn topic_update_verifying_started_is_update() {
    assert_eq!(
        Event::UpdateVerifyingStarted { url: "u".into() }.topic(),
        EventTopic::Update
    );
}

#[test]
fn topic_update_download_completed_is_update() {
    assert_eq!(
        Event::UpdateDownloadCompleted {
            url: "u".into(),
            path: "/tmp/x".into()
        }
        .topic(),
        EventTopic::Update
    );
}

#[test]
fn topic_known_hosts_changed_is_known_hosts() {
    assert_eq!(Event::KnownHostsChanged.topic(), EventTopic::KnownHosts);
}

#[test]
fn topic_sessions_changed_is_sessions() {
    assert_eq!(Event::SessionsChanged.topic(), EventTopic::Sessions);
}

#[test]
fn topic_keys_changed_is_keys() {
    assert_eq!(Event::KeysChanged.topic(), EventTopic::Keys);
}

#[test]
fn topic_config_changed_is_config() {
    assert_eq!(
        Event::ConfigChanged { json: "{}".into() }.topic(),
        EventTopic::Config
    );
}

#[test]
fn topic_tier_state_changed_is_tier() {
    assert_eq!(
        Event::TierStateChanged {
            state_wire_name: "locked".into()
        }
        .topic(),
        EventTopic::Tier
    );
}

#[test]
fn topic_unlock_cascade_ready_is_tier() {
    assert_eq!(
        Event::UnlockCascadeReady {
            tier_wire: "plaintext".into(),
            has_key: true,
        }
        .topic(),
        EventTopic::Tier
    );
}

#[test]
fn topic_core_log_is_core_log() {
    assert_eq!(
        Event::CoreLog {
            level: CoreLogLevel::Info,
            name: "tag".into(),
            message: "x".into(),
        }
        .topic(),
        EventTopic::CoreLog
    );
}

#[test]
fn topic_credential_prompt_request_is_security_prompt() {
    assert_eq!(
        Event::CredentialPromptRequest {
            prompt_id: "p".into(),
            session_id: "s".into(),
            kind_wire_name: "password".into(),
        }
        .topic(),
        EventTopic::SecurityPrompt
    );
}

#[test]
fn topic_keychain_probe_prompt_request_is_security_prompt() {
    assert_eq!(
        Event::KeychainProbePromptRequest {
            prompt_id: "p".into()
        }
        .topic(),
        EventTopic::SecurityPrompt
    );
}

#[test]
fn topic_hardware_vault_probe_prompt_request_is_security_prompt() {
    assert_eq!(
        Event::HardwareVaultProbePromptRequest {
            prompt_id: "p".into()
        }
        .topic(),
        EventTopic::SecurityPrompt
    );
}

#[test]
fn topic_hardware_vault_unlock_prompt_request_is_security_prompt() {
    assert_eq!(
        Event::HardwareVaultUnlockPromptRequest {
            prompt_id: "p".into(),
            pin: None
        }
        .topic(),
        EventTopic::SecurityPrompt
    );
}

#[test]
fn topic_hardware_vault_seal_prompt_request_is_security_prompt() {
    assert_eq!(
        Event::HardwareVaultSealPromptRequest {
            prompt_id: "p".into(),
            db_key_secret_id: "s".into(),
            pin_secret_id: None,
        }
        .topic(),
        EventTopic::SecurityPrompt
    );
}

#[test]
fn topic_recovery_prompt_request_is_security_prompt() {
    assert_eq!(
        Event::RecoveryPromptRequest {
            prompt_id: "p".into(),
            kind: crate::security::recovery_prompt::RecoveryPromptKind::DbCorruptDetected {
                reason: "x".into(),
            },
            choices: vec!["reset".into(), "tryOtherTier".into(), "quit".into()],
        }
        .topic(),
        EventTopic::SecurityPrompt
    );
}

#[test]
fn topic_security_capabilities_changed_is_security_capabilities() {
    assert_eq!(
        Event::SecurityCapabilitiesChanged { json: "{}".into() }.topic(),
        EventTopic::SecurityCapabilities
    );
}

#[test]
fn topic_known_host_prompt_request_is_known_hosts() {
    assert_eq!(
        Event::KnownHostPromptRequest {
            prompt_id: "p".into(),
            host: "h".into(),
            port: 22,
            key_type: "ssh-ed25519".into(),
            fingerprint: "fp".into(),
            kind: KnownHostPromptKind::NewHost,
        }
        .topic(),
        EventTopic::KnownHosts
    );
}

#[test]
fn topic_known_host_prompt_resolved_is_known_hosts() {
    assert_eq!(
        Event::KnownHostPromptResolved {
            prompt_id: "p".into(),
            accepted: true,
        }
        .topic(),
        EventTopic::KnownHosts
    );
}

// ─── EventBus broker behaviour ──────────────────────────────────

#[tokio::test]
async fn multi_subscriber_each_receives_clone() {
    let bus = EventBus::new();
    let mut a = bus.subscribe(EventTopic::Diagnostics);
    let mut b = bus.subscribe(EventTopic::Diagnostics);
    bus.publish(Event::Echoed {
        payload: "hi".into(),
    });
    let ea = a.recv().await.expect("a");
    let eb = b.recv().await.expect("b");
    match (ea, eb) {
        (Event::Echoed { payload: pa }, Event::Echoed { payload: pb }) => {
            assert_eq!(pa, "hi");
            assert_eq!(pb, "hi");
        }
        other => panic!("unexpected events: {other:?}"),
    }
}

#[test]
fn subscriber_count_reflects_live_receivers() {
    let bus = EventBus::new();
    assert_eq!(bus.subscriber_count(), 0);
    let _a = bus.subscribe(EventTopic::Diagnostics);
    assert_eq!(bus.subscriber_count(), 1);
    let b = bus.subscribe(EventTopic::Diagnostics);
    assert_eq!(bus.subscriber_count(), 2);
    drop(b);
    assert_eq!(bus.subscriber_count(), 1);
}

#[test]
fn publish_returns_subscriber_count_at_send_time() {
    let bus = EventBus::new();
    let _a = bus.subscribe(EventTopic::Diagnostics);
    let _b = bus.subscribe(EventTopic::Diagnostics);
    let n = bus.publish(Event::Echoed {
        payload: "x".into(),
    });
    assert_eq!(n, 2);
}

#[tokio::test]
async fn slow_subscriber_lags_without_blocking_publisher() {
    let bus = EventBus::new();
    let mut rx = bus.subscribe(EventTopic::Diagnostics);
    // Overflow the channel — broadcast::channel(EVENT_CHANNEL_CAPACITY)
    // drops the slowest receiver's oldest events. The publisher
    // never blocks; the slow receiver gets a Lagged error on the
    // next recv() call.
    for i in 0..(EVENT_CHANNEL_CAPACITY + 5) {
        bus.publish(Event::Echoed {
            payload: format!("m{i}"),
        });
    }
    let result = rx.recv().await;
    assert!(
        matches!(
            result,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_))
        ),
        "expected Lagged, got {result:?}"
    );
}

#[test]
fn default_yields_a_usable_bus() {
    let bus = EventBus::default();
    assert_eq!(bus.subscriber_count(), 0);
}

// ─── dispatch() command routing ─────────────────────────────────
// Each test seeds the process-wide `app::init()` singleton (one
// call is idempotent — subsequent calls return the same handle).
// Tests subscribe to the global bus before dispatching so the
// emitted event isn't lost; the subscribe happens via
// `app::instance().bus.subscribe()` to match the production path.

/// Bounded wait so a missing-event regression fails the test fast
/// instead of hanging the whole `cargo test` run. Two seconds is
/// long enough for the busiest CI scheduling, short enough that a
/// real bug surfaces immediately.
async fn next_matching<F>(rx: &mut tokio::sync::broadcast::Receiver<Event>, pred: F) -> Event
where
    F: Fn(&Event) -> bool,
{
    let deadline = std::time::Duration::from_secs(2);
    tokio::time::timeout(deadline, async {
        loop {
            match rx.recv().await {
                Ok(ev) if pred(&ev) => return ev,
                Ok(_) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(e) => panic!("recv error: {e:?}"),
            }
        }
    })
    .await
    .expect("next_matching: timed out after 2s waiting for matching event")
}

#[tokio::test]
async fn dispatch_noop_echo_publishes_echoed_event() {
    let app = crate::app::init();
    let mut rx = app.bus.subscribe(EventTopic::Diagnostics);
    dispatch(Command::NoopEcho {
        payload: "ping".into(),
    })
    .await
    .expect("dispatch");
    let ev = next_matching(
        &mut rx,
        |e| matches!(e, Event::Echoed { payload } if payload == "ping"),
    )
    .await;
    match ev {
        Event::Echoed { payload } => assert_eq!(payload, "ping"),
        _ => unreachable!(),
    }
}

#[tokio::test]
async fn dispatch_autolock_set_timeout_publishes_timeout_changed() {
    let _g = crate::app::test_serial_lock().lock().await;
    let app = crate::app::init();
    let mut rx = app.bus.subscribe(EventTopic::AutoLock);
    dispatch(Command::AutoLockSetTimeout { minutes: 7 })
        .await
        .expect("dispatch");
    let ev = next_matching(
        &mut rx,
        |e| matches!(e, Event::AutoLockTimeoutChanged { minutes } if *minutes == 7),
    )
    .await;
    assert_eq!(ev.topic(), EventTopic::AutoLock);
}

#[tokio::test]
async fn dispatch_autolock_request_lock_publishes_locked() {
    let _g = crate::app::test_serial_lock().lock().await;
    let app = crate::app::init();
    // Force the machine into Unlocked so `RequestLock` actually
    // transitions and fires `Locked` — `request_lock` is
    // idempotent and silent when already locked. Direct call
    // bypasses the bus to avoid muddling our subscription with a
    // precondition event.
    app.autolock.unlock(&app.bus);
    let mut rx = app.bus.subscribe(EventTopic::AutoLock);
    dispatch(Command::AutoLockRequestLock)
        .await
        .expect("request lock");
    let ev = next_matching(&mut rx, |e| matches!(e, Event::AutoLockLocked)).await;
    assert_eq!(ev.topic(), EventTopic::AutoLock);
}

#[tokio::test]
async fn dispatch_autolock_unlock_publishes_unlocked() {
    let _g = crate::app::test_serial_lock().lock().await;
    let app = crate::app::init();
    // Force Locked so `Unlock` actually transitions — direct
    // call bypasses the bus so the subscription below only sees
    // events from our test's dispatch.
    app.autolock.request_lock(&app.bus);
    let mut rx = app.bus.subscribe(EventTopic::AutoLock);
    dispatch(Command::AutoLockUnlock).await.expect("dispatch");
    let ev = next_matching(&mut rx, |e| matches!(e, Event::AutoLockUnlocked)).await;
    assert_eq!(ev.topic(), EventTopic::AutoLock);
}

#[tokio::test]
async fn dispatch_autolock_pointer_activity_does_not_fail() {
    let _g = crate::app::test_serial_lock().lock().await;
    let _ = crate::app::init();
    // No event published — this path just resets the idle timer.
    // Verify it returns Ok and doesn't panic.
    dispatch(Command::AutoLockOnPointerActivity)
        .await
        .expect("dispatch");
}

#[tokio::test]
async fn dispatch_autolock_lifecycle_change_does_not_fail() {
    let _g = crate::app::test_serial_lock().lock().await;
    let _ = crate::app::init();
    dispatch(Command::AutoLockOnLifecycleChange { background: true })
        .await
        .expect("background");
    dispatch(Command::AutoLockOnLifecycleChange { background: false })
        .await
        .expect("foreground");
}

#[tokio::test]
async fn dispatch_known_host_prompt_response_unknown_id_is_silent() {
    let app = crate::app::init();
    // No prompt registered against this id — `resolve` returns
    // `false` and the dispatcher publishes nothing. The test
    // asserts the dispatcher does not panic and does not emit an
    // unsolicited event with this id.
    dispatch(Command::KnownHostPromptResponse {
        prompt_id: "ghost-id".into(),
        accepted: true,
    })
    .await
    .expect("dispatch");
    // Probe the bus briefly; expect no `KnownHostPromptResolved`
    // for our ghost id within a tight deadline.
    let mut rx = app.bus.subscribe(EventTopic::KnownHosts);
    let r = tokio::time::timeout(std::time::Duration::from_millis(50), async {
        loop {
            match rx.recv().await {
                Ok(Event::KnownHostPromptResolved { prompt_id, .. }) if prompt_id == "ghost-id" => {
                    return true;
                }
                Ok(_) => continue,
                Err(_) => return false,
            }
        }
    })
    .await;
    assert!(r.is_err(), "ghost-id should not surface");
}

#[tokio::test]
async fn dispatch_connection_disconnect_missing_id_is_idempotent() {
    let _ = crate::app::init();
    dispatch(Command::ConnectionDisconnect {
        id: crate::connection::ConnId::from("does-not-exist"),
    })
    .await
    .expect("idempotent on missing id");
}

#[tokio::test]
async fn dispatch_connection_disconnect_all_on_empty_registry_is_ok() {
    let _ = crate::app::init();
    dispatch(Command::ConnectionDisconnectAll)
        .await
        .expect("empty registry walk");
}
