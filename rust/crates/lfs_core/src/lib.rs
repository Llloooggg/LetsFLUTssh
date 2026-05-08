//! Pure-Rust security/transport core. Frontend-agnostic — no
//! `flutter_rust_bridge`, no `tauri`. Frontends consume through a
//! thin adapter (`lfs_frb` today; `lfs_tauri` / `lfs_cli` possible).
//! Workspace + FRB boundary: see ARCHITECTURE.md §3.14.
//!
//! Security posture (enforced by `[lints]`):
//!   - `unsafe_code = "forbid"` — all FFI lives downstream in `lfs_os_security`.
//!   - Secrets wrap in `zeroize::Zeroizing`.
//!   - Crypto-material equality via `subtle::ConstantTimeEq`.
//!
//! Module-visibility posture: every top-level `pub mod` below is a
//! deliberate consumer surface for `lfs_frb` — the audit's
//! B-WS-5 review confirmed each one has at least one
//! `lfs_core::<mod>::...` reference under `lfs_frb/src/api/` or
//! `lfs_os_security`. Submodules under `db/` / `archive/` /
//! `security/` already use `pub(crate)` where the layer split
//! permits; widening any of those to `pub` requires the same
//! cross-crate-consumer check.

pub mod app;
pub mod app_log;
pub mod archive;
pub mod archive_stage;
pub mod autolock;
pub mod bus;
pub mod config;
pub mod config_store;
pub mod connection;
pub mod crypto;
pub mod db;
pub mod deeplink;
pub mod error;
pub mod folder_path;
pub mod format;
pub mod fs;
pub mod host_info;
pub mod id;
pub mod import;
pub mod keys;
pub mod known_hosts;
pub mod known_hosts_parser;
pub mod log_sanitize;
pub mod migration;
pub mod password_strength;
pub mod path;
pub mod platform;
pub mod portforward;
pub mod qr_codec_decode;
pub mod qr_codec_encode;
pub mod qr_compose;
pub mod rate_limit;
pub mod recorder;
pub mod secrets;
pub mod security;
pub mod session_history;
pub mod session_tree;
pub mod sessions;
pub mod sftp;
pub mod sftp_models;
pub mod snippet_template;
pub mod ssh;
pub mod ssh_config;
pub mod ssh_dir_scan;
pub mod threat_eval;
pub mod transfer;
pub mod transfer_conflict;
pub mod update_http;
pub mod update_metadata;
pub mod update_orchestrator;
pub mod update_signing;

pub use error::Error;

/// Returns the loaded core's package version.
///
/// Used by adapters as a smoke test for the FFI plumbing — the
/// frontend calls into the adapter, the adapter delegates here, the
/// version string round-trips back. Kept around alongside the
/// real entrypoints (`connect_password`, etc.) as a cheap probe.
pub fn ping() -> String {
    format!("lfs_core v{}", env!("CARGO_PKG_VERSION"))
}
