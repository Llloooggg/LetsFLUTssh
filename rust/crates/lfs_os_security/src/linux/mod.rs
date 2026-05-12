//! Linux-only OS-FFI perimeter — TSS2 ESAPI bindings under
//! `tpm` / `tpm_native`. Moved here from `lfs_core` so the audit
//! invariant "`lfs_os_security` is the single OS-FFI perimeter"
//! holds: `lfs_core` must not depend on `tss-esapi` or any other
//! OS-binding crate directly.

/// Local error type for the TPM modules. `lfs_os_security` is
/// the lower edge of the dependency direction so it cannot
/// import `lfs_core::Error`; callers in `lfs_core` map this
/// type to the appropriate `lfs_core::Error` variant at the
/// boundary (Crypto / Io / Platform straight-through).
#[derive(Debug)]
pub enum TpmError {
    Crypto(String),
    Io(String),
    Platform(String),
}

impl std::fmt::Display for TpmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Crypto(s) => write!(f, "crypto: {s}"),
            Self::Io(s) => write!(f, "io: {s}"),
            Self::Platform(s) => write!(f, "platform: {s}"),
        }
    }
}

impl std::error::Error for TpmError {}

pub mod tpm;
pub mod tpm_native;
pub mod tpm_ssh;
