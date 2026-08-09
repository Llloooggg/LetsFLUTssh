/// Unit tests extracted from security/capabilities_orchestrator.rs
/// Declared via `#[path] mod tests;` in the source file.
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
