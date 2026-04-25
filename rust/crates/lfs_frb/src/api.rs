//! FRB-exposed surface. Sub-phases (1.1+) register submodules here
//! (`mod ssh`, `mod keys`, `mod agent`, ...) — each one a thin wrapper
//! over the equivalent module in `lfs_core`.

pub mod app;
pub mod crypto;
pub mod db;
pub mod forward;
pub mod keys;
pub mod sftp;
pub mod ssh;

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
