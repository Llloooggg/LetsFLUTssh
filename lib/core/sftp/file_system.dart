import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/local_fs.dart' as rust_local_fs;
import '../../src/rust/api/path.dart' as rust_path;
import '../../utils/logger.dart';
import '../../utils/platform.dart';
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

/// Local file system implementation.
///
/// File operations route through `lfs_core::fs::local` (FRB
/// async); the Dart side keeps only [initialDir] because that
/// path uses `path_provider` (iOS sandbox / Android scoped
/// storage), which has no clean Rust analog.
class LocalFS implements FileSystem {
  @override
  Future<String> initialDir() async {
    // iOS sandbox: start in the app's Documents folder (visible in Files.app).
    // Users can pick external folders via the folder picker button.
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      AppLogger.instance.log('iOS initial dir: <path>', name: 'LocalFS');
      return docs.path;
    }
    if (Platform.isAndroid) {
      return _androidInitialDir();
    }
    final home = homeDirectory;
    final path = home.isNotEmpty ? home : Directory.current.path;
    AppLogger.instance.log('Initial dir: <path>', name: 'LocalFS');
    return path;
  }

  /// Android: try shared storage first, fall back to app-specific dir
  /// if storage permission is not granted.
  ///
  /// The probe runs Rust-side via `localFsAndroidInitialDir` —
  /// it stats `/storage/emulated/0`, then stats and lists the
  /// `Download` subdirectory because scoped storage on Android
  /// 11+ lets apps see folder names at the root without actual
  /// read access. `null` here means the probe failed (permission
  /// denied / not mounted) and the Dart caller pivots to
  /// `getExternalStorageDirectory()` (Flutter plugin path, no
  /// Rust analog) for the app-specific fallback.
  Future<String> _androidInitialDir() async {
    final probed = await rust_local_fs.localFsAndroidInitialDir(
      homeDir: homeDirectory,
    );
    if (probed != null) return probed;
    AppLogger.instance.log(
      'No shared storage access, falling back to app dir',
      name: 'LocalFS',
      level: LogLevel.warn,
    );
    final appDir = await getExternalStorageDirectory();
    final fallbackPath = appDir?.path ?? Directory.current.path;
    AppLogger.instance.log('Android fallback dir: <path>', name: 'LocalFS');
    return fallbackPath;
  }

  @override
  Future<List<FileEntry>> list(String path) async {
    final List<rust_local_fs.DbLocalFileEntry> rows;
    try {
      rows = await rust_local_fs.localFsList(path: path);
    } catch (e) {
      // Re-throw as FileSystemException so callers that catch it
      // see one stable exception type regardless of FRB error
      // variant. FRB surfaces `Result<_, String>` errors as either
      // an `AnyhowException` or a plain `String`-bearing exception
      // depending on codec; a single broad catch unifies both.
      throw FileSystemException(_describeError(e), path);
    }

    final hiddenNames = Platform.isWindows
        ? (await rust_local_fs.localFsWindowsHiddenNames(
            dir: path,
          )).map((n) => n.toLowerCase()).toSet()
        : const <String>{};

    final entries = <FileEntry>[];
    for (final row in rows) {
      if (hiddenNames.contains(row.name.toLowerCase())) continue;
      entries.add(
        FileEntry(
          name: row.name,
          path: row.path,
          size: row.size.toInt(),
          mode: row.mode,
          modTime: DateTime.fromMillisecondsSinceEpoch(
            row.modTimeUnixMs.toInt(),
          ),
          isDir: row.isDir,
        ),
      );
    }
    sortFileEntries(entries);
    return entries;
  }

  /// Parse Windows `attrib` output and return lowercase names of
  /// hidden/system files via `lfs_core::path::parse_windows_attrib_output`.
  /// Kept as a static for the existing Dart-facing tests; production
  /// callers route through [list] which hits Rust directly.
  static Set<String> parseAttribOutput(String output) =>
      rust_path.pathParseWindowsAttribOutput(output: output).toSet();

  @override
  Future<void> mkdir(String path) async {
    AppLogger.instance.log('Creating directory: <path>', name: 'LocalFS');
    await rust_local_fs.localFsMkdir(path: path);
  }

  @override
  Future<void> remove(String path) async {
    AppLogger.instance.log('Removing: <path>', name: 'LocalFS');
    await rust_local_fs.localFsRemove(path: path);
  }

  @override
  Future<void> removeDir(String path) async {
    AppLogger.instance.log(
      'Removing directory recursively: <path>',
      name: 'LocalFS',
    );
    await rust_local_fs.localFsRemoveDir(path: path);
  }

  @override
  Future<int> dirSize(String path) async {
    final size = await rust_local_fs.localFsDirSize(path: path);
    return size.toInt();
  }

  /// Cheap presence probe — `localFsSymlinkStat` returns `null`
  /// when the path doesn't exist and a populated record otherwise,
  /// without following symlinks. The trait's default parent-list
  /// fallback would burn a full directory listing per probe; the
  /// symlink-aware stat is one syscall.
  @override
  Future<bool> exists(String path) async {
    try {
      return await rust_local_fs.localFsSymlinkStat(path: path) != null;
    } catch (_) {
      return false;
    }
  }

  /// LocalFS lists carry `st_mode` (Unix) or a synthesised mode
  /// (Windows / Android) and `owner` (uid name on Unix, account
  /// string on Windows) on every entry, so both columns always
  /// have useful content.
  @override
  FileSystemCapabilities get capabilities => FileSystemCapabilities.posix;

  @override
  Future<void> rename(String oldPath, String newPath) async {
    AppLogger.instance.log('Renaming: <path> → <path>', name: 'LocalFS');
    await rust_local_fs.localFsRename(oldPath: oldPath, newPath: newPath);
  }

  /// Pull a one-line message out of the FRB error envelope so the
  /// `FileSystemException("Directory not found", path)` shape stays
  /// human-readable in the file_browser error toasts.
  static String _describeError(Object e) {
    final s = e.toString();
    // FRB throws a wrapper class whose toString includes the full
    // message we passed back from Rust; trim a leading
    // "AnyhowException: " when present so the toast doesn't show it.
    const prefix = 'AnyhowException: ';
    if (s.startsWith(prefix)) return s.substring(prefix.length);
    return s;
  }
}
