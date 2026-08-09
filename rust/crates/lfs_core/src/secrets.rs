//! Process-singleton secret store. Plaintext credentials (passwords,
//! key bytes, passphrases) live here, not on the Dart heap. Dart
//! sees only metadata (`hasPassword: bool`, etc.) and references
//! the secrets by id.
//!
//! # Active DB key slot
//!
//! [`ACTIVE_DBKEY_SECRET_ID`] is the canonical slot for the running
//! session's SQLCipher master key. Every code path that needs the DB
//! key — drift's `db_init_from_secret`, the recorder's HKDF-derive,
//! the biometric vault's enroll-on-change, the auto-lock close — pulls
//! through this slot Rust-side, never crossing the FRB boundary as
//! plaintext bytes. The slot is populated when an unlock cascade
//! lands (orchestrator stages, listener promotes) and dropped on
//! auto-lock / wipe.
//!
//! Threading: `Mutex<HashMap>` keeps the API lock-and-clone-out.
//! Reads return a fresh `Zeroizing<Vec<u8>>` so the caller owns the
//! scrub-on-drop guarantee for their copy. No interior `&[u8]`
//! references escape — the lock is released before the returned
//! buffer is touched.
//!
//! Page-locking: each resident secret's heap buffer is `mlock` /
//! `VirtualLock`-pinned (via [`lfs_os_security::lock_memory`]) on
//! insert and unpinned on removal, so the OS can't page a live key
//! out to swap or hibernation. `Zeroizing` then scrubs the bytes on
//! drop. Best-effort: an `mlock` the kernel refuses (e.g.
//! `RLIMIT_MEMLOCK` exhausted) leaves the secret working but
//! swappable. Transient copies handed back by `get` / `take` are not
//! pinned — the caller holds a short-lived working copy. Moving a
//! `Zeroizing<Vec<u8>>` between map slots (`rename`) does not move its
//! heap allocation, so the pin survives the move untouched.
//!
//! ID convention used by the FRB adapter (`lfs_frb::api::app`):
//!   - `sess.password.{session_id}`
//!   - `sess.key.{session_id}`
//!   - `sess.passphrase.{session_id}`
//!   - `key.{key_id}.private`
//!   - `conn.passphrase.{connection_id}`
//!
//! The store doesn't enforce the convention — it just stores bytes
//! against arbitrary string ids — but the documented prefixes keep
//! the namespaces from colliding when callers grow.

use std::collections::HashMap;
use std::sync::Mutex;

use zeroize::Zeroizing;

/// Canonical SecretStore slot for the running session's SQLCipher
/// master key. See module docs for lifecycle.
pub const ACTIVE_DBKEY_SECRET_ID: &str = "app.dbkey.active";

/// Page-lock a resident secret's heap bytes (`mlock` / `VirtualLock`)
/// so the OS can't swap them out. Best-effort — a refused lock is
/// ignored (the secret still works, just swappable). No-op on empty.
fn page_lock(buf: &Zeroizing<Vec<u8>>) {
    if !buf.is_empty() {
        lfs_os_security::lock_memory(buf.as_ptr() as usize, buf.len());
    }
}

/// Reverse of [`page_lock`] — must run *before* the buffer drops so
/// the freed pages aren't returned to the allocator still locked
/// (which would leak against `RLIMIT_MEMLOCK`). `Zeroizing` scrubs
/// the bytes on the subsequent drop.
fn page_unlock(buf: &Zeroizing<Vec<u8>>) {
    if !buf.is_empty() {
        lfs_os_security::unlock_memory(buf.as_ptr() as usize, buf.len());
    }
}

#[derive(Default)]
pub struct SecretStore {
    inner: Mutex<HashMap<String, Zeroizing<Vec<u8>>>>,
}

impl SecretStore {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Store `bytes` under `id`. Replaces any prior value at the
    /// same id (the previous `Zeroizing` buffer scrubs on drop).
    pub fn put(&self, id: &str, bytes: &[u8]) {
        let z = Zeroizing::new(bytes.to_vec());
        page_lock(&z);
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(old) = g.insert(id.to_string(), z) {
            page_unlock(&old);
        }
    }

    pub fn has(&self, id: &str) -> bool {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.contains_key(id)
    }

    /// Return a fresh copy of the stored bytes. Caller owns the
    /// scrub-on-drop guarantee for the returned buffer.
    pub fn get(&self, id: &str) -> Option<Zeroizing<Vec<u8>>> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.get(id).map(|v| Zeroizing::new(v.to_vec()))
    }

    /// Remove the entry under `id`. Idempotent.
    pub fn drop_id(&self, id: &str) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(old) = g.remove(id) {
            page_unlock(&old);
        }
    }

    /// Atomic read-and-remove. Returns the bytes that were
    /// stored under `id`, removing the entry from the map in
    /// the same critical section so concurrent callers see
    /// either the same bytes (if their lock landed first) or
    /// `None` (if ours did). Used by the bus-driven Dart
    /// unlock listener: the orchestrator stages the key, the
    /// listener takes it once for drift, the entry is gone
    /// from the store after a single FRB byte crossing.
    pub fn take(&self, id: &str) -> Option<Zeroizing<Vec<u8>>> {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let removed = g.remove(id);
        // Unpin before handing the buffer out — the caller owns a
        // transient working copy that drops (and scrubs) on its own;
        // leaving it `mlock`ed would leak the pin when it frees.
        if let Some(ref buf) = removed {
            page_unlock(buf);
        }
        removed
    }

    /// Drop every secret under any id. Used by the auth-failure
    /// recovery path that wipes all cached credentials at once.
    pub fn clear(&self) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        for buf in g.values() {
            page_unlock(buf);
        }
        g.clear();
    }

    /// Atomic move: take bytes from `from`, store them under `to`.
    /// `to` is replaced if it already had a value (the previous
    /// `Zeroizing` buffer scrubs on drop). No-op when `from == to`.
    /// Returns `false` when `from` is absent (the slot at `to` is
    /// untouched in that case).
    ///
    /// Used by the unlock cascade to promote a transient
    /// caller-minted secret into the canonical
    /// [`ACTIVE_DBKEY_SECRET_ID`] slot once every consumer (rekey,
    /// keychain write, hardware-vault seal) has had its turn — the
    /// promote happens inside one critical section so a concurrent
    /// `secrets_get` either sees the old `to` or the freshly-moved
    /// bytes, never neither.
    pub fn rename(&self, from: &str, to: &str) -> bool {
        if from == to {
            return self.has(from);
        }
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let Some(buf) = g.remove(from) else {
            return false;
        };
        // `buf` keeps its pin — the move doesn't relocate the heap
        // allocation. Only an overwritten `to` value needs unpinning.
        if let Some(old) = g.insert(to.to_string(), buf) {
            page_unlock(&old);
        }
        true
    }

    /// Snapshot of stored ids — debug/diagnostic only. Returns owned
    /// strings so the caller can drop the mutex before touching the
    /// list.
    pub fn ids(&self) -> Vec<String> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.keys().cloned().collect()
    }
}
#[cfg(test)]
#[path = "../tests/unit/secrets.rs"]
mod tests;
