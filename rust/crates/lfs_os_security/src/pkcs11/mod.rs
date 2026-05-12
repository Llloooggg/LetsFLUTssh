//! PKCS#11 (Cryptoki) hardware-token driver.
//!
//! Lives in `lfs_os_security` (FFI perimeter rule); the `russh::Signer`
//! adapter that wraps the driver into the connect path lives in
//! `lfs_core::ssh::pkcs11_signer`. Mobile builds (Android, iOS)
//! compile to the no-op stub block below — sandboxes there forbid
//! `dlopen` of arbitrary `.dylib` / `.so`, so the FRB shim's
//! `pkcs11_*` calls surface `Error::Unsupported` and the UI renders
//! the matching control disabled with the
//! "Smart-card / PKCS#11 tokens are not available on this platform."
//! reason.
//!
//! Vendor coverage (well-known module paths in [`discovery`]):
//! - OpenSC — OpenPGP card, PIV applets, Estonian / Finnish / German
//!   eID, generic CCID
//! - YubiKey PIV (ykcs11)
//! - JaCarta
//! - Рутокен (Rutoken ECP / ECP2 / Lite)
//! - eToken / SafeNet
//! - Thales Luna network HSM
//! - AWS CloudHSM
//!
//! Algorithm support per the project's SSH wire surface:
//! - `CKK_RSA` + `CKM_RSA_PKCS` → `rsa-sha2-256` / `rsa-sha2-512`
//!   (SHA-1 `ssh-rsa` is refused — server-deprecated)
//! - `CKK_EC` (P-256 / P-384 / P-521) + `CKM_ECDSA` → `ecdsa-sha2-*`
//! - `CKK_EC_EDWARDS` + `CKM_EDDSA` (Pure) → `ssh-ed25519` (PKCS#11
//!   v3.0+; YubiKey PIV does not expose Ed25519 over PKCS#11 today)
//! - `CKK_GOSTR3410` → listed but disabled with "GOST cannot be used
//!   with SSH" (no SSH suite for GOST)

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod discovery;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod error;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod key;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod module;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod session;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod sign;
pub mod uri;

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use error::Error;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use key::{KeyClass, KeyMeta};
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use module::{Module, ModuleKey};
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use session::Session;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use sign::{sign_with_pkcs11, SignOutput, SignRequest};

// Mobile stub — every public surface returns a typed "not available
// on this platform" error so the FRB shim can pass the failure
// through without a separate cfg-gate on every call site.
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
pub mod error {
    use std::fmt;

    /// Same shape as the desktop `Error` enum but with only the
    /// "unsupported on this platform" rung exposed — every desktop
    /// call site that compiles down to the stub binds against this
    /// variant.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub enum Error {
        Unsupported,
    }

    impl fmt::Display for Error {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            f.write_str("pkcs11: tokens not available on this platform")
        }
    }

    impl std::error::Error for Error {}
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
pub use error::Error;
