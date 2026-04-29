//! Per-prompt-type registry for connection credential prompts
//! (Decision 1 / A3 in `docs/RUST_MIGRATION_REMAINING.md`).
//!
//! Mirrors `lfs_core::security::keychain_pepper_prompt::PromptRegistry`
//! shape — typed `tokio::oneshot::Sender<CredentialResponse>` per
//! prompt id, registered by the awaiting Rust connection handler,
//! resolved by the Dart subscriber after the user types a secret
//! into the unlock dialog.
//!
//! Per Decision 1: per-prompt-type typed registry, not a generic
//! JSON shape. Per Decision 2: the Dart UI dialog stays Dart-side
//! (UI rendering is not portable across platforms via Rust); the
//! Rust actor publishes the request + awaits the response.
//!
//! **Currently not wired into the production connect path.**
//! Lands ahead of A3 so the `ConnectionManager` credential
//! overlay actor commit (A3+) targets a stable registry API.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::sync::oneshot;

/// What the connection actor is asking the user for. Mirrors the
/// Dart-era prompt variants (`PasswordPromptDialog` /
/// `PassphrasePromptDialog`) so the UI subscriber picks the right
/// dialog widget without re-classifying.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CredentialPromptKind {
    /// SSH password for the session.
    Password,
    /// Passphrase to decrypt the session's private key.
    Passphrase,
}

impl CredentialPromptKind {
    /// Stable wire name for the bus boundary. Each variant maps
    /// to a string so Dart subscribers branch without parsing
    /// the enum across FRB.
    pub fn wire_name(self) -> &'static str {
        match self {
            CredentialPromptKind::Password => "password",
            CredentialPromptKind::Passphrase => "passphrase",
        }
    }

    pub fn from_wire_name(s: &str) -> Option<Self> {
        match s {
            "password" => Some(CredentialPromptKind::Password),
            "passphrase" => Some(CredentialPromptKind::Passphrase),
            _ => None,
        }
    }
}

/// What the user did. `Cancel` is a terminal outcome the
/// connection actor treats as "auth refused, drop the
/// connect attempt"; `Submit` carries the secret bytes + a
/// "remember for this session" flag.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CredentialResponse {
    /// User typed a secret + tapped Submit. `secret` is moved
    /// into the awaiting Rust handler which stages it in the
    /// SecretStore (so Dart heap drops the plaintext as soon
    /// as the FRB call returns).
    Submit {
        secret: Vec<u8>,
        /// User ticked "Remember for this session" — the
        /// connection actor caches the secret in the per-session
        /// `SecretStore` slot so the next reconnect skips the
        /// dialog.
        remember_for_session: bool,
    },
    /// User dismissed the dialog or tapped Cancel. The
    /// connection actor drops the connect attempt with a
    /// localised "auth cancelled" error.
    Cancel,
}

/// Process-singleton registry of pending credential prompts,
/// keyed by caller-allocated prompt id (UUIDv4).
pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<CredentialResponse>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Park a fresh oneshot under `prompt_id` and return the
    /// receiver. Caller awaits the receiver after publishing
    /// the matching `CredentialPromptRequest` event.
    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<CredentialResponse> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .expect("credential prompt registry mutex poisoned")
            .insert(prompt_id, tx);
        rx
    }

    /// Resolve a pending prompt with the user's response.
    /// Idempotent — a missing prompt id (already resolved, or
    /// the awaiting side timed out / cancelled) is a no-op.
    /// Returns `true` when a receiver was actually woken.
    pub fn resolve(&self, prompt_id: &str, response: CredentialResponse) -> bool {
        let sender = self
            .inner
            .lock()
            .expect("credential prompt registry mutex poisoned")
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(response).is_ok(),
            None => false,
        }
    }

    /// Drop a pending prompt without resolving — used by
    /// connection handlers that abandon the await
    /// (TCP teardown, shutdown, parent-bastion failure).
    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .expect("credential prompt registry mutex poisoned")
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner
            .lock()
            .expect("credential prompt registry mutex poisoned")
            .len()
    }
}

impl Default for PromptRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Process-singleton instance — the connection actor and the
/// FRB response shim share this. Tests use `PromptRegistry::new`
/// directly so they don't share state through `instance()`.
pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn submit_response_carries_secret_and_remember_flag() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p1".into());
        assert!(reg.resolve(
            "p1",
            CredentialResponse::Submit {
                secret: vec![0xAA; 16],
                remember_for_session: true,
            }
        ));
        match rx.await.unwrap() {
            CredentialResponse::Submit {
                secret,
                remember_for_session,
            } => {
                assert_eq!(secret, vec![0xAA; 16]);
                assert!(remember_for_session);
            }
            other => panic!("expected Submit, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn cancel_response_propagates_terminal_outcome() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p2".into());
        assert!(reg.resolve("p2", CredentialResponse::Cancel));
        assert_eq!(rx.await.unwrap(), CredentialResponse::Cancel);
    }

    #[test]
    fn resolve_unknown_prompt_id_is_noop() {
        let reg = PromptRegistry::new();
        assert!(!reg.resolve("ghost", CredentialResponse::Cancel));
    }

    #[test]
    fn cancel_drops_without_resolving() {
        let reg = PromptRegistry::new();
        let _rx = reg.register("p3".into());
        assert_eq!(reg.pending_count(), 1);
        reg.cancel("p3");
        assert_eq!(reg.pending_count(), 0);
    }

    #[test]
    fn prompt_kind_round_trips_through_wire_name() {
        for kind in [
            CredentialPromptKind::Password,
            CredentialPromptKind::Passphrase,
        ] {
            assert_eq!(
                CredentialPromptKind::from_wire_name(kind.wire_name()),
                Some(kind),
            );
        }
        assert_eq!(CredentialPromptKind::from_wire_name("unknown"), None);
    }
}
