//! FRB adapter for `lfs_core::security::capabilities_orchestrator`
//! and the two probe-prompt registries it composes.
//!
//! The orchestrator is async — it fans out four probes concurrently
//! and waits for the slowest. Per-probe timeouts inside the
//! orchestrator (5 s) keep a stuck D-Bus call from freezing the
//! wizard spinner indefinitely.

use lfs_core::security::capabilities_cache as cache;
use lfs_core::security::{
    capabilities_orchestrator, hardware_vault_probe_prompt, keychain_probe_prompt,
};

use crate::api::security_capabilities::DbSecurityCapabilities;

/// Resolve a pending keychain-reachability probe with the
/// `KeyringProbeResult` wire name the Dart subscriber computed
/// from the OS-keychain ping. Wire names: `"available"` /
/// `"linuxNoSecretService"` / `"probeFailed"`. Returns `true`
/// when a receiver was actually woken.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_probe_prompt_resolve(prompt_id: String, wire_name: String) -> bool {
    keychain_probe_prompt::instance().resolve(&prompt_id, wire_name)
}

/// Cancel a pending keychain-reachability probe — used when
/// the Dart subscriber detaches before dispatching (e.g. wizard
/// dismissed mid-flight). Idempotent on a missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_probe_prompt_cancel(prompt_id: String) {
    keychain_probe_prompt::instance().cancel(&prompt_id);
}

/// Resolve a pending hardware-vault probe with the platform-
/// specific reason code the Dart subscriber pulled from
/// `HardwareTierVault.probeDetail()` (which routes through
/// FRB into `lfs_os_security::hardware_tier_vault::
/// probe_detail`). The string is opaque to Rust —
/// `"available"` is the canonical success value, every other
/// value flows through the snapshot's `hardware_probe_code`
/// for the wizard to map to localised reason copy.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_probe_prompt_resolve(prompt_id: String, code: String) -> bool {
    hardware_vault_probe_prompt::instance().resolve(&prompt_id, code)
}

/// Cancel a pending hardware-vault probe — see
/// [`keychain_probe_prompt_cancel`] for the why.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_probe_prompt_cancel(prompt_id: String) {
    hardware_vault_probe_prompt::instance().cancel(&prompt_id);
}

/// Run every capability probe concurrently and push the result
/// snapshot into the cache. Returns the freshly-probed
/// snapshot so the Dart caller doesn't need a follow-up
/// `view` call.
///
/// `is_linux_host` overrides the platform sniff. Production
/// callers pass `Platform.isLinux`.
///
/// Per-probe failures (timeout, missing subscriber, plugin
/// error) collapse to the matching "unavailable" answer rather
/// than `Err` so a stuck D-Bus call never blocks the wizard
/// spinner.
pub async fn capabilities_probe_run(is_linux_host: bool) -> DbSecurityCapabilities {
    capabilities_orchestrator::run(is_linux_host).await.into()
}

/// Pure helper — drop the cached snapshot. Wraps
/// `capabilities_cache::Cache::clear` so the wizard's Recheck
/// button can route through the orchestrator namespace
/// instead of mixing FRB modules.
#[flutter_rust_bridge::frb(sync)]
pub fn capabilities_probe_clear() {
    cache::instance().clear();
}

#[cfg(test)]
mod tests {
    use super::*;

    // The orchestrator's `run` async path fans probes across four
    // platform plugins via the prompt registries; covered by the
    // Dart `capabilities_probe_test.dart` integration suite that
    // wires Dart subscribers to dispatch back through the matching
    // resolve calls. The standalone tests below pin the
    // missing-prompt-id contract on the resolve / cancel surface
    // (used by the cleanup paths when a wizard dismiss races a
    // probe).

    #[test]
    fn keychain_probe_resolve_unknown_id_returns_false() {
        // Pin the documented contract — `false` means "no receiver
        // woken" so a stale dispatch from a dismissed wizard
        // doesn't crash. The shim must never panic here.
        let woke = keychain_probe_prompt_resolve("ghost".into(), "available".into());
        assert!(!woke);
    }

    #[test]
    fn keychain_probe_cancel_unknown_id_is_idempotent() {
        // No-op on missing — the dispatcher cleanup runs
        // unconditionally on subscriber detach.
        keychain_probe_prompt_cancel("ghost".into());
    }

    #[test]
    fn hardware_vault_probe_resolve_unknown_id_returns_false() {
        let woke = hardware_vault_probe_prompt_resolve("ghost".into(), "available".into());
        assert!(!woke);
    }

    #[test]
    fn hardware_vault_probe_cancel_unknown_id_is_idempotent() {
        hardware_vault_probe_prompt_cancel("ghost".into());
    }

    #[test]
    fn capabilities_probe_clear_does_not_panic_on_empty_cache() {
        // Pin the no-panic contract — wizard's Recheck button
        // routes through here on every press, including the first
        // press before any snapshot has landed.
        capabilities_probe_clear();
    }
}
