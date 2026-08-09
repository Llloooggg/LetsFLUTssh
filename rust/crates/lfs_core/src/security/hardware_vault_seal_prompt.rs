//! Per-prompt registry for the hardware-vault *seal* call. Mirrors
//! [`super::hardware_vault_unlock_prompt`] but carries the bytes
//! to be sealed alongside the optional PIN; the response is just
//! `Ok(())` on success or `Err(message)` on plugin / hardware
//! failure.
//!
//! Used by `tier_unlock_orchestrator::first_launch_hardware` so
//! the T2 first-launch arm goes through the same orchestrator +
//! listener pattern as the unlock arms — the orchestrator
//! generates a fresh DB key, asks the Dart subscriber to seal it
//! through `HardwareTierVault.store(key, pin)`, then stages the
//! same bytes in the SecretStore + emits the cascade.
//!
//! Backed by the generic
//! [`super::prompt_registry::PromptRegistry`].

use super::prompt_registry::PromptRegistry as Generic;

/// Outcome of the Dart-side hardware-vault seal call.
///
/// * `Ok(())` — seal succeeded; the bytes the orchestrator passed
///   in are now wrapped by the platform vault and the on-disk
///   blob has been written.
/// * `Err(msg)` — plugin/channel error or hardware refused. The
///   orchestrator falls back to the plaintext / wizard-rerun
///   path on the Dart side.
pub type HardwareVaultSealResponse = Result<(), String>;

/// Process-singleton registry alias.
pub type PromptRegistry = Generic<HardwareVaultSealResponse>;

pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}
#[cfg(test)]
#[path = "../../tests/unit/security_hardware_vault_seal_prompt.rs"]
mod tests;
