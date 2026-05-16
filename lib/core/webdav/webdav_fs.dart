import '../../src/rust/api/webdav.dart' as rust_webdav;
import '../../utils/logger.dart';
import '../sftp/file_system.dart';
import '../sftp/sftp_models.dart';

/// [FileSystem] implementation backed by a live WebDAV transport
/// (`lfs_core::storage::webdav::WebDavProvider` via FRB).
///
/// Mirrors the surface of [RemoteFS] (SFTP) so the file-browser
/// controllers never branch by transport — they hand whatever
/// implements [FileSystem] to the pane controller. The dir-size
/// walk routes through the Provider trait's recursive helper on
/// the Rust side, so a deep tree still pays one FRB call.
class WebDavFileSystem implements FileSystem {
  WebDavFileSystem(this._connection, this._initialDir);

  final rust_webdav.WebDavConnection _connection;
  final String _initialDir;

  /// Last-known root path the browser opens at. WebDAV does not
  /// publish a "current working directory" — the configured base
  /// URL is the implicit root and the caller hands it through at
  /// construction time. The empty string maps to the base URL
  /// itself.
  @override
  Future<String> initialDir() async => _initialDir;

  @override
  Future<List<FileEntry>> list(String path) async {
    AppLogger.instance.log('WebDAV list <path>', name: 'WebDav');
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
    AppLogger.instance.log('WebDAV mkdir <path>', name: 'WebDav');
    await _connection.mkdir(path: path);
  }

  @override
  Future<void> remove(String path) async {
    AppLogger.instance.log('WebDAV remove <path>', name: 'WebDav');
    await _connection.remove(path: path);
  }

  /// Most WebDAV servers cascade DELETE on a collection (Nextcloud,
  /// ownCloud, Apache mod_dav, IIS). Mapping `removeDir` to the
  /// same DELETE keeps the contract identical to [remove] — the
  /// server, not the client, walks the tree.
  @override
  Future<void> removeDir(String path) async {
    AppLogger.instance.log('WebDAV removeDir <path>', name: 'WebDav');
    await _connection.remove(path: path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    AppLogger.instance.log('WebDAV rename <path> → <path>', name: 'WebDav');
    await _connection.rename(from: oldPath, to: newPath);
  }

  @override
  Future<int> dirSize(String path) async {
    final size = await _connection.dirSize(path: path);
    return size.toInt();
  }

  /// Cheap presence probe — one `PROPFIND depth=0` via
  /// `WebDavConnection.stat`. Beats the trait's parent-listing
  /// default for transports where a single-resource probe is
  /// cheaper than a directory walk (every server in practice).
  /// Any error collapses to `false` so the upload-conflict path
  /// treats "404 / 410 / network blip" all as "target absent".
  @override
  Future<bool> exists(String path) async {
    try {
      await _connection.stat(path: path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
