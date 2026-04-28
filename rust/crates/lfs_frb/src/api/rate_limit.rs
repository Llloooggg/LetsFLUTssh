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
