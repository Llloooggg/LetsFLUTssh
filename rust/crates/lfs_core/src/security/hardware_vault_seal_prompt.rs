//! Per-prompt registry for the hardware-vault *seal* call. Mirrors
//! [`super::hardware_vault_unlock_prompt`] but carries the bytes
//! to be sealed alongside the optional PIN; the response is just
//! `Ok(())` on success or `Err(message)` on plugin / hardware
//! failure.
//!
//! Used by `tier_unlock_orchestrator::first_launch_hardware` so
//! the L3 first-launch arm goes through the same orchestrator +
//! listener pattern as the unlock arms — the orchestrator
//! generates a fresh DB key, asks the Dart subscriber to seal it
//! through `HardwareTierVault.store(key, pin)`, then stages the
//! same bytes in the SecretStore + emits the cascade.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// Outcome of the Dart-side hardware-vault seal call.
///
/// * `Ok(())` — seal succeeded; the bytes the orchestrator passed
///   in are now wrapped by the platform vault and the on-disk
///   blob has been written.
/// * `Err(msg)` — plugin/channel error or hardware refused. The
///   orchestrator falls back to the plaintext / wizard-rerun
///   path on the Dart side.
pub type HardwareVaultSealResponse = Result<(), String>;

/// Process-singleton registry of pending hardware-vault seal
/// prompts, keyed by caller-allocated prompt id (UUIDv4).
pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<HardwareVaultSealResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<HardwareVaultSealResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("hardware vault seal prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    pub fn resolve(&self, prompt_id: &str, response: HardwareVaultSealResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("hardware vault seal prompt registry mutex poisoned")
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .expect("hardware vault seal prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("hardware vault seal prompt registry mutex poisoned")
            .len()
    }
}

impl Default for PromptRegistry {
    fn default() -> Self {
        Self::new()
    }
}

pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}

#[cfg(test)]
mod tests {
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
}
