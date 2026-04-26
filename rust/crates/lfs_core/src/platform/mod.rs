//! Platform-specific shims.
//!
//! Per-OS modules live behind `cfg(target_os = "...")` gates so a
//! Windows build never sees the Linux D-Bus glue and an iOS build
//! never pulls a process-spawning helper. Each submodule lands as
//! a self-contained namespace — callers route through
//! `lfs_core::platform::linux::*`, `::macos::*`, etc.

#[cfg(target_os = "linux")]
pub mod linux;

// macOS module is built on Apple targets in production. We
// also expose it under `cfg(test)` on every host so the
// MockRunner-driven unit tests run on the Linux dev box. Both
// flavours compile against pure std + rand — there is no real
// macOS-only API in the source, only macOS-specific CLI shell
// outs that the mock substitutes.
#[cfg(any(target_os = "macos", test))]
pub mod macos;
