//! Windows-only native bindings — CNG / NCrypt for the Tier 4
//! hardware-tier vault.
//!
//! Mirrors the Apple / Android module shape: each platform-specific
//! crypto integration lives in its own submodule under
//! `lfs_os_security`, gated by `cfg(target_os = "windows")`. The FRB
//! layer dispatches per platform; Dart consumers see the unified
//! `lfs_os_security::hardware_tier_vault::*` surface.

pub mod hardware_vault;
pub mod ncrypt_ssh;
