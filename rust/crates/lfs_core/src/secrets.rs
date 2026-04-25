//! Process-singleton secret store. Plaintext credentials (passwords,
//! key bytes, passphrases) live here, not on the Dart heap. Dart
//! sees only metadata (`hasPassword: bool`, etc.) and references
//! the secrets by id.
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
        let mut g = self.inner.lock().expect("secrets lock");
        g.insert(id.to_string(), Zeroizing::new(bytes.to_vec()));
    }

    pub fn has(&self, id: &str) -> bool {
        let g = self.inner.lock().expect("secrets lock");
        g.contains_key(id)
    }

    /// Return a fresh copy of the stored bytes. Caller owns the
    /// scrub-on-drop guarantee for the returned buffer.
    pub fn get(&self, id: &str) -> Option<Zeroizing<Vec<u8>>> {
        let g = self.inner.lock().expect("secrets lock");
        g.get(id).map(|v| Zeroizing::new(v.to_vec()))
    }

    /// Remove the entry under `id`. Idempotent.
    pub fn drop_id(&self, id: &str) {
        let mut g = self.inner.lock().expect("secrets lock");
        g.remove(id);
    }

    /// Drop every secret under any id. Used by the auth-failure
    /// recovery path that wipes all cached credentials at once.
    pub fn clear(&self) {
        let mut g = self.inner.lock().expect("secrets lock");
        g.clear();
    }

    /// Snapshot of stored ids — debug/diagnostic only. Returns owned
    /// strings so the caller can drop the mutex before touching the
    /// list.
    pub fn ids(&self) -> Vec<String> {
        let g = self.inner.lock().expect("secrets lock");
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
}
