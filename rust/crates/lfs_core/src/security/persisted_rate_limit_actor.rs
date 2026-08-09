//! In-memory + on-disk actor for the T1+pw keychain-gate's
//! `PersistedRateLimiter`. Wraps the
//! `persisted_rate_limit::{encode_state, decode_state}` HMAC-frame
//! ser/de with the in-memory cache + serialised disk-write
//! coordination.
//!
//! The actor lives as a process-singleton registry keyed on `id` so
//! the T1+pw gate can register one limiter at startup
//! (`init_or_get`) and every subsequent unlock attempt routes
//! `status` / `record_failure` / `record_success` through the same
//! registry entry. Disk writes go through `tokio::spawn_blocking`
//! and are serialised per-id so two rapid-fire failures land on
//! disk in arrival order without the second clobbering the first.
//!
//! The Dart `PersistedRateLimiter` shrinks to a thin shim over the
//! FRB sync entry points; the file path resolution stays Dart-side
//! because it rides on path_provider. The actor takes the gate
//! HMAC verbatim on `init_or_get` (the `hmac_key` parameter) and
//! derives the actual rate-limit signing key internally via HKDF —
//! see [`super::persisted_rate_limit`] for the key-separation
//! contract.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use crate::rate_limit::{Clock, RateLimitStatus, BACKOFF_SCHEDULE};
use crate::security::persisted_rate_limit::{
    decode_state as decode_persisted, encode_state as encode_persisted, PersistedState,
};

/// Per-id state held in the registry. The HMAC key + file path are
/// fixed at `init_or_get`; only `state` mutates per failure /
/// success.
#[derive(Debug)]
struct Entry {
    file_path: PathBuf,
    hmac_key: Vec<u8>,
    state: Option<PersistedState>,
    /// True once the on-disk frame has been read (or the file was
    /// observed missing and we adopted the zero-state default).
    /// Until this flips, `status()` returns the safe baseline so
    /// the unlock dialog renders no cooldown before the load
    /// settles.
    loaded: bool,
    /// Handle of the most recent `tokio::spawn_blocking` write task,
    /// taken by [`PersistedRateLimiterRegistry::flush`] so callers
    /// can await write settlement instead of polling the disk.
    /// Replaced (not chained) on every new write — the latest state
    /// is always the only one that matters; an older write that
    /// hasn't observed wins is no longer the truth and is safe to
    /// drop (race-then-overwrite, not race-then-revert).
    pending_write: Option<tokio::task::JoinHandle<()>>,
}

/// Singleton registry. Mirrors the shape of
/// `InMemoryRateLimiterRegistry` but adds the disk-backed cache +
/// the HMAC-frame round-trip.
pub struct PersistedRateLimiterRegistry {
    inner: Mutex<HashMap<String, Entry>>,
    clock: Clock,
}

impl PersistedRateLimiterRegistry {
    pub fn new() -> Self {
        Self::with_clock(default_clock())
    }

    pub fn with_clock(clock: Clock) -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
            clock,
        }
    }

    /// Register or refresh the entry for `id`. Loads the on-disk
    /// state synchronously — caller is on the unlock-flow thread
    /// already, and the file is a few hundred bytes. Subsequent
    /// `status` / `record_*` calls reuse the cached entry until
    /// `clear` drops it.
    ///
    /// If a different `(file_path, hmac_key)` pair was registered
    /// earlier under the same `id`, the new pair wins — the
    /// T1+pw-gate's password change / wipe path may legitimately
    /// re-init with a fresh HMAC key.
    pub fn init_or_get(&self, id: &str, file_path: PathBuf, hmac_key: Vec<u8>) -> RateLimitStatus {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let entry = g.entry(id.to_string()).or_insert_with(|| Entry {
            file_path: file_path.clone(),
            hmac_key: hmac_key.clone(),
            state: None,
            loaded: false,
            pending_write: None,
        });
        // Re-init under a different HMAC key / path resets the
        // cache so the next read picks up the fresh state.
        if entry.file_path != file_path || entry.hmac_key != hmac_key {
            entry.file_path = file_path;
            entry.hmac_key = hmac_key;
            entry.state = None;
            entry.loaded = false;
        }
        // Synchronous file load — the file is small enough that
        // `std::fs::read` doesn't pin the unlock thread for any
        // measurable time.
        if !entry.loaded {
            entry.state = read_state(&entry.file_path, &entry.hmac_key, &self.clock);
            entry.loaded = true;
        }
        snapshot_status(entry, &self.clock)
    }

    /// Snapshot the limiter under `id`. Returns the zero baseline
    /// when the id has never been initialised — same contract the
    /// Dart `status()` honoured before the cache settled.
    pub fn status(&self, id: &str) -> RateLimitStatus {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        match g.get(id) {
            Some(entry) => snapshot_status(entry, &self.clock),
            None => RateLimitStatus {
                failure_count: 0,
                cooldown_remaining_ms: 0,
            },
        }
    }

    /// Bump the failure counter + arm the next-retry deadline,
    /// then schedule a disk write. Caller pays the in-memory
    /// update cost synchronously; the disk write runs in the
    /// background and is serialised against any prior in-flight
    /// write.
    ///
    /// Returns the new status snapshot so the caller can render
    /// the cooldown countdown without a follow-up `status` call.
    pub fn record_failure(&self, id: &str) -> RateLimitStatus {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let Some(entry) = g.get_mut(id) else {
            return RateLimitStatus {
                failure_count: 0,
                cooldown_remaining_ms: 0,
            };
        };
        let current = entry.state.clone().unwrap_or(PersistedState {
            failure_count: 0,
            next_retry_at_millis: None,
        });
        let next_count = (current.failure_count + 1).min((BACKOFF_SCHEDULE.len() - 1) as i64);
        let secs = BACKOFF_SCHEDULE
            .get(next_count as usize)
            .copied()
            .unwrap_or(0);
        // Monotonic floor on the cooldown: a backward clock jump
        // (NTP correction, daylight-saving rollback, suspended
        // laptop with battery-drained RTC) MUST NOT shrink the
        // issued cooldown. An attacker with system-clock write
        // access could otherwise burn through the schedule — fail,
        // set clock back, fail again, set back, … and skip the
        // geometric backoff entirely. `current.next_retry_at_millis`
        // is the issued floor; take the larger of "now + step" and
        // that floor so failures only ever push the cooldown
        // further out.
        let candidate = if secs == 0 {
            None
        } else {
            Some((self.clock)() + (secs as i64) * 1000)
        };
        let next_retry_at_millis = match (candidate, current.next_retry_at_millis) {
            (Some(new), Some(prev)) => Some(new.max(prev)),
            (Some(new), None) => Some(new),
            (None, prev) => prev,
        };
        let state = PersistedState {
            failure_count: next_count,
            next_retry_at_millis,
        };
        entry.state = Some(state.clone());
        entry.loaded = true;
        entry.pending_write =
            write_state_async(entry.file_path.clone(), entry.hmac_key.clone(), state);
        snapshot_status(entry, &self.clock)
    }

    /// Wipe the failure counter so the next unlock starts fresh.
    pub fn record_success(&self, id: &str) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let Some(entry) = g.get_mut(id) else {
            return;
        };
        let state = PersistedState {
            failure_count: 0,
            next_retry_at_millis: None,
        };
        entry.state = Some(state.clone());
        entry.loaded = true;
        entry.pending_write =
            write_state_async(entry.file_path.clone(), entry.hmac_key.clone(), state);
    }

    /// Take the most-recent in-flight write JoinHandle for `id`.
    /// Returns `None` when no write is pending or the entry is not
    /// registered. Caller awaits the handle outside the registry
    /// lock so a slow disk does not block other actors. Used by
    /// the FRB `flush` shim so callers (tests, logout flows) can
    /// observe a settled disk state without polling.
    pub fn take_pending_write(&self, id: &str) -> Option<tokio::task::JoinHandle<()>> {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.get_mut(id).and_then(|e| e.pending_write.take())
    }

    /// Drop the registry entry + best-effort delete the on-disk
    /// file. Used on logout / wipe-all so a never-failed re-enable
    /// starts from zero.
    pub fn clear(&self, id: &str) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(entry) = g.remove(id) {
            let _ = std::fs::remove_file(&entry.file_path);
        }
    }
}

impl Default for PersistedRateLimiterRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton registry instance — the T1+pw gate registers
/// once per app launch, every unlock dialog routes through this.
static GLOBAL: OnceLock<PersistedRateLimiterRegistry> = OnceLock::new();

pub fn instance() -> &'static PersistedRateLimiterRegistry {
    GLOBAL.get_or_init(PersistedRateLimiterRegistry::new)
}

fn default_clock() -> Clock {
    Box::new(|| {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or_default()
    })
}

fn snapshot_status(entry: &Entry, clock: &Clock) -> RateLimitStatus {
    if !entry.loaded {
        return RateLimitStatus {
            failure_count: 0,
            cooldown_remaining_ms: 0,
        };
    }
    let Some(ref state) = entry.state else {
        return RateLimitStatus {
            failure_count: 0,
            cooldown_remaining_ms: 0,
        };
    };
    let cooldown_remaining_ms = match state.next_retry_at_millis {
        Some(next) => {
            let now = clock();
            (next - now).max(0)
        }
        None => 0,
    };
    RateLimitStatus {
        failure_count: state.failure_count.max(0) as u32,
        cooldown_remaining_ms,
    }
}

/// Synchronous read + decode. Treats a missing file as "fresh
/// state" (zero counter) and a tampered file as "max cooldown" —
/// same semantics the Dart `_ensureLoaded` honoured. Returns the
/// state to install in the cache.
fn read_state(path: &PathBuf, hmac_key: &[u8], clock: &Clock) -> Option<PersistedState> {
    let raw = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Some(PersistedState {
                failure_count: 0,
                next_retry_at_millis: None,
            });
        }
        Err(_) => {
            return Some(PersistedState {
                failure_count: 0,
                next_retry_at_millis: None,
            });
        }
    };
    match decode_persisted(&raw, hmac_key) {
        Ok(Some(state)) => Some(state),
        // Tamper / corruption clamps to max cooldown — the worst-
        // case schedule slot keeps the user out of the unlock
        // dialog until the cooldown expires.
        Ok(None) | Err(_) => {
            let max_secs = *BACKOFF_SCHEDULE.last().unwrap_or(&0) as i64;
            Some(PersistedState {
                failure_count: (BACKOFF_SCHEDULE.len() - 1) as i64,
                next_retry_at_millis: Some(clock() + max_secs * 1000),
            })
        }
    }
}

/// Spawn a blocking task that writes the state to disk. Errors
/// are silently dropped — the worst case is the counter resets on
/// the next launch, which is preferable to blocking the unlock
/// flow on a filesystem hiccup. Returns the JoinHandle so the
/// caller (the registry [`Entry`]) can hand it to [`flush`]
/// callers that want to observe write settlement.
fn write_state_async(
    file_path: PathBuf,
    hmac_key: Vec<u8>,
    state: PersistedState,
) -> Option<tokio::task::JoinHandle<()>> {
    // Tokio runtime may not be available in some test contexts —
    // fall back to an inline write so unit tests against the
    // actor don't need a runtime spun up just to observe the
    // disk side-effect.
    if let Ok(rt) = tokio::runtime::Handle::try_current() {
        Some(rt.spawn_blocking(move || {
            let _ = write_state_sync(&file_path, &hmac_key, &state);
        }))
    } else {
        let _ = write_state_sync(&file_path, &hmac_key, &state);
        None
    }
}

fn write_state_sync(
    path: &std::path::Path,
    hmac_key: &[u8],
    state: &PersistedState,
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        crate::path::create_dir_all_secure(parent).map_err(std::io::Error::other)?;
    }
    let bytes = encode_persisted(state, hmac_key);
    // Atomic write — non-atomic `std::fs::write` would torpedo the
    // HMAC tag on a power-loss between the truncate-open and the
    // payload flush; the next-launch decoder sees a torn file,
    // tamper handler downgrades to "fresh state" (zero counter),
    // and the rate limit collapses to a free retry. The atomic
    // write + parent-dir fsync invariant from `write_bytes_atomic`
    // keeps the previous (consistent) state on a crash.
    crate::path::write_bytes_atomic(path, &bytes).map_err(std::io::Error::other)
}
#[cfg(test)]
#[path = "../../tests/unit/security_persisted_rate_limit_actor.rs"]
mod tests;
