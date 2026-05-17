//! Platform-specific shims.
//!
//! Per-OS modules live behind `cfg(target_os = "...")` gates so a
//! Windows build never sees the Linux D-Bus glue. Each submodule
//! lands as a self-contained namespace — callers route through
//! `lfs_core::platform::linux::*`.
//!
//! The Apple code-signing / keychain / codesign pipeline lives in
//! `lfs_os_security::macos::code_signing` (single subprocess
//! perimeter); lfs_core reaches it through the FRB shim layer
//! rather than hosting its own per-OS shim here.

#[cfg(target_os = "linux")]
pub mod linux;
