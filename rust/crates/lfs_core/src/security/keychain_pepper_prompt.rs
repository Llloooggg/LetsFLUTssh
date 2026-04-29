//! Per-prompt-type registry for the L2 keychain-pepper-read
//! callback.
//!
//! Mirrors the existing `lfs_core::known_hosts::PromptRegistry`
//! shape — typed `tokio::oneshot::Sender<Option<Vec<u8>>>` per
//! prompt id, registered by the awaiting Rust handler, resolved
//! by the Dart subscriber after the
//! `flutter_secure_storage.read('letsflutssh_l2_pepper')`
//! plugin call returns.
//!
//! Keychain access stays Dart-side because the Flutter plugin
//! already audits that entry point and there is no native Rust
//! crate covering every target platform's keychain backend.
//! The typed per-prompt response (not a generic JSON shape)
//! keeps a Dart-side typo at the wire layer surfacing as a
//! decode failure rather than a silent miscompare.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// Outcome of a keychain pepper read on the Dart side. `None`
/// = the keychain entry is missing (uninitialised / wiped) or
/// the platform plugin returned an error; the Rust caller
/// treats either as "no pepper available" and routes the user
/// through the L2 reset path.
pub type PepperResponse = Option<Vec<u8>>;

/// Process-singleton registry of pending keychain-pepper reads,
/// keyed by caller-allocated prompt id (UUIDv4). The Rust gate
/// actor:
///   1. Allocates a UUIDv4 prompt id
///   2. Calls [`PromptRegistry::register`] to park a fresh
///      oneshot under the id
///   3. Publishes a `BusEvent::KeychainPepperPromptRequest`
///      with the prompt id
///   4. Awaits the oneshot receiver
///
/// The Dart subscriber dispatches the response command after
/// the `flutter_secure_storage.read` returns; the FRB shim
/// wakes the receiver via [`PromptRegistry::resolve`].
pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<PepperResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Park a fresh oneshot under `prompt_id` and return the
    /// receiver. Caller awaits the receiver after publishing
    /// the matching `KeychainPepperPromptRequest` event.
    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<PepperResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("keychain pepper prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    /// Resolve a pending prompt with the keychain read result.
    /// `None` = entry missing / read failed. Idempotent — a
    /// missing prompt id (already resolved, or the awaiting
    /// side timed out) is a no-op. Returns `true` when a
    /// receiver was actually woken.
    pub fn resolve(&self, prompt_id: &str, response: PepperResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("keychain pepper prompt registry mutex poisoned")
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    /// Drop a pending prompt without resolving — used by
    /// handlers that abandon the await (timeout, shutdown).
    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .expect("keychain pepper prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("keychain pepper prompt registry mutex poisoned")
            .len()
    }
}

impl Default for PromptRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton instance — the L2 gate actor and the FRB
/// response shim share this. Tests use `PromptRegistry::new`
/// directly so they don't share state through `instance()`.
pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn register_and_resolve_round_trips_a_response() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p1".into());
        assert_eq!(reg.pending_count(), 1);
        assert!(reg.resolve("p1", Some(vec![1, 2, 3])));
        let received = rx.await.unwrap();
        assert_eq!(received, Some(vec![1, 2, 3]));
        assert_eq!(reg.pending_count(), 0);
    }

    #[tokio::test]
    async fn register_and_resolve_with_missing_pepper_returns_none() {
        // Keychain entry missing / read failed — Dart returns
        // None and the awaiting Rust caller routes through the
        // L2 reset path.
        let reg = PromptRegistry::new();
        let rx = reg.register("p2".into());
        assert!(reg.resolve("p2", None));
        let received = rx.await.unwrap();
        assert_eq!(received, None);
    }

    #[test]
    fn resolve_unknown_prompt_id_is_noop() {
        // Idempotent — a duplicate response (already resolved)
        // or a timed-out await must not panic.
        let reg = PromptRegistry::new();
        assert!(!reg.resolve("ghost", Some(vec![])));
        assert!(!reg.resolve("ghost", None));
    }

    #[test]
    fn cancel_drops_without_resolving() {
        let reg = PromptRegistry::new();
        let _rx = reg.register("p3".into());
        assert_eq!(reg.pending_count(), 1);
        reg.cancel("p3");
        assert_eq!(reg.pending_count(), 0);
        // Resolving the cancelled id is a no-op.
        assert!(!reg.resolve("p3", Some(vec![])));
    }

    #[tokio::test]
    async fn dropping_receiver_makes_resolve_return_false() {
        // Receiver dropped (caller cancelled the await) —
        // tx.send fails silently, resolve returns false to let
        // the caller log the orphaned prompt.
        let reg = PromptRegistry::new();
        let rx = reg.register("p4".into());
        drop(rx);
        assert!(!reg.resolve("p4", Some(vec![1])));
    }

    #[test]
    fn multiple_concurrent_prompts_isolated_by_id() {
        // Two concurrent unlocks (e.g. two windows) get
        // independent prompts; resolving one doesn't affect the
        // other.
        let reg = PromptRegistry::new();
        let _rx1 = reg.register("a".into());
        let _rx2 = reg.register("b".into());
        assert_eq!(reg.pending_count(), 2);
        assert!(reg.resolve("a", Some(vec![1])));
        assert_eq!(reg.pending_count(), 1);
        assert!(reg.resolve("b", Some(vec![2])));
        assert_eq!(reg.pending_count(), 0);
    }
}
