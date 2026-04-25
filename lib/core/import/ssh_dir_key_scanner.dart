import 'dart:io';

import '../../utils/logger.dart';
import 'key_file_helper.dart';
import 'openssh_config_importer.dart' show PemKeyReader;

/// A key file found during a directory scan — not yet imported.
///
/// [path] is the absolute path to the file on disk, [pem] is the raw
/// file contents (validated to contain `PRIVATE KEY`), and [suggestedLabel]
/// is the basename — callers typically append a date suffix before
/// persisting to keep labels unique across re-imports.
class ScannedKey {
  final String path;
  final String pem;
  final String suggestedLabel;

  const ScannedKey({
    required this.path,
    required this.pem,
    required this.suggestedLabel,
  });
}

/// Lists the file paths in a directory. Returns an empty list when the
/// directory is missing or unreadable. Injected for test isolation.
typedef DirectoryLister = List<String> Function(String directory);

/// Scans a directory (typically `~/.ssh`) for PEM private-key files.
///
/// Pure: performs no storage writes and does not mutate anything. The
/// actual persistence of selected keys happens through `KeyStore` in the
/// UI layer — this class only produces candidates.
class SshDirKeyScanner {
  final PemKeyReader readPem;
  final DirectoryLister listDir;

  SshDirKeyScanner({PemKeyReader? readPem, DirectoryLister? listDir})
    : readPem = readPem ?? KeyFileHelper.tryReadPemKey,
      listDir = listDir ?? _defaultListDir;

  /// Scan [directoryPath] for files that look like PEM private keys.
  ///
  /// Skips obvious non-key files (`.pub`, `known_hosts*`, `config`,
  /// `authorized_keys*`) to avoid noisy dialog rows. Files that fail
  /// [readPem] (too large / not PEM / unreadable) are simply omitted.
  /// Results are deduplicated by file path and sorted alphabetically.
  Future<List<ScannedKey>> scan(String directoryPath) async {
    final paths = List<String>.of(listDir(directoryPath))..sort();
    final result = <ScannedKey>[];
    for (final path in paths) {
      final name = _basename(path);
      if (_isObviousNonKey(name)) continue;
      final pem = await readPem(path);
      if (pem == null) continue;
      result.add(ScannedKey(path: path, pem: pem, suggestedLabel: name));
    }
    return result;
  }

  static bool _isObviousNonKey(String name) {
    if (name.endsWith('.pub')) return true;
    if (name == 'config') return true;
    if (name == 'authorized_keys' || name.startsWith('authorized_keys')) {
      return true;
    }
    if (name.startsWith('known_hosts')) return true;
    return false;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }

  static List<String> _defaultListDir(String directory) {
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(followLinks: false)
          .whereType<File>()
          .map((f) => f.path)
          .toList();
    } catch (e) {
      // Permission denied (common on `~/.ssh` when the user runs a
      // sandboxed build without the Documents scope) returns empty
      // so the UI surfaces "no keys found" gracefully. Logging the
      // underlying error makes "why didn't my keys show up" a
      // greppable question instead of a silent miss.
      AppLogger.instance.log(
        'SshDirKeyScanner: list "$directory" failed (returning empty): $e',
        name: 'SshDirKeyScanner',
      );
      return const [];
    }
  }
}
