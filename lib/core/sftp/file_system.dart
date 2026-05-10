import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/local_fs.dart' as rust_local_fs;
import '../../src/rust/api/path.dart' as rust_path;
import '../../utils/logger.dart';
import '../../utils/platform.dart';
import 'sftp_models.dart';

/// Abstract file system interface — local or remote.
abstract class FileSystem {
  Future<List<FileEntry>> list(String path);
  Future<String> initialDir();
  Future<void> mkdir(String path);
  Future<void> remove(String path);
  Future<void> removeDir(String path);
  Future<void> rename(String oldPath, String newPath);

  /// Recursively calculate the total size of a directory.
  Future<int> dirSize(String path);
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
  /// Uses a deeper probe (listing a subdirectory) because scoped storage
  /// on Android 11+ lets apps see folder names at the root without actual
  /// read access to their contents.
  Future<String> _androidInitialDir() async {
    final shared = Directory(homeDirectory); // /storage/emulated/0
    try {
      if (await shared.exists()) {
        // Probe a real subdirectory — the root listing succeeds even
        // without MANAGE_EXTERNAL_STORAGE on Android 11+.
        final download = Directory('${shared.path}/Download');
        if (await download.exists()) {
          await download.list().first;
        }
        return shared.path;
      }
    } catch (_) {
      // Permission denied — fall back to app-specific external storage
      AppLogger.instance.log(
        'No shared storage access, falling back to app dir',
        name: 'LocalFS',
        level: LogLevel.warn,
      );
    }
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
      // Match the prior Dart shape so callers that catch
      // FileSystemException keep working. FRB surfaces
      // `Result<_, String>` errors as either an `AnyhowException`
      // or a plain `String`-bearing exception depending on
      // codec; a single broad catch unifies both.
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
