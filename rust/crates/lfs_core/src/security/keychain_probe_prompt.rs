//! Per-prompt registry for the keychain probe the
//! capabilities orchestrator runs.
//!
//! The probe asks Dart "is the OS secure storage reachable?":
//! Linux subscribers run an in-process zbus
//! `SecretService::connect` against `org.freedesktop.secrets`;
//! non-Linux subscribers do a live
//! `lfs_os_security::secure_key_storage` write/read/delete
//! round-trip against a transient probe key. Both shapes
//! collapse to the same response — the wire name of the
//! `lfs_core::security::capabilities::KeyringProbeResult` enum.
//!
//! Backed by the generic
//! [`super::prompt_registry::PromptRegistry`]. The shape used to
//! be hand-rolled here, byte-for-byte the same as the four
//! sibling prompt registries; the generic collapses all five.

use super::prompt_registry::PromptRegistry as Generic;

/// Outcome of a Dart-side keychain probe call. Wire name of one
/// of the `KeyringProbeResult` variants — `"available"`,
/// `"linuxNoSecretService"`, `"probeFailed"`. The orchestrator
/// maps the string back to the typed enum.
pub type KeychainProbeResponse = String;

/// Process-singleton registry alias — same surface as the other
/// prompt registries (register / resolve / cancel /
/// pending_count) parameterised over [`KeychainProbeResponse`].
pub type PromptRegistry = Generic<KeychainProbeResponse>;

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
