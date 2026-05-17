import '../../src/rust/api/sftp_models.dart' as rust_sftp_models;

/// Unified file entry model for local and remote file systems.
class FileEntry {
  final String name;
  final String path;
  final int size;
  final int mode; // Unix permissions (e.g. 0755)
  final DateTime modTime;
  final bool isDir;
  final String owner;

  const FileEntry({
    required this.name,
    required this.path,
    required this.size,
    this.mode = 0,
    required this.modTime,
    required this.isDir,
    this.owner = '',
  });

  /// Render Unix mode bits as `drwxr-xr-x` via
  /// `lfs_core::sftp_models::mode_string` — the chmod-letter
  /// grammar lives in Rust.
  String get modeString =>
      rust_sftp_models.sftpModeString(mode: mode, isDir: isDir);
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
/// via `lfs_core::sftp_models::sort_file_entries` — the dirs-first
/// + case-insensitive grammar lives in Rust.
void sortFileEntries(List<FileEntry> entries) {
  final keys = entries
      .map(
        (e) => rust_sftp_models.DbFileSortKey(
          isDir: e.isDir,
          nameLower: e.name.toLowerCase(),
        ),
      )
      .toList(growable: false);
  final indices = rust_sftp_models.sftpSortFileEntries(keys: keys);
  final sorted = [for (final i in indices) entries[i]];
  entries
    ..clear()
    ..addAll(sorted);
}
