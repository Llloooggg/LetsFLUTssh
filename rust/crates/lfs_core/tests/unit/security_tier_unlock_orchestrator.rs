/// Unit tests extracted from security/tier_unlock_orchestrator.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::security::tier_machine::{instance, TierState};

/// All three tests in this module mutate the process-singleton
/// tier-machine + rate-limiter registry. cargo's default
/// multi-threaded test runner would interleave dispatches and
/// race assertions; serialise here so each scenario sees a
/// quiescent global state. Parallelism stays on for the rest
/// of the suite.
///
/// Uses `tokio::sync::Mutex` (not `std::sync::Mutex`) so the
/// async tests can hold the guard across `.await` without
/// tripping the `await_holding_lock` clippy lint.
fn serial_mutex() -> &'static tokio::sync::Mutex<()> {
    crate::app::test_serial_lock()
}

#[test]
fn unlock_plaintext_self_advances_to_unlocked() {
    // Sync test — `blocking_lock` against the tokio Mutex
    // since we don't have an async runtime here.
    let _guard = serial_mutex().blocking_lock();
    // Drive the singleton through the cascade. Other tests
    // in this binary touch the same singleton so we don't
    // assert from any starting state — only that the final
    // state is Unlocked under the Plaintext tier.
    let _ = crate::app::init();
    unlock_plaintext();
    let m = instance();
    let g = m.lock().unwrap_or_else(|e| e.into_inner());
    assert_eq!(g.state(), TierState::Unlocked);
    assert_eq!(g.tier(), SecurityTier::Plaintext);
}

/// Bypass-prevention regression: when the in-memory limiter
/// for `tier_unlock.keychain_with_password` is locked, the
/// orchestrator must short-circuit to `WrongSecret` before
/// it ever calls into `pinned_support_dir()` (which would
/// panic in tests because no support dir is pinned). If the
/// rate-limit gate ever regresses out of the orchestrator,
/// this test panics on the missing pin instead of returning
/// `WrongSecret`.
#[tokio::test]
async fn unlock_keychain_with_password_short_circuits_when_limiter_locked() {
    let _guard = serial_mutex().lock().await;
    let _ = crate::app::init();
    let limiters = &crate::app::instance().rate_limiters;

    // Drive enough record_failure calls to exhaust the
    // backoff schedule (10 entries; index >=1 arms a non-
    // zero cooldown, so a single failure is enough). Use
    // a fresh id-suffix to avoid bleed between tests in
    // this binary.
    for _ in 0..crate::rate_limit::BACKOFF_SCHEDULE.len() {
        limiters.record_failure(KEYCHAIN_PW_UNLOCK_LIMITER_ID);
    }
    assert!(
        limiters.status(KEYCHAIN_PW_UNLOCK_LIMITER_ID).is_locked(),
        "limiter must be locked before invoking the orchestrator"
    );

    let outcome = unlock_keychain_with_password("any-wrong-password".into()).await;
    assert_eq!(outcome, UnlockOutcome::WrongSecret);

    // Cleanup so subsequent tests in this binary that touch
    // the T1+pw limiter start fresh.
    limiters.record_success(KEYCHAIN_PW_UNLOCK_LIMITER_ID);
}

/// Mirror of the above for the Paranoid tier. Argon2id is
/// the only attacker brake without the limiter; if the
/// `is_locked` short-circuit regresses, this test would
/// pay the KDF cost (or panic on missing pinned support_dir),
/// neither of which is `WrongSecret` returning fast.
#[tokio::test]
async fn unlock_paranoid_short_circuits_when_limiter_locked() {
    let _guard = serial_mutex().lock().await;
    let _ = crate::app::init();
    let limiters = &crate::app::instance().rate_limiters;

    for _ in 0..crate::rate_limit::BACKOFF_SCHEDULE.len() {
        limiters.record_failure(PARANOID_UNLOCK_LIMITER_ID);
    }
    assert!(
        limiters.status(PARANOID_UNLOCK_LIMITER_ID).is_locked(),
        "Paranoid limiter must be locked before invoking the orchestrator"
    );

    let started = std::time::Instant::now();
    let outcome = unlock_paranoid("any-wrong-password".into()).await;
    let elapsed = started.elapsed();
    assert_eq!(outcome, UnlockOutcome::WrongSecret);
    // Belt-and-braces — Argon2id at production params costs
    // 400-1500 ms; a short-circuit returns in <10 ms. If we
    // somehow took the verify path despite the lock, the
    // wall-clock would expose it even before the missing-pin
    // panic surfaces.
    assert!(
        elapsed < std::time::Duration::from_millis(100),
        "short-circuit took too long: {elapsed:?}"
    );

    limiters.record_success(PARANOID_UNLOCK_LIMITER_ID);
}

/// `unlock_hardware(empty)` must surface a typed error before
/// the prompt registry fires — the Hardware tier is always
/// password-gated and an empty string means the caller never
/// collected a secret. The signature requires `String`, so
/// "no secret at all" can't even be expressed at the type
/// level; the empty-string check guards the legacy
/// FRB-shim wire shape that round-trips through a `String`
/// container.
#[tokio::test]
async fn unlock_hardware_empty_password_returns_typed_error() {
    let _guard = serial_mutex().lock().await;
    let _ = crate::app::init();
    let limiters = &crate::app::instance().rate_limiters;
    // Reset the limiter so prior tests in this binary do not
    // mask the short-circuit assertion.
    limiters.record_success(HARDWARE_UNLOCK_LIMITER_ID);

    let outcome = unlock_hardware(String::new()).await;
    match outcome {
        UnlockOutcome::PluginError(code) => {
            assert_eq!(code, "hardware_password_required");
        }
        other => panic!("expected PluginError(hardware_password_required), got {other:?}"),
    }
}

/// Bus contract: the orchestrator publishes
/// `BusEvent::UnlockCascadeReady { tier_wire, has_key }` AFTER
/// the existing `TierStateChanged.unlocked` event so the Dart
/// listener subscribes to a single payload instead of probing
/// the tier machine + secret store directly. Plaintext is the
/// simplest path to exercise without a real keychain / hardware
/// vault — every cascade-bearing tier shares the same helper.
#[tokio::test]
async fn unlock_plaintext_publishes_cascade_ready_event() {
    let _guard = serial_mutex().lock().await;
    let app = crate::app::init();
    let mut rx = app.bus.subscribe(crate::bus::EventTopic::Tier);
    unlock_plaintext();

    // Walk the topic stream until we see the cascade-ready
    // event. The orchestrator also publishes the
    // intermediate `TierStateChanged.{unlocking,unlocked}`
    // transitions on the same channel; we ignore them and
    // assert only on the new variant.
    let deadline = std::time::Duration::from_secs(2);
    let event = tokio::time::timeout(deadline, async {
        loop {
            match rx.recv().await {
                Ok(Event::UnlockCascadeReady { tier_wire, has_key }) => {
                    return (tier_wire, has_key);
                }
                Ok(_) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(e) => panic!("recv error: {e:?}"),
            }
        }
    })
    .await
    .expect("cascade event must fire within 2s");

    assert_eq!(
        event.0, "plaintext",
        "tier_wire must mirror the unlocked tier"
    );
    // Plaintext stages an empty buffer; the slot is still
    // present so the probe-shape `has_key` follows
    // `secrets_has(ACTIVE_DBKEY_SECRET_ID)` semantics — true
    // when the entry exists at all, empty or not.
    assert!(event.1, "has_key must reflect the staged slot probe");
}
