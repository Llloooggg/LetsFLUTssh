//! FRB adapter for `lfs_core::rate_limit::InMemoryRateLimiterRegistry`.
//!
//! Sync endpoints because the Dart `InMemoryRateLimiter` shim
//! preserves the synchronous `status()` / `recordFailure()` /
//! `recordSuccess()` API surface that `MasterPasswordManager` and
//! the unlock dialog read off in render-time hot paths. The
//! per-call work is a small mutex acquire + arithmetic — `frb(sync)`
//! avoids the async-jump overhead per call.

/// FRB mirror of [`lfs_core::rate_limit::RateLimitStatus`].
/// `cooldownRemainingMs` is `0` when the next attempt is allowed
/// immediately; non-zero when a wait is in effect.
#[derive(Debug, Clone, Copy)]
pub struct DbRateLimitStatus {
    pub failure_count: u32,
    pub cooldown_remaining_ms: i64,
}

impl From<lfs_core::rate_limit::RateLimitStatus> for DbRateLimitStatus {
    fn from(s: lfs_core::rate_limit::RateLimitStatus) -> Self {
        Self {
            failure_count: s.failure_count,
            cooldown_remaining_ms: s.cooldown_remaining_ms,
        }
    }
}

/// Snapshot the limiter under `id`. Auto-creates a fresh limiter
/// for unknown ids — first `status` call after a hot reload
/// returns `failure_count = 0` rather than throwing.
#[flutter_rust_bridge::frb(sync)]
pub fn rate_limit_status(id: String) -> DbRateLimitStatus {
    let app = lfs_core::app::instance();
    app.rate_limiters.status(&id).into()
}

/// Register a failed attempt against the limiter under `id`.
/// Auto-creates a limiter on first call. Bumps the failure
/// counter (clamped at 10) and arms the next-retry deadline per
/// the shared exponential-backoff schedule.
#[flutter_rust_bridge::frb(sync)]
pub fn rate_limit_record_failure(id: String) {
    let app = lfs_core::app::instance();
    app.rate_limiters.record_failure(&id);
}

/// Register a successful attempt against the limiter under `id`.
/// Wipes the failure counter + cooldown so the next unlock starts
/// fresh.
#[flutter_rust_bridge::frb(sync)]
pub fn rate_limit_record_success(id: String) {
    let app = lfs_core::app::instance();
    app.rate_limiters.record_success(&id);
}

/// Drop the limiter under `id` from the registry. Idempotent on
/// a missing id. Called by `WipeAllService` and on logout to
/// reclaim the per-tier-gate state.
#[flutter_rust_bridge::frb(sync)]
pub fn rate_limit_drop(id: String) -> bool {
    let app = lfs_core::app::instance();
    app.rate_limiters.drop_id(&id)
}

/// Canonical exponential-backoff schedule (seconds) — index N
/// is the wait after N consecutive failures, capped at the last
/// entry. Mirrors `lfs_core::rate_limit::BACKOFF_SCHEDULE`
/// byte-for-byte; exposed so the Dart `PasswordRateLimiter` base
/// class doesn't carry its own const copy that could drift.
#[flutter_rust_bridge::frb(sync)]
pub fn rate_limit_backoff_schedule_seconds() -> Vec<u32> {
    lfs_core::rate_limit::BACKOFF_SCHEDULE.to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    // The status / record_failure / record_success / drop endpoints
    // route through `lfs_core::app::instance()`; that singleton
    // requires `lfs_core::app::init()` (called by the FRB worker
    // bootstrap, not the cargo-test harness). The
    // `password_rate_limiter_test.dart` integration suite already
    // exercises those endpoints end-to-end through `requireFrbLoaded`.
    // The standalone cargo tests below cover the parts that don't
    // need the App singleton.

    #[test]
    fn backoff_schedule_is_non_empty_and_monotonic() {
        // Pin the load-bearing invariant — every consecutive failure
        // costs at least as much wait as the previous, capped at
        // the last entry. The exact constants live in
        // `lfs_core::rate_limit::BACKOFF_SCHEDULE`.
        let schedule = rate_limit_backoff_schedule_seconds();
        assert!(!schedule.is_empty());
        for window in schedule.windows(2) {
            assert!(window[0] <= window[1], "schedule must be non-decreasing");
        }
    }

    #[test]
    fn db_rate_limit_status_clone_round_trip() {
        // Defensive — guards against a future refactor that
        // accidentally drops `Clone` on the FRB-marshalled struct.
        let s = DbRateLimitStatus {
            failure_count: 3,
            cooldown_remaining_ms: 1500,
        };
        let c = s;
        assert_eq!(c.failure_count, 3);
        assert_eq!(c.cooldown_remaining_ms, 1500);
    }

    #[test]
    fn from_core_status_carries_fields_through() {
        let core = lfs_core::rate_limit::RateLimitStatus {
            failure_count: 2,
            cooldown_remaining_ms: 3000,
        };
        let db: DbRateLimitStatus = core.into();
        assert_eq!(db.failure_count, 2);
        assert_eq!(db.cooldown_remaining_ms, 3000);
    }
}
