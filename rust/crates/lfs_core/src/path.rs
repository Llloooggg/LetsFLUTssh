//! Path + filesystem helpers shared between the core and its
//! frontends.
//!
//! Two concerns live here today:
//!
//! * Tilde-prefix expansion (`~/.ssh/config` →
//!   `/home/<user>/.ssh/config`). Centralised so every consumer
//!   resolves home the same way; previously the Dart side had its
//!   own copy in `openssh_config_importer.dart`, the macOS resign
//!   orchestrator had a third, and they each picked their own
//!   environment-variable preference.
//!
//! * `harden_file_perms` — best-effort perm tightening for files
//!   under app-support that hold encryption keys / verifier blobs
//!   / rate-limit state. Mirror of the Dart-side
//!   `utils/file_utils.dart::hardenFilePerms` so a write from
//!   either side ends up at the same on-disk perms (Unix 0600 /
//!   Windows owner-only ACL).
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

/// Lock down [`path`]'s permissions to owner-only.
///
/// * Unix (Linux / macOS / Android / iOS) — `chmod 0600`. Matches
///   the OpenSSH expectation for every file under `~/.ssh/`.
/// * Windows — best-effort `icacls /inheritance:r /grant:r
///   <user>:(F)` shell-out. Removes inherited ACLs and grants the
///   current user full control. No-op when `USERNAME` is empty
///   (CI / service-account contexts that don't carry the env var).
/// * Other targets — no-op (iOS / Android already sandbox per-app
///   storage tighter than `chmod 600`).
///
/// Best-effort: any failure is swallowed and reported as `Err` for
/// the caller to log; the caller never aborts the surrounding write
/// because of a perm-tighten miss. A hardened file that crashed on
/// startup is worse than an unhardened one that works.
#[cfg(unix)]
pub fn harden_file_perms(path: &std::path::Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    let perms = std::fs::Permissions::from_mode(0o600);
    std::fs::set_permissions(path, perms).map_err(|e| format!("chmod 600 {}: {e}", path.display()))
}

#[cfg(windows)]
pub fn harden_file_perms(path: &std::path::Path) -> Result<(), String> {
    // `windows::*` would need a new dep; mirror the Dart shape
    // (icacls shell-out) instead. Same syscalls icacls itself wraps,
    // no extra crate surface to audit.
    let user = std::env::var("USERNAME").unwrap_or_default();
    if user.is_empty() {
        return Ok(());
    }
    let status = std::process::Command::new("icacls")
        .arg(path)
        .arg("/inheritance:r")
        .arg("/grant:r")
        .arg(format!("{user}:(F)"))
        .status()
        .map_err(|e| format!("spawn icacls: {e}"))?;
    if !status.success() {
        return Err(format!(
            "icacls {} exited with {:?}",
            path.display(),
            status.code()
        ));
    }
    Ok(())
}

#[cfg(not(any(unix, windows)))]
pub fn harden_file_perms(_path: &std::path::Path) -> Result<(), String> {
    Ok(())
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

    #[cfg(unix)]
    #[test]
    fn harden_file_perms_sets_owner_only_mode() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("secret.bin");
        std::fs::write(&path, b"x").unwrap();
        // Pre-condition: default umask leaves at least group-readable
        // bits on a fresh file. Sanity-check before the call.
        let before = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_ne!(before, 0o600, "test setup got 0600 unexpectedly");

        harden_file_perms(&path).unwrap();

        let after = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(after, 0o600);
    }

    #[cfg(unix)]
    #[test]
    fn harden_file_perms_errors_on_missing_path() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("does-not-exist");
        let err = harden_file_perms(&path).unwrap_err();
        assert!(err.contains("chmod"));
    }
}
