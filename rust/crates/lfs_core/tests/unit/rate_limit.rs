/// Unit tests extracted from rate_limit.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;

fn fake_clock(start_ms: i64) -> (Clock, Arc<AtomicI64>) {
    let cell = Arc::new(AtomicI64::new(start_ms));
    let clone = cell.clone();
    let f: Clock = Box::new(move || clone.load(Ordering::SeqCst));
    (f, cell)
}

#[test]
fn first_failure_arms_one_second_cooldown() {
    let (clock, cell) = fake_clock(1_000);
    let l = InMemoryRateLimiter::with_clock(clock);
    l.record_failure();
    let s = l.status();
    assert_eq!(s.failure_count, 1);
    assert_eq!(s.cooldown_remaining_ms, 1_000);
    // After 999 ms, still locked.
    cell.store(1_999, Ordering::SeqCst);
    assert!(l.status().is_locked());
    // After exactly 1 s, no longer locked.
    cell.store(2_000, Ordering::SeqCst);
    assert!(!l.status().is_locked());
}

#[test]
fn schedule_doubles_then_caps_at_sixty() {
    let (clock, _cell) = fake_clock(0);
    let l = InMemoryRateLimiter::with_clock(clock);
    let expected = BACKOFF_SCHEDULE;
    for (i, _) in expected.iter().enumerate().skip(1) {
        l.record_failure();
        assert_eq!(l.status().failure_count, i as u32);
        assert_eq!(l.status().cooldown_remaining_ms, expected[i] as i64 * 1000);
    }
    // Extra failures past the cap clamp the counter and keep
    // the cooldown at the 60 s cap.
    l.record_failure();
    assert_eq!(
        l.status().failure_count,
        (BACKOFF_SCHEDULE.len() - 1) as u32
    );
    assert_eq!(l.status().cooldown_remaining_ms, 60_000);
}

#[test]
fn record_success_resets_state() {
    let (clock, cell) = fake_clock(0);
    let l = InMemoryRateLimiter::with_clock(clock);
    for _ in 0..3 {
        l.record_failure();
    }
    l.record_success();
    let s = l.status();
    assert_eq!(s.failure_count, 0);
    assert_eq!(s.cooldown_remaining_ms, 0);
    assert!(!s.is_locked());
    // Still works correctly after success: a new failure
    // re-arms the index-1 cooldown, not whatever it was.
    l.record_failure();
    assert_eq!(l.status().failure_count, 1);
    cell.store(0, Ordering::SeqCst);
    assert_eq!(l.status().cooldown_remaining_ms, 1_000);
}

#[test]
fn no_failures_means_no_cooldown() {
    let l = InMemoryRateLimiter::new();
    let s = l.status();
    assert_eq!(s.failure_count, 0);
    assert_eq!(s.cooldown_remaining_ms, 0);
    assert!(!s.is_locked());
}

#[test]
fn elapsed_past_deadline_clamps_to_zero() {
    let (clock, cell) = fake_clock(0);
    let l = InMemoryRateLimiter::with_clock(clock);
    l.record_failure();
    // Jump well past the deadline — cooldown clamps to zero
    // rather than going negative.
    cell.store(60_000_000, Ordering::SeqCst);
    let s = l.status();
    assert_eq!(s.cooldown_remaining_ms, 0);
    assert!(!s.is_locked());
}
