/// Unit tests extracted from security/keychain_probe_prompt.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn register_and_resolve_round_trips() {
    let reg = PromptRegistry::new();
    let rx = reg.register("p1".into());
    assert!(reg.resolve("p1", "available".into()));
    assert_eq!(rx.await.unwrap(), "available");
    assert_eq!(reg.pending_count(), 0);
}

#[tokio::test]
async fn linux_no_secret_service_round_trips() {
    let reg = PromptRegistry::new();
    let rx = reg.register("p2".into());
    assert!(reg.resolve("p2", "linuxNoSecretService".into()));
    assert_eq!(rx.await.unwrap(), "linuxNoSecretService");
}

#[test]
fn cancel_drops_without_resolving() {
    let reg = PromptRegistry::new();
    let _rx = reg.register("p".into());
    reg.cancel("p");
    assert_eq!(reg.pending_count(), 0);
    assert!(!reg.resolve("p", "available".into()));
}
