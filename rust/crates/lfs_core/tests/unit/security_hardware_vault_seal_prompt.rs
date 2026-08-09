/// Unit tests extracted from security/hardware_vault_seal_prompt.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn round_trips_success() {
    let reg = PromptRegistry::new();
    let rx = reg.register("s1".into());
    assert!(reg.resolve("s1", Ok(())));
    assert_eq!(rx.await.unwrap(), Ok(()));
}

#[tokio::test]
async fn round_trips_plugin_error() {
    let reg = PromptRegistry::new();
    let rx = reg.register("s2".into());
    assert!(reg.resolve("s2", Err("tpm2-tools missing".into())));
    assert_eq!(rx.await.unwrap(), Err("tpm2-tools missing".into()));
}

#[test]
fn cancel_drops_without_resolving() {
    let reg = PromptRegistry::new();
    let _rx = reg.register("s".into());
    reg.cancel("s");
    assert_eq!(reg.pending_count(), 0);
    assert!(!reg.resolve("s", Ok(())));
}
