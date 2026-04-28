//! FRB adapter for `lfs_core::path`. Tilde-prefix expansion as a
//! synchronous one-shot — Dart hands in a `~` / `~/...` path,
//! Rust resolves against `$HOME` / `$USERPROFILE` and returns the
//! expanded string.
//!
//! **Mobile semantics intentionally differ.** Dart's
//! `homeDirectory` getter prefers `EXTERNAL_STORAGE` on Android
//! (shared storage `/storage/emulated/0`) over `$HOME` (the app's
//! private data dir). The Rust helper has no equivalent
//! Android-specific fallback — it follows the desktop / iOS
//! resolution order strictly. Today's only call site (Dart
//! `OpenSshConfigImporter.expandHome`) keeps using the Dart
//! getter so import-on-Android behaviour stays unchanged; the
//! Rust helper is here for future Rust-side callers (a Rust
//! port of the OpenSSH parser, the macOS resign orchestrator)
//! that have no Android consumer.

/// Expand a leading `~` against the running process's home
/// directory. See [`lfs_core::path::expand_tilde`] for the
/// resolution rules.
#[flutter_rust_bridge::frb(sync)]
pub fn path_expand_tilde(path: String) -> String {
    lfs_core::path::expand_tilde(&path)
}

/// Atomic byte write — writes [`bytes`] to `<path>.tmp`, hardens
/// the tmp file to owner-only perms, then renames to [`path`].
/// Caller is responsible for ensuring the parent directory exists.
///
/// Sync because the per-call work is one `write` syscall + one
/// `rename` syscall; the bytes themselves rarely top a few KiB
/// (KDF salt, marker payloads, sealed-blob envelopes, rate-limit
/// state). The Dart `writeBytesAtomic` shipped sync to the same
/// callers; routing through FRB sync preserves the contract.
#[flutter_rust_bridge::frb(sync)]
pub fn path_write_bytes_atomic(path: String, bytes: Vec<u8>) -> Result<(), String> {
    lfs_core::path::write_bytes_atomic(std::path::Path::new(&path), &bytes)
}

/// Tighten [`path`] to owner-only perms — `chmod 600` on Unix,
/// `icacls /inheritance:r /grant:r` on Windows, no-op on iOS /
/// Android (sandboxed app storage). Best-effort: returns the OS
/// error as `Err(String)` for the caller to log, never panics.
///
/// Sync because the per-call work is one syscall on Unix and one
/// short-lived subprocess on Windows; both run in microseconds
/// and the call sites (drift WAL/SHM sidecars, explicit
/// post-write hardening for files where the writer cannot use
/// `path_write_bytes_atomic`) are not on hot paths.
#[flutter_rust_bridge::frb(sync)]
pub fn path_harden_file_perms(path: String) -> Result<(), String> {
    lfs_core::path::harden_file_perms(std::path::Path::new(&path))
}

/// Extract the basename portion of [`path`], normalising Windows
/// `\` separators to `/` first. Mirrors the Dart
/// `KeyFileHelper.basename` shape so file pickers + importers
/// share one rule.
#[flutter_rust_bridge::frb(sync)]
pub fn path_basename(path: String) -> String {
    lfs_core::path::basename(&path)
}

/// True when [`path`] contains a `..` segment after normalising
/// Windows separators. Used by the OpenSSH-config importer to
/// short-circuit traversal-style `IdentityFile` entries before
/// trying to read the file.
#[flutter_rust_bridge::frb(sync)]
pub fn path_is_suspicious(path: String) -> bool {
    lfs_core::path::is_suspicious_path(&path)
}

/// Shorten a path to its last two non-empty segments, prefixed
/// with `.../`. Used by the transfer panel + history rows to
/// keep long paths readable in narrow row widths without losing
/// the trailing context.
#[flutter_rust_bridge::frb(sync)]
pub fn path_shorten_to_two_segments(path: String) -> String {
    lfs_core::path::shorten_to_two_segments(&path)
}
