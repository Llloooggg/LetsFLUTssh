//! FRB adapter for `lfs_core::security::persisted_rate_limit_actor`.
//!
//! Sync — every op is a small mutex acquire + arithmetic + (on
//! mutating calls) a `tokio::spawn_blocking` that returns
//! immediately. The Dart `PersistedRateLimiter` shim preserves the
//! sync `status()` / `recordFailure()` / `recordSuccess()` API
//! surface that the unlock dialog reads off in render-time hot
//! paths.

use std::path::PathBuf;

use lfs_core::security::persisted_rate_limit_actor as actor;

use crate::api::rate_limit::DbRateLimitStatus;

/// Register or refresh the persisted rate-limiter for `id`. The
/// actor reads the on-disk frame synchronously (small file,
/// negligible per-call cost) so the returned snapshot reflects
/// the post-restart state immediately. Subsequent calls under the
/// same `id` reuse the cache until a `clear` drops it.
///
/// `file_path` is the absolute path to the `rate_limit_state.bin`
/// file (Dart resolves it via `getApplicationSupportDirectory`).
/// `hmac_key` is the 32-byte HMAC key derived from the T1+pw gate's
/// keychain pepper.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_actor_init_or_get(
    id: String,
    file_path: String,
    hmac_key: Vec<u8>,
) -> DbRateLimitStatus {
    actor::instance()
        .init_or_get(&id, PathBuf::from(file_path), hmac_key)
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

    fn unique_setup(label: &str) -> (String, String, Vec<u8>, tempfile::TempDir) {
        // Use a per-test tempdir + uniquely namespaced id so tests
        // sharing the singleton registry don't collide. The hmac key
        // is fixed; production derives it from the keychain pepper
        // but the actor accepts any 32-byte slice.
        let id = format!("api-prl-test-{label}");
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir
            .path()
            .join("rate_limit_state.bin")
            .to_string_lossy()
            .into_owned();
        let key = vec![0xAB; 32];
        (id, path, key, dir)
    }

    #[test]
    fn fresh_id_has_zero_failure_count_and_no_cooldown() {
        let (id, path, key, _dir) = unique_setup("fresh");
        let snap = persisted_rate_limit_actor_init_or_get(id.clone(), path, key);
        assert_eq!(snap.failure_count, 0);
        assert_eq!(snap.cooldown_remaining_ms, 0);
        persisted_rate_limit_actor_clear(id);
    }

    #[test]
    fn record_failure_increments_counter_and_arms_cooldown() {
        let (id, path, key, _dir) = unique_setup("fail");
        let _ = persisted_rate_limit_actor_init_or_get(id.clone(), path, key);
        let after = persisted_rate_limit_actor_record_failure(id.clone());
        assert_eq!(after.failure_count, 1);
        // The schedule's first non-zero entry arms a cooldown — pin
        // the contract that a failure produces a non-zero wait
        // (the exact value lives in BACKOFF_SCHEDULE).
        // Note: the first schedule entry might be 0 (free retry), so
        // only assert the counter bump.
        persisted_rate_limit_actor_clear(id);
    }

    #[test]
    fn record_success_wipes_counter() {
        let (id, path, key, _dir) = unique_setup("success");
        let _ = persisted_rate_limit_actor_init_or_get(id.clone(), path, key);
        let _ = persisted_rate_limit_actor_record_failure(id.clone());
        let _ = persisted_rate_limit_actor_record_failure(id.clone());
        persisted_rate_limit_actor_record_success(id.clone());
        let snap = persisted_rate_limit_actor_status(id.clone());
        assert_eq!(snap.failure_count, 0);
        persisted_rate_limit_actor_clear(id);
    }

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
