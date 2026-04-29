//! Per-prompt registry for keychain *write* / *delete* /
//! *contains* operations the Rust actors need to compose without
//! hosting the `flutter_secure_storage` audit perimeter
//! themselves.
//!
//! Mirrors the read-only `keychain_pepper_prompt::PromptRegistry`
//! shape; the read path is intentionally kept on its own
//! single-purpose registry so the existing wiring + tests don't
//! churn. This module covers the write / delete / contains ops
//! the L2 setPassword / clear / isConfigured actor commands need
//! and the keychain-purge wipe path hooks into.
//!
//! Plaintext discipline: the pepper bytes are base64-encoded on
//! the way through the bus event so the JSON-shaped FRB carrier
//! never has to round-trip raw bytes through serde_json.
//! Discipline matches the existing `letsflutssh_l2_pepper` Dart
//! storage format (base64 string in flutter_secure_storage).

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// Op the Dart subscriber must execute when it sees the matching
/// `BusEvent::KeychainOpPromptRequest`. Wire names match the
/// strings carried over the bus + FRB so the Dart side branches
/// on a typed enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeychainOpKind {
    /// `flutter_secure_storage.read(key)` → bytes (base64-decoded
    /// by the Dart subscriber before responding).
    Read,
    /// `flutter_secure_storage.containsKey(key)` → presence bool
    /// surfaced as `Ok(Some(empty))` on hit, `Ok(None)` on miss.
    Contains,
    /// `flutter_secure_storage.write(key, value_b64)`. Response
    /// `Ok(None)` on success, `Err(msg)` on failure — caller
    /// rolls back any prior disk side-effects on failure.
    Write { value_b64: String },
    /// `flutter_secure_storage.delete(key)`. Response `Ok(None)`
    /// on success, `Err(msg)` on failure.
    Delete,
}

impl KeychainOpKind {
    pub fn wire_name(&self) -> &'static str {
        match self {
            KeychainOpKind::Read => "read",
            KeychainOpKind::Contains => "contains",
            KeychainOpKind::Write { .. } => "write",
            KeychainOpKind::Delete => "delete",
        }
    }
}

/// Outcome of the Dart-side keychain plugin call.
///
/// * `Ok(Some(bytes))` — `Read` returned bytes, or `Contains`
///   returned true (bytes empty in the latter case).
/// * `Ok(None)` — `Read` / `Contains` missed (no entry), or
///   `Write` / `Delete` succeeded.
/// * `Err(msg)` — plugin error. The actor branches on this to
///   decide whether to roll back (write path) or log + swallow
///   (delete path).
pub type KeychainOpResponse = Result<Option<Vec<u8>>, String>;

/// Process-singleton registry of pending keychain op prompts,
/// keyed by caller-allocated prompt id (UUIDv4).
///
/// The Rust actor:
///   1. Allocates a prompt id
///   2. Calls [`PromptRegistry::register`] to park a fresh
///      oneshot
///   3. Publishes a `BusEvent::KeychainOpPromptRequest` with
///      the prompt id + key + op wire name + (for write)
///      base64-encoded value
///   4. Awaits the oneshot receiver
///
/// The Dart subscriber (`keychain_op_prompt_listener.dart`)
/// dispatches the matching `flutter_secure_storage` call after
/// seeing the bus event; the FRB shim wakes the receiver via
/// [`PromptRegistry::resolve`].
pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<KeychainOpResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Park a fresh oneshot under `prompt_id` and return the
    /// receiver. Caller awaits the receiver after publishing
    /// the matching `KeychainOpPromptRequest` event.
    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<KeychainOpResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("keychain op prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    /// Resolve a pending prompt with the keychain op result.
    /// Idempotent — a missing prompt id (already resolved, or
    /// the awaiting side timed out) is a no-op. Returns `true`
    /// when a receiver was actually woken.
    pub fn resolve(&self, prompt_id: &str, response: KeychainOpResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("keychain op prompt registry mutex poisoned")
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
            .expect("keychain op prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("keychain op prompt registry mutex poisoned")
            .len()
    }
}

impl Default for PromptRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton instance — actors and the FRB response shim
/// share this. Tests use `PromptRegistry::new` directly.
pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn write_op_round_trips_success() {
        let reg = PromptRegistry::new();
        let rx = reg.register("w1".into());
        assert!(reg.resolve("w1", Ok(None)));
        let received = rx.await.unwrap();
        assert_eq!(received, Ok(None));
    }

    #[tokio::test]
    async fn write_op_round_trips_failure() {
        let reg = PromptRegistry::new();
        let rx = reg.register("w2".into());
        assert!(reg.resolve("w2", Err("plugin: locked".into())));
        let received = rx.await.unwrap();
        assert_eq!(received, Err("plugin: locked".into()));
    }

    #[tokio::test]
    async fn contains_op_present_returns_some_empty() {
        // Dart subscriber surfaces "key present" as Ok(Some(empty bytes)).
        let reg = PromptRegistry::new();
        let rx = reg.register("c1".into());
        assert!(reg.resolve("c1", Ok(Some(Vec::new()))));
        assert_eq!(rx.await.unwrap(), Ok(Some(Vec::new())));
    }

    #[tokio::test]
    async fn contains_op_absent_returns_none() {
        let reg = PromptRegistry::new();
        let rx = reg.register("c2".into());
        assert!(reg.resolve("c2", Ok(None)));
        assert_eq!(rx.await.unwrap(), Ok(None));
    }

    #[test]
    fn wire_names_round_trip() {
        assert_eq!(KeychainOpKind::Read.wire_name(), "read");
        assert_eq!(KeychainOpKind::Contains.wire_name(), "contains");
        assert_eq!(
            KeychainOpKind::Write {
                value_b64: "x".into()
            }
            .wire_name(),
            "write"
        );
        assert_eq!(KeychainOpKind::Delete.wire_name(), "delete");
    }

    #[test]
    fn cancel_drops_without_resolving() {
        let reg = PromptRegistry::new();
        let _rx = reg.register("p".into());
        reg.cancel("p");
        assert_eq!(reg.pending_count(), 0);
        assert!(!reg.resolve("p", Ok(None)));
    }

    #[test]
    fn resolve_unknown_id_is_noop() {
        let reg = PromptRegistry::new();
        assert!(!reg.resolve("ghost", Ok(None)));
    }
}
