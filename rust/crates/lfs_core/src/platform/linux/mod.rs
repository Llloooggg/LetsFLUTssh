//! Linux-only platform shims. Gated under
//! `cfg(target_os = "linux")` from the parent module so the
//! Cargo target dep table can drop `zbus` on every other host.
//!
//! `tpm` + `tpm_native` retired here — both moved into
//! `lfs_os_security::linux::tpm` to satisfy the audit
//! invariant that `lfs_os_security` is the single OS-FFI
//! perimeter. `lfs_core::security::hardware_tier_vault::linux`
//! now reaches the TPM bindings via that crate.

pub mod fprintd;
