//! Path + filesystem helpers shared between the core and its
//! frontends.
//!
//! Two concerns live here today:
//!
//! * Tilde-prefix expansion (`~/.ssh/config` →
//!   `/home/<user>/.ssh/config`). Centralised so every consumer
//!   resolves home the same way and picks the same
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

/// True when [`name`] is safe to join onto a download directory.
///
/// SFTP servers supply directory-entry names as untrusted bytes;
/// the directory-walk download path joins each onto the user-chosen
/// destination, and `p.join` does not normalise. A name carrying a
/// path separator, a `.`/`..` traversal segment, or a NUL would land
/// the file outside the destination (or silently truncate the path
/// at the NUL on most filesystems). Reject those; interior spaces
/// are legitimate filename content and stay allowed.
#[must_use]
pub fn is_safe_transfer_entry_name(name: &str) -> bool {
    if name.is_empty() {
        return false;
    }
    if name == "." || name == ".." {
        return false;
    }
    // Both separator families: a Windows-shaped server name must not
    // drift through a POSIX-only check.
    if name.contains('/') || name.contains('\\') {
        return false;
    }
    if name.contains('\0') {
        return false;
    }
    // Whitespace-only names round-trip differently across platform
    // canonicalisation; reject them outright. Interior whitespace in
    // an otherwise-real name is fine.
    if name.trim().is_empty() {
        return false;
    }
    true
}

/// Parse Windows `attrib` command output and return the lowercase
/// basename of every file flagged Hidden (H) or System (S). Used
/// by `LocalFS.list` on Windows to filter the directory view to
/// match what Explorer would hide. Caller spawns `cmd /c attrib *`
/// and feeds stdout here; we own the pure parsing.
///
/// Each `attrib` line has the shape `"     A  SH  C:\path\file"`
/// — a run of attribute letters then a space-padded gap then the
/// full path. Attribute letters are uppercase ASCII; the row only
/// fires when an `H` or `S` is present in the attribute run.
///
/// Output is lowercased to match the Dart caller's lookup-set
/// convention.
#[must_use]
pub fn parse_windows_attrib_output(output: &str) -> std::collections::HashSet<String> {
    let mut hidden: std::collections::HashSet<String> = std::collections::HashSet::new();
    for raw_line in output.split('\n') {
        if let Some(bn) = parse_attrib_line(raw_line) {
            hidden.insert(bn);
        }
    }
    hidden
}

/// Parse a single `attrib` output line. Returns the lowercase
/// basename when the line carries a Hidden (`H`) or System (`S`)
/// flag, or `None` for blank lines / lines without an attribute run
/// / rows that are neither hidden nor system.
fn parse_attrib_line(raw_line: &str) -> Option<String> {
    let trimmed = raw_line.trim_end();
    if trimmed.is_empty() {
        return None;
    }
    let idx = attr_run_end(trimmed)?;
    let attrs = trimmed[..=idx].to_ascii_uppercase();
    if !attrs.contains('H') && !attrs.contains('S') {
        return None;
    }
    let full_path = trimmed[idx + 3..].trim();
    // Windows basename — split on `\` then take the tail.
    let bn = full_path.rsplit(['\\', '/']).next().unwrap_or(full_path);
    Some(bn.to_lowercase())
}

/// Index of the last `[A-Z]  ` (capital letter followed by two
/// spaces) in `trimmed` — the boundary between the attribute run
/// and the path. Walk right-to-left so paths containing capitals
/// don't false-match.
fn attr_run_end(trimmed: &str) -> Option<usize> {
    let bytes = trimmed.as_bytes();
    if bytes.len() < 3 {
        return None;
    }
    for i in (0..bytes.len() - 2).rev() {
        let c = bytes[i];
        if c.is_ascii_uppercase() && bytes[i + 1] == b' ' && bytes[i + 2] == b' ' {
            return Some(i);
        }
    }
    None
}

/// Separator family for [`parent`]. `Posix` forces `/`-only
/// parsing (SFTP remote paths, always forward-slash); `Windows`
/// recognises both `\` and `/` and the `C:\` drive-root form;
/// `Auto` infers from the string — a `\` or a `X:`-style drive
/// prefix selects Windows rules, otherwise POSIX. The file pane
/// passes `Auto` so the same `navigateUp` handles the Windows local
/// pane (native `C:\Users\foo`) and the SFTP pane (forward-slash)
/// without a platform branch at the call site.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PathStyle {
    Posix,
    Windows,
    Auto,
}

/// Parent directory of [`path`], or `None` when the path has no
/// parent (POSIX / SFTP root `/`, a Windows drive root `C:\`, an
/// empty string, or a bare relative segment with no separator).
///
/// A trailing separator is stripped first so `parent("/a/b/")` is
/// `/a`, not `/a/b`. The POSIX root collapses to `/` (parent of
/// `/foo` is `/`). The Windows drive root snaps its trailing
/// separator back so `parent(r"C:\Users")` returns `C:\` (the form
/// `list()` expects) rather than the bare `C:`. Returning `None` at
/// a root lets the caller render "Up" as a no-op rather than
/// dropping to a wrong directory the lister then rejects.
#[must_use]
pub fn parent(path: &str, style: PathStyle) -> Option<String> {
    if path.is_empty() || path == "/" {
        return None;
    }
    let windows = match style {
        PathStyle::Posix => false,
        PathStyle::Windows => true,
        PathStyle::Auto => path.contains('\\') || is_windows_drive_prefixed(path),
    };
    if windows {
        windows_parent(path)
    } else {
        posix_parent(path)
    }
}

/// True when `path` starts with a `X:` drive-letter prefix
/// (`C:\Users`, `D:/data`, or the bare `C:`). Used by [`PathStyle::Auto`]
/// to pick Windows rules for a drive-rooted path even when it uses
/// forward slashes.
fn is_windows_drive_prefixed(path: &str) -> bool {
    let mut chars = path.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic()) && chars.next() == Some(':')
}

fn posix_parent(path: &str) -> Option<String> {
    let trimmed = path.strip_suffix('/').unwrap_or(path);
    if trimmed.is_empty() {
        // Was just "/" after stripping — root has no parent.
        return None;
    }
    match trimmed.rfind('/') {
        None => None,                     // bare relative segment, no parent
        Some(0) => Some("/".to_string()), // "/foo" → "/"
        Some(idx) => Some(trimmed[..idx].to_string()),
    }
}

fn windows_parent(path: &str) -> Option<String> {
    // A drive root in any separator form (`C:\`, `D:/`, bare `C:`)
    // has no parent.
    if is_windows_drive_root(path) {
        return None;
    }
    let trimmed = match path.chars().last() {
        Some('\\') | Some('/') => &path[..path.len() - 1],
        _ => path,
    };
    // Re-check after trimming: `C:\` trims to `C:`.
    if is_windows_drive_root(trimmed) {
        return None;
    }
    let idx = trimmed.rfind(['\\', '/'])?;
    let up = &trimmed[..idx];
    // `up` of `C:\Users` is `C:`; snap the drive root's trailing
    // separator back so the lister gets the canonical `C:\` form.
    if is_windows_drive_root(up) {
        return Some(format!("{up}\\"));
    }
    Some(up.to_string())
}

/// True when `path` is a Windows drive root in any separator form:
/// `C:`, `C:\`, or `C:/`.
fn is_windows_drive_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    match bytes.len() {
        2 => bytes[0].is_ascii_alphabetic() && bytes[1] == b':',
        3 => bytes[0].is_ascii_alphabetic() && bytes[1] == b':' && matches!(bytes[2], b'\\' | b'/'),
        _ => false,
    }
}

/// Generate the `n`-th `"stem (N)ext"` sibling-name candidate
/// next to [`path`]. Used by the transfer-conflict resolver +
/// the local + remote drag-into-existing flows: each attempt
/// asks the FS whether the candidate is free, incrementing `n`
/// until a slot opens.
///
/// Splitting rule matches GNOME Files / Finder: only the **final**
/// extension is preserved, so `archive.tar.gz` becomes
/// `archive.tar (N).gz`. `README` (no extension) becomes
/// `README (N)`.
///
/// `posix` selects the path-separator family — `true` for SFTP
/// remote paths, `false` for the local OS native form (which
/// matches `\` on Windows + `/` elsewhere).
///
/// Generates the candidate text only — checking whether the
/// slot exists stays caller-side (it needs FS / SFTP I/O).
#[must_use]
pub fn sibling_candidate(path: &str, n: u32, posix: bool) -> String {
    let sep = if posix || !path.contains('\\') {
        '/'
    } else {
        '\\'
    };
    // Find the dirname / basename split — last separator.
    let (dir, base) = match path.rfind(sep) {
        Some(idx) => (&path[..=idx], &path[idx + 1..]),
        None => ("", path),
    };
    // Last `.` inside the basename, ignoring leading `.` (a
    // dotfile like `.bashrc` has no extension).
    let ext_idx = base.rfind('.').filter(|&i| i > 0);
    let (stem, ext) = match ext_idx {
        Some(i) => (&base[..i], &base[i..]),
        None => (base, ""),
    };
    format!("{dir}{stem} ({n}){ext}")
}

/// Shorten a path to its last two non-empty segments (joined with
/// `/`), prefixed with `.../`. Used by the transfer panel to keep
/// long paths readable in the row width without losing the
/// trailing context. Returns the input verbatim when it has at
/// most two segments; empty in → empty out.
#[must_use]
pub fn shorten_to_two_segments(path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    let normalized = path.replace('\\', "/");
    let parts: Vec<&str> = normalized.split('/').filter(|s| !s.is_empty()).collect();
    if parts.len() <= 2 {
        return normalized;
    }
    let tail = &parts[parts.len() - 2..];
    format!(".../{}", tail.join("/"))
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
///   the OpenSSH expectation for every file under `~/.ssh/`. Redundant
///   on Android / iOS — per-app storage is already UID-sandboxed by the
///   OS — but harmless and keeps the path uniform.
/// * Windows — delegates to
///   [`lfs_os_security::path::harden_file_perms_windows`], which sets
///   an owner-only DACL via the Win32 security APIs (equivalent to
///   `icacls /inheritance:r /grant:r <user>:(F)`, no subprocess). The
///   OS-API FFI lives in `lfs_os_security` because that crate is the
///   single audit perimeter for OS-API FFI + subprocess spawning.
/// * Other targets (wasm / unknown) — no-op.
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
    // Subprocess invocation lives in `lfs_os_security` (the single
    // audit perimeter for OS-API FFI / subprocess spawning); this
    // arm is a thin delegate. The `chmod(2)` syscall the Unix arm
    // wraps stays in `lfs_core` because `std::fs::set_permissions`
    // is not subprocess-bound and the audit-perimeter rule only
    // governs OS-API FFI + subprocess spawning.
    lfs_os_security::path::harden_file_perms_windows(path)
}

#[cfg(not(any(unix, windows)))]
pub fn harden_file_perms(_path: &std::path::Path) -> Result<(), String> {
    Ok(())
}

/// Lock down [`path`]'s directory permissions to owner-only
/// (`chmod 0700` on Unix). Mirror of [`harden_file_perms`] for
/// directories — used by the app-support parent-dir creation flow
/// so a freshly-created `~/.local/share/letsflutssh` does not land
/// under the inherited umask (commonly 0755 → group/other read).
///
/// Best-effort: any failure surfaces as `Err` for the caller to
/// log; callers never abort the surrounding write because of a
/// perm-tighten miss.
///
/// Windows is a no-op — `%APPDATA%\<app>` inherits the user's
/// profile ACL which is already restricted to the running user.
/// Tightening a directory's ACL further affects file inheritance
/// and risks breaking subsequent in-place writes; the inherited
/// ACL is the established Windows convention.
#[cfg(unix)]
pub fn harden_dir_perms(path: &std::path::Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    let perms = std::fs::Permissions::from_mode(0o700);
    std::fs::set_permissions(path, perms).map_err(|e| format!("chmod 700 {}: {e}", path.display()))
}

#[cfg(not(unix))]
pub fn harden_dir_perms(_path: &std::path::Path) -> Result<(), String> {
    Ok(())
}

/// Symlink-safe sync read for persisted-format files. Opens with
/// `O_NOFOLLOW` on Unix so a (hostile) pre-existing symlink at
/// the path resolves to `ELOOP` rather than routing the read
/// through to whatever the symlink targets (`/etc/shadow`, the
/// user's mailbox, …). Windows passes through to `fs::read` —
/// NTFS reparse points need elevated rights to create at user-
/// support paths in the first place.
///
/// Use this for every read of a credential / KDF / verifier /
/// marker artefact under `support_dir`. User-chosen paths
/// (download destinations, archive imports the user picked) keep
/// the standard `fs::read` so a user's own symlink in their
/// Downloads folder still works.
pub fn read_bytes_secure(path: &std::path::Path) -> std::io::Result<Vec<u8>> {
    use std::io::Read as _;
    let mut opts = std::fs::OpenOptions::new();
    opts.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.custom_flags(libc::O_NOFOLLOW);
    }
    let mut f = opts.open(path)?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)?;
    Ok(buf)
}

/// `create_dir_all` + [`harden_dir_perms`] for directories the app
/// owns under the platform's app-support tree. A fresh-install
/// run that creates `~/.local/share/letsflutssh` would otherwise
/// land at the user's umask (typically 0755 — group + other read);
/// secret-bearing artefacts inside expect 0600 file perms but the
/// containing directory listing leaks the artefact filenames.
/// This helper closes that gap: directories carrying credentials
/// land at 0700 from creation onward.
///
/// Caller restriction — pass only paths under app-support (or
/// equivalent). User-chosen download / export folders must keep
/// their inherited perms; this helper would lock the user out of
/// their own Documents / Downloads.
pub fn create_dir_all_secure(path: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(path).map_err(|e| format!("create dir {}: {e}", path.display()))?;
    let _ = harden_dir_perms(path);
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
    use rand::Rng;
    use std::io::Write as _;
    // Random 32-bit suffix on the tmp filename so concurrent
    // writers to the same destination do not collide on the
    // intermediate file. Mirror of the Dart `_rng.nextInt(1 << 30)`
    // shape — the suffix only needs to be process-unique long
    // enough for the rename to land; collisions across processes
    // are caught by the rename step itself.
    let mut salt = [0u8; 4];
    rand::rng().fill_bytes(&mut salt);
    let suffix = u32::from_le_bytes(salt);
    let parent = path.parent().unwrap_or(std::path::Path::new("."));
    let stem = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| String::from("blob"));
    let tmp = parent.join(format!("{stem}.tmp{suffix:08x}"));
    // Write + fsync the tmp file before rename. Without the fsync,
    // a power-loss / OS panic between the rename and the kernel
    // flushing the data pages can leave the destination pointing at
    // an empty / truncated file even though the directory entry
    // resolved. Every artefact this helper writes (KDF state,
    // hardware-vault blob, rate-limit history, keychain marker,
    // tier-transition marker) is cold-launch-load-bearing — a torn
    // post-crash state forces a tier reset / data-wipe path the
    // user did not ask for. `sync_data` flushes file contents but
    // skips metadata that doesn't affect file integrity, so it is
    // strictly cheaper than `sync_all` while still closing the
    // payload-corruption window.
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.create(true).write(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            // O_NOFOLLOW on the tmp open: a (very unlikely)
            // pre-existing symlink at the random-suffix path would
            // otherwise route the write through it. Random-suffix
            // brute-force inside a 0700 parent is the only attack
            // surface; this closes it for free.
            // O_EXCL with O_CREAT: fail if the tmp file already
            // exists rather than truncating an attacker-planted one.
            // The 32-bit OsRng salt means a real collision is a
            // bug-not-an-attack; surfacing the error is the right
            // posture.
            opts.mode(0o600);
            opts.custom_flags(libc::O_NOFOLLOW | libc::O_EXCL);
        }
        let mut f = opts
            .open(&tmp)
            .map_err(|e| format!("create {}: {e}", tmp.display()))?;
        if let Err(e) = f.write_all(bytes) {
            // Drop the partial tmp so the next write does not
            // re-collide on the same suffix.
            drop(f);
            let _ = std::fs::remove_file(&tmp);
            return Err(format!("write {}: {e}", tmp.display()));
        }
        if let Err(e) = f.sync_data() {
            drop(f);
            let _ = std::fs::remove_file(&tmp);
            return Err(format!("fsync {}: {e}", tmp.display()));
        }
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
    // fsync the parent directory so the rename itself survives a
    // crash. Without this, Linux + Apple can lose the rename even
    // though the file's data pages flushed (the directory entry
    // sits in the page cache until the next inode-touching event).
    // Best-effort — Windows has no directory-fsync primitive on
    // POSIX semantics (`File::open` on a dir + `sync_all` is a
    // no-op there); the `MoveFileExW` underlying `std::fs::rename`
    // is durable enough in practice for the artefacts we ship.
    #[cfg(unix)]
    {
        if let Ok(dir) = std::fs::File::open(parent) {
            let _ = dir.sync_all();
        }
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

    #[test]
    fn safe_entry_name_accepts_plain_names() {
        assert!(is_safe_transfer_entry_name("readme.txt"));
        assert!(is_safe_transfer_entry_name("img-2024_05.png"));
    }

    #[test]
    fn safe_entry_name_accepts_interior_spaces() {
        // Spaces inside a real filename are legitimate content.
        assert!(is_safe_transfer_entry_name("my file.txt"));
        assert!(is_safe_transfer_entry_name("a b c"));
    }

    #[test]
    fn safe_entry_name_accepts_dotfile() {
        assert!(is_safe_transfer_entry_name(".bashrc"));
    }

    #[test]
    fn safe_entry_name_accepts_dotdot_prefix() {
        // "..foo" is not the `..` traversal segment.
        assert!(is_safe_transfer_entry_name("..foo"));
    }

    #[test]
    fn safe_entry_name_rejects_empty() {
        assert!(!is_safe_transfer_entry_name(""));
    }

    #[test]
    fn safe_entry_name_rejects_self_and_parent_refs() {
        assert!(!is_safe_transfer_entry_name("."));
        assert!(!is_safe_transfer_entry_name(".."));
    }

    #[test]
    fn safe_entry_name_rejects_separators() {
        assert!(!is_safe_transfer_entry_name("a/b"));
        assert!(!is_safe_transfer_entry_name("a\\b"));
        assert!(!is_safe_transfer_entry_name("../../etc/cron.d/x"));
        assert!(!is_safe_transfer_entry_name("/etc/passwd"));
    }

    #[test]
    fn safe_entry_name_rejects_embedded_nul() {
        assert!(!is_safe_transfer_entry_name("foo\0bar"));
        assert!(!is_safe_transfer_entry_name("trailing\0"));
    }

    #[test]
    fn safe_entry_name_rejects_whitespace_only() {
        assert!(!is_safe_transfer_entry_name("   "));
        assert!(!is_safe_transfer_entry_name("\t\n"));
    }

    #[test]
    fn safe_entry_name_invariant_holds_over_adversarial_inputs() {
        // Property-style sweep: any name containing a separator, a
        // NUL, or equal to ""/"."/".."/whitespace-only is rejected;
        // the predicate never panics. Built from hostile fragments
        // mixed with benign ones the way a malicious SFTP server
        // would shape directory entries.
        let fragments = [
            "",
            ".",
            "..",
            "/",
            "\\",
            "\0",
            " ",
            "\t",
            "a",
            "file.txt",
            "..foo",
            "中文",
            "💥",
            "\u{202E}rcs.exe",
            "a\0b",
            "../x",
            "x/../y",
            "C:\\Windows",
        ];
        for a in &fragments {
            for b in &fragments {
                let name = format!("{a}{b}");
                let unsafe_shape = name.is_empty()
                    || name == "."
                    || name == ".."
                    || name.contains('/')
                    || name.contains('\\')
                    || name.contains('\0')
                    || name.trim().is_empty();
                assert_eq!(
                    is_safe_transfer_entry_name(&name),
                    !unsafe_shape,
                    "name {name:?} classified wrong"
                );
            }
        }
        // A huge name with no banned char is still safe; with one is
        // not — length alone is not a rejection axis.
        let huge = "x".repeat(100_000);
        assert!(is_safe_transfer_entry_name(&huge));
        let huge_sep = format!("{huge}/y");
        assert!(!is_safe_transfer_entry_name(&huge_sep));
    }

    #[test]
    fn parent_of_posix_file_drops_to_dir() {
        assert_eq!(
            parent("/home/user/file.txt", PathStyle::Posix).as_deref(),
            Some("/home/user")
        );
    }

    #[test]
    fn parent_of_first_level_posix_collapses_to_root() {
        assert_eq!(parent("/home", PathStyle::Posix).as_deref(), Some("/"));
    }

    #[test]
    fn parent_of_posix_root_is_none() {
        assert!(parent("/", PathStyle::Posix).is_none());
        assert!(parent("/", PathStyle::Auto).is_none());
    }

    #[test]
    fn parent_strips_trailing_slash_first() {
        assert_eq!(
            parent("/home/user/", PathStyle::Posix).as_deref(),
            Some("/home")
        );
    }

    #[test]
    fn parent_of_empty_is_none() {
        assert!(parent("", PathStyle::Auto).is_none());
    }

    #[test]
    fn parent_of_bare_relative_segment_is_none() {
        assert!(parent("file.txt", PathStyle::Posix).is_none());
    }

    #[test]
    fn parent_of_windows_path_drops_to_dir() {
        assert_eq!(
            parent(r"C:\Users\foo\file.txt", PathStyle::Auto).as_deref(),
            Some(r"C:\Users\foo")
        );
    }

    #[test]
    fn parent_of_windows_first_level_snaps_drive_root() {
        // Parent of `C:\Users` is the drive root `C:\`, not bare `C:`.
        assert_eq!(
            parent(r"C:\Users", PathStyle::Auto).as_deref(),
            Some(r"C:\")
        );
    }

    #[test]
    fn parent_of_windows_drive_root_is_none() {
        assert!(parent(r"C:\", PathStyle::Auto).is_none());
        assert!(parent("C:", PathStyle::Windows).is_none());
        assert!(parent("D:/", PathStyle::Auto).is_none());
    }

    #[test]
    fn parent_auto_detects_windows_from_forward_slash_drive() {
        // Drive-prefixed even with forward slashes → Windows rules,
        // so the drive root snaps back with a backslash.
        assert_eq!(parent("C:/Users", PathStyle::Auto).as_deref(), Some(r"C:\"));
    }

    #[test]
    fn parent_auto_treats_plain_path_as_posix() {
        assert_eq!(
            parent("/var/log/app", PathStyle::Auto).as_deref(),
            Some("/var/log")
        );
    }

    #[test]
    fn shorten_returns_empty_for_empty() {
        assert_eq!(shorten_to_two_segments(""), "");
    }

    #[test]
    fn shorten_passes_through_paths_with_two_or_fewer_segments() {
        assert_eq!(shorten_to_two_segments("foo"), "foo");
        assert_eq!(shorten_to_two_segments("foo/bar"), "foo/bar");
        assert_eq!(shorten_to_two_segments("/foo"), "/foo");
    }

    #[test]
    fn shorten_keeps_last_two_segments_for_deep_paths() {
        assert_eq!(
            shorten_to_two_segments("/home/user/projects/myrepo/file.txt"),
            ".../myrepo/file.txt"
        );
    }

    #[test]
    fn shorten_normalizes_windows_separators() {
        assert_eq!(
            shorten_to_two_segments(r"C:\Users\u\Downloads\file.txt"),
            ".../Downloads/file.txt"
        );
    }

    #[test]
    fn sibling_candidate_inserts_n_before_extension() {
        assert_eq!(
            sibling_candidate("/home/u/report.txt", 1, true),
            "/home/u/report (1).txt"
        );
        assert_eq!(
            sibling_candidate("/home/u/report.txt", 42, true),
            "/home/u/report (42).txt"
        );
    }

    #[test]
    fn sibling_candidate_only_preserves_final_extension() {
        // "archive.tar.gz" → "archive.tar (1).gz" — matches GNOME
        // Files / Finder behaviour.
        assert_eq!(
            sibling_candidate("/home/u/archive.tar.gz", 1, true),
            "/home/u/archive.tar (1).gz"
        );
    }

    #[test]
    fn sibling_candidate_handles_extensionless_files() {
        assert_eq!(
            sibling_candidate("/home/u/README", 1, true),
            "/home/u/README (1)"
        );
    }

    #[test]
    fn sibling_candidate_handles_dotfiles_as_extensionless() {
        // ".bashrc" — leading dot is not an extension.
        assert_eq!(
            sibling_candidate("/home/u/.bashrc", 1, true),
            "/home/u/.bashrc (1)"
        );
    }

    #[test]
    fn sibling_candidate_handles_bare_filename() {
        assert_eq!(sibling_candidate("file.txt", 1, true), "file (1).txt");
    }

    #[test]
    fn sibling_candidate_uses_native_separator_when_not_posix() {
        // Windows path; posix=false should use `\` as the
        // dirname separator.
        assert_eq!(
            sibling_candidate(r"C:\Users\u\file.txt", 1, false),
            r"C:\Users\u\file (1).txt"
        );
    }

    #[test]
    fn parse_attrib_finds_hidden_files() {
        let out = "A    H  C:\\Users\\u\\hidden.txt\n\
                   A       C:\\Users\\u\\visible.txt\n\
                   A   S   C:\\Users\\u\\system.txt\n";
        let result = parse_windows_attrib_output(out);
        assert!(result.contains("hidden.txt"));
        assert!(result.contains("system.txt"));
        assert!(!result.contains("visible.txt"));
    }

    #[test]
    fn parse_attrib_normalizes_to_lowercase() {
        let out = "A    H  C:\\Users\\u\\HIDDEN.TXT\n";
        let result = parse_windows_attrib_output(out);
        assert!(result.contains("hidden.txt"));
        assert!(!result.contains("HIDDEN.TXT"));
    }

    #[test]
    fn parse_attrib_skips_blank_and_malformed_lines() {
        let out = "\n\nblank line\nA   H  C:\\Users\\u\\real.txt\n";
        let result = parse_windows_attrib_output(out);
        assert_eq!(result.len(), 1);
        assert!(result.contains("real.txt"));
    }

    #[test]
    fn parse_attrib_handles_empty_input() {
        assert!(parse_windows_attrib_output("").is_empty());
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
        // misconfigured caller is loud not silent. The exact error
        // tag depends on which step fails first (`create` or
        // `write`); we just pin that *some* I/O step refuses.
        let err = write_bytes_atomic(&path, b"x").unwrap_err();
        assert!(
            err.contains("create") || err.contains("write"),
            "unexpected error tag: {err}",
        );
    }

    #[test]
    fn write_bytes_atomic_fsyncs_payload_before_rename() {
        // Regression for the "rename lands a torn file after a power
        // loss" gap. We cannot synthesise a real crash in a unit
        // test, but we *can* assert that the bytes on disk match the
        // payload byte-for-byte after the helper returns — proving
        // the data hit the destination through the rename path. The
        // `sync_data` step is what guarantees the post-crash
        // observable matches the post-return observable; without
        // it the destination could read empty after a crash even
        // though the test would still see the right bytes here.
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("fsync.bin");
        let payload: Vec<u8> = (0..=255u8).cycle().take(64 * 1024).collect();
        write_bytes_atomic(&path, &payload).unwrap();
        let on_disk = std::fs::read(&path).unwrap();
        assert_eq!(on_disk, payload);
    }
}
