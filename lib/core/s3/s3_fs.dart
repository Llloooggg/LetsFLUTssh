import '../../src/rust/api/s3.dart' as rust_s3;
import '../../utils/logger.dart';
import '../sftp/file_system.dart';
import '../sftp/sftp_models.dart';

/// [FileSystem] implementation backed by a live S3 transport
/// (`lfs_core::storage::s3::S3Provider` via FRB).
///
/// Mirrors the surface of [RemoteFS] (SFTP) and [WebDavFileSystem]
/// so the file-browser controllers never branch by transport — they
/// hand whatever implements [FileSystem] to the pane controller.
/// Recursive prefix sizing routes through the Provider's
/// continuation-token walker on the Rust side, so a deep tree pays
/// one FRB call instead of one per page.
class S3FileSystem implements FileSystem {
  S3FileSystem(this._connection, this._initialDir);

  final rust_s3.S3Connection _connection;
  final String _initialDir;

  /// Initial path the browser opens at. S3 has no "current
  /// working directory" — the configured default bucket + prefix
  /// is the implicit root and the caller hands it through at
  /// construction time. The empty string maps to the default
  /// bucket root.
  @override
  Future<String> initialDir() async => _initialDir;

  @override
  Future<List<FileEntry>> list(String path) async {
    AppLogger.instance.log('S3 list <path>', name: 'S3');
    final entries = await _connection.list(path: path);
    final out = <FileEntry>[];
    for (final e in entries) {
      out.add(
        FileEntry(
          name: e.name,
          path: e.path,
          size: e.size.toInt(),
          isDir: e.isDir,
          modTime: e.modifiedUnixMs != null
              ? DateTime.fromMillisecondsSinceEpoch(e.modifiedUnixMs!.toInt())
              : DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    sortFileEntries(out);
    return out;
  }

  @override
  Future<void> mkdir(String path) async {
    AppLogger.instance.log('S3 mkdir <path>', name: 'S3');
    await _connection.mkdir(path: path);
  }

  @override
  Future<void> remove(String path) async {
    AppLogger.instance.log('S3 remove <path>', name: 'S3');
    await _connection.remove(path: path);
  }

  /// S3 has no native directories — directory removal is the same
  /// `DeleteObject` call against the `<prefix>/` marker key. Bulk
  /// recursive delete (walk + delete every child) is a follow-up;
  /// for v1 the file browser issues one DELETE per entry on the
  /// caller side.
  @override
  Future<void> removeDir(String path) async {
    AppLogger.instance.log('S3 removeDir <path>', name: 'S3');
    await _connection.remove(path: path);
  }

  /// Server-side `CopyObject` + `DeleteObject` — not atomic. A
  /// reader between the two calls observes both source and target;
  /// the Rust Provider documents the same shape.
  @override
  Future<void> rename(String oldPath, String newPath) async {
    AppLogger.instance.log('S3 rename <path> → <path>', name: 'S3');
    await _connection.rename(from: oldPath, to: newPath);
  }

  @override
  Future<int> dirSize(String path) async {
    final size = await _connection.dirSize(path: path);
    return size.toInt();
  }

  /// No single-call object-store walker — recurse via the shared
  /// `list`-based helper. S3 has no symlinks to skip, so the
  /// `ListObjectsV2`-per-prefix recursion enumerates every key.
  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String root, {int maxDepth = 100}) =>
      flatWalkViaList(this, root, maxDepth: maxDepth);

  /// Cheap presence probe — one `HeadObject` via
  /// `S3Connection.stat`. Beats the trait's parent-listing default
  /// because `ListObjectsV2` over an unknown prefix is heavier
  /// than a single HEAD. Errors collapse to `false` so the
  /// upload-conflict path treats every failure ("key not found",
  /// "access denied", network blip) as "target absent" — the
  /// SFTP-side conflict resolver has the same shape.
  @override
  Future<bool> exists(String path) async {
    try {
      await _connection.stat(path: path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// S3 objects carry neither POSIX mode metadata nor a per-object
  /// owner — the bucket has one owning AWS account, and HeadObject
  /// has no `st_mode` field. Falls back to the all-false default,
  /// which the file pane uses to hide the "Mode" and "Owner"
  /// columns.
  @override
  FileSystemCapabilities get capabilities => FileSystemCapabilities.objectStore;
}
