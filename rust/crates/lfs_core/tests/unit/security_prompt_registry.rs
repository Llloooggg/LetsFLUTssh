/// Unit tests extracted from security/prompt_registry.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn register_resolve_round_trips_arbitrary_response() {
    let reg: PromptRegistry<u32> = PromptRegistry::new();
    let rx = reg.register("a".into());
    assert!(reg.resolve("a", 42));
    assert_eq!(rx.await.unwrap(), 42);
    assert_eq!(reg.pending_count(), 0);
}

#[tokio::test]
async fn round_trips_result_response() {
    let reg: PromptRegistry<Result<(), String>> = PromptRegistry::new();
    let rx = reg.register("ok".into());
    assert!(reg.resolve("ok", Ok(())));
    assert_eq!(rx.await.unwrap(), Ok(()));

    let rx = reg.register("err".into());
    assert!(reg.resolve("err", Err("boom".into())));
    assert_eq!(rx.await.unwrap(), Err("boom".into()));
}

#[test]
fn cancel_drops_without_resolving() {
    let reg: PromptRegistry<u32> = PromptRegistry::new();
    let _rx = reg.register("p".into());
    reg.cancel("p");
    assert_eq!(reg.pending_count(), 0);
    assert!(!reg.resolve("p", 1));
}

#[test]
fn resolve_unknown_prompt_id_is_noop() {
    let reg: PromptRegistry<u32> = PromptRegistry::new();
    assert!(!reg.resolve("ghost", 0));
}

#[tokio::test]
async fn poisoned_mutex_recovers_via_into_inner() {
    // Spawn a thread that locks the registry and panics, then
    // verify subsequent calls still resolve cleanly. Mirrors
    // the FRB-side poison-recovery contract.
    let reg: &'static PromptRegistry<u32> = Box::leak(Box::new(PromptRegistry::new()));
    let inner = Arc::clone(&reg.inner);
    let h = std::thread::spawn(move || {
        let _g = inner.lock().unwrap_or_else(|p| p.into_inner());
        panic!("intentional poison");
    });
    let _ = h.join();
    assert!(reg.inner.is_poisoned());
    // Recovery path — register + resolve still work.
    let rx = reg.register("post".into());
    assert!(reg.resolve("post", 7));
    assert_eq!(rx.await.unwrap(), 7);
}

#[tokio::test]
async fn register_with_timeout_drops_pending_entry_on_expiry() {
    // Caller registers but the Dart subscriber never dispatches
    // a response. After the timeout the entry must be gone from
    // the map and the awaiter must wake with Err — every caller
    // already routes that to a fail-safe default.
    let reg: PromptRegistry<u32> = PromptRegistry::new();
    let rx = reg.register_with_timeout("slow".into(), Duration::from_millis(50));
    assert_eq!(reg.pending_count(), 1, "entry parked at register time");
    // Awaiting the receiver yields the timeout cancellation —
    // the spawned guard drops the sender out of the map.
    let outcome = rx.await;
    assert!(outcome.is_err(), "receiver must wake with Err on timeout");
    assert_eq!(reg.pending_count(), 0, "guard removed the pending entry");
}

#[tokio::test]
async fn register_with_timeout_does_not_clobber_resolved_entry() {
    // A resolve that lands before the timeout must win — the
    // guard's later remove() is a no-op (the id is gone) and
    // the awaiter sees the resolved value.
    let reg: PromptRegistry<u32> = PromptRegistry::new();
    let rx = reg.register_with_timeout("fast".into(), Duration::from_millis(200));
    assert!(reg.resolve("fast", 99));
    assert_eq!(rx.await.unwrap(), 99);
    // Let the timeout fire; the late guard must not bring the
    // pending_count above zero.
    tokio::time::sleep(Duration::from_millis(250)).await;
    assert_eq!(reg.pending_count(), 0);
}
