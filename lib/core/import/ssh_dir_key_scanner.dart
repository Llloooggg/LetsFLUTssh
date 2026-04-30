import '../../src/rust/api/keys.dart' as rust_keys;
import '../../src/rust/api/ssh_dir_scan.dart' as rust_scan;
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
/// directory is missing or unreadable. Test-only seam.
typedef DirectoryLister = List<String> Function(String directory);

/// Scans a directory (typically `~/.ssh`) for PEM private-key files.
///
/// Production calls route through `lfs_core::ssh_dir_scan::scan`, which
/// owns the directory walk, the non-key filename filter, the size cap,
/// and the PEM / PPK detection in a single Rust pass.
///
/// Tests can still pass [listDir] / [readPem] to drive the scan from
/// in-memory data — the unit suite exercises the orchestration that
/// way without staging real files. When either seam is provided the
/// Dart loop runs locally; otherwise the single FRB call returns the
/// finished result.
class SshDirKeyScanner {
  final PemKeyReader? readPem;
  final DirectoryLister? listDir;

  SshDirKeyScanner({this.readPem, this.listDir});

  /// Scan [directoryPath] for files that look like PEM private keys.
  ///
  /// Skips obvious non-key files (`.pub`, `known_hosts*`, `config`,
  /// `authorized_keys*`). Files that fail the PEM check (too large,
  /// not PEM, unreadable, encrypted PPK) are silently omitted.
  /// Results are sorted alphabetically by path.
  Future<List<ScannedKey>> scan(String directoryPath) async {
    if (listDir == null && readPem == null) {
      return rust_scan
          .sshDirScan(directory: directoryPath)
          .map(
            (k) => ScannedKey(
              path: k.path,
              pem: k.pem,
              suggestedLabel: k.suggestedLabel,
            ),
          )
          .toList(growable: false);
    }
    return _scanWithSeams(directoryPath);
  }

  /// Test-only path — runs the same orchestration as the Rust scanner
  /// using the injected callbacks. Production code never lands here.
  Future<List<ScannedKey>> _scanWithSeams(String directoryPath) async {
    final reader = readPem ?? KeyFileHelper.tryReadPemKey;
    final lister = listDir ?? (_) => const <String>[];
    final paths = List<String>.of(lister(directoryPath))..sort();
    final result = <ScannedKey>[];
    for (final path in paths) {
      final name = KeyFileHelper.basename(path);
      if (rust_keys.keysIsObviousNonKeyFilename(filename: name)) continue;
      final pem = await reader(path);
      if (pem == null) continue;
      result.add(ScannedKey(path: path, pem: pem, suggestedLabel: name));
    }
    return result;
  }
}
