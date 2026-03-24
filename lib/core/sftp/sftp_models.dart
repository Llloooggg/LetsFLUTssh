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

  String get modeString {
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
