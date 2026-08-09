/// Unit tests extracted from security/hardware_vault_unlock_prompt.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn round_trips_success() {
    let reg = PromptRegistry::new();
    let rx = reg.register("u1".into());
    assert!(reg.resolve("u1", Ok(Some(vec![1, 2, 3]))));
    assert_eq!(rx.await.unwrap(), Ok(Some(vec![1, 2, 3])));
}

#[tokio::test]
async fn round_trips_wrong_pin() {
    let reg = PromptRegistry::new();
    let rx = reg.register("u2".into());
    assert!(reg.resolve("u2", Ok(None)));
    assert_eq!(rx.await.unwrap(), Ok(None));
}

#[tokio::test]
async fn round_trips_plugin_error() {
    let reg = PromptRegistry::new();
    let rx = reg.register("u3".into());
    assert!(reg.resolve("u3", Err("channel missing".into())));
    assert_eq!(rx.await.unwrap(), Err("channel missing".into()));
}

#[test]
fn cancel_drops_without_resolving() {
    let reg = PromptRegistry::new();
    let _rx = reg.register("u".into());
    reg.cancel("u");
    assert_eq!(reg.pending_count(), 0);
    assert!(!reg.resolve("u", Ok(None)));
}
