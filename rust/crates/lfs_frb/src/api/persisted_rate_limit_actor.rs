//! FRB adapter for `lfs_core::security::persisted_rate_limit_actor`.
//!
//! Sync — every op is a small mutex acquire + arithmetic + (on
//! mutating calls) a `tokio::spawn_blocking` that returns
//! immediately. The Dart `PersistedRateLimiter` shim preserves the
//! sync `status()` / `recordFailure()` / `recordSuccess()` API
//! surface that the unlock dialog reads off in render-time hot
//! paths.

use lfs_core::security::master_password;
use lfs_core::security::persisted_rate_limit_actor as actor;

use crate::api::rate_limit::DbRateLimitStatus;

/// Canonical persisted-rate-limit state file under the app-support dir.
const RATE_LIMIT_STATE_FILE: &str = "rate_limit_state.bin";

/// Register or refresh the persisted rate-limiter for `id`. The
/// actor reads the on-disk frame synchronously (small file,
/// negligible per-call cost) so the returned snapshot reflects
/// the post-restart state immediately. Subsequent calls under the
/// same `id` reuse the cache until a `clear` drops it.
///
/// The state file is `rate_limit_state.bin` under the app-support
/// directory pinned at `config_store_init` — resolved Rust-side, so
/// Dart no longer threads a path in. `hmac_key` is the 32-byte HMAC
/// key derived from the T1+pw gate's keychain pepper. Falls back to
/// the in-memory baseline (no cooldown) when the pin is not yet set.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_actor_init_or_get(id: String, hmac_key: Vec<u8>) -> DbRateLimitStatus {
    let Ok(dir) = master_password::try_pinned_support_dir() else {
        return actor::instance().status(&id).into();
    };
    actor::instance()
        .init_or_get(&id, dir.join(RATE_LIMIT_STATE_FILE), hmac_key)
        .into()
}

/// Snapshot the limiter under `id`. Returns the zero baseline for
/// an unknown id — the Dart wrapper falls back to "no cooldown"
/// before the first `init_or_get` settles.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_actor_status(id: String) -> DbRateLimitStatus {
    actor::instance().status(&id).into()
}

/// Bump the failure counter + arm the next-retry deadline +
/// schedule a disk write. Returns the new status snapshot so the
/// caller can render the cooldown without a follow-up status
/// call.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_actor_record_failure(id: String) -> DbRateLimitStatus {
    actor::instance().record_failure(&id).into()
}

/// Wipe the failure counter so the next unlock starts fresh.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_actor_record_success(id: String) {
    actor::instance().record_success(&id);
}

/// Drop the registry entry + best-effort delete the on-disk
/// file. Used on logout / wipe-all so a re-enable starts from
/// zero.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_actor_clear(id: String) {
    actor::instance().clear(&id);
}

/// Await the most-recent in-flight disk write for `id`. Returns
/// immediately when nothing is pending. Tests that observe on-disk
/// state can block on this deterministically — the alternative
/// (sleep-and-pray heuristic) races on slow runners.
pub async fn persisted_rate_limit_actor_flush(id: String) {
    if let Some(handle) = actor::instance().take_pending_write(&id) {
        // JoinError on cancellation is harmless — the next write
        // is the truth, not the one we were awaiting.
        let _ = handle.await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The init_or_get / record / clear lifecycle is covered against
    // the explicit-path API in
    // `lfs_core::security::persisted_rate_limit_actor`; these FRB
    // wrappers only resolve the pinned support dir and delegate. The
    // path-free status / clear contracts stay pinned here.

    #[test]
    fn status_on_unknown_id_returns_zero_baseline() {
        // Pin the documented contract — Dart wrappers fall back to
        // "no cooldown" before the first `init_or_get` settles.
        let snap = persisted_rate_limit_actor_status("api-prl-test-unknown".into());
        assert_eq!(snap.failure_count, 0);
        assert_eq!(snap.cooldown_remaining_ms, 0);
    }

    #[test]
    fn clear_on_unknown_id_is_idempotent() {
        // No-op on missing — wipe-all flow runs unconditionally.
        persisted_rate_limit_actor_clear("api-prl-test-already-cleared".into());
    }
}
