//! Process-singleton registry mapping connection ids to live
//! [`Provider`] handles. The Rust-side transfer worker pool looks
//! up the provider by connection id when running a non-SSH task —
//! the SSH path uses `app.connections` (the russh actor map) and
//! routes through `crate::sftp::Sftp`, but WebDAV / S3 have no
//! russh actor, so without this registry the worker couldn't reach
//! their providers.
//!
//! Lifecycle: the FRB connect helpers (`webdav_connect`,
//! `s3_connect`) call [`ProviderRegistry::register`] right after
//! the connect probe succeeds. The returned opaque FRB handle
//! (`WebDavConnection` / `S3Connection`) holds a
//! [`ProviderRegistration`] guard that calls
//! [`ProviderRegistry::unregister`] on `Drop` — so the moment the
//! Dart side drops its handle (disconnect, app teardown), the
//! global slot frees. The registry never owns the only `Arc` to
//! the provider; the opaque handle on the Dart side does. The
//! registry's clone is purely a back-channel for the transfer
//! worker.
//!
//! Keying by **connection id** rather than session id matches the
//! existing `app.connections: ConnectionRegistry` shape — a single
//! saved session can spawn multiple reconnect attempts, each with
//! its own connection id, and the transfer queue tracks tasks by
//! the connection id the file browser captured at enqueue time.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, Weak};

use crate::storage::Provider;

/// Process-singleton map: connection id → live [`Provider`].
///
/// Locking: a plain `Mutex` (not `RwLock`) — the registry is on
/// the hot path for every transfer task `execute`, but a transfer
/// rate of even 100/sec sees one lock per task lookup, and
/// contention against the connect/disconnect path is rare. Keep
/// the surface uniform with [`crate::secrets::SecretStore`].
#[derive(Default)]
pub struct ProviderRegistry {
    inner: Mutex<HashMap<String, Arc<dyn Provider>>>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register `provider` under `connection_id`. Replaces any
    /// prior entry under the same id — a re-connect on the same id
    /// (rare; the connections notifier mints a fresh UUID per
    /// attempt) gets the newer provider rather than two stale
    /// `Arc`s racing.
    pub fn register(&self, connection_id: &str, provider: Arc<dyn Provider>) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.insert(connection_id.to_string(), provider);
    }

    /// Drop the entry under `connection_id`. Idempotent on a
    /// missing id (the FRB-opaque `Drop` may race with an explicit
    /// disconnect).
    pub fn unregister(&self, connection_id: &str) {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.remove(connection_id);
    }

    /// Fetch a clone of the provider Arc for `connection_id`.
    /// Returns `None` when the slot is empty — the caller (the
    /// transfer executor) treats that as "this is an SSH session,
    /// fall through to the russh actor path".
    pub fn get(&self, connection_id: &str) -> Option<Arc<dyn Provider>> {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.get(connection_id).cloned()
    }

    /// Whether a slot exists for `connection_id`. Cheap probe
    /// used by tests; production callers use [`Self::get`].
    pub fn contains(&self, connection_id: &str) -> bool {
        let g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.contains_key(connection_id)
    }
}

/// RAII guard that unregisters a connection id on `Drop`. The
/// FRB-opaque connect handle owns one — when the Dart side drops
/// the handle the guard drops, the registry slot frees, and the
/// `Arc<dyn Provider>` clone the registry held releases.
///
/// `registry` is held as a `Weak` so a guard outliving the global
/// `AppState` (only conceivable during process teardown) doesn't
/// dereference a dangling pointer.
pub struct ProviderRegistration {
    connection_id: String,
    registry: Weak<ProviderRegistry>,
}

impl ProviderRegistration {
    /// Create a guard tied to `registry` for `connection_id`. The
    /// caller is responsible for having called
    /// [`ProviderRegistry::register`] before constructing the
    /// guard; the two operations bookend a single registration.
    pub fn new(registry: Weak<ProviderRegistry>, connection_id: String) -> Self {
        Self {
            connection_id,
            registry,
        }
    }
}

impl Drop for ProviderRegistration {
    fn drop(&mut self) {
        if let Some(registry) = self.registry.upgrade() {
            registry.unregister(&self.connection_id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{ByteStream, Entry, Metadata, ProviderFuture};
    use std::sync::atomic::{AtomicU32, Ordering};

    /// Tiny `Provider` stand-in — every method panics; tests below
    /// never call them. The registry only stores and surfaces the
    /// Arc; behaviour is irrelevant.
    struct NoopProvider {
        drops: Arc<AtomicU32>,
    }

    impl Drop for NoopProvider {
        fn drop(&mut self) {
            self.drops.fetch_add(1, Ordering::SeqCst);
        }
    }

    impl Provider for NoopProvider {
        fn list<'a>(&'a self, _: &'a str) -> ProviderFuture<'a, Vec<Entry>> {
            unimplemented!()
        }
        fn stat<'a>(&'a self, _: &'a str) -> ProviderFuture<'a, Metadata> {
            unimplemented!()
        }
        fn mkdir<'a>(&'a self, _: &'a str) -> ProviderFuture<'a, ()> {
            unimplemented!()
        }
        fn remove<'a>(&'a self, _: &'a str) -> ProviderFuture<'a, ()> {
            unimplemented!()
        }
        fn rename<'a>(&'a self, _: &'a str, _: &'a str) -> ProviderFuture<'a, ()> {
            unimplemented!()
        }
        fn get_stream<'a>(
            &'a self,
            _: &'a str,
            _: Option<(u64, u64)>,
        ) -> ProviderFuture<'a, ByteStream> {
            unimplemented!()
        }
        fn put_stream<'a>(
            &'a self,
            _: &'a str,
            _: ByteStream,
            _: Option<u64>,
        ) -> ProviderFuture<'a, ()> {
            unimplemented!()
        }
        fn dir_size<'a>(&'a self, _: &'a str) -> ProviderFuture<'a, u64> {
            unimplemented!()
        }
    }

    fn provider(drops: Arc<AtomicU32>) -> Arc<dyn Provider> {
        Arc::new(NoopProvider { drops })
    }

    #[test]
    fn register_then_get_returns_same_arc() {
        let drops = Arc::new(AtomicU32::new(0));
        let registry = ProviderRegistry::new();
        let p = provider(drops.clone());
        registry.register("c1", p.clone());
        let got = registry.get("c1").expect("registered");
        assert!(Arc::ptr_eq(&p, &got));
    }

    #[test]
    fn get_missing_id_returns_none() {
        let registry = ProviderRegistry::new();
        assert!(registry.get("missing").is_none());
    }

    #[test]
    fn unregister_drops_the_slot() {
        let drops = Arc::new(AtomicU32::new(0));
        let registry = ProviderRegistry::new();
        registry.register("c1", provider(drops.clone()));
        assert!(registry.contains("c1"));
        registry.unregister("c1");
        assert!(!registry.contains("c1"));
    }

    #[test]
    fn unregister_missing_id_is_idempotent() {
        let registry = ProviderRegistry::new();
        registry.unregister("never-registered");
        // No panic, no state.
        assert!(!registry.contains("never-registered"));
    }

    #[test]
    fn register_replaces_existing_entry_and_drops_prior_arc() {
        // Re-connect on the same id replaces the older provider.
        // The older `Arc` has only one strong reference left after
        // replacement (the test's `first`), and dropping that
        // drops the underlying NoopProvider — bumping the counter.
        let drops = Arc::new(AtomicU32::new(0));
        let registry = ProviderRegistry::new();
        let first = provider(drops.clone());
        registry.register("c1", first.clone());
        let second = provider(drops.clone());
        registry.register("c1", second);
        // Registry now owns `second`; `first` still has the
        // local reference — drop it and observe the counter rise.
        drop(first);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn registration_guard_unregisters_on_drop() {
        // The FRB-opaque handle owns a `ProviderRegistration`; when
        // the Dart side drops the handle the guard drops, and the
        // registry slot frees. This is the disconnect-on-handle-drop
        // contract — a leak here means a dropped session's provider
        // hangs around forever.
        let drops = Arc::new(AtomicU32::new(0));
        let registry = Arc::new(ProviderRegistry::new());
        registry.register("c1", provider(drops.clone()));
        assert!(registry.contains("c1"));
        let guard = ProviderRegistration::new(Arc::downgrade(&registry), "c1".into());
        drop(guard);
        assert!(!registry.contains("c1"));
    }

    #[test]
    fn registration_guard_after_app_teardown_is_a_noop() {
        // The guard holds a `Weak` to the registry so a guard that
        // outlives the global `AppState` (process teardown) doesn't
        // dereference a dangling pointer when it drops.
        let registry = Arc::new(ProviderRegistry::new());
        let weak = Arc::downgrade(&registry);
        let guard = ProviderRegistration::new(weak, "c1".into());
        drop(registry); // Simulate app teardown.
        drop(guard); // Must not panic / segfault.
    }
}
