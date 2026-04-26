//! Linux-only platform shims. Gated under
//! `cfg(target_os = "linux")` from the parent module so the
//! Cargo target dep table can drop `zbus` on every other host.

pub mod fprintd;
pub mod tpm;
