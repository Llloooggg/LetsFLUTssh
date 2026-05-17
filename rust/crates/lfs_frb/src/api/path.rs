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

/// Tighten [`path`] to owner-only perms — `chmod 600` on Unix,
/// `icacls /inheritance:r /grant:r` on Windows, no-op on iOS /
/// Android (sandboxed app storage). Best-effort: returns the OS
/// error as `Err(String)` for the caller to log, never panics.
///
/// Async + `spawn_blocking` because the Windows path spawns a
/// subprocess (`icacls`) and a sync FRB shim would block the
/// Dart event loop until the child returns. Unix `chmod` is a
/// single syscall and could be sync, but a uniform async
/// signature is simpler than splitting per-OS API surfaces.
pub async fn path_harden_file_perms(path: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::path::harden_file_perms(std::path::Path::new(&path))
    })
    .await
    .map_err(|e| format!("path_harden_file_perms join: {e}"))?
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

/// Parse `cmd /c attrib *` output and return the lowercase
/// basenames of files flagged Hidden (H) or System (S). Used by
/// the Windows directory lister to filter the view to match
/// what Explorer would hide. Pure parser — caller spawns the
/// subprocess and feeds stdout here.
#[flutter_rust_bridge::frb(sync)]
pub fn path_parse_windows_attrib_output(output: String) -> Vec<String> {
    let mut out: Vec<String> = lfs_core::path::parse_windows_attrib_output(&output)
        .into_iter()
        .collect();
    out.sort();
    out
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

    #[test]
    fn parse_windows_attrib_returns_sorted_basenames() {
        // `attrib *` output: column 1 holds the flag set, the
        // tail holds the absolute path. Hidden + System rows must
        // come back as lowercase basenames, sorted, deduplicated.
        let output = "\
A H        C:\\Users\\Alice\\Hidden.bin                       \r\n\
   S       C:\\Users\\Alice\\System.bin                       \r\n\
A          C:\\Users\\Alice\\Plain.bin                        \r\n";
        let basenames = path_parse_windows_attrib_output(output.to_string());
        assert!(basenames.iter().any(|s| s == "hidden.bin"));
        assert!(basenames.iter().any(|s| s == "system.bin"));
        assert!(!basenames.iter().any(|s| s == "plain.bin"));
        // Sorted.
        let mut copy = basenames.clone();
        copy.sort();
        assert_eq!(basenames, copy);
    }
}
