//! FRB adapter for `lfs_core::security::persisted_rate_limit`.
//!
//! Sync everywhere — every op is a JSON parse + base64 + one
//! SHA-256 digest. The L2 unlock dialog drives both encode + decode
//! per cooldown-state load, so the no-async-hop overhead is worth
//! the few-microsecond saving.
//!
//! What stays Dart-side: the actual file I/O for
//! `rate_limit_state.bin` (atomic write via `writeBytesAtomic` +
//! 0600 hardening) and the in-memory state caching that
//! `PersistedRateLimiter` does between disk reads.

use lfs_core::security::persisted_rate_limit as rl;

/// FRB mirror of
/// `lfs_core::security::persisted_rate_limit::PersistedState`.
#[derive(Debug, Clone)]
pub struct DbPersistedRateLimitState {
    pub failure_count: i64,
    pub next_retry_at_millis: Option<i64>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_encode(
    failure_count: i64,
    next_retry_at_millis: Option<i64>,
    hmac_key: Vec<u8>,
) -> Vec<u8> {
    rl::encode_state(
        &rl::PersistedState {
            failure_count,
            next_retry_at_millis,
        },
        &hmac_key,
    )
}

/// Parse + HMAC-verify the on-disk frame. Returns `None` for a
/// tamper / corruption signal so the Dart caller falls through to
/// "no state on disk" without surfacing the parse error.
#[flutter_rust_bridge::frb(sync)]
pub fn persisted_rate_limit_decode(
    bytes: Vec<u8>,
    hmac_key: Vec<u8>,
) -> Option<DbPersistedRateLimitState> {
    rl::decode_state(&bytes, &hmac_key)
        .ok()
        .flatten()
        .map(|s| DbPersistedRateLimitState {
            failure_count: s.failure_count,
            next_retry_at_millis: s.next_retry_at_millis,
        })
}
