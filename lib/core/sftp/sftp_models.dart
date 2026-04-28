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

  /// Render Unix mode bits as `drwxr-xr-x`. Routes through
  /// `lfs_core::sftp_models::mode_string` so the chmod-letter
  /// grammar lives one place; falls back to the inline ladder
  /// when the FRB native lib is not loaded.
  String get modeString {
    try {
      return rust_sftp_models.sftpModeString(mode: mode, isDir: isDir);
    } catch (_) {
      if (mode == 0) return '---';
      final buf = StringBuffer();
      buf.write(isDir ? 'd' : '-');
      for (var i = 8; i >= 0; i--) {
        final bit = (mode >> i) & 1;
        final chars = ['x', 'w', 'r'];
        buf.write(bit == 1 ? chars[i % 3] : '-');
      }
      return buf.toString();
    }
  }
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

/// Sort file entries: directories first, then alphabetical by name.
/// Routes through `lfs_core::sftp_models::sort_file_entries` so the
/// dirs-first + case-insensitive grammar lives one place; falls
/// back to a stable inline sort for flutter_test contexts that
/// don't load the FRB native lib.
void sortFileEntries(List<FileEntry> entries) {
  try {
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
  } catch (_) {
    entries.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
}
