//! Generic prompt-id → oneshot-response registry.
//!
//! Five modules under `lfs_core::security` (`credential_prompt`,
//! `keychain_probe_prompt`, `hardware_vault_probe_prompt`,
//! `hardware_vault_unlock_prompt`, `hardware_vault_seal_prompt`)
//! all carried byte-for-byte the same shape: a
//! `Mutex<HashMap<String, oneshot::Sender<R>>>` plus
//! register / resolve / cancel / pending_count over `R`. ≈600
//! LOC of copy-paste the type-system collapses to one generic.
//!
//! This module owns the canonical [`PromptRegistry<R>`]; each
//! per-prompt module re-aliases the generic with its specific
//! response type and keeps its own process-singleton + module-
//! level helpers (e.g. `wire_name` enums).
//!
//! ## Contract
//!
//! - `register(id)` parks a fresh `oneshot` channel under `id`
//!   and returns the receiver. Caller awaits it.
//! - `resolve(id, response)` removes the pending entry, sends
//!   the response, returns `true` when a receiver was actually
//!   woken, `false` when the id was unknown (already resolved,
//!   awaiting side timed out, etc.).
//! - `cancel(id)` drops the pending sender without sending —
//!   used by handlers that abandon the await on TCP teardown /
//!   shutdown / parent-bastion failure.
//! - `pending_count()` exposes the live entry count for tests +
//!   diagnostics.
//!
//! Mutex sites use `unwrap_or_else(|p| p.into_inner())` recovery
//! rather than `expect("...poisoned")` — the registries are
//! reachable from FRB-served paths and a panic across that
//! boundary corrupts in-flight Dart Futures, the same FFI-safety
//! discipline the rest of the FRB-adjacent lock sites apply.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// Generic prompt-id → oneshot-response registry. `R` is the
/// per-call response type the calling module wants delivered to
/// the awaiter — `Result<(), String>` for seal calls, a typed
/// enum for credential responses, a `String` for probe wire
/// names, etc.
pub struct PromptRegistry<R: Send + 'static> {
    inner: Mutex<HashMap<String, oneshot::Sender<R>>>,
}

impl<R: Send + 'static> PromptRegistry<R> {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Park a fresh oneshot under `prompt_id` and return the
    /// receiver. The awaiting Rust handler holds the receiver
    /// across whatever event-publish + Dart-handler round-trip
    /// the prompt drives.
    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<R> {
        let (tx, rx) = oneshot::channel();
        self.lock().insert(prompt_id, tx);
        rx
    }

    /// Resolve a pending prompt with the user's response. Returns
    /// `true` when a receiver was actually woken; `false` when
    /// the id was unknown or already resolved.
    pub fn resolve(&self, prompt_id: &str, response: R) -> bool {
        let sender = self.lock().remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    /// Drop a pending prompt without resolving — used when the
    /// awaiting handler abandons the wait (connection teardown,
    /// shutdown). Idempotent on a missing id.
    pub fn cancel(&self, prompt_id: &str) {
        self.lock().remove(prompt_id);
    }

    /// Live entry count. Tests + diagnostics only.
    pub fn pending_count(&self) -> usize {
        self.lock().len()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, oneshot::Sender<R>>> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
}

impl<R: Send + 'static> Default for PromptRegistry<R> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
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
        let h = std::thread::spawn(move || {
            let _g = reg.lock();
            panic!("intentional poison");
        });
        let _ = h.join();
        assert!(reg.inner.is_poisoned());
        // Recovery path — register + resolve still work.
        let rx = reg.register("post".into());
        assert!(reg.resolve("post", 7));
        assert_eq!(rx.await.unwrap(), 7);
    }
}
