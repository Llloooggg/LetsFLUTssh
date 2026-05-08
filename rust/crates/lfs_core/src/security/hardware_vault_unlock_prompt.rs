//! Per-prompt registry for the hardware-vault *unlock* call
//! (Linux TPM via `tpm2-tools` + Apple/Android/Windows method
//! channels). Mirrors the read-only hardware-vault probe
//! registry shape but carries the PIN payload + returns the
//! unsealed key bytes.
//!
//! Keychain access stays Dart-side because the platform vault
//! APIs (Secure Enclave / StrongBox / Windows Hello / TPM CLI)
//! all sit behind plugins or method channels with no mature
//! parallel Rust crate covering every platform's behavioural
//! quirks. The Linux variant could in principle route directly
//! through `lfs_os_security::linux::tpm` without a prompt;
//! the orchestrator picks that branch where it can and falls
//! back to the prompt path on every other host.
//!
//! Backed by the generic
//! [`super::prompt_registry::PromptRegistry`].

use super::prompt_registry::PromptRegistry as Generic;

/// Outcome of the Dart-side hardware-vault unlock call.
///
/// * `Ok(Some(bytes))` — unseal succeeded; bytes are the raw
///   DB key.
/// * `Ok(None)` — wrong PIN / user cancel / hardware reported
///   failure with no recoverable detail. Caller routes through
///   the T2 reset path.
/// * `Err(msg)` — plugin error / channel unreachable. Caller
///   surfaces the message in the support log + falls back to
///   plaintext.
pub type HardwareVaultUnlockResponse = Result<Option<Vec<u8>>, String>;

/// Process-singleton registry alias.
pub type PromptRegistry = Generic<HardwareVaultUnlockResponse>;

pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn round_trips_success() {
        let reg = PromptRegistry::new();
        let rx = reg.register("u1".into());
        assert!(reg.resolve("u1", Ok(Some(vec![1, 2, 3]))));
        assert_eq!(rx.await.unwrap(), Ok(Some(vec![1, 2, 3])));
    }

    #[tokio::test]
    async fn round_trips_wrong_pin() {
        let reg = PromptRegistry::new();
        let rx = reg.register("u2".into());
        assert!(reg.resolve("u2", Ok(None)));
        assert_eq!(rx.await.unwrap(), Ok(None));
    }

    #[tokio::test]
    async fn round_trips_plugin_error() {
        let reg = PromptRegistry::new();
        let rx = reg.register("u3".into());
        assert!(reg.resolve("u3", Err("channel missing".into())));
        assert_eq!(rx.await.unwrap(), Err("channel missing".into()));
    }

    #[test]
    fn cancel_drops_without_resolving() {
        let reg = PromptRegistry::new();
        let _rx = reg.register("u".into());
        reg.cancel("u");
        assert_eq!(reg.pending_count(), 0);
        assert!(!reg.resolve("u", Ok(None)));
    }
}
