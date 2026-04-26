//! Platform-specific shims.
//!
//! Per-OS modules live behind `cfg(target_os = "...")` gates so a
//! Windows build never sees the Linux D-Bus glue and an iOS build
//! never pulls a process-spawning helper. Each submodule lands as
//! a self-contained namespace — callers route through
//! `lfs_core::platform::linux::*`, `::macos::*`, etc.

#[cfg(target_os = "linux")]
pub mod linux;
