/// Unit tests extracted from ssh/verbose_log.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn ssh_target_filter_matches_russh_only() {
    assert!(is_ssh_target("russh"));
    assert!(is_ssh_target("russh::client::encrypted"));
    assert!(is_ssh_target("russh_sftp::client"));
    assert!(!is_ssh_target("tokio::net"));
    assert!(!is_ssh_target("reqwest"));
}

#[test]
fn set_verbose_flips_the_flag() {
    set_verbose(true);
    assert!(is_verbose());
    set_verbose(false);
    assert!(!is_verbose());
}
