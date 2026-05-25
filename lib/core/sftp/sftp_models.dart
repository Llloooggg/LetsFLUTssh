import '../../src/rust/api/sftp_models.dart' as rust_sftp_models;

/// Unified file entry model for local and remote file systems.
class FileEntry {
  final String name;
  final String path;
  final int size;
  final int mode; // Unix permissions (e.g. 0755)
  final DateTime modTime;
  final bool isDir;

  /// True when the entry is a symbolic link (resolved via `lstat`,
  /// not by following the target). Delete routing keys on this so a
  /// link is unlinked rather than recursed into — recursing through
  /// a symlinked directory would wipe the link's *target* contents.
  /// Defaults false for backends without a link concept (WebDAV/S3).
  final bool isSymlink;

  final String owner;

  const FileEntry({
    required this.name,
    required this.path,
    required this.size,
    this.mode = 0,
    required this.modTime,
    required this.isDir,
    this.isSymlink = false,
    this.owner = '',
  });

  /// Render Unix mode bits as `drwxr-xr-x` via
  /// `lfs_core::sftp_models::mode_string` — the chmod-letter
  /// grammar lives in Rust.
  String get modeString =>
      rust_sftp_models.sftpModeString(mode: mode, isDir: isDir);
}

/// One leaf file from a recursive directory walk. [relPath] is the
/// `/`-joined path relative to the walk root; the enumeration +
/// per-segment safety validation + symlink-skip all happen Rust-side
/// (`lfs_core::fs::local::flat_walk_files` / `Sftp::flat_walk_files`).
/// The transfer enqueue loop re-joins [relPath] onto the source +
/// destination roots.
class FlatFileLeaf {
  final String relPath;
  final int size;

  const FlatFileLeaf({required this.relPath, required this.size});
}

/// Transfer progress callback data.
class TransferProgress {
  final String fileName;
  final int totalBytes;
  final int doneBytes;
  final bool isUpload;
  final bool isCompleted;

  const TransferProgress({
    required this.fileName,
    required this.totalBytes,
    required this.doneBytes,
    required this.isUpload,
    this.isCompleted = false,
  });

  double get percent =>
      totalBytes > 0 ? (doneBytes / totalBytes * 100).clamp(0, 100) : 0;
}

/// Sort file entries: directories first, then alphabetical by name
/// — the default post-`list()` order. Delegates to
/// [sortFileEntriesBy] with the Name column ascending so the grammar
/// stays single-sourced in `lfs_core::sftp_models::sort_file_entries_by`.
void sortFileEntries(List<FileEntry> entries) {
  sortFileEntriesBy(entries, rust_sftp_models.DbSortField.name, true);
}

/// Sort [entries] in place by [field] + direction via
/// `lfs_core::sftp_models::sort_file_entries_by`. Directories always
/// lead regardless of column / direction; the comparison rules
/// (case-folding, numeric / temporal ordering) are Rust-owned — Dart
/// only projects each row's sortable axes and re-keys against the
/// returned permutation.
void sortFileEntriesBy(
  List<FileEntry> entries,
  rust_sftp_models.DbSortField field,
  bool ascending,
) {
  final keys = entries
      .map(
        (e) => rust_sftp_models.DbFileSortKey(
          isDir: e.isDir,
          nameLower: e.name.toLowerCase(),
          size: BigInt.from(e.size),
          mode: e.mode,
          modTimeUnixMs: e.modTime.millisecondsSinceEpoch,
          ownerLower: e.owner.toLowerCase(),
        ),
      )
      .toList(growable: false);
  final indices = rust_sftp_models.sftpSortFileEntriesBy(
    keys: keys,
    field: field,
    ascending: ascending,
  );
  final sorted = [for (final i in indices) entries[i]];
  entries
    ..clear()
    ..addAll(sorted);
}
