import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../../utils/logger.dart';
import 'errors.dart';
import 'file_system.dart';
import 'sftp_models.dart';

/// SFTP service wrapper over dartssh2.
class SFTPService {
  static const maxRecursionDepth = 100;

  /// Chunk size for streaming file uploads (64 KiB).
  static const _uploadChunkSize = 65536;

  /// Maximum number of files transferred in parallel within a single
  /// directory level during [uploadDir] / [downloadDir]. Kept modest
  /// on purpose: dartssh2 pipelines channel operations over a single
  /// TCP connection, and too many concurrent SFTP file handles can
  /// blow past the server-side MaxSessions limit (OpenSSH defaults to
  /// 10). Subdirectories are still walked sequentially, so the global
  /// in-flight count is bounded by this constant.
  static const _maxConcurrentFileTransfers = 4;

  final SftpClient _sftp;

  SFTPService(this._sftp);

  /// Create from SSH client.
  static Future<SFTPService> fromSSHClient(SSHClient client) async {
    final sftp = await client.sftp();
    return SFTPService(sftp);
  }

  /// List directory contents, sorted (dirs first, alphabetical).
  Future<List<FileEntry>> list(String path) async {
    try {
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
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'list', path);
    }
  }

  /// Get working directory (home).
  Future<String> getwd() async {
    try {
      return await _sftp.absolute('.');
    } catch (e) {
      throw SFTPError.wrap(e, 'getwd');
    }
  }

  /// Check whether a remote path exists.
  Future<bool> exists(String path) async {
    try {
      await _sftp.stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get file info.
  Future<FileEntry> stat(String path) async {
    try {
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
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'stat', path);
    }
  }

  /// Create directory.
  Future<void> mkdir(String path) async {
    AppLogger.instance.log('Creating remote directory: $path', name: 'SFTP');
    try {
      await _sftp.mkdir(path);
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'mkdir', path);
    }
  }

  /// Remove file.
  Future<void> remove(String path) async {
    AppLogger.instance.log('Removing remote file: $path', name: 'SFTP');
    try {
      await _sftp.remove(path);
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'remove', path);
    }
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
    try {
      await _sftp.rename(oldPath, newPath);
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'rename', oldPath);
    }
  }

  /// Upload a local file to remote path with progress.
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    try {
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
            await remoteFile.writeBytes(
              Uint8List.fromList(chunk),
              offset: done,
            );
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
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'upload', remotePath);
    }
  }

  /// Download a remote file to local path with progress.
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {
    try {
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
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'download', remotePath);
    }
  }

  /// Upload a local directory recursively to remote path with progress.
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    final dir = Directory(localDir);
    // Count files via streaming to avoid loading entire directory tree into memory.
    var totalFiles = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) totalFiles++;
    }
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

    // Split the directory contents into files and subdirs. Files at this
    // level run in parallel (bounded by [_maxConcurrentFileTransfers]);
    // subdirectories are walked sequentially so the global in-flight count
    // never exceeds the limit even on deep trees.
    final dir = Directory(localDir);
    final files = <File>[];
    final subdirs = <Directory>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        subdirs.add(entity);
      } else if (entity is File) {
        files.add(entity);
      }
    }

    await _parallelForEach(files, _maxConcurrentFileTransfers, (file) async {
      final name = p.basename(file.path);
      final remotePath = p.posix.join(remoteDir, name);
      await upload(file.path, remotePath, null);
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
    });

    for (final sub in subdirs) {
      final name = p.basename(sub.path);
      await _uploadDirRecursive(
        sub.path,
        p.posix.join(remoteDir, name),
        onProgress,
        totalFiles,
        counter,
        depth + 1,
      );
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

    // Mirror [_uploadDirRecursive]: split into files + subdirs, transfer
    // the file bucket in parallel at this level, recurse into subdirs
    // sequentially so global concurrency stays bounded.
    final items = await list(remoteDir);
    final files = items.where((i) => !i.isDir).toList();
    final subdirs = items.where((i) => i.isDir).toList();

    await _parallelForEach(files, _maxConcurrentFileTransfers, (item) async {
      final localPath = p.join(localDir, item.name);
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
    });

    for (final sub in subdirs) {
      await _downloadDirRecursive(
        sub.path,
        p.join(localDir, sub.name),
        onProgress,
        totalFiles,
        counter,
        depth + 1,
      );
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

/// Run [action] for every element in [items] with at most [concurrency]
/// in-flight calls. Workers pull from a shared queue so slow entries do
/// not stall the faster ones. Errors propagate from [Future.wait]; a
/// failed worker aborts the remaining queue by design.
Future<void> _parallelForEach<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T) action,
) async {
  if (items.isEmpty) return;
  final queue = List<T>.of(items);
  final limit = concurrency.clamp(1, queue.length);
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      await action(next);
    }
  }

  await Future.wait(List.generate(limit, (_) => worker()));
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

  /// Maximum directory recursion depth to prevent runaway traversals.
  static const _maxRecursionDepth = 64;

  @override
  Future<int> dirSize(String path, [int depth = 0]) async {
    if (depth >= _maxRecursionDepth) return 0;
    int total = 0;
    final entries = await sftp.list(path);
    for (final entry in entries) {
      if (entry.isDir) {
        total += await dirSize(entry.path, depth + 1);
      } else {
        total += entry.size;
      }
    }
    return total;
  }
}
