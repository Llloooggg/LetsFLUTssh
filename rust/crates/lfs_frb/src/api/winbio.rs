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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn count_units_returns_an_integer_without_panic() {
        // On non-Windows the documented contract is `-1`; on Windows
        // the value is implementation-dependent. Pin only the
        // no-panic + non-zero-int contract.
        let units = winbio_count_units();
        // The Dart caller expects `0` to mean "no units enrolled" and
        // `-1` to mean "non-Windows / WinBio unavailable"; positive
        // values are a count. All three are valid; the only invariant
        // is "never panic".
        let _ = units;
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn non_windows_target_returns_negative_one() {
        // Pin the cross-platform stub contract — the Dart caller
        // short-circuits on `Platform.isWindows`, but the shim
        // surfaces `-1` so a misrouted call surfaces a clean
        // sentinel rather than a mystery linker symbol.
        assert_eq!(winbio_count_units(), -1);
    }
}
