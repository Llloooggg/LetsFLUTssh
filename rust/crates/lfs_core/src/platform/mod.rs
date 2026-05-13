//! Platform-specific shims.
//!
//! Per-OS modules live behind `cfg(target_os = "...")` gates so a
//! Windows build never sees the Linux D-Bus glue and an iOS build
//! never pulls a process-spawning helper. Each submodule lands as
//! a self-contained namespace — callers route through
//! `lfs_core::platform::linux::*`, `::macos::*`, etc.

#[cfg(target_os = "linux")]
pub mod linux;

// macOS module is built on Apple targets in production. We also
// expose it under `cfg(test)` on Unix-like hosts so the
// MockRunner-driven unit tests run on the Linux dev box. The
// `unix` arm in the test gate keeps the module out of a Windows
// test compile (`cargo test --target x86_64-pc-windows-*` or the
// workspace cross-clippy) — `use std::os::unix::fs::PermissionsExt`
// inside the macOS shell-out helpers does not resolve on Windows.
#[cfg(any(target_os = "macos", all(test, unix)))]
pub mod macos;
