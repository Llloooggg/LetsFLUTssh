/// Unit tests extracted from security/persisted_rate_limit_actor.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;
use tempfile::TempDir;

fn fake_clock(start_ms: i64) -> (Clock, Arc<AtomicI64>) {
    let cell = Arc::new(AtomicI64::new(start_ms));
    let clone = cell.clone();
    let f: Clock = Box::new(move || clone.load(Ordering::SeqCst));
    (f, cell)
}

fn fresh_registry() -> (PersistedRateLimiterRegistry, Arc<AtomicI64>) {
    let (clock, cell) = fake_clock(1_000);
    (PersistedRateLimiterRegistry::with_clock(clock), cell)
}

#[test]
fn init_returns_zero_baseline_for_fresh_id() {
    let (reg, _) = fresh_registry();
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    let s = reg.init_or_get("gate", path, vec![1u8; 32]);
    assert_eq!(s.failure_count, 0);
    assert_eq!(s.cooldown_remaining_ms, 0);
}

#[test]
fn record_failure_arms_one_second_cooldown() {
    let (reg, cell) = fresh_registry();
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    reg.init_or_get("gate", path, vec![1u8; 32]);
    let s = reg.record_failure("gate");
    assert_eq!(s.failure_count, 1);
    // BACKOFF_SCHEDULE[1] = 1 second.
    assert_eq!(s.cooldown_remaining_ms, 1_000);
    cell.store(1_999, Ordering::SeqCst);
    let still_locked = reg.status("gate");
    assert!(still_locked.is_locked());
}

#[test]
fn record_success_resets_counter() {
    let (reg, _) = fresh_registry();
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    reg.init_or_get("gate", path, vec![1u8; 32]);
    reg.record_failure("gate");
    reg.record_failure("gate");
    reg.record_success("gate");
    let s = reg.status("gate");
    assert_eq!(s.failure_count, 0);
    assert_eq!(s.cooldown_remaining_ms, 0);
}

#[test]
fn record_failure_persists_across_init_with_same_key() {
    // Simulates an app restart — second registry instance
    // re-inits under the same path + key and reads back the
    // last persisted state.
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    let key = vec![7u8; 32];
    let (reg1, _) = fresh_registry();
    reg1.init_or_get("gate", path.clone(), key.clone());
    reg1.record_failure("gate");
    // Sync write path runs inline when there's no tokio
    // runtime current — tests use the inline path so the file
    // lands on disk before the second registry reads it.

    let (reg2, _) = fresh_registry();
    let s = reg2.init_or_get("gate", path, key);
    assert_eq!(s.failure_count, 1);
}

#[test]
fn re_init_under_new_key_resets_cache() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    let (reg, _) = fresh_registry();
    reg.init_or_get("gate", path.clone(), vec![1u8; 32]);
    reg.record_failure("gate");
    // Re-init with a different HMAC key — the state file is
    // unreadable under the new key, so the cache resets to
    // the worst-case-cooldown clamp (tamper handling). New
    // failure_count is the schedule's last slot.
    let s = reg.init_or_get("gate", path, vec![2u8; 32]);
    assert!(
        s.failure_count as usize >= BACKOFF_SCHEDULE.len() - 1,
        "tamper handling clamps to max cooldown",
    );
}

#[test]
fn clear_removes_id_and_file() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    let (reg, _) = fresh_registry();
    reg.init_or_get("gate", path.clone(), vec![1u8; 32]);
    reg.record_failure("gate");
    reg.clear("gate");
    // Status returns zero baseline — entry is gone.
    let s = reg.status("gate");
    assert_eq!(s.failure_count, 0);
    assert!(!path.exists());
}

#[test]
fn status_for_unknown_id_returns_zero_baseline() {
    let (reg, _) = fresh_registry();
    let s = reg.status("never-initialised");
    assert_eq!(s.failure_count, 0);
    assert_eq!(s.cooldown_remaining_ms, 0);
}

#[test]
fn corrupt_file_clamps_to_max_cooldown() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    std::fs::write(&path, b"not a valid envelope").unwrap();
    let (reg, _) = fresh_registry();
    let s = reg.init_or_get("gate", path, vec![1u8; 32]);
    assert!(s.is_locked());
    assert_eq!(s.failure_count as usize, BACKOFF_SCHEDULE.len() - 1);
}

/// Backward clock jump (NTP correction, suspended laptop, user
/// dropping their system time) MUST NOT shrink an issued
/// cooldown. An attacker with system-clock write access could
/// otherwise burn through the geometric backoff:
///   1. Trigger N failures → cooldown ladder peaks.
///   2. Set clock back N seconds.
///   3. Each new `record_failure` would issue `now + step`
///      against the rolled-back `now`, undershooting the
///      persisted floor and freeing the unlock dialog earlier
///      than the schedule says.
///
/// Monotonic floor clamps the new `next_retry_at_millis` to
/// `max(now + step, prev_next_retry_at_millis)` so backward
/// jumps cannot shrink the cooldown.
#[test]
fn backward_clock_jump_does_not_shrink_cooldown() {
    let (reg, cell) = fresh_registry();
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("rate_limit_state.bin");
    reg.init_or_get("gate", path, vec![1u8; 32]);

    // Step the clock forward + record three failures so the
    // schedule lands on a non-trivial cooldown (BACKOFF_SCHEDULE
    // = [0, 1, 2, 4, ...] — three failures arms a 4 s wait).
    cell.store(10_000, Ordering::SeqCst);
    reg.record_failure("gate");
    reg.record_failure("gate");
    let after_third = reg.record_failure("gate");
    assert_eq!(after_third.failure_count, 3);
    assert!(after_third.cooldown_remaining_ms >= 4_000);

    // Roll the clock back 100 s — simulates the suspend / NTP
    // jump / hostile timezone change. The third-failure cooldown
    // floor is still pinned at wall-time 14 000 ms.
    cell.store(10_000 - 100_000, Ordering::SeqCst);

    // Fourth failure under the rolled-back clock. New cooldown
    // step is BACKOFF_SCHEDULE[4] = 8 s; without the floor we
    // would issue `(rolled_back) + 8000` ≈ -82 000 ms, far
    // before the third-failure floor at 14 000 ms — and the
    // status snapshot at any time after wall-time 0 would show
    // "not locked" even though the user is mid-cooldown. The
    // monotonic floor pins the new value to `max(new, prev)`
    // so the cooldown end stays at 14 000 ms (or grows; it
    // never shrinks).
    reg.record_failure("gate");

    // Snap the clock back to a wall-time still inside the
    // pinned cooldown (13 500 ms < 14 000 ms floor). Without
    // the floor this reads as expired (cooldown ms = 0); with
    // the floor it reports the remaining 500 ms.
    cell.store(13_500, Ordering::SeqCst);
    let snapshot = reg.status("gate");
    assert!(
        snapshot.is_locked(),
        "cooldown floor lost after backward clock jump: {snapshot:?}",
    );
}
