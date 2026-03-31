import 'dart:io';

import 'package:path/path.dart' as p;

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

/// Local file system implementation using dart:io.
class LocalFS implements FileSystem {
  @override
  Future<String> initialDir() async {
    final home = homeDirectory;
    return home.isNotEmpty ? home : Directory.current.path;
  }

  @override
  Future<List<FileEntry>> list(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) throw FileSystemException('Directory not found', path);

    // On Windows, collect hidden/system file names to filter out.
    final hiddenNames = Platform.isWindows
        ? await _windowsHiddenNames(path)
        : const <String>{};

    final entries = <FileEntry>[];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (hiddenNames.contains(name.toLowerCase())) continue;
      final stat = await entity.stat();
      entries.add(FileEntry(
        name: name,
        path: entity.path,
        size: stat.size,
        mode: stat.mode,
        modTime: stat.modified,
        isDir: stat.type == FileSystemEntityType.directory,
      ));
    }

    sortFileEntries(entries);
    return entries;
  }

  /// Run `attrib` on [dirPath] and return lowercase names of hidden/system files.
  static Future<Set<String>> _windowsHiddenNames(String dirPath) async {
    try {
      final result = await Process.run(
        'cmd',
        ['/c', 'attrib', '*'],
        workingDirectory: dirPath,
        stdoutEncoding: const SystemEncoding(),
      );
      if (result.exitCode != 0) return {};
      return parseAttribOutput(result.stdout as String);
    } catch (_) {
      return {};
    }
  }

  /// Parse Windows `attrib` output and return lowercase names of hidden/system files.
  ///
  /// Each line has the format: "     A  SH  C:\path\file"
  /// Attribute letters: S=System, H=Hidden.
  static Set<String> parseAttribOutput(String output) {
    final hidden = <String>{};
    for (final line in output.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) continue;
      final attrEnd = trimmed.lastIndexOf(RegExp(r'[A-Z]  '));
      if (attrEnd < 0) continue;
      final attrs = trimmed.substring(0, attrEnd + 1).toUpperCase();
      if (attrs.contains('H') || attrs.contains('S')) {
        final fullPath = trimmed.substring(attrEnd + 3).trim();
        hidden.add(p.windows.basename(fullPath).toLowerCase());
      }
    }
    return hidden;
  }

  @override
  Future<void> mkdir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> remove(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  @override
  Future<void> removeDir(String path) async {
    await Directory(path).delete(recursive: true);
  }

  @override
  Future<int> dirSize(String path) async {
    int total = 0;
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Skip unreadable files
        }
      }
    }
    return total;
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final type = await FileSystemEntity.type(oldPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
  }
}
