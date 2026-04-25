// Engine-agnostic SFTP service surface — the subset of operations
// `RemoteFS` (the FileSystem implementation behind file_browser)
// needs. Backed by `RustSftpFs` (russh-sftp via the FRB bindings).
//
// Recursive directory walking (`uploadDir`, `downloadDir`, `removeDir`)
// is supplied by this abstract class on top of the leaf primitives
// (`upload`, `download`, `mkdir`, `remove`, `removeEmptyDir`, `list`).

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../src/rust/api/sftp.dart' as rust_sftp;
import '../../utils/logger.dart';
import '../ssh/transport/ssh_transport.dart';
import 'errors.dart';
import 'file_system.dart';
import 'sftp_models.dart';

/// Maximum recursion depth for directory walking. Guards against
/// runaway traversal on cyclic symlinks or pathologically deep trees.
const int sftpMaxRecursionDepth = 100;

/// Files transferred in parallel within a single directory level by
/// the default `uploadDir` / `downloadDir` walker. Modest on purpose:
/// both transports pipeline SFTP ops over a single channel, and too
/// many concurrent file handles can blow past the server-side
/// MaxSessions / MaxStartups limits (OpenSSH defaults to 10).
/// Subdirectories are walked sequentially so the global in-flight
/// count stays bounded by this constant.
const int sftpMaxConcurrentFileTransfers = 4;

/// File-browser-shaped subset of an SFTP client.
abstract class RemoteSftpFs {
  Future<String> getwd();
  Future<List<FileEntry>> list(String path);

  /// Cheap existence check. Implementations stat the path and
  /// return true on success, false on any error.
  Future<bool> exists(String path);

  Future<void> mkdir(String path);
  Future<void> remove(String path);

  /// Remove an empty directory (no recursion). Engines must implement
  /// this — used by the default [removeDir] walker after it has
  /// drained the directory contents.
  Future<void> removeEmptyDir(String path);

  Future<void> rename(String oldPath, String newPath);

  /// Upload a local file to a remote path. `onProgress` fires per
  /// streamed chunk; the final callback carries `isCompleted: true`.
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  );

  /// Download a remote file to a local path. `onProgress` fires per
  /// streamed chunk; the final callback carries `isCompleted: true`.
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  );

  /// Tear down the underlying client. Idempotent.
  void close();

  /// Recursively delete a remote directory. Walks the tree depth-first,
  /// removing files and empty directories, then drops [path] itself.
  Future<void> removeDir(String path) => _removeDirRecursive(path, 0);

  Future<void> _removeDirRecursive(String path, int depth) async {
    if (depth >= sftpMaxRecursionDepth) {
      throw StateError(
        'Maximum recursion depth ($sftpMaxRecursionDepth) exceeded',
      );
    }
    final items = await list(path);
    for (final item in items) {
      if (item.isDir) {
        await _removeDirRecursive(item.path, depth + 1);
      } else {
        await remove(item.path);
      }
    }
    await removeEmptyDir(path);
  }

  /// Upload a local directory recursively to a remote path. Files at
  /// each level transfer in parallel ([sftpMaxConcurrentFileTransfers]
  /// in flight); subdirectories are walked sequentially so global
  /// concurrency stays bounded.
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    var totalFiles = 0;
    await for (final entity in Directory(localDir).list(recursive: true)) {
      if (entity is File) totalFiles++;
    }
    final counter = _TransferCounter();
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
    _TransferCounter counter,
    int depth,
  ) async {
    if (depth >= sftpMaxRecursionDepth) {
      throw StateError(
        'Maximum recursion depth ($sftpMaxRecursionDepth) exceeded',
      );
    }
    // mkdir is best-effort — directory may already exist on the remote.
    // Engines surface SFTPError; downgrade to a log line and continue.
    try {
      await mkdir(remoteDir);
    } catch (e) {
      AppLogger.instance.log('mkdir $remoteDir: $e', name: 'SFTP');
    }

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

    await _parallelForEach(files, sftpMaxConcurrentFileTransfers, (file) async {
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

  /// Download a remote directory recursively to a local path. Same
  /// concurrency model as [uploadDir].
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    final totalFiles = await _countRemoteFiles(remoteDir, 0);
    final counter = _TransferCounter();
    await _downloadDirRecursive(
      remoteDir,
      localDir,
      onProgress,
      totalFiles,
      counter,
      0,
    );
  }

  Future<int> _countRemoteFiles(String remoteDir, int depth) async {
    if (depth >= sftpMaxRecursionDepth) return 0;
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
    _TransferCounter counter,
    int depth,
  ) async {
    if (depth >= sftpMaxRecursionDepth) {
      throw StateError(
        'Maximum recursion depth ($sftpMaxRecursionDepth) exceeded',
      );
    }
    await Directory(localDir).create(recursive: true);

    final items = await list(remoteDir);
    final files = items.where((i) => !i.isDir).toList();
    final subdirs = items.where((i) => i.isDir).toList();

    await _parallelForEach(files, sftpMaxConcurrentFileTransfers, (item) async {
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
}

/// Mutable counter for tracking total files done across recursive calls.
class _TransferCounter {
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

/// `RemoteSftpFs` implementation backed by the Rust core SFTP path
/// (`lib/src/rust/api/sftp.dart`). Used by `SFTPInitializer` when
/// the connection is on the Rust transport.
///
/// Open via `RustSftpFs.create(transport)` — the factory waits on
/// `transport.openSftp()` (which allocates a fresh channel +
/// `request_subsystem("sftp")` server-side), then wraps the
/// returned `SshSftp` opaque handle.
class RustSftpFs extends RemoteSftpFs {
  RustSftpFs._(this._sftp);

  final rust_sftp.SshSftp _sftp;

  static Future<RustSftpFs> create(SshTransport transport) async {
    final raw = await transport.openSftp();
    if (raw is! rust_sftp.SshSftp) {
      // Defensive — `RustTransport.openSftp` is the only impl today,
      // but the abstraction allows for test mocks to return any
      // shape; reject early so the file browser fails with a clear
      // type error instead of a downstream NoSuchMethod.
      throw StateError(
        'RustSftpFs.create requires a transport that returns an '
        'rust_sftp.SshSftp; got ${raw.runtimeType}',
      );
    }
    return RustSftpFs._(raw);
  }

  @override
  Future<String> getwd() async {
    try {
      // The Rust core's `canonicalize` resolves `.` against the
      // server's working directory — same shape OpenSSH's `getwd`
      // returns for an SFTP session.
      return await _sftp.canonicalize(path: '.');
    } catch (e) {
      throw SFTPError.wrap(e, 'getwd');
    }
  }

  @override
  Future<List<FileEntry>> list(String path) async {
    try {
      final entries = await _sftp.list(path: path);
      final out = <FileEntry>[];
      for (final e in entries) {
        if (e.name == '.' || e.name == '..') continue;
        out.add(
          FileEntry(
            name: e.name,
            // POSIX join — caller is expected to pass POSIX paths
            // (the SFTP server-side filesystem).
            path: path == '/' ? '/${e.name}' : '$path/${e.name}',
            size: e.size.toInt(),
            mode: e.permissions,
            modTime: e.modifiedUnix != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    e.modifiedUnix!.toInt() * 1000,
                  )
                : DateTime.now(),
            isDir: e.isDir,
            owner: '',
          ),
        );
      }
      sortFileEntries(out);
      return out;
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'list', path);
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await _sftp.stat(path: path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> mkdir(String path) async {
    try {
      await _sftp.mkdir(path: path);
    } catch (e) {
      throw SFTPError.wrap(e, 'mkdir', path);
    }
  }

  @override
  Future<void> remove(String path) async {
    try {
      await _sftp.removeFile(path: path);
    } catch (e) {
      throw SFTPError.wrap(e, 'remove', path);
    }
  }

  @override
  Future<void> removeEmptyDir(String path) async {
    try {
      await _sftp.removeDir(path: path);
    } catch (e) {
      throw SFTPError.wrap(e, 'removeDir', path);
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    try {
      await _sftp.rename(oldPath: oldPath, newPath: newPath);
    } catch (e) {
      throw SFTPError.wrap(e, 'rename', oldPath);
    }
  }

  /// Chunk size for streaming file transfers (64 KiB) — same as
  /// russh-sftp's default packet size.
  static const _chunkSize = 65536;

  @override
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    try {
      final localFile = File(localPath);
      final fileSize = await localFile.length();
      final remote = await rust_sftp.sshSftpCreate(
        sftp: _sftp,
        path: remotePath,
      );
      final raf = await localFile.open(mode: FileMode.read);
      try {
        var done = 0;
        while (true) {
          final chunk = await raf.read(_chunkSize);
          if (chunk.isEmpty) break;
          await remote.writeAll(data: Uint8List.fromList(chunk));
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
        // Rust SFTP file drops on the FRB side when the wrapper goes
        // out of scope.
      }
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'upload', remotePath);
    }
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {
    try {
      final remote = await rust_sftp.sshSftpOpen(sftp: _sftp, path: remotePath);
      final meta = await remote.metadata();
      final fileSize = meta.size is int
          ? meta.size as int
          : (meta.size as num).toInt();
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      final sink = localFile.openWrite();
      try {
        var done = 0;
        while (true) {
          final chunk = await remote.readChunk(maxBytes: _chunkSize);
          if (chunk.isEmpty) break;
          sink.add(chunk);
          done += chunk.length;
          onProgress?.call(
            TransferProgress(
              fileName: p.basename(remotePath),
              totalBytes: fileSize,
              doneBytes: done,
              isUpload: false,
              isCompleted: done >= fileSize,
            ),
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } on SFTPError {
      rethrow;
    } catch (e) {
      throw SFTPError.wrap(e, 'download', remotePath);
    }
  }

  @override
  void close() {
    // Rust SFTP handle drops on the FRB side when the wrapper goes
    // out of scope; explicit close is a no-op here.
    AppLogger.instance.log(
      'RustSftpFs.close (no-op — handle drops on dispose)',
      name: 'Sftp',
    );
  }
}

/// Remote file system implementation wrapping a [RemoteSftpFs].
class RemoteFS implements FileSystem {
  final RemoteSftpFs sftp;

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
