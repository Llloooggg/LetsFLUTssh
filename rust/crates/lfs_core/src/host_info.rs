//! Host platform queries.
//!
//! Replaces the Dart `lib/utils/platform.dart` surface — the
//! `homeDirectory` env-var lookup, the `is_mobile` / `is_desktop`
//! / `is_macos` compile-time booleans. Rust owns the resolution
//! so future `lfs_cli` / `lfs_tauri` consumers see the same
//! answer the Flutter app does.
//!
//! **Why a separate module from `platform/`.** The `platform/`
//! tree holds OS-specific shims that compile only on their
//! target (`linux::*`, `macos::*`). `host_info` is a single set
//! of functions every target compiles — it answers "which OS am
//! I on" rather than "give me the per-OS implementation".
//!
//! On `is_mobile` / `is_desktop` / `is_macos`: these are
//! `cfg!(target_os = ...)` predicates and therefore compile-time
//! constants tied to the binary's target. The Dart caller still
//! crosses an FFI boundary to read them so the flag is sourced
//! once, identically, on both sides — but in test contexts where
//! FRB is not bootstrapped the Dart wrapper falls back to
//! `dart:io`'s `Platform.isXyz`. Mathematically identical answer
//! (same binary target → same constants), so the fallback never
//! drifts from the Rust truth.

/// User home directory.
///
/// Resolution rules match the previous Dart implementation:
///
/// - **Android**: `EXTERNAL_STORAGE` env (set by the OS to point
///   at the shared internal storage root, e.g.
///   `/storage/emulated/0`); falls back to that literal path
///   when the env is missing — every Android we ship to has the
///   variable so the literal is a defensive belt.
/// - **All other targets** (Linux / macOS / iOS / Windows):
///   `HOME`, then `USERPROFILE` (Windows uses the latter), empty
///   string when neither is set. iOS sandbox sets `HOME` to the
///   per-app container — the same env lookup picks it up.
pub fn home_directory() -> String {
    if cfg!(target_os = "android") {
        return std::env::var("EXTERNAL_STORAGE")
            .unwrap_or_else(|_| "/storage/emulated/0".to_string());
    }
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_default()
}

/// True on Android or iOS.
pub fn is_mobile() -> bool {
    cfg!(any(target_os = "android", target_os = "ios"))
}

/// True on Linux, macOS, or Windows.
pub fn is_desktop() -> bool {
    cfg!(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows"
    ))
}

/// True on macOS. Wraps `cfg!(target_os = "macos")` so the Dart
/// side has a single FFI surface for the macOS-only UI gates
/// (Settings → security identity block, first-launch self-sign
/// pre-prompt) instead of running an `dart:io` predicate.
pub fn is_macos() -> bool {
    cfg!(target_os = "macos")
}
#[cfg(test)]
#[path = "../tests/unit/host_info.rs"]
mod tests;
