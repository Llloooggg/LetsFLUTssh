//! Path helpers shared between the core and its frontends.
//!
//! Today: tilde-prefix expansion (`~/.ssh/config` →
//! `/home/<user>/.ssh/config`). Centralised so every consumer
//! resolves home the same way; previously the Dart side had its
//! own copy in `openssh_config_importer.dart`, the macOS resign
//! orchestrator had a third, and they each picked their own
//! environment-variable preference.
//!
//! Resolution order matches OpenSSH and bash:
//!   1. `$HOME` if set and non-empty.
//!   2. `$USERPROFILE` (Windows fallback) if set and non-empty.
//!
//! When neither variable resolves, the input is returned
//! verbatim — better to leave the literal `~` than to point at a
//! wrong directory and corrupt user data.

/// Expand a leading `~` or `~/` against the running user's home
/// directory. Other tilde shapes (`~user/foo`) are left as-is
/// — they cannot be resolved without nss / passwd lookups, and
/// every call site in this codebase only writes the bare-tilde
/// form.
pub fn expand_tilde(path: &str) -> String {
    if path == "~" {
        return home_dir().unwrap_or_else(|| path.to_string());
    }
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = home_dir() {
            // Preserve trailing slashes / the empty-rest case
            // (`~/` → `<home>/`) so callers that expect a
            // directory-style path keep their separator.
            if rest.is_empty() {
                return format!("{home}/");
            }
            return format!("{home}/{rest}");
        }
    }
    path.to_string()
}

fn home_dir() -> Option<String> {
    if let Ok(h) = std::env::var("HOME") {
        if !h.is_empty() {
            return Some(h);
        }
    }
    if let Ok(h) = std::env::var("USERPROFILE") {
        if !h.is_empty() {
            return Some(h);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Tests mutate process-wide environment variables. Run them
    /// serialised under a `Mutex` so parallel cargo-test runs
    /// don't trample each other's `HOME`. Lock acquired with
    /// `unwrap_or_else` to keep poisoning from skipping tests.
    use std::sync::Mutex;
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn bare_tilde_resolves_to_home() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::set_var("HOME", "/tmp/fakehome");
        assert_eq!(expand_tilde("~"), "/tmp/fakehome");
    }

    #[test]
    fn tilde_slash_prefix_expands() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::set_var("HOME", "/tmp/fakehome");
        assert_eq!(expand_tilde("~/.ssh/config"), "/tmp/fakehome/.ssh/config");
    }

    #[test]
    fn tilde_slash_only_keeps_separator() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::set_var("HOME", "/tmp/fakehome");
        assert_eq!(expand_tilde("~/"), "/tmp/fakehome/");
    }

    #[test]
    fn user_tilde_form_left_unchanged() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::set_var("HOME", "/tmp/fakehome");
        assert_eq!(expand_tilde("~bob/foo"), "~bob/foo");
    }

    #[test]
    fn no_home_returns_input_verbatim() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::remove_var("HOME");
        std::env::remove_var("USERPROFILE");
        assert_eq!(expand_tilde("~/.ssh/config"), "~/.ssh/config");
    }

    #[test]
    fn userprofile_fallback_when_home_unset() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        std::env::remove_var("HOME");
        std::env::set_var("USERPROFILE", "C:\\Users\\bob");
        assert_eq!(expand_tilde("~/foo"), "C:\\Users\\bob/foo");
        std::env::remove_var("USERPROFILE");
    }

    #[test]
    fn absolute_path_unchanged() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(expand_tilde("/absolute/path"), "/absolute/path");
    }
}
