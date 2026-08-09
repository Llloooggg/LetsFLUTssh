/// Unit tests extracted from secrets.rs
/// Declared via `#[path] mod tests;` in the source file.
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
