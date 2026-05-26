import '../../src/rust/api/path.dart' as rust_path;
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
      // Parent + basename grammar is Rust-owned. SFTP paths are
      // always POSIX, so this default (used by the legacy `RemoteFS`
      // shim + in-process test stubs) forces POSIX parsing. A `null`
      // parent means a root / bare segment with no directory to list.
      final dir = rust_path.pathParent(
        path: path,
        style: rust_path.DbPathStyle.posix,
      );
      if (dir == null) return false;
      final name = rust_path.pathBasename(path: path);
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

  /// Recursively enumerate every leaf (non-directory) file under
  /// [root], skipping symlinks and validating each entry name, and
  /// return each as a [FlatFileLeaf] whose `relPath` is `/`-joined
  /// relative to [root]. Used by the transfer walker to enqueue one
  /// task per file without a Dart-side per-level recursion.
  ///
  /// `LocalFS` and `RemoteFS` (SFTP) override this with a single
  /// Rust FRB call so the whole walk runs Rust-/server-side over one
  /// hop. Object-store backends (WebDAV / S3) that have no single-call
  /// walker delegate to [flatWalkViaList], the shared `list`-based
  /// recursion. `maxDepth` bounds a cyclic tree.
  Future<List<FlatFileLeaf>> flatWalkFiles(String root, {int maxDepth = 100});

  /// What this backend can surface. Defaults to "nothing populated"
  /// — the conservative shape that matches every HTTP-style object
  /// store. Concrete backends override with the constants on
  /// [FileSystemCapabilities] or a tailored instance.
  FileSystemCapabilities get capabilities => FileSystemCapabilities.objectStore;
}

/// Shared `list`-based recursive walk for [FileSystem.flatWalkFiles]
/// backends that have no single-call walker (WebDAV / S3 object
/// stores). Recurses through [fs] with [FileSystem.list] per level,
/// collecting leaf files with their `/`-joined relative paths.
/// Bounded by [maxDepth] against a cyclic tree.
Future<List<FlatFileLeaf>> flatWalkViaList(
  FileSystem fs,
  String root, {
  int maxDepth = 100,
}) {
  Future<List<FlatFileLeaf>> walk(
    String dir,
    String relPrefix,
    int depth,
  ) async {
    if (depth >= maxDepth) return const [];
    final out = <FlatFileLeaf>[];
    final entries = await fs.list(dir);
    for (final entry in entries) {
      final childRel = relPrefix.isEmpty
          ? entry.name
          : '$relPrefix/${entry.name}';
      if (entry.isDir) {
        out.addAll(await walk(entry.path, childRel, depth + 1));
      } else {
        out.add(FlatFileLeaf(relPath: childRel, size: entry.size));
      }
    }
    return out;
  }

  return walk(root, '', 0);
}
