/// Unit tests extracted from app.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn init_is_idempotent() {
    let a = init();
    let b = init();
    assert!(Arc::ptr_eq(&a, &b));
}

#[test]
fn secrets_round_trip_via_singleton() {
    let app = init();
    app.secrets.put("singleton-test", b"value");
    assert_eq!(&*app.secrets.get("singleton-test").unwrap(), b"value");
    app.secrets.drop_id("singleton-test");
}
