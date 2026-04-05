import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../utils/logger.dart';
import 'file_system.dart';
import 'sftp_models.dart';

/// SFTP service wrapper over dartssh2.
class SFTPService {
  static const maxRecursionDepth = 100;

  /// Chunk size for streaming file uploads (64 KiB).
  static const _uploadChunkSize = 65536;

  final SftpClient _sftp;

  SFTPService(this._sftp);

  /// Create from SSH client.
  static Future<SFTPService> fromSSHClient(SSHClient client) async {
    final sftp = await client.sftp();
    return SFTPService(sftp);
  }

  /// List directory contents, sorted (dirs first, alphabetical).
  Future<List<FileEntry>> list(String path) async {
    final items = await _sftp.listdir(path);
    final entries = <FileEntry>[];
    for (final item in items) {
      final name = item.filename;
      if (name == '.' || name == '..') continue;
      final attr = item.attr;
      // Parse owner from longname (ls -l format: "perms links owner group ...")
      final owner = _parseOwner(item.longname);
      entries.add(
        FileEntry(
          name: name,
          path: p.posix.join(path, name),
          size: attr.size ?? 0,
          mode: attr.mode?.value ?? 0,
          modTime: attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
              : DateTime.now(),
          isDir: attr.isDirectory,
          owner: owner,
        ),
      );
    }
    sortFileEntries(entries);
    return entries;
  }

  /// Get working directory (home).
  Future<String> getwd() async {
    return await _sftp.absolute('.');
  }

  /// Get file info.
  Future<FileEntry> stat(String path) async {
    final attr = await _sftp.stat(path);
    return FileEntry(
      name: p.posix.basename(path),
      path: path,
      size: attr.size ?? 0,
      mode: attr.mode?.value ?? 0,
      modTime: attr.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
          : DateTime.now(),
      isDir: attr.isDirectory,
    );
  }

  /// Create directory.
  Future<void> mkdir(String path) async {
    AppLogger.instance.log('Creating remote directory: $path', name: 'SFTP');
    await _sftp.mkdir(path);
  }

  /// Remove file.
  Future<void> remove(String path) async {
    AppLogger.instance.log('Removing remote file: $path', name: 'SFTP');
    await _sftp.remove(path);
  }

  /// Remove directory recursively.
  Future<void> removeDir(String path) => _removeDirRecursive(path, 0);

  Future<void> _removeDirRecursive(String path, int depth) async {
    if (depth >= maxRecursionDepth) {
      throw StateError('Maximum recursion depth ($maxRecursionDepth) exceeded');
    }
    final items = await list(path);
    for (final item in items) {
      if (item.isDir) {
        await _removeDirRecursive(item.path, depth + 1);
      } else {
        await remove(item.path);
      }
    }
    await _sftp.rmdir(path);
  }

  /// Rename / move.
  Future<void> rename(String oldPath, String newPath) async {
    AppLogger.instance.log(
      'Renaming remote: $oldPath → $newPath',
      name: 'SFTP',
    );
    await _sftp.rename(oldPath, newPath);
  }

  /// Upload a local file to remote path with progress.
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    final file = File(localPath);
    final fileSize = await file.length();
    final remoteFile = await _sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );

    try {
      var done = 0;
      final raf = await file.open(mode: FileMode.read);
      try {
        while (true) {
          final chunk = await raf.read(_uploadChunkSize);
          if (chunk.isEmpty) break;
          await remoteFile.writeBytes(Uint8List.fromList(chunk), offset: done);
          done += chunk.length;
          onProgress?.call(
            TransferProgress(
              fileName: p.basename(localPath),
              totalBytes: fileSize,
              doneBytes: done,
              isUpload: true,
              isCompleted: done >= fileSize,
            ),
          );
        }
      } finally {
        await raf.close();
      }
    } finally {
      remoteFile.close();
    }
  }

  /// Download a remote file to local path with progress.
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {
    final attr = await _sftp.stat(remotePath);
    final fileSize = attr.size ?? 0;
    final remoteFile = await _sftp.open(remotePath);
    final localFile = File(localPath);
    await localFile.parent.create(recursive: true);

    try {
      final sink = localFile.openWrite();
      try {
        var done = 0;
        final content = remoteFile.read();
        await for (final chunk in content) {
          sink.add(chunk);
          done += chunk.length;
          onProgress?.call(
            TransferProgress(
              fileName: p.posix.basename(remotePath),
              totalBytes: fileSize,
              doneBytes: done,
              isUpload: false,
              isCompleted: done >= fileSize,
            ),
          );
        }
      } finally {
        await sink.close();
      }
    } finally {
      remoteFile.close();
    }
  }

  /// Upload a local directory recursively to remote path with progress.
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    final dir = Directory(localDir);
    final allFiles = await dir.list(recursive: true).toList();
    final totalFiles = allFiles.whereType<File>().length;
    final counter = _Counter();

    await _uploadDirRecursive(
      localDir,
      remoteDir,
      onProgress,
      totalFiles,
      counter,
      0,
    );
  }

  Future<void> _uploadDirRecursive(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
    int totalFiles,
    _Counter counter,
    int depth,
  ) async {
    if (depth >= maxRecursionDepth) {
      throw StateError('Maximum recursion depth ($maxRecursionDepth) exceeded');
    }
    // Create remote directory
    try {
      await _sftp.mkdir(remoteDir);
    } catch (e) {
      // Directory may already exist — log but don't fail
      AppLogger.instance.log('mkdir $remoteDir: $e', name: 'SFTP');
    }

    final dir = Directory(localDir);
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      final remotePath = p.posix.join(remoteDir, name);

      if (entity is Directory) {
        await _uploadDirRecursive(
          entity.path,
          remotePath,
          onProgress,
          totalFiles,
          counter,
          depth + 1,
        );
      } else if (entity is File) {
        await upload(entity.path, remotePath, null);
        counter.value++;
        onProgress?.call(
          TransferProgress(
            fileName: name,
            totalBytes: totalFiles,
            doneBytes: counter.value,
            isUpload: true,
            isCompleted: counter.value >= totalFiles,
          ),
        );
      }
    }
  }

  /// Download a remote directory recursively to local path with progress.
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    final totalFiles = await _countRemoteFiles(remoteDir, 0);
    final counter = _Counter();
    await _downloadDirRecursive(
      remoteDir,
      localDir,
      onProgress,
      totalFiles,
      counter,
      0,
    );
  }

  /// Count total files (non-directory) recursively in a remote directory.
  Future<int> _countRemoteFiles(String remoteDir, int depth) async {
    if (depth >= maxRecursionDepth) return 0;
    final items = await list(remoteDir);
    var count = 0;
    for (final item in items) {
      if (item.isDir) {
        count += await _countRemoteFiles(item.path, depth + 1);
      } else {
        count++;
      }
    }
    return count;
  }

  Future<void> _downloadDirRecursive(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
    int totalFiles,
    _Counter counter,
    int depth,
  ) async {
    if (depth >= maxRecursionDepth) {
      throw StateError('Maximum recursion depth ($maxRecursionDepth) exceeded');
    }
    await Directory(localDir).create(recursive: true);

    final items = await list(remoteDir);

    for (final item in items) {
      final localPath = p.join(localDir, item.name);

      if (item.isDir) {
        await _downloadDirRecursive(
          item.path,
          localPath,
          onProgress,
          totalFiles,
          counter,
          depth + 1,
        );
      } else {
        await download(item.path, localPath, null);
        counter.value++;
        onProgress?.call(
          TransferProgress(
            fileName: item.name,
            totalBytes: totalFiles,
            doneBytes: counter.value,
            isUpload: false,
            isCompleted: counter.value >= totalFiles,
          ),
        );
      }
    }
  }

  void close() {
    _sftp.close();
  }

  /// Parse owner from ls -l longname: "-rwxr-xr-x 1 root root 4096 ..."
  static String _parseOwner(String longname) {
    final parts = longname.split(RegExp(r'\s+'));
    // parts[0]=perms, [1]=links, [2]=owner, [3]=group
    if (parts.length >= 3) return parts[2];
    return '';
  }
}

/// Mutable counter for tracking progress across recursive calls.
class _Counter {
  int value = 0;
}

/// Remote file system implementation wrapping SFTPService.
class RemoteFS implements FileSystem {
  final SFTPService sftp;

  RemoteFS(this.sftp);

  @override
  Future<String> initialDir() => sftp.getwd();

  @override
  Future<List<FileEntry>> list(String path) => sftp.list(path);

  @override
  Future<void> mkdir(String path) => sftp.mkdir(path);

  @override
  Future<void> remove(String path) => sftp.remove(path);

  @override
  Future<void> removeDir(String path) => sftp.removeDir(path);

  @override
  Future<void> rename(String oldPath, String newPath) =>
      sftp.rename(oldPath, newPath);

  @override
  Future<int> dirSize(String path) async {
    int total = 0;
    final entries = await sftp.list(path);
    for (final entry in entries) {
      if (entry.isDir) {
        total += await dirSize(entry.path);
      } else {
        total += entry.size;
      }
    }
    return total;
  }
}
