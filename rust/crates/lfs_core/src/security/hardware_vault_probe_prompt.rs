//! Per-prompt registry for the hardware-vault probe the
//! capabilities orchestrator runs on Apple / Android / Windows.
//!
//! Linux uses the in-process `lfs_core::platform::linux::tpm`
//! probe directly (no Dart round-trip needed); the other three
//! platforms route through `MethodChannel('com.letsflutssh/
//! hardware_vault').invokeMethod('probeDetail')` which only
//! Dart can reach. The Dart subscriber returns the platform-
//! specific reason code verbatim — `"available"`, `"unknown"`,
//! `"no_secure_enclave"`, `"strongbox_unavailable"`,
//! `"tpm_missing"`, etc. The orchestrator stores it in the
//! `SecurityCapabilities.hardware_probe_code` field; the wizard
//! / Settings UI maps it back to localised reason copy.
//!
//! `MethodChannel` access stays Dart-side because the Flutter
//! plugin already audits those entry points and there is no
//! parallel native plugin per platform. The registry's typed
//! response (a code string) keeps the Dart subscriber's
//! responsibility narrow — execute the channel call, return
//! the verbatim code.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// Outcome of the Dart `MethodChannel` probe call. Free-form
/// platform code string — `"available"` is the canonical
/// success value, everything else is a per-platform unavail
/// reason. `"unknown"` covers the channel-unreachable / no-
/// such-method case.
pub type HardwareVaultProbeResponse = String;

pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<HardwareVaultProbeResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<HardwareVaultProbeResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("hardware vault probe prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    pub fn resolve(&self, prompt_id: &str, response: HardwareVaultProbeResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("hardware vault probe prompt registry mutex poisoned")
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .expect("hardware vault probe prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("hardware vault probe prompt registry mutex poisoned")
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
    async fn unknown_code_round_trips() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p2".into());
        assert!(reg.resolve("p2", "no_secure_enclave".into()));
        assert_eq!(rx.await.unwrap(), "no_secure_enclave");
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
