//! Per-prompt registry for the hardware-vault probe the
//! capabilities orchestrator runs on Apple / Android / Windows.
//!
//! Linux uses the in-process `lfs_os_security::linux::tpm`
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
//! Backed by the generic
//! [`super::prompt_registry::PromptRegistry`].

use super::prompt_registry::PromptRegistry as Generic;

/// Outcome of the Dart `MethodChannel` probe call. Free-form
/// platform code string — `"available"` is the canonical
/// success value, everything else is a per-platform unavail
/// reason. `"unknown"` covers the channel-unreachable / no-
/// such-method case.
pub type HardwareVaultProbeResponse = String;

/// Process-singleton registry alias.
pub type PromptRegistry = Generic<HardwareVaultProbeResponse>;

pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}
#[cfg(test)]
#[path = "../../tests/unit/security_hardware_vault_probe_prompt.rs"]
mod tests;
