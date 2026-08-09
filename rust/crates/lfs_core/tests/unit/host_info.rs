/// Unit tests extracted from host_info.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn home_directory_returns_non_empty_string_in_normal_env() {
    // Test environments always have HOME set on POSIX hosts and
    // USERPROFILE on Windows, so the resolver should produce a
    // path. We don't assert the value — just that the lookup
    // doesn't error out and returns *something*.
    let home = home_directory();
    if cfg!(any(target_os = "linux", target_os = "macos")) {
        // On Linux/macOS dev hosts HOME is always set under
        // `cargo test` — assert non-empty to lock the contract.
        assert!(!home.is_empty(), "HOME must resolve under cargo test");
    }
}

#[test]
fn platform_predicates_match_target_cfg() {
    // Sanity-check that the booleans are mutually consistent
    // with the build target. We can't assert exact values
    // (build matrix may be Linux, macOS, etc.) so the test
    // checks the partition: exactly one of mobile/desktop is
    // true; macOS implies desktop.
    assert_ne!(is_mobile(), is_desktop());
    if is_macos() {
        assert!(is_desktop());
    }
}
