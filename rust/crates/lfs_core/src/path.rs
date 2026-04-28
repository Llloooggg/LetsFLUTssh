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

/// Extract the basename portion of [`path`], normalising Windows
/// `\` separators to `/` first. Returns the input unchanged when
/// the path has no separator (already a bare basename).
///
/// Pure helper used by the OpenSSH-config importer + the
/// `~/.ssh` directory scanner — every file picker that needs to
/// surface "what file is this?" without parsing the full path.
#[must_use]
pub fn basename(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    match normalized.rfind('/') {
        Some(idx) => normalized[idx + 1..].to_string(),
        None => normalized,
    }
}

/// True when [`path`] contains a `..` segment after normalising
/// Windows separators. A maliciously-crafted `~/.ssh/config` could
/// point `IdentityFile` at `~/../../etc/shadow`; the importer
/// short-circuits on this rule before trying to read the file.
///
/// Absolute paths the user wrote intentionally are still allowed —
/// only literal `..` segments inside the path raise the flag.
#[must_use]
pub fn is_suspicious_path(path: &str) -> bool {
    let normalized = path.replace('\\', "/");
    normalized.split('/').any(|seg| seg == "..")
}

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

/// Atomic byte write: writes [`bytes`] to `<path>.tmp`, hardens the
/// tmp file to owner-only perms via [`harden_file_perms`], then
/// renames to [`path`]. A crash mid-flush leaves either the
/// previous file content or the tmp file behind — never a torn
/// destination.
///
/// Mirror of the Dart-side `utils/file_utils.dart::writeBytesAtomic`
/// — every secret-bearing artefact under app-support (KDF salt,
/// tier-transition marker, hardware-vault blob, rate-limit state,
/// keychain marker, …) routes through this so the on-disk perms
/// contract lives one place. Caller is responsible for ensuring
/// the parent directory exists; this helper does not implicitly
/// create it because the per-tier writers all have their own
/// `create_dir_all` step earlier in the flow + the implicit
/// behaviour would mask "support dir was never resolved" bugs.
pub fn write_bytes_atomic(path: &std::path::Path, bytes: &[u8]) -> Result<(), String> {
    use rand::RngCore;
    // Random 32-bit suffix on the tmp filename so concurrent
    // writers to the same destination do not collide on the
    // intermediate file. Mirror of the Dart `_rng.nextInt(1 << 30)`
    // shape — the suffix only needs to be process-unique long
    // enough for the rename to land; collisions across processes
    // are caught by the rename step itself.
    let mut salt = [0u8; 4];
    rand::rngs::OsRng.fill_bytes(&mut salt);
    let suffix = u32::from_le_bytes(salt);
    let parent = path.parent().unwrap_or(std::path::Path::new("."));
    let stem = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| String::from("blob"));
    let tmp = parent.join(format!("{stem}.tmp{suffix:08x}"));
    if let Err(e) = std::fs::write(&tmp, bytes) {
        return Err(format!("write {}: {e}", tmp.display()));
    }
    // Best-effort harden — a chmod failure on the tmp file is the
    // same posture the Dart writer shipped (log + swallow). The
    // rename completes regardless so the destination always lands.
    let _ = harden_file_perms(&tmp);
    if let Err(e) = std::fs::rename(&tmp, path) {
        // Clean up the tmp on rename failure so a wedged tier
        // switch does not litter app-support with stale tmps.
        let _ = std::fs::remove_file(&tmp);
        return Err(format!("rename {}: {e}", path.display()));
    }
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

    #[test]
    fn basename_returns_input_for_bare_filename() {
        assert_eq!(basename("file.txt"), "file.txt");
    }

    #[test]
    fn basename_returns_last_segment_for_unix_path() {
        assert_eq!(basename("/home/user/file.txt"), "file.txt");
    }

    #[test]
    fn basename_normalizes_windows_separators() {
        assert_eq!(basename(r"C:\Users\u\file.txt"), "file.txt");
    }

    #[test]
    fn basename_handles_trailing_separator() {
        assert_eq!(basename("/home/user/"), "");
    }

    #[test]
    fn is_suspicious_path_flags_dotdot_segment() {
        assert!(is_suspicious_path("/home/user/../../etc/shadow"));
        assert!(is_suspicious_path("../config"));
    }

    #[test]
    fn is_suspicious_path_passes_clean_paths() {
        assert!(!is_suspicious_path("/home/user/.ssh/id_ed25519"));
        assert!(!is_suspicious_path("file.txt"));
    }

    #[test]
    fn is_suspicious_path_flags_dotdot_with_windows_separators() {
        assert!(is_suspicious_path(r"C:\Users\u\..\..\Windows"));
    }

    #[test]
    fn is_suspicious_path_passes_dotdotextension() {
        // ".." is the trigger; "..foo" is not a traversal segment.
        assert!(!is_suspicious_path("/home/user/..foo"));
    }

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

    #[test]
    fn write_bytes_atomic_round_trips_payload() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("payload.bin");
        write_bytes_atomic(&path, b"hello, atomic world").unwrap();
        let contents = std::fs::read(&path).unwrap();
        assert_eq!(contents, b"hello, atomic world");
    }

    #[test]
    fn write_bytes_atomic_overwrites_existing() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("payload.bin");
        std::fs::write(&path, b"first version").unwrap();
        write_bytes_atomic(&path, b"second version").unwrap();
        let contents = std::fs::read(&path).unwrap();
        assert_eq!(contents, b"second version");
    }

    #[test]
    fn write_bytes_atomic_leaves_no_tmp_on_success() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("payload.bin");
        write_bytes_atomic(&path, b"x").unwrap();
        assert!(path.exists());
        // No leftover `.tmp*` files anywhere in the parent dir.
        let leftover: Vec<_> = std::fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
            .collect();
        assert!(leftover.is_empty(), "stale tmp file: {leftover:?}");
    }

    #[test]
    fn write_bytes_atomic_concurrent_writes_do_not_corrupt_destination() {
        // Mirror of the Dart `writeFileAtomic preserves content on
        // concurrent writes` test. Three parallel writes to the
        // same destination must produce a non-corrupt file with one
        // of the three payloads — the random tmp suffix prevents
        // intermediate-file collisions.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("race.bin");
        let path_a = path.clone();
        let path_b = path.clone();
        let path_c = path.clone();
        let h_a = std::thread::spawn(move || write_bytes_atomic(&path_a, b"a"));
        let h_b = std::thread::spawn(move || write_bytes_atomic(&path_b, b"b"));
        let h_c = std::thread::spawn(move || write_bytes_atomic(&path_c, b"c"));
        h_a.join().unwrap().unwrap();
        h_b.join().unwrap().unwrap();
        h_c.join().unwrap().unwrap();
        let final_bytes = std::fs::read(&path).unwrap();
        assert_eq!(final_bytes.len(), 1);
        assert!(matches!(final_bytes[0], b'a' | b'b' | b'c'));
    }

    #[cfg(unix)]
    #[test]
    fn write_bytes_atomic_lands_destination_at_owner_only_perms() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("payload.bin");
        write_bytes_atomic(&path, b"x").unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[test]
    fn write_bytes_atomic_errors_when_parent_dir_missing() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("does-not-exist").join("payload.bin");
        // Caller is responsible for `create_dir_all`; this helper
        // surfaces ENOENT rather than implicitly creating it, so a
        // misconfigured caller is loud not silent.
        let err = write_bytes_atomic(&path, b"x").unwrap_err();
        assert!(err.contains("write"));
    }
}
