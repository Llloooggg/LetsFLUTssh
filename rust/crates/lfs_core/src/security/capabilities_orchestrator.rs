//! Capabilities probe orchestrator — fans out one prompt per
//! probe + the in-process Linux fprintd check, composes the
//! [`SecurityCapabilities`] snapshot, and pushes it through
//! [`crate::security::capabilities_cache::Cache::set`].
//!
//! Every Dart-side probe (biometric / keychain / hardware-vault
//! method-channel) goes through a typed prompt registry — the
//! actual plugin call stays Dart-side because the Flutter
//! plugin ecosystem already audits those entry points and there
//! is no mature Rust crate covering every target platform's
//! `local_auth` / `flutter_secure_storage` / hardware-vault
//! method-channel shape. The Linux fprintd check stays
//! in-process Rust because the `lfs_core::platform::linux::fprintd`
//! D-Bus shim already exists.
//!
//! Probes run concurrently via `tokio::join!`. A per-probe
//! timeout collapses stuck D-Bus calls / unresponsive plugins
//! to the matching "unavailable" answer rather than blocking
//! the wizard spinner forever.

use std::time::Duration;

use crate::bus::Event;
use crate::security::capabilities::{KeyringProbeResult, SecurityCapabilities};
use crate::security::capabilities_cache::Cache;
use crate::security::{hardware_vault_probe_prompt, keychain_probe_prompt};

/// Hard upper bound for any single probe round-trip. Stuck
/// D-Bus calls / unresponsive native plugins fall back to the
/// matching "unavailable" answer rather than blocking the
/// wizard's spinner. Mirrors the spirit of the Dart-side
/// `safely(...)` helper — log + default + keep going.
const PROBE_TIMEOUT: Duration = Duration::from_secs(5);

/// UUIDv4-shaped prompt id. Mirrors the same id-shape every
/// other prompt registry uses.
fn generate_prompt_id() -> String {
    use rand::Rng;
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Run every capability probe, compose the snapshot, push it
/// into the process-singleton cache, and return the snapshot
/// to the caller.
///
/// `is_linux_host` overrides the platform sniff — production
/// callers pass `cfg!(target_os = "linux")`; tests can swap a
/// fixed value to exercise both branches without conditional
/// compilation.
///
/// **Linux fprintd path** runs in-process via
/// `lfs_core::platform::linux::fprintd::has_enrolled_fingers`;
/// non-Linux hosts skip it (returns `false`). The hardware-
/// vault probe is also skipped on Linux — the Dart-era code
/// routes Linux through the TPM CLI probe at the provider
/// layer, which lives entirely Rust-side already; the cache
/// snapshot's `hardware_probe_code` is filled by that path
/// rather than this orchestrator.
pub async fn run(is_linux_host: bool) -> SecurityCapabilities {
    // 1. Biometric probe — prompt round-trip to Dart's
    //    `local_auth.canCheckBiometrics`.
    let biometric_fut = run_biometric_probe();
    // 2. Keychain probe — prompt round-trip to Dart's keychain
    //    reachability ping.
    let keychain_fut = run_keychain_probe();
    // 3. Hardware vault probe — non-Linux only (Linux uses the
    //    in-process TPM probe at the provider layer).
    let hardware_fut = run_hardware_vault_probe(is_linux_host);
    // 4. Linux fprintd — in-process D-Bus check, Linux only.
    let fprintd_fut = run_fprintd_probe(is_linux_host);

    let (biometric, keychain, hardware_code, fprintd) =
        tokio::join!(biometric_fut, keychain_fut, hardware_fut, fprintd_fut);

    let snapshot = SecurityCapabilities {
        keychain_available: keychain == KeyringProbeResult::Available,
        hardware_vault_available: hardware_code == "available",
        biometric_available: biometric,
        fprintd_available: fprintd,
        is_linux_host,
        keychain_probe: keychain,
        hardware_probe_code: hardware_code,
    };

    // Push into the cache. The cache itself fires
    // `BusEvent::SecurityCapabilitiesChanged` only on a delta,
    // so back-to-back rechecks on a static host don't thrash
    // subscribers.
    Cache::set(
        crate::security::capabilities_cache::instance(),
        snapshot.clone(),
    );

    snapshot
}

async fn run_biometric_probe() -> bool {
    // Linux still goes through `lfs_core::platform::linux::fprintd`
    // separately via `run_fprintd_probe` so the daemon-missing /
    // reader-absent / no-finger-enrolled distinction stays visible.
    // Apple / Windows / Android route through
    // `lfs_os_security::biometric_auth::check_availability` which
    // wraps LAContext / UserConsentVerifier / BiometricManager
    // (JNI). A timeout collapses a stuck native probe to "not
    // available" rather than blocking the wizard's spinner.
    matches!(
        tokio::time::timeout(
            PROBE_TIMEOUT,
            lfs_os_security::biometric_auth::check_availability(),
        )
        .await,
        Ok(Ok(()))
    )
}

async fn run_keychain_probe() -> KeyringProbeResult {
    let prompt_id = generate_prompt_id();
    let receiver = keychain_probe_prompt::instance().register(prompt_id.clone());
    crate::app::instance()
        .bus
        .publish(Event::KeychainProbePromptRequest {
            prompt_id: prompt_id.clone(),
        });
    match tokio::time::timeout(PROBE_TIMEOUT, receiver).await {
        Ok(Ok(wire_name)) => KeyringProbeResult::from_wire_name(&wire_name)
            .unwrap_or(KeyringProbeResult::ProbeFailed),
        _ => {
            keychain_probe_prompt::instance().cancel(&prompt_id);
            KeyringProbeResult::ProbeFailed
        }
    }
}

async fn run_hardware_vault_probe(is_linux_host: bool) -> String {
    if is_linux_host {
        // Linux flows through the in-process TPM CLI probe at
        // the provider layer; the orchestrator leaves the code
        // at "unknown" so the provider can overwrite it after
        // calling `lfs_os_security::linux::tpm::probe`. A
        // future refactor folds that probe in here too once the
        // Linux provider's ordering constraints are sorted.
        return "unknown".to_string();
    }
    let prompt_id = generate_prompt_id();
    let receiver = hardware_vault_probe_prompt::instance().register(prompt_id.clone());
    crate::app::instance()
        .bus
        .publish(Event::HardwareVaultProbePromptRequest {
            prompt_id: prompt_id.clone(),
        });
    match tokio::time::timeout(PROBE_TIMEOUT, receiver).await {
        Ok(Ok(code)) if !code.is_empty() => code,
        _ => {
            hardware_vault_probe_prompt::instance().cancel(&prompt_id);
            "unknown".to_string()
        }
    }
}

async fn run_fprintd_probe(is_linux_host: bool) -> bool {
    if !is_linux_host {
        return false;
    }
    #[cfg(target_os = "linux")]
    {
        // `has_enrolled_fingers` already collapses every D-Bus
        // failure to false, so a stuck daemon does not need a
        // separate timeout here — but apply one anyway as belt
        // and braces against a future change.
        tokio::time::timeout(
            PROBE_TIMEOUT,
            crate::platform::linux::fprintd::has_enrolled_fingers(),
        )
        .await
        .unwrap_or_default()
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `from_wire_name` rejects unknown variants and the
    /// orchestrator falls back to `ProbeFailed`. Catches a
    /// codegen drift / Dart-side typo at the wire-name layer
    /// without crashing the wizard.
    #[test]
    fn unknown_keychain_wire_name_falls_back_to_probe_failed() {
        assert!(KeyringProbeResult::from_wire_name("typo-of-the-future").is_none());
    }

    /// On non-Linux hosts the orchestrator returns `false` for
    /// fprintd without touching the D-Bus stack — guards
    /// against a refactor that accidentally drops the
    /// is_linux_host gate.
    #[tokio::test]
    async fn fprintd_probe_short_circuits_on_non_linux() {
        let r = run_fprintd_probe(false).await;
        assert!(!r);
    }

    /// On Linux the hardware-vault probe returns `"unknown"`
    /// without dispatching a prompt — the orchestrator leaves
    /// the actual code-fill to the provider's TPM CLI probe.
    #[tokio::test]
    async fn hardware_vault_probe_returns_unknown_on_linux() {
        let r = run_hardware_vault_probe(true).await;
        assert_eq!(r, "unknown");
    }
}
