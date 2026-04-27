//! Pure-Rust security/transport core for LetsFLUTssh.
//!
//! Frontend-agnostic by design — this crate contains no
//! `flutter_rust_bridge`, no `tauri`, and no other adapter-layer
//! concerns. Frontends consume the crate through a thin adapter:
//!
//!   - `lfs_frb`   — flutter_rust_bridge bindings for the Flutter app
//!   - `lfs_tauri` — (future) tauri command bindings, if we ever pivot
//!   - `lfs_cli`   — (future) headless CLI / scripting binary
//!
//! See `docs/RUST_CORE_MIGRATION_PLAN.md` §3.1 for the hexagonal
//! layout rationale and §4.1 for the migration mechanism on the
//! Flutter side.
//!
//! Security posture (also enforced by the crate `[lints]` table):
//!   - `unsafe_code = "forbid"` — no raw FFI / pointer surgery here.
//!   - Secret buffers under our control wrap in `zeroize::Zeroizing`.
//!   - Crypto-material equality uses `subtle::ConstantTimeEq`, never `==`.

pub mod app;
pub mod archive;
pub mod autolock;
pub mod bus;
pub mod connection;
pub mod crypto;
pub mod db;
pub mod deeplink;
pub mod error;
pub mod keys;
pub mod known_hosts_parser;
pub mod log_sanitize;
pub mod migration;
pub mod password_strength;
pub mod path;
pub mod platform;
pub mod portforward;
pub mod qr_codec_decode;
pub mod rate_limit;
pub mod recorder;
pub mod secrets;
pub mod sftp;
pub mod ssh;
pub mod ssh_config;
pub mod threat_eval;
pub mod threat_vocabulary;
pub mod transfer;
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
