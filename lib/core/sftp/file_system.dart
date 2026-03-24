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

    final entries = <FileEntry>[];
    await for (final entity in dir.list()) {
      final stat = await entity.stat();
      entries.add(FileEntry(
        name: p.basename(entity.path),
        path: entity.path,
        size: stat.size,
        mode: stat.mode,
        modTime: stat.modified,
        isDir: stat.type == FileSystemEntityType.directory,
      ));
    }

    _sort(entries);
    return entries;
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
  Future<void> rename(String oldPath, String newPath) async {
    final type = await FileSystemEntity.type(oldPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
  }

  void _sort(List<FileEntry> entries) {
    entries.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
}
