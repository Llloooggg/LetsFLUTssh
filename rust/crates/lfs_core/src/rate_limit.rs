//! In-memory password-attempt rate limiter.
//!
//! Owns the exponential-backoff schedule + transition rules used
//! across every password-bearing tier. The persistent variant
//! (HMAC-authenticated state file used by the L2 keychain gate)
//! lives next door in
//! [`crate::security::persisted_rate_limit_actor`] — both share
//! [`BACKOFF_SCHEDULE`] so the timing is identical regardless of
//! whether counters survive a process restart.

use std::sync::Mutex;

/// Seconds to wait between attempts after N consecutive
/// failures. Index 0 = "no failures yet, no wait"; index 1 =
/// "one failure, wait 1 s"; every index above doubles up to the
/// 60-second cap. Mirrors `PasswordRateLimiter.backoffSchedule`
/// in the Dart layer.
pub const BACKOFF_SCHEDULE: [u32; 10] = [0, 1, 2, 4, 8, 16, 32, 60, 60, 60];

/// Snapshot of the limiter's current state. `cooldown_remaining_ms`
/// is `0` when the next attempt is immediately allowed; non-zero
/// when a wait is in effect.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RateLimitStatus {
    pub failure_count: u32,
    pub cooldown_remaining_ms: i64,
}

impl RateLimitStatus {
    pub fn is_locked(&self) -> bool {
        self.cooldown_remaining_ms > 0
    }
}

/// Clock returning Unix-millis. Production wires
/// [`SystemTime::now`]; tests inject a deterministic step.
pub type Clock = Box<dyn Fn() -> i64 + Send + Sync>;

fn default_clock() -> Clock {
    Box::new(|| {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0)
    })
}

#[derive(Debug, Default)]
struct State {
    failure_count: u32,
    next_retry_at_ms: Option<i64>,
}

/// In-memory variant. Used for the Paranoid master-password
/// path where the Argon2id KDF is the real attacker brake; a
/// persistent counter would only inconvenience legitimate users
/// without raising the cryptographic bar.
pub struct InMemoryRateLimiter {
    state: Mutex<State>,
    now_fn: Clock,
}

impl InMemoryRateLimiter {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(State::default()),
            now_fn: default_clock(),
        }
    }

    /// Builder used by tests — supply a deterministic clock.
    pub fn with_clock(clock: Clock) -> Self {
        Self {
            state: Mutex::new(State::default()),
            now_fn: clock,
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().expect("rate limiter mutex poisoned")
    }

    /// Snapshot the limiter for the UI — failure count + remaining
    /// cooldown derived against the current clock.
    pub fn status(&self) -> RateLimitStatus {
        let g = self.lock();
        let cooldown = match g.next_retry_at_ms {
            Some(at) => {
                let now = (self.now_fn)();
                (at - now).max(0)
            }
            None => 0,
        };
        RateLimitStatus {
            failure_count: g.failure_count,
            cooldown_remaining_ms: cooldown,
        }
    }

    /// Register a failed attempt. Bumps the failure counter
    /// (clamped at the schedule cap) and arms the next-retry
    /// deadline at `now + schedule[count]`.
    pub fn record_failure(&self) {
        let cap = (BACKOFF_SCHEDULE.len() - 1) as u32;
        let mut g = self.lock();
        g.failure_count = (g.failure_count + 1).min(cap);
        let secs = BACKOFF_SCHEDULE[g.failure_count as usize];
        g.next_retry_at_ms = if secs == 0 {
            None
        } else {
            Some((self.now_fn)() + (secs as i64) * 1000)
        };
    }

    /// Register a successful attempt. Wipes the counter +
    /// cooldown so the next unlock starts fresh.
    pub fn record_success(&self) {
        let mut g = self.lock();
        g.failure_count = 0;
        g.next_retry_at_ms = None;
    }
}

impl Default for InMemoryRateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

impl Default for InMemoryRateLimiterRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton registry of in-memory rate limiters keyed by
/// caller-allocated id. Owned by `AppState`. The Dart shim
/// instantiates one per [`MasterPasswordManager`] / per-tier-gate
/// and routes through these sync FRB endpoints; the Rust side
/// owns the canonical state across hot-reload, settings nav,
/// and unlock cycles.
pub struct InMemoryRateLimiterRegistry {
    inner: Mutex<std::collections::HashMap<String, InMemoryRateLimiter>>,
}

impl InMemoryRateLimiterRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(std::collections::HashMap::new()),
        }
    }

    /// Snapshot the limiter under `id`. Auto-creates a fresh
    /// limiter for unknown ids — the first `status()` call after a
    /// hot reload should not throw.
    pub fn status(&self, id: &str) -> RateLimitStatus {
        let mut g = self
            .inner
            .lock()
            .expect("rate limiter registry mutex poisoned");
        g.entry(id.to_string()).or_default().status()
    }

    /// Register a failed attempt against `id`. Auto-creates a
    /// limiter on first failure.
    pub fn record_failure(&self, id: &str) {
        let mut g = self
            .inner
            .lock()
            .expect("rate limiter registry mutex poisoned");
        g.entry(id.to_string()).or_default().record_failure();
    }

    /// Register a successful attempt against `id`. Auto-creates a
    /// limiter (idempotent) — `recordSuccess` on a never-failed
    /// id is a no-op.
    pub fn record_success(&self, id: &str) {
        let mut g = self
            .inner
            .lock()
            .expect("rate limiter registry mutex poisoned");
        g.entry(id.to_string()).or_default().record_success();
    }

    /// Drop the limiter for `id`. Used at logout / wipe-all to
    /// reclaim memory; idempotent on a missing id.
    pub fn drop_id(&self, id: &str) -> bool {
        self.inner
            .lock()
            .expect("rate limiter registry mutex poisoned")
            .remove(id)
            .is_some()
    }

    pub fn count(&self) -> usize {
        self.inner
            .lock()
            .expect("rate limiter registry mutex poisoned")
            .len()
    }
}

#[cfg(test)]
mod tests {
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
}
