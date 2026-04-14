import 'dart:io';

import '../../features/settings/export_import.dart';
import '../../utils/logger.dart';
import '../../utils/platform.dart';
import '../security/key_store.dart';
import '../session/session.dart';
import '../ssh/openssh_config_parser.dart';
import '../ssh/ssh_config.dart';
import 'key_file_helper.dart';

/// Reader that returns PEM contents for a path, or null if unreadable /
/// not a private key. Injected for testability (file system isolation).
typedef PemKeyReader = String? Function(String path);

/// Result of preparing a config-file import — ready to pass to ImportService.
class OpenSshConfigImportPreview {
  final ImportResult result;

  /// Number of parsed host entries (before filtering).
  final int parsedHosts;

  /// Host aliases whose IdentityFile could not be read. Sessions for these
  /// are still imported (with empty credentials) so the user can fill them
  /// in later.
  final List<String> hostsWithMissingKeys;

  const OpenSshConfigImportPreview({
    required this.result,
    required this.parsedHosts,
    required this.hostsWithMissingKeys,
  });
}

/// Builds an [ImportResult] from an OpenSSH config file.
///
/// Pure: performs no storage writes, no UI. Wiring into the settings
/// screen (file picker, preview dialog, apply) happens elsewhere.
class OpenSshConfigImporter {
  final PemKeyReader readPem;

  /// Instance used only for its stateless [KeyStore.importKey] — avoids
  /// duplicating the PEM→SshKeyEntry parsing logic already there.
  final KeyStore _keyParser;

  OpenSshConfigImporter({PemKeyReader? readPem, KeyStore? keyParser})
    : readPem = readPem ?? KeyFileHelper.tryReadPemKey,
      _keyParser = keyParser ?? KeyStore();

  /// Expand a leading `~` in [path] to the user's home directory.
  /// Paths without `~` pass through untouched.
  static String expandHome(String path) {
    if (path == '~') return homeDirectory;
    if (path.startsWith('~/')) return '$homeDirectory${path.substring(1)}';
    return path;
  }

  /// Build an import preview from raw config content.
  ///
  /// [folderLabel] is where imported sessions land — recommended to include
  /// the date so users can tell where hosts came from after the fact.
  OpenSshConfigImportPreview buildPreview({
    required String configContent,
    required String folderLabel,
    ImportMode mode = ImportMode.merge,
  }) {
    final entries = parseOpenSshConfig(configContent);
    final sessions = <Session>[];
    final keys = <SshKeyEntry>[];
    final keyIdByFingerprint = <String, String>{};
    final missingKeys = <String>[];

    for (final entry in entries) {
      final (keyId, keyMissing) = _resolveIdentityKey(
        entry,
        keys,
        keyIdByFingerprint,
      );
      if (keyMissing) missingKeys.add(entry.host);

      sessions.add(
        Session(
          label: entry.host,
          folder: folderLabel,
          server: ServerAddress(
            host: entry.effectiveHost,
            port: entry.port ?? 22,
            user: entry.user ?? '',
          ),
          auth: SessionAuth(
            authType: keyId.isNotEmpty ? AuthType.key : AuthType.password,
            keyId: keyId,
          ),
        ),
      );
    }

    return OpenSshConfigImportPreview(
      result: ImportResult(
        sessions: sessions,
        managerKeys: keys,
        mode: mode,
        emptyFolders: sessions.isEmpty ? const {} : {folderLabel},
      ),
      parsedHosts: entries.length,
      hostsWithMissingKeys: missingKeys,
    );
  }

  /// Resolve the IdentityFile list for an entry to a key id (empty when none
  /// found). Reads each candidate through [readPem]; the first one that
  /// parses as a PEM private key wins. Dedups within this import by
  /// fingerprint so two hosts pointing at the same key share one [SshKeyEntry].
  ///
  /// Returns (keyId, missingKeyFlag). `missingKeyFlag` is true when the
  /// entry *declared* an IdentityFile but none of them were readable —
  /// useful for warning the user in the preview. Entries that declare no
  /// IdentityFile at all are not considered missing.
  (String, bool) _resolveIdentityKey(
    OpenSshConfigEntry entry,
    List<SshKeyEntry> keys,
    Map<String, String> keyIdByFingerprint,
  ) {
    if (entry.identityFiles.isEmpty) return ('', false);
    for (final rawPath in entry.identityFiles) {
      final path = expandHome(rawPath);
      final pem = readPem(path);
      if (pem == null) continue;
      final fp = KeyStore.privateKeyFingerprint(pem);
      final existingId = keyIdByFingerprint[fp];
      if (existingId != null) return (existingId, false);
      try {
        final keyEntry = _keyParser.importKey(pem, _keyLabel(rawPath));
        keys.add(keyEntry);
        keyIdByFingerprint[fp] = keyEntry.id;
        return (keyEntry.id, false);
      } catch (e) {
        AppLogger.instance.log(
          'Skipped unparseable key at $path: $e',
          name: 'SshConfigImport',
        );
      }
    }
    return ('', true);
  }

  /// Derive a human label for a key from its file path. Uses the basename
  /// so "~/.ssh/id_ed25519" becomes "id_ed25519".
  static String _keyLabel(String rawPath) {
    final sep = Platform.pathSeparator;
    final normalized = rawPath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    final base = idx < 0 ? normalized : normalized.substring(idx + 1);
    return base.isEmpty ? rawPath : base.replaceAll(sep, '_');
  }
}
