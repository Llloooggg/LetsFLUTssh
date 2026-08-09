/// Unit tests extracted from transfer_conflict.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn dec(action: ConflictAction, all: bool) -> ConflictDecision {
    ConflictDecision {
        action,
        apply_to_all: all,
    }
}

#[test]
fn fresh_state_has_no_cache_and_is_not_cancelled() {
    let s = BatchState::default();
    assert!(s.cached().is_none());
    assert!(!s.is_cancelled());
}

#[test]
fn record_decision_returns_the_action_when_apply_to_all_is_false() {
    let mut s = BatchState::default();
    let result = s.record_decision(dec(ConflictAction::Skip, false));
    assert_eq!(result, ConflictAction::Skip);
    // Not cached when apply_to_all is false.
    assert!(s.cached().is_none());
}

#[test]
fn record_decision_caches_action_when_apply_to_all_is_true() {
    let mut s = BatchState::default();
    s.record_decision(dec(ConflictAction::Replace, true));
    assert_eq!(s.cached(), Some(ConflictAction::Replace));
}

#[test]
fn record_decision_cancel_sets_cancelled_flag_and_skips_caching() {
    let mut s = BatchState::default();
    // `apply_to_all=true` on a cancel must NOT cache `Cancel`
    // as the per-row action — cancellation already short-
    // circuits future calls.
    s.record_decision(dec(ConflictAction::Cancel, true));
    assert!(s.is_cancelled());
    assert!(s.cached().is_none());
}

#[test]
fn record_decision_short_circuits_after_cancel() {
    let mut s = BatchState::default();
    s.record_decision(dec(ConflictAction::Cancel, false));
    // Subsequent prompts return Cancel without consulting
    // the new decision.
    let result = s.record_decision(dec(ConflictAction::Replace, true));
    assert_eq!(result, ConflictAction::Cancel);
    // And the cache stays empty.
    assert!(s.cached().is_none());
}

#[test]
fn reset_clears_cache_and_cancellation() {
    let mut s = BatchState::default();
    s.record_decision(dec(ConflictAction::Replace, true));
    s.record_decision(dec(ConflictAction::Cancel, false));
    assert!(s.is_cancelled());
    s.reset();
    assert!(!s.is_cancelled());
    assert!(s.cached().is_none());
}

#[test]
fn registry_create_drop_round_trip() {
    let r = BatchStateRegistry::new();
    r.create("h1");
    assert!(r.cached("h1").is_none());
    assert!(!r.is_cancelled("h1"));
    r.drop("h1");
    // Unknown handle reads as default — no panic.
    assert!(r.cached("h1").is_none());
    assert!(!r.is_cancelled("h1"));
}

#[test]
fn registry_record_decision_caches_per_handle() {
    let r = BatchStateRegistry::new();
    r.record_decision("h1", dec(ConflictAction::Replace, true));
    r.record_decision("h2", dec(ConflictAction::Skip, false));
    // h1 cached Replace; h2 didn't cache anything.
    assert_eq!(r.cached("h1"), Some(ConflictAction::Replace));
    assert!(r.cached("h2").is_none());
}

#[test]
fn registry_short_circuits_after_cancel_per_handle() {
    let r = BatchStateRegistry::new();
    r.record_decision("h1", dec(ConflictAction::Cancel, false));
    // Subsequent record on h1 returns Cancel without
    // affecting h2.
    let result = r.record_decision("h1", dec(ConflictAction::Replace, true));
    assert_eq!(result, ConflictAction::Cancel);
    assert!(r.is_cancelled("h1"));
    assert!(!r.is_cancelled("h2"));
}
