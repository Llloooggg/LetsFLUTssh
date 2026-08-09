/// Unit tests extracted from storage/sftp.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

/// Tests cover the pure type-mapping helpers. The trait
/// methods themselves drive an `Sftp` engine over an SSH
/// channel — those round trip through the russh-sftp
/// integration fixture under `lfs_frb` / Dart's
fn dir_entry(
    name: &str,
    is_dir: bool,
    is_symlink: bool,
    size: u64,
    mtime: Option<i64>,
) -> DirEntry {
    DirEntry {
        name: name.into(),
        size,
        is_dir,
        is_symlink,
        modified_unix: mtime,
        permissions: 0,
    }
}

fn file_metadata(is_dir: bool, is_symlink: bool, size: u64, mtime: Option<i64>) -> FileMetadata {
    FileMetadata {
        size,
        is_dir,
        is_symlink,
        modified_unix: mtime,
        permissions: 0,
    }
}

#[test]
fn entry_from_dir_entry_maps_file_kind() {
    let raw = dir_entry("notes.txt", false, false, 1024, Some(1_700_000_000));
    let out = entry_from_dir_entry(&raw, "/home/u");
    assert_eq!(out.kind, EntryKind::File);
    assert_eq!(out.name, "notes.txt");
    assert_eq!(out.path, "/home/u/notes.txt");
}

#[test]
fn entry_from_dir_entry_maps_dir_kind() {
    let raw = dir_entry("projects", true, false, 0, None);
    let out = entry_from_dir_entry(&raw, "/home/u");
    assert_eq!(out.kind, EntryKind::Dir);
    assert_eq!(out.path, "/home/u/projects");
}

#[test]
fn entry_from_dir_entry_maps_symlink_kind() {
    // Symlink-to-dir: server resolves the target metadata and
    // sets both flags. The provider mapping must surface
    // `Symlink` so callers can decide whether to follow the
    // link or unlink it.
    let raw = dir_entry("link", true, true, 0, None);
    let out = entry_from_dir_entry(&raw, "/srv");
    assert_eq!(out.kind, EntryKind::Symlink);
    assert_eq!(out.path, "/srv/link");
}

#[test]
fn entry_from_dir_entry_carries_size_and_mtime() {
    // Wire-format guarantee: SFTP mtime is unix seconds; the
    // provider surface exchanges milliseconds. Pinning the
    // ×1000 conversion catches a regression that would silently
    // shift every timestamp by three orders of magnitude.
    let raw = dir_entry("big.bin", false, false, u64::MAX, Some(1_700_000_000));
    let out = entry_from_dir_entry(&raw, "/data");
    assert_eq!(out.size_bytes, u64::MAX);
    assert_eq!(out.modified_unix_ms, Some(1_700_000_000_000));
}

#[test]
fn entry_from_dir_entry_omits_mtime_when_server_did() {
    // Servers may omit mtime — the converter must pass the
    // gap through as `None` rather than substituting 0
    // (which would surface as the unix epoch in the UI).
    let raw = dir_entry("opaque", false, false, 12, None);
    let out = entry_from_dir_entry(&raw, "/x");
    assert_eq!(out.modified_unix_ms, None);
}

#[test]
fn entry_from_dir_entry_joins_root_path_without_double_slash() {
    // Caller is expected to trim a trailing slash before
    // calling; an empty-string parent (root listing) must
    // still produce a leading-slash path so consumers can
    // round-trip it back into `list` / `stat`.
    let raw = dir_entry("etc", true, false, 0, None);
    let out = entry_from_dir_entry(&raw, "");
    assert_eq!(out.path, "/etc");
}

#[test]
fn metadata_from_file_metadata_round_trip() {
    let raw = file_metadata(false, false, 2048, Some(42));
    let out = metadata_from_file_metadata(&raw);
    assert_eq!(out.kind, EntryKind::File);
    assert_eq!(out.size_bytes, 2048);
    assert_eq!(out.modified_unix_ms, Some(42_000));
}

#[test]
fn metadata_from_file_metadata_maps_symlink_when_flagged() {
    // `Sftp::stat` resolves symlinks, but a chain that ends
    // at another symlink still surfaces with `is_symlink =
    // true`. The kind mapping must honour the flag rather
    // than blindly preferring `is_dir`.
    let raw = file_metadata(true, true, 0, None);
    let out = metadata_from_file_metadata(&raw);
    assert_eq!(out.kind, EntryKind::Symlink);
}

#[test]
fn kind_from_flags_prefers_symlink_over_dir() {
    // Tightest pin on the precedence rule — a server flagging
    // both must produce `Symlink` so the remove walker treats
    // the entry as a link (unlinks the entry itself) rather
    // than a directory (would recurse into the target).
    assert_eq!(kind_from_flags(true, true), EntryKind::Symlink);
    assert_eq!(kind_from_flags(true, false), EntryKind::Dir);
    assert_eq!(kind_from_flags(false, true), EntryKind::Symlink);
    assert_eq!(kind_from_flags(false, false), EntryKind::File);
}

#[test]
fn unix_seconds_to_ms_saturates_on_overflow() {
    // The ×1000 conversion must not panic on a near-max
    // timestamp — the helper saturates rather than wrapping,
    // so a server reporting `i64::MAX` seconds yields
    // `i64::MAX` ms instead of overflowing.
    assert_eq!(unix_seconds_to_ms(i64::MAX), i64::MAX);
    assert_eq!(unix_seconds_to_ms(0), 0);
    assert_eq!(unix_seconds_to_ms(1), 1_000);
}
