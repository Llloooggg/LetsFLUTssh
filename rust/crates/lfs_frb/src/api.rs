//! FRB-exposed surface. Submodules register here (`mod ssh`,
//! `mod keys`, `mod agent`, ...) — each one a thin wrapper over
//! the equivalent module in `lfs_core`.

pub mod app;
pub mod archive;
pub mod archive_stage;
pub mod auth_compose;
pub mod biometric_probe_prompt;
pub mod bus;
pub mod capabilities_cache;
pub mod capabilities_orchestrator;
pub mod config;
pub mod connection;
pub mod credential_prompt;
pub mod crypto;
pub mod db;
pub mod deeplink;
pub mod folder_path;
pub mod format;
pub mod host_info;
pub mod forward;
pub mod hardware_tier_vault;
pub mod keychain_marker;
pub mod keychain_op_prompt;
pub mod keychain_password_gate;
pub mod keychain_pepper_prompt;
pub mod keys;
pub mod known_hosts_parser;
pub mod log_sanitize;
pub mod master_password;
pub mod migration;
pub mod os_security;
pub mod password_strength;
pub mod path;
pub mod persisted_rate_limit;
pub mod persisted_rate_limit_actor;
pub mod qr_codec_encode;
pub mod qr_compose;
pub mod rate_limit;
pub mod recorder;
pub mod security_capabilities;
pub mod security_config;
pub mod session_history;
pub mod session_tree;
pub mod sessions;
pub mod sessions_registry;
pub mod sftp;
pub mod sftp_models;
pub mod snippet_template;
pub mod ssh;
pub mod ssh_config;
pub mod threat_eval;
pub mod tier_machine;
pub mod tier_transition_marker;
pub mod tier_unlock_orchestrator;
pub mod tpm;
pub mod transfer;
pub mod transfer_conflict;
pub mod update_http;
pub mod update_metadata;
pub mod update_signing;
pub mod winbio;
pub mod wipe;
pub mod wipe_keychain;
pub mod wizard_setup;

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
