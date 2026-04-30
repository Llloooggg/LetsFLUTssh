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
