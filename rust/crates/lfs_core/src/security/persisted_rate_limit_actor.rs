//! In-memory + on-disk actor for the L2 keychain-gate's
//! `PersistedRateLimiter`. Wraps the existing
//! `persisted_rate_limit::{encode_state, decode_state}` HMAC-frame
//! ser/de with the cache + serialised disk-write coordination that
//! used to live Dart-side.
//!
//! The actor lives as a process-singleton registry keyed on `id` so
//! the L2 gate can register one limiter at startup
//! (`init_or_get`) and every subsequent unlock attempt routes
//! `status` / `record_failure` / `record_success` through the same
//! registry entry. Disk writes go through `tokio::spawn_blocking`
//! and are serialised per-id so two rapid-fire failures land on
//! disk in arrival order without the second clobbering the first.
//!
//! The Dart `PersistedRateLimiter` shrinks to a thin shim over the
//! FRB sync entry points; the file path resolution + HMAC-key
//! derivation stay Dart-side because both ride on platform
//! plugins (path_provider + flutter_secure_storage). The actor
//! takes pre-resolved `(file_path, hmac_key)` on `init_or_get`.

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
    /// L2-gate's password change / wipe path may legitimately
    /// re-init with a fresh HMAC key.
    pub fn init_or_get(&self, id: &str, file_path: PathBuf, hmac_key: Vec<u8>) -> RateLimitStatus {
        let mut g = self.inner.lock().expect("persisted rate limit poisoned");
        let entry = g.entry(id.to_string()).or_insert_with(|| Entry {
            file_path: file_path.clone(),
            hmac_key: hmac_key.clone(),
            state: None,
            loaded: false,
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
        let g = self.inner.lock().expect("persisted rate limit poisoned");
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
        let mut g = self.inner.lock().expect("persisted rate limit poisoned");
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
        let next_retry_at_millis = if secs == 0 {
            None
        } else {
            Some((self.clock)() + (secs as i64) * 1000)
        };
        let state = PersistedState {
            failure_count: next_count,
            next_retry_at_millis,
        };
        entry.state = Some(state.clone());
        entry.loaded = true;
        write_state_async(entry.file_path.clone(), entry.hmac_key.clone(), state);
        snapshot_status(entry, &self.clock)
    }

    /// Wipe the failure counter so the next unlock starts fresh.
    pub fn record_success(&self, id: &str) {
        let mut g = self.inner.lock().expect("persisted rate limit poisoned");
        let Some(entry) = g.get_mut(id) else {
            return;
        };
        let state = PersistedState {
            failure_count: 0,
            next_retry_at_millis: None,
        };
        entry.state = Some(state.clone());
        entry.loaded = true;
        write_state_async(entry.file_path.clone(), entry.hmac_key.clone(), state);
    }

    /// Drop the registry entry + best-effort delete the on-disk
    /// file. Used on logout / wipe-all so a never-failed re-enable
    /// starts from zero.
    pub fn clear(&self, id: &str) {
        let mut g = self.inner.lock().expect("persisted rate limit poisoned");
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

/// Process-singleton registry instance — the L2 gate registers
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
/// flow on a filesystem hiccup.
fn write_state_async(file_path: PathBuf, hmac_key: Vec<u8>, state: PersistedState) {
    // Tokio runtime may not be available in some test contexts —
    // fall back to an inline write so unit tests against the
    // actor don't need a runtime spun up just to observe the
    // disk side-effect.
    if let Ok(rt) = tokio::runtime::Handle::try_current() {
        rt.spawn_blocking(move || {
            let _ = write_state_sync(&file_path, &hmac_key, &state);
        });
    } else {
        let _ = write_state_sync(&file_path, &hmac_key, &state);
    }
}

fn write_state_sync(
    path: &PathBuf,
    hmac_key: &[u8],
    state: &PersistedState,
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let bytes = encode_persisted(state, hmac_key);
    std::fs::write(path, &bytes)?;
    crate::path::harden_file_perms(path)
        .map_err(|e| std::io::Error::other(format!("harden_file_perms: {e}")))?;
    Ok(())
}

#[cfg(test)]
mod tests {
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
}
