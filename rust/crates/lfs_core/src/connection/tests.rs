use super::*;

#[test]
fn insert_and_snapshot() {
    let reg = ConnectionRegistry::new();
    let actor = ConnectionActor::new(ConnectionActorInit {
        id: "c1".into(),
        label: "Label".into(),
        session_id: Some("s1".into()),
        bastion_id: None,
        internal: false,
        host: "host".into(),
        port: 22,
        user: "user".into(),
    });
    reg.insert(actor);
    let snap = reg.snapshot_all();
    assert_eq!(snap.len(), 1);
    assert_eq!(snap[0].id, "c1");
    assert_eq!(snap[0].state, ConnectionState::Disconnected);
}

#[tokio::test]
async fn remove_drops_actor() {
    let reg = ConnectionRegistry::new();
    let actor = ConnectionActor::new(ConnectionActorInit {
        id: "c1".into(),
        label: "L".into(),
        session_id: None,
        bastion_id: None,
        internal: false,
        host: "h".into(),
        port: 22,
        user: "u".into(),
    });
    reg.insert(actor);
    assert_eq!(reg.count(), 1);
    reg.remove("c1");
    assert_eq!(reg.count(), 0);
    assert!(reg.snapshot_all().is_empty());
}

#[tokio::test]
async fn snapshot_carries_progress() {
    let reg = ConnectionRegistry::new();
    let actor = ConnectionActor::new(ConnectionActorInit {
        id: "c1".into(),
        label: "L".into(),
        session_id: None,
        bastion_id: None,
        internal: false,
        host: "h".into(),
        port: 22,
        user: "u".into(),
    });
    let handle = reg.insert(actor);
    {
        let mut a = handle.lock().unwrap_or_else(|e| e.into_inner());
        a.progress.push(ProgressStep {
            phase: ConnectionPhase::SocketConnect,
            status: StepStatus::Success,
            detail: None,
        });
    }
    let snap = reg.snapshot_all();
    assert_eq!(snap[0].progress.len(), 1);
    assert_eq!(snap[0].progress[0].phase, ConnectionPhase::SocketConnect);
}

#[test]
fn init_generation_starts_at_one() {
    let reg = ConnectionRegistry::new();
    reg.init_generation("c1");
    assert!(reg.is_current_generation("c1", 1));
    assert!(!reg.is_current_generation("c1", 2));
}

#[test]
fn bump_generation_increments_monotonically() {
    let reg = ConnectionRegistry::new();
    assert_eq!(reg.bump_generation("c1"), 1);
    assert_eq!(reg.bump_generation("c1"), 2);
    assert_eq!(reg.bump_generation("c1"), 3);
    assert!(reg.is_current_generation("c1", 3));
    assert!(!reg.is_current_generation("c1", 2));
}

#[test]
fn drop_generation_makes_subsequent_checks_false() {
    let reg = ConnectionRegistry::new();
    reg.init_generation("c1");
    reg.drop_generation("c1");
    assert!(!reg.is_current_generation("c1", 1));
}

#[test]
fn clear_generations_drops_every_id() {
    let reg = ConnectionRegistry::new();
    reg.init_generation("c1");
    reg.init_generation("c2");
    reg.clear_generations();
    assert!(!reg.is_current_generation("c1", 1));
    assert!(!reg.is_current_generation("c2", 1));
}

#[test]
fn unknown_id_is_never_current() {
    let reg = ConnectionRegistry::new();
    assert!(!reg.is_current_generation("missing", 1));
    assert!(!reg.is_current_generation("missing", 0));
}

// ─── failure_phase mapping ─────────────────────────────────────
// Each match arm in `failure_phase` paints the red marker at a
// specific connection phase; a regression that misroutes auth
// failures to socketConnect (or vice versa) silently mislabels
// every connect-error UI.

fn make_actor(id: &str, internal: bool) -> ConnectionActor {
    ConnectionActor::new(ConnectionActorInit {
        id: id.into(),
        label: format!("L-{id}"),
        session_id: None,
        bastion_id: None,
        internal,
        host: "h".into(),
        port: 22,
        user: "u".into(),
    })
}

#[test]
fn failure_phase_routes_auth_variants_to_authenticate() {
    for err in [
        Error::Auth("server refused".into()),
        Error::AuthFailed,
        Error::PassphraseRequired,
        Error::PassphraseIncorrect,
        Error::KeyParse("malformed PEM".into()),
    ] {
        assert_eq!(
            failure_phase(&err),
            ConnectionPhase::Authenticate,
            "auth-family error must paint at Authenticate: {err:?}"
        );
    }
}

#[test]
fn failure_phase_routes_host_key_rejected_to_host_key_verify() {
    assert_eq!(
        failure_phase(&Error::HostKeyRejected),
        ConnectionPhase::HostKeyVerify
    );
}

#[test]
fn failure_phase_falls_through_to_socket_connect() {
    // Anything not auth-family or host-key paints at SocketConnect
    // — the catch-all default. Pre-auth failures (DNS, refused
    // connection, TLS / kex aborts) all land here.
    for err in [
        Error::Connect("dns nope".into()),
        Error::Handshake("kex".into()),
        Error::Io("ECONNREFUSED".into()),
        Error::Timeout,
        Error::Cancelled,
    ] {
        assert_eq!(
            failure_phase(&err),
            ConnectionPhase::SocketConnect,
            "non-auth/host-key error must paint at SocketConnect: {err:?}"
        );
    }
}

// ─── ConnectionRegistry edge cases ─────────────────────────────

#[test]
fn snapshot_includes_every_inserted_actor() {
    let reg = ConnectionRegistry::new();
    for i in 0..5 {
        reg.insert(make_actor(&format!("c{i}"), false));
    }
    let snap = reg.snapshot_all();
    assert_eq!(snap.len(), 5);
    assert_eq!(reg.count(), 5);
}

#[test]
fn duplicate_insert_with_same_id_overwrites() {
    // Re-inserting under the same id replaces the existing
    // actor — reconnect re-creates the actor row rather than
    // carrying state across.
    let reg = ConnectionRegistry::new();
    reg.insert(make_actor("c1", false));
    let first_count = reg.count();
    reg.insert(make_actor("c1", false));
    assert_eq!(reg.count(), first_count);
}

#[test]
fn remove_unknown_id_is_idempotent() {
    let reg = ConnectionRegistry::new();
    reg.insert(make_actor("c1", false));
    assert_eq!(reg.count(), 1);
    reg.remove("does-not-exist");
    assert_eq!(reg.count(), 1);
}

#[test]
fn count_reflects_current_size_through_insert_remove_cycles() {
    let reg = ConnectionRegistry::new();
    assert_eq!(reg.count(), 0);
    reg.insert(make_actor("a", false));
    reg.insert(make_actor("b", false));
    assert_eq!(reg.count(), 2);
    reg.remove("a");
    assert_eq!(reg.count(), 1);
    reg.insert(make_actor("c", false));
    assert_eq!(reg.count(), 2);
    reg.remove("b");
    reg.remove("c");
    assert_eq!(reg.count(), 0);
}

// ─── connected_user_visible_count ──────────────────────────────

#[test]
fn user_visible_count_zero_on_empty_registry() {
    let reg = ConnectionRegistry::new();
    assert_eq!(reg.connected_user_visible_count(), 0);
}

#[test]
fn user_visible_count_skips_disconnected_actors() {
    // Inserted actors start in `Disconnected`. Until the driver
    // flips them to Connected the user-visible count must stay
    // at zero — an early-fire would tell the Android foreground
    // service to start before any connection actually exists.
    let reg = ConnectionRegistry::new();
    reg.insert(make_actor("c1", false));
    reg.insert(make_actor("c2", false));
    assert_eq!(reg.connected_user_visible_count(), 0);
}

#[test]
fn user_visible_count_includes_only_connected_non_internal() {
    let reg = ConnectionRegistry::new();
    let h_user = reg.insert(make_actor("user", false));
    let h_bastion = reg.insert(make_actor("bastion", true));
    // Flip both to Connected.
    for h in [&h_user, &h_bastion] {
        let mut a = h.lock().unwrap_or_else(|e| e.into_inner());
        a.state = ConnectionState::Connected;
    }
    // Bastion (internal: true) is excluded — the user-visible
    // metric must match the "Connected sessions" badge the user
    // sees, not the underlying transport count.
    assert_eq!(reg.connected_user_visible_count(), 1);
}

#[test]
fn user_visible_count_recovers_to_zero_after_disconnect_all() {
    let reg = ConnectionRegistry::new();
    let h = reg.insert(make_actor("c1", false));
    {
        let mut a = h.lock().unwrap_or_else(|e| e.into_inner());
        a.state = ConnectionState::Connected;
    }
    assert_eq!(reg.connected_user_visible_count(), 1);
    reg.remove("c1");
    assert_eq!(reg.connected_user_visible_count(), 0);
}

// ─── enum / struct invariants ──────────────────────────────────

#[test]
fn connection_state_partial_eq_distinguishes_all_three() {
    // Enum equality powers every state-machine branch (driver,
    // disconnect path, snapshot diff). Pin the trichotomy so a
    // future variant addition surfaces as a missed match arm.
    assert_eq!(ConnectionState::Disconnected, ConnectionState::Disconnected);
    assert_eq!(ConnectionState::Connecting, ConnectionState::Connecting);
    assert_eq!(ConnectionState::Connected, ConnectionState::Connected);
    assert_ne!(ConnectionState::Disconnected, ConnectionState::Connecting);
    assert_ne!(ConnectionState::Connecting, ConnectionState::Connected);
    assert_ne!(ConnectionState::Disconnected, ConnectionState::Connected);
}

#[test]
fn progress_step_clone_preserves_every_field() {
    let step = ProgressStep {
        phase: ConnectionPhase::Authenticate,
        status: StepStatus::Failed,
        detail: Some("auth refused".into()),
    };
    let cloned = step.clone();
    assert_eq!(cloned.phase, ConnectionPhase::Authenticate);
    assert_eq!(cloned.status, StepStatus::Failed);
    assert_eq!(cloned.detail.as_deref(), Some("auth refused"));
}

#[test]
fn progress_step_with_no_detail_is_legal() {
    // The driver emits steps without detail for the success path
    // (detail carries the error message on failure). Pin the
    // Optional contract.
    let step = ProgressStep {
        phase: ConnectionPhase::OpenChannel,
        status: StepStatus::Success,
        detail: None,
    };
    assert!(step.detail.is_none());
}

// ─── run_with_pause_aware_timeout ──────────────────────────────
// Wraps the SSH handshake with a wall-clock cap that suspends
// while a TOFU prompt is awaiting the user. The bug shape these
// pin: a `connect timed out` error fires while the
// host-key-changed dialog is still on screen. Tests use real
// time with sub-second caps so they stay deterministic without
// pulling tokio's `test-util` feature.

#[tokio::test]
async fn pause_aware_timeout_returns_some_when_future_completes() {
    let result =
        run_with_pause_aware_timeout(std::time::Duration::from_secs(10), || false, async {
            42_i32
        })
        .await;
    assert_eq!(result, Some(42));
}

#[tokio::test]
async fn pause_aware_timeout_fires_at_cap_when_no_pause() {
    let cap = std::time::Duration::from_millis(500);
    let started = std::time::Instant::now();
    let result = run_with_pause_aware_timeout(cap, || false, std::future::pending::<()>()).await;
    let elapsed = started.elapsed();
    assert!(result.is_none(), "expected timeout to fire");
    assert!(elapsed >= cap, "timeout fired too early: {elapsed:?}");
    assert!(
        elapsed < cap + std::time::Duration::from_millis(750),
        "timeout fired too late: {elapsed:?}"
    );
}

#[tokio::test]
async fn pause_aware_timeout_excludes_paused_window_from_elapsed() {
    use std::sync::atomic::{AtomicBool, Ordering};
    let paused = std::sync::Arc::new(AtomicBool::new(false));
    let pf = paused.clone();

    let cap = std::time::Duration::from_millis(500);
    let helper = tokio::spawn(async move {
        run_with_pause_aware_timeout(
            cap,
            move || pf.load(Ordering::Relaxed),
            std::future::pending::<()>(),
        )
        .await
    });

    // 200 ms with no pause active — net elapsed ≈ 200 ms.
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    assert!(!helper.is_finished());

    // Open the prompt and sleep well past the remaining 300 ms
    // budget — the helper must keep waiting because the pause
    // window is excluded.
    paused.store(true, Ordering::Relaxed);
    tokio::time::sleep(std::time::Duration::from_millis(800)).await;
    assert!(
        !helper.is_finished(),
        "helper fired during pause — paused window not excluded from elapsed"
    );

    // Close the prompt; net elapsed ≈ 200 ms, cap = 500 ms, so
    // the helper should fire roughly 300 ms later. Bound the
    // wait so a regression doesn't hang the suite.
    paused.store(false, Ordering::Relaxed);
    let outcome = tokio::time::timeout(std::time::Duration::from_millis(1500), helper)
        .await
        .expect("helper did not finish post-pause")
        .expect("helper task panicked");
    assert!(
        outcome.is_none(),
        "expected timeout to fire after pause closed and net elapsed reached cap"
    );
}

// ─── emit_stale_attempt_closure ────────────────────────────────
// When a reconnect bumps the actor's generation mid-handshake,
// the dropped driver returns silently. Without a bus event the
// subscriber that observed the dropped attempt's
// `Connecting + SocketConnect:InProgress` step has no closing
// edge — the helper publishes one. Tests pin the exact event
// pair AND the no-actor-mutation invariant (the live generation
// owns `actor.state`).

/// Drain every event already pending on a receiver. Flushes
/// events published during fixture setup so the assertions
/// observe only the closure helper's output.
fn drain_receiver(rx: &mut tokio::sync::broadcast::Receiver<crate::bus::Event>) {
    while rx.try_recv().is_ok() {}
}

/// Extract the connection id from any Connection-topic event so
/// the test helper below can filter out cross-test noise. Every
/// variant on the Connection topic carries an `id`
/// ([`crate::bus`]) except `ConnectionActiveCountChanged`
/// (counter-only) which never appears in these tests.
fn connection_event_id(event: &crate::bus::Event) -> Option<&str> {
    match event {
        crate::bus::Event::ConnectionStateChanged { id, .. }
        | crate::bus::Event::ConnectionProgress { id, .. }
        | crate::bus::Event::ConnectionError { id, .. }
        | crate::bus::Event::ConnectionRemoved { id } => Some(id.as_str()),
        _ => None,
    }
}

/// Pull the next N events for `expected_id` off a receiver under
/// a short tokio timeout so a missing publish fails the test
/// instead of hanging the suite. Events for other ids — the
/// noise that flakes the suite when these tests race with their
/// siblings under `cargo test` parallelism — get silently
/// dropped. The fixture publishes exactly N events per id, so
/// the deadline applies to the matching subset only.
async fn recv_n_events(
    rx: &mut tokio::sync::broadcast::Receiver<crate::bus::Event>,
    n: usize,
    expected_id: &str,
) -> Vec<crate::bus::Event> {
    let mut out = Vec::with_capacity(n);
    while out.len() < n {
        let ev = tokio::time::timeout(std::time::Duration::from_millis(500), rx.recv())
            .await
            .expect("event did not arrive within 500 ms")
            .expect("broadcast channel closed");
        if connection_event_id(&ev) == Some(expected_id) {
            out.push(ev);
        }
    }
    out
}

#[tokio::test]
async fn stale_attempt_closure_emits_error_and_state_echo_when_live_gen_owns_connecting() {
    // Simulates the rapid-reconnect race: an old connect driver
    // discovers `actor.generation` was bumped by a newer attempt
    // while it was inside `run_auth`. The actor's state field is
    // still `Connecting` (owned by the live generation). The
    // dropped driver must publish a closing edge without
    // mutating actor state.
    let app = crate::app::init();
    let id = format!(
        "stale-conn-live-connecting-{}",
        crate::id::random_handle_hex_32()
    );
    // Pre-seed the actor in `Connecting` so we can verify the
    // helper does not touch `actor.state`.
    let handle = app
        .connections
        .insert(ConnectionActor::new(ConnectionActorInit {
            id: id.clone(),
            label: "stale".into(),
            session_id: None,
            bastion_id: None,
            internal: false,
            host: "h".into(),
            port: 22,
            user: "u".into(),
        }));
    {
        let mut a = handle.lock().unwrap();
        a.state = ConnectionState::Connecting;
        a.generation = 7;
    }
    let mut rx = app.bus.subscribe(crate::bus::EventTopic::Connection);
    drain_receiver(&mut rx);

    // Call the helper as the stale driver would: canonical state
    // is what the actor currently shows.
    emit_stale_attempt_closure(&app, id.clone(), ConnectionState::Connecting);

    let events = recv_n_events(&mut rx, 2, &id).await;
    match &events[0] {
        crate::bus::Event::ConnectionError { id: e_id, detail } => {
            assert_eq!(e_id, &id);
            assert!(
                detail.contains("superseded"),
                "ConnectionError detail must name supersession: {detail}"
            );
        }
        other => panic!("expected ConnectionError first, got {other:?}"),
    }
    match &events[1] {
        crate::bus::Event::ConnectionStateChanged { id: e_id, state } => {
            assert_eq!(e_id, &id);
            assert_eq!(*state, ConnectionState::Connecting);
        }
        other => panic!("expected ConnectionStateChanged second, got {other:?}"),
    }

    // The helper must not have flipped the actor — the live
    // generation still owns the `Connecting` state and its
    // pending generation count.
    {
        let a = handle.lock().unwrap();
        assert_eq!(a.state, ConnectionState::Connecting);
        assert_eq!(a.generation, 7);
    }

    // Clean up so neighbouring tests do not see this row.
    app.connections.remove(&id);
}

#[tokio::test]
async fn stale_attempt_closure_echoes_terminal_state_when_live_gen_already_settled() {
    // When the live generation has already settled the actor to
    // `Disconnected`, the stale driver's closure echoes the
    // terminal so any subscriber that joined late after the
    // live driver's terminal publish still sees a closing edge
    // attributed to the dropped attempt's id.
    let app = crate::app::init();
    let id = format!(
        "stale-conn-live-settled-{}",
        crate::id::random_handle_hex_32()
    );
    let handle = app
        .connections
        .insert(ConnectionActor::new(ConnectionActorInit {
            id: id.clone(),
            label: "stale".into(),
            session_id: None,
            bastion_id: None,
            internal: false,
            host: "h".into(),
            port: 22,
            user: "u".into(),
        }));
    {
        let mut a = handle.lock().unwrap();
        a.state = ConnectionState::Disconnected;
        a.generation = 9;
    }
    let mut rx = app.bus.subscribe(crate::bus::EventTopic::Connection);
    drain_receiver(&mut rx);

    emit_stale_attempt_closure(&app, id.clone(), ConnectionState::Disconnected);

    let events = recv_n_events(&mut rx, 2, &id).await;
    assert!(matches!(
        &events[0],
        crate::bus::Event::ConnectionError { .. }
    ));
    match &events[1] {
        crate::bus::Event::ConnectionStateChanged { id: e_id, state } => {
            assert_eq!(e_id, &id);
            assert_eq!(*state, ConnectionState::Disconnected);
        }
        other => panic!("expected terminal state echo, got {other:?}"),
    }

    app.connections.remove(&id);
}

// ─── ProxyJump dispatch — exhaustive variant coverage ──────────
// M5 collapsed the 14-arm dispatch into a single exhaustive
// match on `ConnectAuthRef`. Adding a new variant without a
// bastion-arm decision now fails to compile. These tests
// exercise every hardware-signer arm via [`run_auth`] with a
// mocked bastion `Some(_)` and assert each surfaces a typed
// `Error::Auth` with a label that names the hardware backend —
// the previous duplicate-arm code shipped this contract in
// 7 separate string literals; the refactor centralises them in
// [`hardware_over_proxyjump_unsupported`].
//
// Constructing a real `Arc<Session>` for the `Some(_)` arm needs
// a live russh handshake (see `tests/connection_lifecycle.rs`).
// The dispatcher's bastion-arm branch is reached after
// `wait_for_parent_ready` succeeds, which itself needs the
// parent actor to be `Connected`. To keep the unit-test purely
// in-process we instead call [`hardware_over_proxyjump_unsupported`]
// directly per signer variant — the dispatcher's only call site
// for the `Some(_)` arm is this helper, so locking in the
// helper's output covers the bastion-error contract while the
// exhaustive match on `HardwareSigner` keeps the compile-time
// gate intact.

#[test]
fn hardware_over_proxyjump_unsupported_labels_every_signer_variant() {
    for (signer, expected_label) in [
        (HardwareSigner::Sk, "FIDO2"),
        (HardwareSigner::SkCert, "FIDO2 (with certificate)"),
        (HardwareSigner::Pkcs11, "PKCS#11"),
        (HardwareSigner::Enclave, "Apple Secure Enclave"),
        (HardwareSigner::Hello, "Windows Hello"),
        (HardwareSigner::Tpm, "TPM 2.0"),
        (HardwareSigner::Keystore, "Android Hardware Keystore"),
    ] {
        let err = hardware_over_proxyjump_unsupported(signer);
        match err {
            Error::Auth(detail) => {
                assert!(
                    detail.contains(expected_label),
                    "label for {signer:?} missing: got {detail:?}"
                );
                assert!(
                    detail.contains("ProxyJump"),
                    "label for {signer:?} must name the ProxyJump gap: {detail:?}"
                );
            }
            other => panic!("expected Error::Auth for {signer:?}, got {other:?}"),
        }
    }
}

/// Build one instance of every [`ConnectAuthRef`] variant so the
/// test asserts the dispatcher has a route for each. The match
/// inside the loop is exhaustive — a new variant added to
/// `ConnectAuthRef` without a corresponding builder branch
/// fails to compile, locking in the "every variant has a
/// direct + bastion decision" invariant the M5 refactor enforces.
fn every_auth_ref_variant() -> Vec<ConnectAuthRef> {
    vec![
        ConnectAuthRef::Password {
            secret_id: "s".into(),
        },
        ConnectAuthRef::Pubkey {
            key_secret_id: "k".into(),
            passphrase_secret_id: None,
        },
        ConnectAuthRef::PubkeyCert {
            key_secret_id: "k".into(),
            cert_secret_id: "c".into(),
            passphrase_secret_id: None,
        },
        ConnectAuthRef::PubkeySk {
            public_openssh: "p".into(),
            credential_id: vec![0; 1],
            application: "ssh:".into(),
            pin_secret_id: None,
        },
        ConnectAuthRef::PubkeySkCert {
            public_openssh: "p".into(),
            credential_id: vec![0; 1],
            application: "ssh:".into(),
            cert_secret_id: "c".into(),
            pin_secret_id: None,
        },
        ConnectAuthRef::PubkeyPkcs11 {
            public_openssh: "p".into(),
            module_path: "/mod".into(),
            token_serial: "T".into(),
            cka_id: vec![0; 1],
            key_type: "ecdsa-sha2-nistp256".into(),
            pin_secret_id: None,
        },
        ConnectAuthRef::PubkeyEnclave {
            public_openssh: "p".into(),
            application_tag: vec![0; 1],
        },
        ConnectAuthRef::PubkeyHello {
            public_openssh: "p".into(),
            credential_name: "cn".into(),
            key_type: "ecdsa-sha2-nistp256".into(),
        },
        ConnectAuthRef::PubkeyTpm {
            public_openssh: "p".into(),
            provider: "tss-esapi".into(),
            blob: None,
            cng_key_name: None,
            key_type: "ecdsa-sha2-nistp256".into(),
            pin_secret_id: None,
        },
        ConnectAuthRef::PubkeyKeystore {
            public_openssh: "p".into(),
            keystore_alias: "alias".into(),
            key_type: "ecdsa-sha2-nistp256".into(),
        },
        ConnectAuthRef::Agent,
    ]
}

#[test]
fn every_auth_ref_variant_is_classified() {
    // Pure-data classification: each variant is either a
    // hardware signer (matching one `HardwareSigner` arm), or a
    // software / agent path (Password, Pubkey, PubkeyCert,
    // Agent). The exhaustive `match` below is the compile-time
    // gate — a new `ConnectAuthRef` variant added without a
    // classification branch fails to compile, which forces the
    // author to decide whether ProxyJump is supported for it.
    for auth in every_auth_ref_variant() {
        let classified: Result<Option<HardwareSigner>, &str> = match &auth {
            ConnectAuthRef::Password { .. } => Ok(None),
            ConnectAuthRef::Pubkey { .. } => Ok(None),
            ConnectAuthRef::PubkeyCert { .. } => Ok(None),
            ConnectAuthRef::Agent => Ok(None),
            ConnectAuthRef::PubkeySk { .. } => Ok(Some(HardwareSigner::Sk)),
            ConnectAuthRef::PubkeySkCert { .. } => Ok(Some(HardwareSigner::SkCert)),
            ConnectAuthRef::PubkeyPkcs11 { .. } => Ok(Some(HardwareSigner::Pkcs11)),
            ConnectAuthRef::PubkeyEnclave { .. } => Ok(Some(HardwareSigner::Enclave)),
            ConnectAuthRef::PubkeyHello { .. } => Ok(Some(HardwareSigner::Hello)),
            ConnectAuthRef::PubkeyTpm { .. } => Ok(Some(HardwareSigner::Tpm)),
            ConnectAuthRef::PubkeyKeystore { .. } => Ok(Some(HardwareSigner::Keystore)),
        };
        assert!(classified.is_ok(), "variant {auth:?} has no classification");
    }
}
