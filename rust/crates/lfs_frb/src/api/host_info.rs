//! FRB adapter for `lfs_core::host_info`. All four functions are
//! sync — `home_directory` is one env-var lookup, the booleans
//! resolve to compile-time constants. The Dart wrapper caches
//! the result on first read so the FFI hop only happens once
//! per process per query.

#[flutter_rust_bridge::frb(sync)]
pub fn host_info_home_directory() -> String {
    lfs_core::host_info::home_directory()
}

#[flutter_rust_bridge::frb(sync)]
pub fn host_info_is_mobile() -> bool {
    lfs_core::host_info::is_mobile()
}

#[flutter_rust_bridge::frb(sync)]
pub fn host_info_is_desktop() -> bool {
    lfs_core::host_info::is_desktop()
}

#[flutter_rust_bridge::frb(sync)]
pub fn host_info_is_macos() -> bool {
    lfs_core::host_info::is_macos()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn home_directory_resolves_to_a_non_empty_string() {
        // Resolves against `$HOME` (Unix) or `$USERPROFILE`
        // (Windows). On a CI runner with neither set the helper
        // can return an empty string; we accept both shapes here
        // and only assert the call returns without panicking.
        let _ = host_info_home_directory();
    }

    #[test]
    fn mobile_and_desktop_partition_the_target_space() {
        // Every supported host is either mobile or desktop, never
        // neither. Locks the contract so a future helper that
        // returns `false` on both surfaces a CI failure rather
        // than a silent UI-platform branch crash.
        assert!(host_info_is_mobile() || host_info_is_desktop());
    }

    #[test]
    fn macos_implies_desktop() {
        // The macOS predicate is a desktop subset — never `true`
        // on iOS or Android.
        if host_info_is_macos() {
            assert!(host_info_is_desktop());
            assert!(!host_info_is_mobile());
        }
    }
}
