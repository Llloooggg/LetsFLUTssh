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
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::oneshot;

/// Generic prompt-id → oneshot-response registry. `R` is the
/// per-call response type the calling module wants delivered to
/// the awaiter — `Result<(), String>` for seal calls, a typed
/// enum for credential responses, a `String` for probe wire
/// names, etc.
pub struct PromptRegistry<R: Send + 'static> {
    inner: Arc<Mutex<HashMap<String, oneshot::Sender<R>>>>,
}

impl<R: Send + 'static> PromptRegistry<R> {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Park a fresh oneshot under `prompt_id` and return the
    /// receiver. The awaiting Rust handler holds the receiver
    /// across whatever event-publish + Dart-handler round-trip
    /// the prompt drives.
    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<R> {
        let (tx, rx) = oneshot::channel();
        Self::lock_arc(&self.inner).insert(prompt_id, tx);
        rx
    }

    /// Park a fresh oneshot under `prompt_id` with an auto-cancel
    /// guard. When the timeout elapses before any
    /// [`resolve`](Self::resolve) / [`cancel`](Self::cancel)
    /// removes the entry, the entry is dropped — the awaiting
    /// receiver wakes with `Err(RecvError)`, which every caller
    /// already maps to a fail-safe default (no destructive
    /// action on an unanswered prompt).
    ///
    /// Default behaviour for callers that don't need a timeout is
    /// unchanged: keep calling [`register`](Self::register).
    pub fn register_with_timeout(
        &self,
        prompt_id: String,
        timeout: Duration,
    ) -> oneshot::Receiver<R> {
        let rx = self.register(prompt_id.clone());
        let inner = Arc::clone(&self.inner);
        tokio::spawn(async move {
            tokio::time::sleep(timeout).await;
            // `remove` returns `Some` only if no resolver got there
            // first; the resulting `Sender` drops out of scope here
            // and the awaiter's `rx.await` returns `Err`. Idempotent
            // on an already-resolved id.
            Self::lock_arc(&inner).remove(&prompt_id);
        });
        rx
    }

    /// Resolve a pending prompt with the user's response. Returns
    /// `true` when a receiver was actually woken; `false` when
    /// the id was unknown or already resolved.
    pub fn resolve(&self, prompt_id: &str, response: R) -> bool {
        let sender = Self::lock_arc(&self.inner).remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    /// Drop a pending prompt without resolving — used when the
    /// awaiting handler abandons the wait (connection teardown,
    /// shutdown). Idempotent on a missing id.
    pub fn cancel(&self, prompt_id: &str) {
        Self::lock_arc(&self.inner).remove(prompt_id);
    }

    /// Live entry count. Tests + diagnostics only.
    pub fn pending_count(&self) -> usize {
        Self::lock_arc(&self.inner).len()
    }

    fn lock_arc(
        m: &Arc<Mutex<HashMap<String, oneshot::Sender<R>>>>,
    ) -> std::sync::MutexGuard<'_, HashMap<String, oneshot::Sender<R>>> {
        m.lock().unwrap_or_else(|p| p.into_inner())
    }
}

impl<R: Send + 'static> Default for PromptRegistry<R> {
    fn default() -> Self {
        Self::new()
    }
}
#[cfg(test)]
#[path = "../../tests/unit/security_prompt_registry.rs"]
mod tests;
