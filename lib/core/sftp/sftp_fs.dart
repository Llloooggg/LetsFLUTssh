// Engine-agnostic SFTP service surface — the subset of operations
// `RemoteFS` (the FileSystem implementation behind file_browser)
// needs. Backed by `RustSftpFs` (russh-sftp via the FRB bindings),
// which delegates leaves and recursive walks to `lfs_core::sftp`.

import 'package:path/path.dart' as p;

import '../../src/rust/api/sftp.dart' as rust_sftp;
import '../../utils/logger.dart';
import '../ssh/transport/ssh_transport.dart';
import 'errors.dart';
import 'file_system.dart';
import 'sftp_models.dart';

/// File-browser-shaped subset of an SFTP client. Recursive walks
/// (`uploadDir`, `downloadDir`, `removeDir`) are part of the contract;
/// the production `RustSftpFs` impl forwards them to the matching
/// `lfs_core::sftp` Rust functions in a single FRB call so the per-
/// entry recursion never crosses the bridge.
abstract class RemoteSftpFs {
  Future<String> getwd();
  Future<List<FileEntry>> list(String path);
  Future<int> dirSizeRecursive(String path, int maxDepth);

  /// Cheap existence check. Implementations stat the path and
  /// return true on success, false on any error.
  Future<bool> exists(String path);

  Future<void> mkdir(String path);
  Future<void> remove(String path);

  /// Remove an empty directory (no recursion). Pairs with [removeDir]
  /// — the latter drains the contents first, then drops the empty
  /// shell.
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

  /// Recursively delete a remote directory.
  Future<void> removeDir(String path);

  /// Upload a local directory recursively to a remote path.
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  );

  /// Download a remote directory recursively to a local path.
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  );
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
  Future<int> dirSizeRecursive(String path, int maxDepth) async {
    final total = await _sftp.dirSizeRecursive(path: path, maxDepth: maxDepth);
    return total.toInt();
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

  /// Override the abstract default — the recursive walk lives in
  /// `lfs_core::sftp::Sftp::remove_dir_recursive`, so the Dart
  /// caller pays one FRB roundtrip instead of N (one per file +
  /// one per directory). Depth cap: 100.
  @override
  Future<void> removeDir(String path) async {
    try {
      await _sftp.removeDirRecursive(path: path);
    } catch (e) {
      throw SFTPError.wrap(e, 'removeDir', path);
    }
  }

  /// Recursive directory upload — the walker, the per-file
  /// streaming and the depth cap all live Rust-side now. The
  /// Dart caller subscribes to the FRB Stream for per-file
  /// completion events; cancelling the subscription propagates
  /// cooperative cancellation to the Rust walker which bails at
  /// the next yield point.
  @override
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    try {
      final stream = _sftp.uploadDir(localDir: localDir, remoteDir: remoteDir);
      await for (final evt in stream) {
        onProgress?.call(
          TransferProgress(
            fileName: evt.fileName,
            totalBytes: evt.totalFiles.toInt(),
            doneBytes: evt.doneFiles.toInt(),
            isUpload: true,
            isCompleted: evt.doneFiles >= evt.totalFiles,
          ),
        );
      }
    } catch (e) {
      throw SFTPError.wrap(e, 'uploadDir', remoteDir);
    }
  }

  /// Recursive directory download — same shape as [uploadDir].
  @override
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    try {
      final stream = _sftp.downloadDir(
        remoteDir: remoteDir,
        localDir: localDir,
      );
      await for (final evt in stream) {
        onProgress?.call(
          TransferProgress(
            fileName: evt.fileName,
            totalBytes: evt.totalFiles.toInt(),
            doneBytes: evt.doneFiles.toInt(),
            isUpload: false,
            isCompleted: evt.doneFiles >= evt.totalFiles,
          ),
        );
      }
    } catch (e) {
      throw SFTPError.wrap(e, 'downloadDir', remoteDir);
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

  @override
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    // Single FRB call: the open / read-loop / write-loop / fsync
    // chain runs Rust-side; the Dart side only listens to a
    // per-byte progress stream. One FRB call regardless of file
    // size (a per-chunk `raf.read → writeAll` shape would issue
    // ~1600 hops on a 100 MiB file at the default chunk size).
    try {
      final fileName = p.basename(localPath);
      await for (final evt in _sftp.streamUploadFile(
        localPath: localPath,
        remotePath: remotePath,
      )) {
        final done = evt.doneBytes.toInt();
        final total = evt.totalBytes.toInt();
        onProgress?.call(
          TransferProgress(
            fileName: fileName,
            totalBytes: total,
            doneBytes: done,
            isUpload: true,
            isCompleted: total > 0 && done >= total,
          ),
        );
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
      final fileName = p.basename(remotePath);
      await for (final evt in _sftp.streamDownloadFile(
        remotePath: remotePath,
        localPath: localPath,
      )) {
        final done = evt.doneBytes.toInt();
        final total = evt.totalBytes.toInt();
        onProgress?.call(
          TransferProgress(
            fileName: fileName,
            totalBytes: total,
            doneBytes: done,
            isUpload: false,
            isCompleted: total > 0 && done >= total,
          ),
        );
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
  /// Matches the Rust-side `dir_size_recursive` cap; the FRB call
  /// runs the entire walk over one SFTP channel pair instead of
  /// paying N FRB hops per subdirectory.
  static const _maxRecursionDepth = 64;

  @override
  Future<int> dirSize(String path, [int depth = 0]) =>
      sftp.dirSizeRecursive(path, _maxRecursionDepth);
}
