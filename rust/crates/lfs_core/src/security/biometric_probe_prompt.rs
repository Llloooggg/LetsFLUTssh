//! Per-prompt-type registry for biometric capability probes
//! (Decision 1 / C5 in `docs/RUST_MIGRATION_REMAINING.md`).
//!
//! The L3 hardware-tier path needs to know whether the platform
//! biometric API is reachable + has an enrolment configured. The
//! probe itself is a Dart-plugin call (`local_auth.canCheckBiometrics`
//! on every platform; `BiometricManager.canAuthenticate` on
//! Android via the plugin); the Rust capability cache fires this
//! prompt and awaits the typed response.
//!
//! Mirrors `lfs_core::security::keychain_pepper_prompt::PromptRegistry`
//! shape — typed `tokio::oneshot::Sender<BiometricProbeResponse>`
//! per prompt id. Per Decision 1: per-prompt-type typed registry.
//! Per Decision 2: biometric plugin stays Dart-side (no mature
//! Rust crate covers every target platform's `local_auth` shape).
//!
//! **Currently not wired into the production capabilities probe.**
//! Lands ahead of C5 so the `SecurityCapabilities` cache actor
//! commit (C5+) targets a stable registry API.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// What the Dart subscriber found out about the platform's
/// biometric API.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BiometricProbeResponse {
    /// True when `local_auth.canCheckBiometrics` returns true
    /// AND there's at least one enrolled fingerprint / face.
    /// `false` covers every other case (no hardware, no
    /// enrolment, plugin error, simulator).
    pub available: bool,
    /// Stable classifier code so the UI shows an actionable
    /// hint. Mirrors the per-platform `HardwareProbeDetail`
    /// enum's biometric-side wire shape (`ios_passcode_not_set`
    /// / `android_no_enrolment` / `linux_no_fprintd` / etc).
    /// Empty when `available == true`.
    pub classifier_code: String,
}

/// Process-singleton registry of pending biometric probes.
pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<BiometricProbeResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<BiometricProbeResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("biometric probe prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    pub fn resolve(&self, prompt_id: &str, response: BiometricProbeResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("biometric probe prompt registry mutex poisoned")
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .expect("biometric probe prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("biometric probe prompt registry mutex poisoned")
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
    async fn available_response_carries_empty_classifier() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p1".into());
        assert!(reg.resolve(
            "p1",
            BiometricProbeResponse {
                available: true,
                classifier_code: String::new(),
            }
        ));
        let got = rx.await.unwrap();
        assert!(got.available);
        assert!(got.classifier_code.is_empty());
    }

    #[tokio::test]
    async fn unavailable_response_carries_classifier_code() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p2".into());
        assert!(reg.resolve(
            "p2",
            BiometricProbeResponse {
                available: false,
                classifier_code: "ios_passcode_not_set".into(),
            }
        ));
        let got = rx.await.unwrap();
        assert!(!got.available);
        assert_eq!(got.classifier_code, "ios_passcode_not_set");
    }

    #[test]
    fn resolve_unknown_prompt_id_is_noop() {
        let reg = PromptRegistry::new();
        assert!(!reg.resolve(
            "ghost",
            BiometricProbeResponse {
                available: false,
                classifier_code: String::new(),
            }
        ));
    }

    #[test]
    fn cancel_drops_without_resolving() {
        let reg = PromptRegistry::new();
        let _rx = reg.register("p3".into());
        reg.cancel("p3");
        assert_eq!(reg.pending_count(), 0);
    }

    #[test]
    fn pending_count_isolated_per_id() {
        let reg = PromptRegistry::new();
        let _r1 = reg.register("a".into());
        let _r2 = reg.register("b".into());
        assert_eq!(reg.pending_count(), 2);
    }
}
