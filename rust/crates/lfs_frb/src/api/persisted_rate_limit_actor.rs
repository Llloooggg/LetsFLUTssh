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
/// `hmac_key` is the 32-byte HMAC key derived from the L2 gate's
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
