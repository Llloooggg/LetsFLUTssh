//! FRB shim for the WinBio physical-unit-count probe.
//!
//! The unsafe `winbio.dll` FFI lives in
//! `lfs_os_security::winbio`. This module is a one-line bridge
//! so Dart can call it through FRB. Mirrors `os_security.rs`'s
//! shape (delegate to `lfs_os_security`, no logic in the
//! adapter).
//!
//! Returns `-1` on non-Windows hosts so the caller's tier-
//! availability probe stays a single integer surface across
//! every platform.

#[flutter_rust_bridge::frb(sync)]
pub fn winbio_count_units() -> i64 {
    lfs_os_security::winbio::count_units()
}
