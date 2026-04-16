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

/// Classifier for PEM encryption state. Matches [KeyFileHelper.isEncryptedPem]
/// in production; stubbed out in tests so they don't have to craft real
/// bcrypt-wrapped key material.
typedef EncryptedPemDetector = bool Function(String pem);

/// Result of preparing a config-file import — ready to pass to ImportService.
class OpenSshConfigImportPreview {
  final ImportResult result;

  /// Number of parsed host entries (before filtering).
  final int parsedHosts;

  /// Host aliases for which no usable key could be resolved — includes both
  /// the "file missing / unreadable" case and the "file exists but is
  /// passphrase-encrypted" case, because from the session's point of view the
  /// outcome is identical: the session is imported without a key. The UI
  /// surfaces this as a single "these hosts have no credentials" warning.
  final List<String> hostsWithMissingKeys;

  /// Subset of [hostsWithMissingKeys] where the IdentityFile was readable but
  /// rejected as a passphrase-protected key. Callers that want to surface a
  /// more specific "decrypt the key first" hint can read this field;
  /// everyone else can ignore it and rely on [hostsWithMissingKeys] alone.
  final List<String> hostsWithEncryptedKeys;

  const OpenSshConfigImportPreview({
    required this.result,
    required this.parsedHosts,
    this.hostsWithMissingKeys = const [],
    this.hostsWithEncryptedKeys = const [],
  });
}

/// Builds an [ImportResult] from an OpenSSH config file.
///
/// Pure: performs no storage writes, no UI. Wiring into the settings
/// screen (file picker, preview dialog, apply) happens elsewhere.
class OpenSshConfigImporter {
  final PemKeyReader readPem;
  final EncryptedPemDetector isEncryptedPem;

  /// Instance used only for its stateless [KeyStore.importKey] — avoids
  /// duplicating the PEM→SshKeyEntry parsing logic already there.
  final KeyStore _keyParser;

  OpenSshConfigImporter({
    PemKeyReader? readPem,
    EncryptedPemDetector? isEncryptedPem,
    KeyStore? keyParser,
  }) : readPem = readPem ?? KeyFileHelper.tryReadPemKey,
       isEncryptedPem = isEncryptedPem ?? KeyFileHelper.isEncryptedPem,
       _keyParser = keyParser ?? KeyStore();

  /// Expand a leading `~` in [path] to the user's home directory.
  /// Paths without `~` pass through untouched.
  static String expandHome(String path) {
    if (path == '~') return homeDirectory;
    if (path.startsWith('~/')) return '$homeDirectory${path.substring(1)}';
    return path;
  }

  /// Delegates to [KeyFileHelper.isSuspiciousPath]. Kept as a thin wrapper so
  /// existing callers / tests that reach for
  /// `OpenSshConfigImporter.isSuspiciousPath` keep working without pulling
  /// the helper import everywhere.
  static bool isSuspiciousPath(String path) =>
      KeyFileHelper.isSuspiciousPath(path);

  /// Build an import preview from raw config content.
  ///
  /// [folderLabel] is where imported sessions land — recommended to include
  /// the date so users can tell where hosts came from after the fact.
  OpenSshConfigImportPreview buildPreview({
    required String configContent,
    required String folderLabel,
    String keyLabelSuffix = '',
    ImportMode mode = ImportMode.merge,
  }) {
    final entries = parseOpenSshConfig(configContent);
    final sessions = <Session>[];
    final keys = <SshKeyEntry>[];
    final keyIdByFingerprint = <String, String>{};
    final missingKeys = <String>[];
    final encryptedKeys = <String>[];

    for (final entry in entries) {
      final resolution = _resolveIdentityKey(
        entry,
        keys,
        keyIdByFingerprint,
        keyLabelSuffix,
      );
      // Both missing and encrypted outcomes leave the host without a usable
      // key, so both feed [missingKeys] — keeps the existing UI warning
      // accurate regardless of which failure mode we hit.
      if (resolution.missing || resolution.encrypted) {
        missingKeys.add(entry.host);
      }
      if (resolution.encrypted) encryptedKeys.add(entry.host);

      sessions.add(_buildSessionForEntry(entry, resolution.keyId, folderLabel));
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
      hostsWithEncryptedKeys: encryptedKeys,
    );
  }

  /// Build a [Session] for [entry] honouring the user-declared
  /// `PreferredAuthentications` ordering — the importer must not default to
  /// [AuthType.key] when the user explicitly asked for password auth, even if
  /// an IdentityFile is also set (OpenSSH itself picks password first in that
  /// case). See [OpenSshConfigEntry.preferredAuthTypes].
  Session _buildSessionForEntry(
    OpenSshConfigEntry entry,
    String keyId,
    String folderLabel,
  ) {
    final preferred = entry.preferredAuthTypes;
    final AuthType authType;
    if (preferred != null && preferred.isNotEmpty) {
      authType = preferred.first;
    } else if (keyId.isNotEmpty) {
      authType = AuthType.key;
    } else {
      authType = AuthType.password;
    }
    return Session(
      label: entry.host,
      folder: folderLabel,
      server: ServerAddress(
        host: entry.effectiveHost,
        port: entry.port ?? 22,
        user: entry.user ?? '',
      ),
      auth: SessionAuth(
        authType: authType,
        keyId: authType == AuthType.key ? keyId : '',
      ),
    );
  }

  /// Resolve the IdentityFile list for an entry to a key id. Reads each
  /// candidate through [readPem]; the first one that parses as a PEM private
  /// key wins. Dedups within this import by fingerprint so two hosts
  /// pointing at the same key share one [SshKeyEntry].
  ///
  /// Returns a structured result distinguishing three outcomes:
  /// * ok: `keyId` populated, no flags — caller stores the session with key.
  /// * encrypted: at least one IdentityFile exists but couldn't be parsed
  ///   because it's passphrase-protected — `keyId` empty, `encrypted=true`.
  /// * missing: the entry *declared* an IdentityFile but none were readable
  ///   — `keyId` empty, `missing=true`.
  _KeyResolution _resolveIdentityKey(
    OpenSshConfigEntry entry,
    List<SshKeyEntry> keys,
    Map<String, String> keyIdByFingerprint,
    String keyLabelSuffix,
  ) {
    if (entry.identityFiles.isEmpty) return const _KeyResolution('');
    var sawEncrypted = false;
    for (final rawPath in entry.identityFiles) {
      if (KeyFileHelper.isSuspiciousPath(rawPath)) {
        AppLogger.instance.log(
          'Rejected IdentityFile with traversal segments: $rawPath',
          name: 'SshConfigImport',
        );
        continue;
      }
      final path = expandHome(rawPath);
      final pem = readPem(path);
      if (pem == null) continue;
      if (isEncryptedPem(pem)) {
        sawEncrypted = true;
        AppLogger.instance.log(
          'IdentityFile at $path is encrypted — needs passphrase',
          name: 'SshConfigImport',
        );
        continue;
      }
      final fp = KeyStore.privateKeyFingerprint(pem);
      final existingId = keyIdByFingerprint[fp];
      if (existingId != null) return _KeyResolution(existingId);
      try {
        final keyEntry = _keyParser.importKey(
          pem,
          _keyLabel(rawPath, keyLabelSuffix),
        );
        keys.add(keyEntry);
        keyIdByFingerprint[fp] = keyEntry.id;
        return _KeyResolution(keyEntry.id);
      } catch (e) {
        AppLogger.instance.log(
          'Skipped unparseable key at $path: $e',
          name: 'SshConfigImport',
        );
      }
    }
    return _KeyResolution('', encrypted: sawEncrypted, missing: !sawEncrypted);
  }

  /// Derive a human label for a key from its file path. Uses the basename
  /// so "~/.ssh/id_ed25519" becomes "id_ed25519", optionally with a
  /// trailing [suffix] for uniqueness across imports (e.g. a date stamp).
  static String _keyLabel(String rawPath, String suffix) {
    final sep = Platform.pathSeparator;
    final baseRaw = KeyFileHelper.basename(rawPath);
    final base = baseRaw.isEmpty ? rawPath : baseRaw.replaceAll(sep, '_');
    return suffix.isEmpty ? base : '$base $suffix';
  }
}

/// Outcome of [OpenSshConfigImporter._resolveIdentityKey]. Exactly one of
/// the flags is true when [keyId] is empty; [keyId] is always empty when
/// [encrypted] or [missing].
class _KeyResolution {
  final String keyId;
  final bool encrypted;
  final bool missing;
  const _KeyResolution(
    this.keyId, {
    this.encrypted = false,
    this.missing = false,
  });
}
