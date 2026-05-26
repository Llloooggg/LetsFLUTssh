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
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.insert(id.to_string(), Zeroizing::new(bytes.to_vec()));
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
        g.remove(id);
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
        g.remove(id)
    }

    /// Drop every secret under any id. Used by the auth-failure
    /// recovery path that wipes all cached credentials at once.
    pub fn clear(&self) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
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
        g.insert(to.to_string(), buf);
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
mod tests {
    use super::*;

    #[test]
    fn put_get_round_trip() {
        let store = SecretStore::new();
        store.put("k1", b"hello");
        let got = store.get("k1").unwrap();
        assert_eq!(&*got, b"hello");
    }

    #[test]
    fn missing_id_returns_none() {
        let store = SecretStore::new();
        assert!(store.get("missing").is_none());
        assert!(!store.has("missing"));
    }

    #[test]
    fn put_replaces_existing() {
        let store = SecretStore::new();
        store.put("k1", b"first");
        store.put("k1", b"second");
        assert_eq!(&*store.get("k1").unwrap(), b"second");
    }

    #[test]
    fn drop_id_is_idempotent() {
        let store = SecretStore::new();
        store.put("k1", b"x");
        store.drop_id("k1");
        store.drop_id("k1");
        assert!(!store.has("k1"));
    }

    #[test]
    fn clear_drops_everything() {
        let store = SecretStore::new();
        store.put("k1", b"a");
        store.put("k2", b"b");
        store.clear();
        assert_eq!(store.ids().len(), 0);
    }

    #[test]
    fn rename_moves_bytes_atomically() {
        let store = SecretStore::new();
        store.put("transient", b"hello");
        assert!(store.rename("transient", "active"));
        assert!(!store.has("transient"));
        assert_eq!(&*store.get("active").unwrap(), b"hello");
    }

    #[test]
    fn rename_replaces_existing_target() {
        let store = SecretStore::new();
        store.put("transient", b"new");
        store.put("active", b"old");
        store.rename("transient", "active");
        assert_eq!(&*store.get("active").unwrap(), b"new");
        assert!(!store.has("transient"));
    }

    #[test]
    fn rename_self_is_idempotent_when_present() {
        let store = SecretStore::new();
        store.put("k", b"x");
        assert!(store.rename("k", "k"));
        assert_eq!(&*store.get("k").unwrap(), b"x");
    }

    #[test]
    fn rename_returns_false_when_source_absent() {
        let store = SecretStore::new();
        store.put("active", b"keep");
        assert!(!store.rename("missing", "active"));
        // Target untouched.
        assert_eq!(&*store.get("active").unwrap(), b"keep");
    }
}
