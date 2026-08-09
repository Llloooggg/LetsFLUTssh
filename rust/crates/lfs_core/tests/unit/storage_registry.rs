/// Unit tests extracted from storage/registry.rs
/// Declared via `#[path] mod tests;` in the source file.
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
