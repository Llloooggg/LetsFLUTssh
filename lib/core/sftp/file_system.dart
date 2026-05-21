import 'sftp_models.dart';

/// Capability set a [FileSystem] backend declares to its callers.
///
/// One struct per backend is **strictly more economical** than a
/// getter per capability — adding a new capability is a field on
/// this class plus a literal update in each production impl; test
/// stubs that don't care just keep the default-constructed value.
/// Compare the per-getter shape: every new capability landed an
/// `@override bool get X => false;` on every `implements FileSystem`
/// site, which over time turned test files into capability-declaration
/// boilerplate without any test-related signal.
///
/// All fields default to `false`. Backends opt in by listing the
/// capabilities they actually populate.
class FileSystemCapabilities {
  /// Whether the backend populates `FileEntry.mode` with meaningful
  /// POSIX permission bits. True for SFTP (server returns `st_mode`)
  /// and LocalFS on every host (Rust's `localFsList` synthesises a
  /// mode on Windows / Android). False for HTTP-based backends:
  /// WebDAV PROPFIND doesn't surface POSIX modes and S3 `HeadObject`
  /// doesn't carry them, so the column would render `--------` on
  /// every row. The file-browser pane gates the "Mode" column on
  /// this so non-POSIX backends don't reserve screen space.
  final bool posixMode;

  /// Whether the backend populates `FileEntry.owner` with a
  /// meaningful string. True for SFTP (server returns the owning
  /// uid name) and LocalFS (uid name on Unix, owner SID on
  /// Windows). False for backends without a per-resource owner
  /// concept — WebDAV `displayname` is not an owner, S3 buckets
  /// have a single account owner not per-object.
  final bool owner;

  const FileSystemCapabilities({this.posixMode = false, this.owner = false});

  /// Convenience constant for the common "HTTP-style object store
  /// with no POSIX metadata" backend (WebDAV, S3). Lets the impl
  /// write `capabilities = FileSystemCapabilities.objectStore`
  /// instead of repeating the all-default struct.
  static const objectStore = FileSystemCapabilities();

  /// All POSIX metadata available. Used by both SFTP-backed remote
  /// filesystems and LocalFS.
  static const posix = FileSystemCapabilities(posixMode: true, owner: true);
}

/// Abstract file system interface — local or remote.
abstract class FileSystem {
  Future<List<FileEntry>> list(String path);
  Future<String> initialDir();
  Future<void> mkdir(String path);
  Future<void> remove(String path);
  Future<void> removeDir(String path);
  Future<void> rename(String oldPath, String newPath);

  /// Whether `path` exists on this backend. Used by the conflict
  /// resolver in `TransferHelpers` to decide between
  /// skip / keep-both / replace before enqueueing an upload. The
  /// default implementation falls back to a one-shot directory
  /// listing of the parent so backends that don't expose a
  /// dedicated probe (the legacy `RemoteFS` shim, in-process test
  /// stubs) still answer correctly; native implementations
  /// (`RemoteSftpFs`, `WebDavFileSystem`, `S3FileSystem`) override
  /// with their cheap path. Errors collapse to `false` so the
  /// callers treat them as "target does not exist" (the SFTP
  /// LSTAT-NotFound shape).
  Future<bool> exists(String path) async {
    try {
      final dir = _posixDirname(path);
      final name = _posixBasename(path);
      if (name.isEmpty) return false;
      final entries = await list(dir);
      for (final entry in entries) {
        if (entry.name == name) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Recursively calculate the total size of a directory.
  Future<int> dirSize(String path);

  /// What this backend can surface. Defaults to "nothing populated"
  /// — the conservative shape that matches every HTTP-style object
  /// store. Concrete backends override with the constants on
  /// [FileSystemCapabilities] or a tailored instance.
  FileSystemCapabilities get capabilities => FileSystemCapabilities.objectStore;
}

String _posixDirname(String path) {
  if (path.isEmpty) return '/';
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = trimmed.lastIndexOf('/');
  if (i < 0) return '';
  if (i == 0) return '/';
  return trimmed.substring(0, i);
}

String _posixBasename(String path) {
  if (path.isEmpty) return '';
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = trimmed.lastIndexOf('/');
  if (i < 0) return trimmed;
  return trimmed.substring(i + 1);
}
