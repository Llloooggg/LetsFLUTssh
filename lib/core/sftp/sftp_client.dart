import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'file_system.dart';
import 'sftp_models.dart';

/// SFTP service wrapper over dartssh2.
class SFTPService {
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
      entries.add(FileEntry(
        name: name,
        path: p.posix.join(path, name),
        size: attr.size ?? 0,
        mode: attr.mode?.value ?? 0,
        modTime: attr.modifyTime != null
            ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
            : DateTime.now(),
        isDir: attr.isDirectory,
      ));
    }
    _sort(entries);
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
    await _sftp.mkdir(path);
  }

  /// Remove file.
  Future<void> remove(String path) async {
    await _sftp.remove(path);
  }

  /// Remove directory recursively.
  Future<void> removeDir(String path) async {
    final items = await list(path);
    for (final item in items) {
      if (item.isDir) {
        await removeDir(item.path);
      } else {
        await remove(item.path);
      }
    }
    await _sftp.rmdir(path);
  }

  /// Rename / move.
  Future<void> rename(String oldPath, String newPath) async {
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
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );

    try {
      var done = 0;
      final stream = file.openRead();
      await for (final chunk in stream) {
        await remoteFile.writeBytes(Uint8List.fromList(chunk), offset: done);
        done += chunk.length;
        onProgress?.call(TransferProgress(
          fileName: p.basename(localPath),
          totalBytes: fileSize,
          doneBytes: done,
          isUpload: true,
          isCompleted: done >= fileSize,
        ));
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
      var done = 0;
      final content = remoteFile.read();
      await for (final chunk in content) {
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(TransferProgress(
          fileName: p.posix.basename(remotePath),
          totalBytes: fileSize,
          doneBytes: done,
          isUpload: false,
          isCompleted: done >= fileSize,
        ));
      }
      await sink.close();
    } finally {
      remoteFile.close();
    }
  }

  void close() {
    _sftp.close();
  }

  void _sort(List<FileEntry> entries) {
    entries.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
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
}
