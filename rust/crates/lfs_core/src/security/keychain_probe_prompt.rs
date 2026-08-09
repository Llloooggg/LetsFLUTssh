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
//! [`super::prompt_registry::PromptRegistry`] — collapses the
//! identical register / resolve / cancel surface shared by all
//! five prompt registries into one parameterised type.

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
#[path = "../../tests/unit/security_keychain_probe_prompt.rs"]
mod tests;
