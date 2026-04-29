//! Per-prompt registry for the keychain probe the
//! capabilities orchestrator runs.
//!
//! The probe asks Dart "is the OS secure storage reachable?":
//! Linux subscribers run a `gdbus call …
//! org.freedesktop.secrets` ping; non-Linux subscribers do a
//! live `flutter_secure_storage.write/read/delete` round-trip
//! against a transient probe key. Both shapes collapse to the
//! same response — the wire name of the
//! `lfs_core::security::capabilities::KeyringProbeResult` enum.
//!
//! `flutter_secure_storage` access stays Dart-side because the
//! Flutter plugin already audits those entry points and there
//! is no mature Rust crate covering every target platform's
//! keychain shape. The registry uses a typed response (the
//! enum's wire name) rather than a free-form payload so a
//! Dart-side typo at the wire-name layer surfaces as a
//! `from_wire_name` decode failure rather than a silent
//! mis-classification.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// Outcome of a Dart-side keychain probe call. Wire name of one
/// of the `KeyringProbeResult` variants — `"available"`,
/// `"linuxNoSecretService"`, `"probeFailed"`. The orchestrator
/// maps the string back to the typed enum.
pub type KeychainProbeResponse = String;

pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<KeychainProbeResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<KeychainProbeResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("keychain probe prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    pub fn resolve(&self, prompt_id: &str, response: KeychainProbeResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("keychain probe prompt registry mutex poisoned")
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .expect("keychain probe prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("keychain probe prompt registry mutex poisoned")
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
}
