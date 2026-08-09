//! Cross-class libsecret-noise gate for Linux installs.
//!
//! Background — `flutter_secure_storage` on Linux uses libsecret,
//! which emits a non-recoverable `g_warning` to stderr the moment
//! it cannot talk to a running / unlocked keyring daemon. That
//! makes a cold `containsKey` / `read` on a system where the
//! keyring was never touched (WSL, containers, minimal desktops
//! without `gnome-keyring-daemon` / `kwalletd`) spam stderr on
//! every launch.
//!
//! This module owns the on-disk marker file every keychain-using
//! class consults before issuing a libsecret probe: the marker is
//! laid down only after a successful keychain *write*, so a
//! subsequent `read` is safe to attempt.
//!
//! The marker itself holds nothing sensitive (`'1'`), but sits next
//! to `credentials.*` in the app-support dir at 0600 so the whole
//! directory keeps a single permission contract.
//!
//! Mirror of the Dart-side `LinuxKeychainMarker` class — the Dart
//! façade is now a thin wrapper that resolves the platform
//! `getApplicationSupportDirectory()` path and delegates each op
//! across the FRB boundary.

use std::fs;
use std::path::Path;

use crate::path::write_bytes_atomic;

/// File name stored under the platform's app-support directory.
/// Mirror of the Dart-side `_fileName` constant.
pub const MARKER_FILE_NAME: &str = "keychain_enabled";

/// True when the marker file is on disk under [`support_dir`],
/// meaning at least one prior session wrote a secret into the
/// keychain successfully. Callers use this as the gate before any
/// `containsKey` / `read` on Linux to avoid triggering libsecret
/// warnings in absence of the keyring daemon.
///
/// The Dart facade short-circuits to `true` on non-Linux platforms
/// before reaching this function — the keyring APIs on macOS /
/// Windows / mobile do not emit stderr warnings the same way, so
/// no gating is needed there. Keeping that platform branch Dart-side
/// keeps this Rust surface platform-agnostic.
pub fn exists(support_dir: &Path) -> bool {
    support_dir.join(MARKER_FILE_NAME).exists()
}

/// Lay down the marker after a successful keychain write. Safe to
/// call from multiple keychain-using classes — the file is a flag,
/// not a counter; idempotent on a re-write.
///
/// Routes through [`write_bytes_atomic`] so the marker file lands
/// at the same 0600 perms the rest of `app-support` enforces, and
/// concurrent `set` calls cannot trip on the intermediate file
/// (random tmp suffix).
pub fn set(support_dir: &Path) -> Result<(), String> {
    crate::path::create_dir_all_secure(support_dir)?;
    write_bytes_atomic(&support_dir.join(MARKER_FILE_NAME), b"1")
}

/// Drop the marker when the last keychain entry across all users is
/// removed. Called from `SecureKeyStorage.deleteKey` Dart-side — see
/// the full lifecycle contract there. Other classes do NOT clear on
/// their own delete because a different class may still have an
/// entry on disk. Idempotent on a missing file.
pub fn clear(support_dir: &Path) -> Result<(), String> {
    let path = support_dir.join(MARKER_FILE_NAME);
    if !path.exists() {
        return Ok(());
    }
    fs::remove_file(&path).map_err(|e| format!("delete {}: {e}", path.display()))
}
#[cfg(test)]
#[path = "../../tests/unit/security_keychain_marker.rs"]
mod tests;
