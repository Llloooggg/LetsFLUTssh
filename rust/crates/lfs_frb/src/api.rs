//! FRB-exposed surface. Submodules register here (`mod ssh`,
//! `mod keys`, `mod agent`, ...) — each one a thin wrapper over
//! the equivalent module in `lfs_core`.

pub mod app;
pub mod archive;
pub mod bus;
pub mod crypto;
pub mod db;
pub mod deeplink;
pub mod forward;
pub mod keys;
pub mod known_hosts_parser;
pub mod log_sanitize;
pub mod password_strength;
pub mod path;
pub mod recorder;
pub mod sftp;
pub mod ssh;
pub mod ssh_config;
pub mod transfer;
pub mod winbio;

/// FFI plumbing init — runs once when Dart loads the native blob.
/// Sets up the FRB default user utils (panic hook, logging hook).
/// Required by FRB 2.x; do not remove.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Smoke test for the FFI plumbing — Dart calls this, gets back the
/// loaded core's version string, confirms the native blob loaded
/// correctly and matches the build that codegen ran against.
#[flutter_rust_bridge::frb(sync)]
pub fn ping() -> String {
    lfs_core::ping()
}
