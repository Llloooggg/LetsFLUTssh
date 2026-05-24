//! FRB adapter for `lfs_core::path`. Tilde-prefix expansion as a
//! synchronous one-shot — Dart hands in a `~` / `~/...` path,
//! Rust resolves against `$HOME` / `$USERPROFILE` and returns the
//! expanded string.
//!
//! **Mobile semantics intentionally differ.** Dart's
//! `homeDirectory` getter prefers `EXTERNAL_STORAGE` on Android
//! (shared storage `/storage/emulated/0`) over `$HOME` (the app's
//! private data dir). The Rust helper has no equivalent
//! Android-specific fallback — it follows the desktop / iOS
//! resolution order strictly. Today's only call site (Dart
//! `OpenSshConfigImporter.expandHome`) keeps using the Dart
//! getter so import-on-Android behaviour stays unchanged; the
//! Rust helper is here for future Rust-side callers (a Rust
//! port of the OpenSSH parser, the macOS resign orchestrator)
//! that have no Android consumer.

use crate::api::frb_err;

/// Expand a leading `~` against the running process's home
/// directory. See [`lfs_core::path::expand_tilde`] for the
/// resolution rules.
#[flutter_rust_bridge::frb(sync)]
pub fn path_expand_tilde(path: String) -> String {
    lfs_core::path::expand_tilde(&path)
}

/// Atomic byte write — writes [`bytes`] to `<path>.tmp`, hardens
/// the tmp file to owner-only perms, then renames to [`path`].
/// Caller is responsible for ensuring the parent directory exists.
///
/// Sync because the per-call work is one `write` syscall + one
/// `rename` syscall; the bytes themselves rarely top a few KiB
/// (KDF salt, marker payloads, sealed-blob envelopes, rate-limit
/// state). The Dart `writeBytesAtomic` shipped sync to the same
/// callers; routing through FRB sync preserves the contract.
#[flutter_rust_bridge::frb(sync)]
pub fn path_write_bytes_atomic(path: String, bytes: Vec<u8>) -> Result<(), String> {
    lfs_core::path::write_bytes_atomic(std::path::Path::new(&path), &bytes)
}

/// Tighten [`path`] to owner-only perms — `chmod 600` on Unix
/// (incl. Android / iOS, where it is redundant under the OS app
/// sandbox but harmless), an owner-only DACL via the Win32 security
/// APIs on Windows. Best-effort: returns the OS error as
/// `Err(String)` for the caller to log, never panics.
///
/// Async + `spawn_blocking` keeps the perm-tighten off the FRB
/// worker's event loop. The underlying ops are fast filesystem-
/// metadata syscalls (no subprocess on any platform), so a sync
/// shim would also work; the uniform async signature is kept to
/// avoid splitting per-OS API surfaces.
pub async fn path_harden_file_perms(path: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::path::harden_file_perms(std::path::Path::new(&path))
    })
    .await
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("path_harden_file_perms join: {e}"),
        )
    })?
}

/// Extract the basename portion of [`path`], normalising Windows
/// `\` separators to `/` first. Mirrors the Dart
/// `KeyFileHelper.basename` shape so file pickers + importers
/// share one rule.
#[flutter_rust_bridge::frb(sync)]
pub fn path_basename(path: String) -> String {
    lfs_core::path::basename(&path)
}

/// True when [`path`] contains a `..` segment after normalising
/// Windows separators. Used by the OpenSSH-config importer to
/// short-circuit traversal-style `IdentityFile` entries before
/// trying to read the file.
#[flutter_rust_bridge::frb(sync)]
pub fn path_is_suspicious(path: String) -> bool {
    lfs_core::path::is_suspicious_path(&path)
}

/// True when [`name`] is a single safe directory-entry name to join
/// onto a download destination. SFTP servers supply entry names as
/// untrusted bytes; the directory-walk download path rejects any
/// name that could escape the user-chosen folder (path separator,
/// `.`/`..` traversal, NUL, whitespace-only). Interior spaces are
/// allowed. See [`lfs_core::path::is_safe_transfer_entry_name`].
#[flutter_rust_bridge::frb(sync)]
pub fn path_is_safe_entry_name(name: String) -> bool {
    lfs_core::path::is_safe_transfer_entry_name(&name)
}

/// Separator family for [`path_parent`] — mirrors
/// `lfs_core::path::PathStyle`. `Auto` infers from the string (a
/// `\` or a `X:` drive prefix selects Windows rules); the file pane
/// passes `Auto` so one call handles the Windows local pane and the
/// forward-slash SFTP pane.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbPathStyle {
    Posix,
    Windows,
    Auto,
}

impl From<DbPathStyle> for lfs_core::path::PathStyle {
    fn from(d: DbPathStyle) -> Self {
        match d {
            DbPathStyle::Posix => lfs_core::path::PathStyle::Posix,
            DbPathStyle::Windows => lfs_core::path::PathStyle::Windows,
            DbPathStyle::Auto => lfs_core::path::PathStyle::Auto,
        }
    }
}

/// Parent directory of `path`, or `null` when the path has no
/// parent (POSIX / SFTP root, a Windows drive root, an empty
/// string, or a bare relative segment). The file pane's `navigateUp`
/// and the `RemoteFS.exists` dirname fallback both route here so the
/// Windows / POSIX parent grammar lives one place. See
/// [`lfs_core::path::parent`].
#[flutter_rust_bridge::frb(sync)]
pub fn path_parent(path: String, style: DbPathStyle) -> Option<String> {
    lfs_core::path::parent(&path, style.into())
}

/// Shorten a path to its last two non-empty segments, prefixed
/// with `.../`. Used by the transfer panel + history rows to
/// keep long paths readable in narrow row widths without losing
/// the trailing context.
#[flutter_rust_bridge::frb(sync)]
pub fn path_shorten_to_two_segments(path: String) -> String {
    lfs_core::path::shorten_to_two_segments(&path)
}

/// Generate the `n`-th `"stem (N)ext"` sibling-name candidate
/// next to [`path`]. Caller checks whether the candidate exists
/// and increments `n`; the helper only constructs the name
/// (matches GNOME Files / Finder splitting — only the final
/// extension is preserved). `posix=true` selects `/` as the
/// dirname separator.
#[flutter_rust_bridge::frb(sync)]
pub fn path_sibling_candidate(path: String, n: u32, posix: bool) -> String {
    lfs_core::path::sibling_candidate(&path, n, posix)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basename_strips_unix_dirs() {
        assert_eq!(
            path_basename("/home/alice/.ssh/id_ed25519".into()),
            "id_ed25519"
        );
    }

    #[test]
    fn basename_normalises_windows_separators() {
        assert_eq!(
            path_basename(r"C:\Users\Alice\config.json".into()),
            "config.json",
        );
    }

    #[test]
    fn is_suspicious_flags_traversal_segment() {
        assert!(path_is_suspicious("/etc/../passwd".into()));
        assert!(path_is_suspicious(r"C:\Users\..\System32\config".into()));
    }

    #[test]
    fn is_suspicious_passes_clean_paths() {
        assert!(!path_is_suspicious("/home/alice/.ssh/config".into()));
        assert!(!path_is_suspicious("notes.txt".into()));
    }

    #[test]
    fn is_safe_entry_name_accepts_plain_and_spaced_names() {
        assert!(path_is_safe_entry_name("readme.txt".into()));
        assert!(path_is_safe_entry_name("my file.txt".into()));
        assert!(path_is_safe_entry_name(".bashrc".into()));
        assert!(path_is_safe_entry_name("..foo".into()));
    }

    #[test]
    fn is_safe_entry_name_rejects_escaping_shapes() {
        assert!(!path_is_safe_entry_name("".into()));
        assert!(!path_is_safe_entry_name(".".into()));
        assert!(!path_is_safe_entry_name("..".into()));
        assert!(!path_is_safe_entry_name("a/b".into()));
        assert!(!path_is_safe_entry_name("a\\b".into()));
        assert!(!path_is_safe_entry_name("foo\0bar".into()));
        assert!(!path_is_safe_entry_name("   ".into()));
    }

    #[test]
    fn path_parent_resolves_posix_and_windows_and_roots() {
        assert_eq!(
            path_parent("/home/user/file.txt".into(), DbPathStyle::Posix).as_deref(),
            Some("/home/user")
        );
        assert!(path_parent("/".into(), DbPathStyle::Auto).is_none());
        assert_eq!(
            path_parent(r"C:\Users\foo".into(), DbPathStyle::Auto).as_deref(),
            Some(r"C:\Users")
        );
        // Parent of a first-level dir snaps back to the drive root.
        assert_eq!(
            path_parent(r"C:\Users".into(), DbPathStyle::Auto).as_deref(),
            Some(r"C:\")
        );
        assert!(path_parent(r"C:\".into(), DbPathStyle::Auto).is_none());
        assert!(path_parent("notes.txt".into(), DbPathStyle::Posix).is_none());
    }

    #[test]
    fn shorten_to_two_segments_collapses_long_paths() {
        let s = path_shorten_to_two_segments("/var/log/letsflutssh/recordings/run.lfsr".into());
        assert!(s.starts_with(".../"), "got: {s}");
        assert!(s.contains("recordings/"));
        assert!(s.ends_with("run.lfsr"));
    }

    #[test]
    fn sibling_candidate_appends_index() {
        // GNOME Files / Finder shape: stem + " (N)" + extension.
        let c = path_sibling_candidate("/tmp/photo.jpg".into(), 1, true);
        assert!(c.contains("photo"));
        assert!(c.ends_with(".jpg"));
        assert!(c.contains("(1)") || c.contains(" 1"), "got: {c}");
    }
}
