//! macOS-only platform shims. Gated under
//! `cfg(target_os = "macos")` from the parent module so non-Apple
//! hosts skip the entire subtree.
//!
//! Mirrors the Dart `lib/platform/macos/code_signing/*` flow:
//! self-signed cert generation (`/usr/bin/openssl`), keychain
//! import + trust (`/usr/bin/security`), and inside-out
//! re-signing (`/usr/bin/codesign`). The orchestrator on top
//! lives in [`resign_service`].
//!
//! **Untested target.** This module is shipped as a port of the
//! Dart implementation byte-for-byte, but the build host is
//! Linux WSL — no macOS verification has been done. The Dart
//! side stays as the production driver until the macOS test
//! pass lands.

pub mod cert_factory;
pub mod codesigner;
pub mod keychain;
pub mod process;
pub mod resign_service;
