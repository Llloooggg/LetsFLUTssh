import 'dart:io';

import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../core/sftp/file_system.dart';
import '../core/sftp/sftp_models.dart';
import '../src/rust/api/local_fs.dart' as rust_local_fs;
import '../utils/logger.dart';
import '../utils/platform.dart';

/// Local file system implementation.
///
/// File operations route through `lfs_core::fs::local` (FRB async),
/// but the adapter lives in `platform/` rather than `core/` because
/// [initialDir] resolves the OS sandbox start directory via
/// `path_provider` (iOS Documents, Android scoped storage) — a
/// Flutter-plugin path with no clean Rust analog. The network
/// `FileSystem` implementations (SftpFS / WebdavFS) stay in `core/`;
/// only the local one is platform-bound.
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
      // `localFsListVisible` drops Windows Hidden / System files
      // Rust-side so the pane matches Explorer — the hidden-name
      // decision + filter loop are no longer Dart's. Identical to
      // a plain list on every non-Windows target.
      rows = await rust_local_fs.localFsListVisible(path: path);
    } catch (e) {
      // Re-throw as FileSystemException so callers that catch it
      // see one stable exception type regardless of FRB error
      // variant. FRB surfaces `Result<_, String>` errors as either
      // an `AnyhowException` or a plain `String`-bearing exception
      // depending on codec; a single broad catch unifies both.
      throw FileSystemException(describeError(e), path);
    }

    final entries = <FileEntry>[];
    for (final row in rows) {
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
          isSymlink: row.isSymlink,
        ),
      );
    }
    sortFileEntries(entries);
    return entries;
  }

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

  /// Single FRB call — the recursive enumeration, symlink-skip, and
  /// per-segment name validation all run in `lfs_core::fs::local`.
  /// The upload walker calls this instead of recursing through
  /// `dart:io` / per-level `list`.
  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(
    String root, {
    int maxDepth = 100,
  }) async {
    final leaves = await rust_local_fs.localFsFlatWalkFiles(
      root: root,
      maxDepth: maxDepth,
    );
    return [
      for (final e in leaves)
        FlatFileLeaf(relPath: e.relPath, size: e.size.toInt()),
    ];
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
  @visibleForTesting
  static String describeError(Object e) {
    final s = e.toString();
    // FRB throws a wrapper class whose toString includes the full
    // message we passed back from Rust; trim a leading
    // "AnyhowException: " when present so the toast doesn't show it.
    const prefix = 'AnyhowException: ';
    if (s.startsWith(prefix)) return s.substring(prefix.length);
    return s;
  }
}
