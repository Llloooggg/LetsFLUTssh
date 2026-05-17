//! macOS TPM SSH stub — Apple platforms have no exposed TPM 2.0
//! interface (the Apple T2 / Secure Enclave is fundamentally a
//! different architecture). The Dart UI hides the toolbar entry on
//! Apple via the capability-ladder rung 4 ("honestly hide") because
//! the Apple Secure Enclave path ([`super::super::apple_se_ssh`])
//! covers the same security niche.
//!
//! This module exists to keep the cfg-graph clean: the FRB layer
//! references `lfs_os_security::tpm_ssh` unconditionally and routes
//! Apple builds to this stub, which returns
//! [`TpmSshError::Unavailable`] verbatim.

#![cfg(target_os = "macos")]

/// Stub error mirroring the Linux module's error envelope so the
/// callsite (`lfs_frb::api::tpm_ssh`) can branch on a single typed
/// variant regardless of platform.
#[derive(Debug, Clone)]
pub enum TpmSshError {
    /// macOS / iOS have no exposed TPM 2.0 interface. The Dart
    /// wizard renders the toolbar entry hidden via rung 4.
    Unavailable,
}

impl std::fmt::Display for TpmSshError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unavailable => write!(
                f,
                "TPM 2.0 SSH keys are not available on Apple platforms; \
                 use the Apple Secure Enclave key type instead"
            ),
        }
    }
}

impl std::error::Error for TpmSshError {}
