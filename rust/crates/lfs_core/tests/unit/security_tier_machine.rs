/// Unit tests extracted from security/tier_machine.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn fail() -> TierEvent {
    TierEvent::UnlockFailed {
        reason: UnlockFailureReason::WrongSecret,
    }
}

// ── Transition table coverage ──────────────────────────────

#[test]
fn locked_unlock_requested_moves_to_unlocking() {
    assert_eq!(
        next_state(TierState::Locked, &TierEvent::UnlockRequested),
        Some(TierState::Unlocking),
    );
}

#[test]
fn locked_wiped_moves_to_wiping() {
    assert_eq!(
        next_state(TierState::Locked, &TierEvent::Wiped),
        Some(TierState::Wiping),
    );
}

#[test]
fn locked_drops_unlock_succeeded_unlock_failed_lock_requested() {
    // Defensive: the bootstrap path may legitimately fire
    // these spuriously after a tier-transition crash. The
    // table drops them rather than wedging the machine.
    assert_eq!(
        next_state(TierState::Locked, &TierEvent::UnlockSucceeded),
        None,
    );
    assert_eq!(next_state(TierState::Locked, &fail()), None);
    assert_eq!(
        next_state(TierState::Locked, &TierEvent::LockRequested),
        None,
    );
}

#[test]
fn unlocking_succeeded_moves_to_unlocked() {
    assert_eq!(
        next_state(TierState::Unlocking, &TierEvent::UnlockSucceeded),
        Some(TierState::Unlocked),
    );
}

#[test]
fn unlocking_failed_falls_back_to_locked() {
    assert_eq!(
        next_state(TierState::Unlocking, &fail()),
        Some(TierState::Locked),
    );
}

#[test]
fn unlocking_lock_requested_falls_back_to_locked() {
    // Race: user dismissed unlock dialog while auto-lock
    // timer fired. Defensive — drop to locked rather than
    // wedging in Unlocking.
    assert_eq!(
        next_state(TierState::Unlocking, &TierEvent::LockRequested),
        Some(TierState::Locked),
    );
}

#[test]
fn unlocking_drops_unlock_requested_repeat() {
    // User double-tapped the unlock button — the second
    // request is a no-op, the in-flight prompt resolves.
    assert_eq!(
        next_state(TierState::Unlocking, &TierEvent::UnlockRequested),
        None,
    );
}

#[test]
fn unlocked_lock_requested_moves_to_locked() {
    assert_eq!(
        next_state(TierState::Unlocked, &TierEvent::LockRequested),
        Some(TierState::Locked),
    );
}

#[test]
fn unlocked_wiped_moves_to_wiping() {
    assert_eq!(
        next_state(TierState::Unlocked, &TierEvent::Wiped),
        Some(TierState::Wiping),
    );
}

#[test]
fn unlocked_drops_unlock_events() {
    assert_eq!(
        next_state(TierState::Unlocked, &TierEvent::UnlockRequested),
        None,
    );
    assert_eq!(
        next_state(TierState::Unlocked, &TierEvent::UnlockSucceeded),
        None,
    );
    assert_eq!(next_state(TierState::Unlocked, &fail()), None);
}

#[test]
fn wiping_is_terminal() {
    // Every event from Wiping returns None — the only legal
    // exit is process restart, which constructs a fresh
    // Machine in Locked against the post-wipe empty support
    // dir. Property test: no event escapes the terminal
    // state.
    for event in [
        TierEvent::UnlockRequested,
        TierEvent::UnlockSucceeded,
        fail(),
        TierEvent::LockRequested,
        TierEvent::Wiped,
    ] {
        assert_eq!(
            next_state(TierState::Wiping, &event),
            None,
            "wiping must drop {event:?}",
        );
    }
}

// ── Machine handle ────────────────────────────────────────

#[test]
fn machine_starts_locked_in_supplied_tier() {
    let m = Machine::new(SecurityTier::Hardware);
    assert_eq!(m.state(), TierState::Locked);
    assert_eq!(m.tier(), SecurityTier::Hardware);
}

#[test]
fn machine_dispatch_advances_state_on_valid_event() {
    let mut m = Machine::new(SecurityTier::Plaintext);
    let next = m.dispatch(&TierEvent::UnlockRequested);
    assert_eq!(next, Some(TierState::Unlocking));
    assert_eq!(m.state(), TierState::Unlocking);
}

#[test]
fn machine_dispatch_returns_none_on_invalid_event() {
    let mut m = Machine::new(SecurityTier::Plaintext);
    // Locked + UnlockSucceeded = invalid (defensive drop).
    let result = m.dispatch(&TierEvent::UnlockSucceeded);
    assert_eq!(result, None);
    // State unchanged.
    assert_eq!(m.state(), TierState::Locked);
}

#[test]
fn machine_full_unlock_cycle() {
    let mut m = Machine::new(SecurityTier::Keychain);
    m.dispatch(&TierEvent::UnlockRequested).unwrap();
    m.dispatch(&TierEvent::UnlockSucceeded).unwrap();
    assert_eq!(m.state(), TierState::Unlocked);
    m.dispatch(&TierEvent::LockRequested).unwrap();
    assert_eq!(m.state(), TierState::Locked);
}

#[test]
fn machine_failed_unlock_falls_back_to_locked() {
    let mut m = Machine::new(SecurityTier::Paranoid);
    m.dispatch(&TierEvent::UnlockRequested).unwrap();
    m.dispatch(&fail()).unwrap();
    assert_eq!(m.state(), TierState::Locked);
}

#[test]
fn try_advance_plaintext_self_advances_to_unlocked() {
    let mut m = Machine::new(SecurityTier::Plaintext);
    m.dispatch(&TierEvent::UnlockRequested).unwrap();
    assert_eq!(m.state(), TierState::Unlocking);
    let next = m.try_advance().unwrap();
    assert_eq!(next, TierState::Unlocked);
    assert_eq!(m.state(), TierState::Unlocked);
}

#[test]
fn try_advance_other_tiers_waits_for_handler() {
    for tier in [
        SecurityTier::Keychain,
        SecurityTier::Hardware,
        SecurityTier::Paranoid,
    ] {
        let mut m = Machine::new(tier);
        m.dispatch(&TierEvent::UnlockRequested).unwrap();
        assert_eq!(m.state(), TierState::Unlocking);
        // Non-plaintext tiers stay in Unlocking — the per-tier
        // handler resolves through the typed prompt registry
        // later.
        assert_eq!(m.try_advance(), None);
        assert_eq!(m.state(), TierState::Unlocking);
    }
}

#[test]
fn try_advance_outside_unlocking_is_noop() {
    // From Locked / Unlocked / Wiping there's nothing to
    // advance from — the function returns None without
    // mutating state.
    let mut m = Machine::new(SecurityTier::Plaintext);
    assert_eq!(m.try_advance(), None);
    assert_eq!(m.state(), TierState::Locked);

    m.dispatch(&TierEvent::UnlockRequested).unwrap();
    m.dispatch(&TierEvent::UnlockSucceeded).unwrap();
    assert_eq!(m.state(), TierState::Unlocked);
    assert_eq!(m.try_advance(), None);
    assert_eq!(m.state(), TierState::Unlocked);
}

#[test]
fn machine_set_tier_swaps_active_tier_without_state_change() {
    // Wizard / settings tier change does not move state on
    // its own — the caller fires `UnlockRequested` separately
    // when ready.
    let mut m = Machine::new(SecurityTier::Plaintext);
    m.set_tier(SecurityTier::Hardware);
    assert_eq!(m.tier(), SecurityTier::Hardware);
    assert_eq!(m.state(), TierState::Locked);
}

#[test]
fn unlock_failure_reasons_carry_detail() {
    // Property: every UnlockFailed reason variant is
    // distinguishable so the UI can pick the right copy.
    let wrong = TierEvent::UnlockFailed {
        reason: UnlockFailureReason::WrongSecret,
    };
    let plugin = TierEvent::UnlockFailed {
        reason: UnlockFailureReason::PluginUnavailable {
            code: "linux_device_missing".into(),
        },
    };
    let cancelled = TierEvent::UnlockFailed {
        reason: UnlockFailureReason::UserCancelled,
    };
    let corrupt = TierEvent::UnlockFailed {
        reason: UnlockFailureReason::Corruption {
            detail: "kdf record HMAC mismatch".into(),
        },
    };
    // All four are distinct events for transition purposes
    // (table can later branch on reason without changing the
    // state graph).
    assert_ne!(wrong, plugin);
    assert_ne!(plugin, cancelled);
    assert_ne!(cancelled, corrupt);
    assert_ne!(corrupt, wrong);
}
