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
//! deliberate consumer surface for `lfs_frb`. Each one has at
//! least one `lfs_core::<mod>::...` reference under
//! `lfs_frb/src/api/` or `lfs_os_security`. Submodules under
//! `db/` / `archive/` / `security/` already use `pub(crate)`
//! where the layer split permits; widening any of those to `pub`
//! requires the same cross-crate-consumer check.
//!
//! Two top-level modules are intentionally `pub(crate)`:
//! [`app_log`] (macros are `#[macro_export]`-d to the crate root,
//! so external callers reach them via `lfs_core::app_log_info!`
//! not `lfs_core::app_log::log!`) and [`autolock`] (consumed only
//! through `crate::app::App::autolock`, which itself stays
//! `pub(crate)` so the machine's lifecycle remains owned here).

pub mod app;
pub(crate) mod app_log;
pub mod archive;
pub mod archive_stage;
pub(crate) mod autolock;
pub mod bus;
pub mod clipboard;
pub mod config;
pub mod config_store;
pub mod connection;
pub mod crypto;
pub mod db;
pub mod deeplink;
pub mod error;
// Direct CTAP2 over USB HID for hardware-bound SSH keys
// (`sk-ssh-ed25519@openssh.com` / `sk-ecdsa-sha2-nistp256@openssh.com`).
// Gated by the `fido2` Cargo feature; the module stubs out the
// surface to `is_available() = false` when the feature is off so
// the runtime probe drives the capability ladder.
pub mod fido2;
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
pub mod logger;
pub mod migration;
pub mod password_strength;
pub mod path;
pub mod platform;
pub mod portforward;
pub mod qr_codec_decode;
pub mod qr_codec_encode;
pub mod rate_limit;
pub mod recorder;
// S3-compatible transport (AWS REST + SigV4 signer + multipart
// upload orchestrator). Sibling to `webdav` / `ssh` / `sftp`;
// both the file-browser provider (`storage::s3::S3Provider`) and
// the FRB adapter (`lfs_frb::api::s3`) consume it. Lives at the
// same level so neither consumer dips into the other's tree.
pub mod s3;
pub mod secrets;
pub mod security;
pub mod session_history;
pub mod session_json;
pub mod session_tree;
pub mod sessions;
pub mod sftp;
pub mod sftp_models;
pub mod snippet_template;
pub mod ssh;
// In-process ssh-agent endpoint that exposes hardware-bound SSH
// keys (FIDO2 today; future PKCS#11 / TPM / Secure Enclave / NCrypt /
// Keystore) to external SSH-protocol-speaking applications on the
// same host. Cfg-gated to desktop targets internally; the module
// itself stays `pub` so the FRB adapter can name the surface
// (`start_endpoint`, `stop`, `AgentStatus`).
pub mod ssh_agent;
pub mod ssh_config;
pub mod ssh_dir_scan;
// `storage` is the backend-agnostic byte-store abstraction
// (`Provider` trait + `SftpProvider`). No FRB consumer yet — the
// dispatcher lands with the second backend (S3, WebDAV). Stays
// `pub` because the items are public API of the crate and the
// next commit wires them into `lfs_frb::api::storage`.
pub mod storage;
// WebDAV sync orchestrator (push + pull + LWW merge). Consumed by
// `lfs_frb::api::sync`; the Settings UI's "Push now" / "Pull now"
// buttons land here through that adapter.
pub mod sync;
// Headless terminal-emulation core: ANSI parser + grid + scrollback +
// scroll-region + selection, owned Rust-side (the "Rust owns data AND
// logic" pillar). Wraps `alacritty_terminal` and resolves every cell's
// color to concrete RGB so the future FRB/Flutter renderer never sees
// Named/Indexed colors. No FRB types here — the bridge lands later.
pub mod terminal;
pub mod threat_eval;
pub mod transfer;
pub mod transfer_conflict;
pub mod update;
// Raw WebDAV transport (PROPFIND / GET / PUT / DELETE / MKCOL /
// MOVE + basic / digest / bearer auth + multistatus parser).
// Consumed by both the sync orchestrator and the WebDAV
// `storage::Provider` impl; lives at the same level as `ssh` /
// `sftp` so neither consumer needs to dip into the other's
// module tree to reach the transport.
pub mod webdav;
pub(crate) mod xml;

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
