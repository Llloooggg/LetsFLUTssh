import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart';

import '../../core/config/app_config.dart';
import '../../core/security/key_store.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../utils/logger.dart';

/// .lfs (LetsFLUTssh) archive format — ZIP encrypted with AES-256-GCM.
///
/// Structure inside ZIP:
///   sessions.json  — full session data WITH credentials
///   config.json    — app configuration
///   known_hosts    — TOFU host key database
///
/// The ZIP bytes are encrypted with AES-256-GCM using a key derived from
/// a master password via PBKDF2 (600k iterations, SHA-256).
class ExportImport {
  static const _saltLen = 32;
  static const _ivLen = 12;
  static const _pbkdf2Iterations = 600000;
  static const _sessionsFile = 'sessions.json';
  static const _keysFile = 'keys.json';
  static const _emptyFoldersFile = 'empty_folders.json';
  static const _configFile = 'config.json';
  static const _knownHostsFile = 'known_hosts';

  /// Export app data to an encrypted .lfs file.
  ///
  /// [options] controls what data to include in the export.
  /// [emptyFolders] set of empty folder paths to preserve.
  /// [knownHostsContent] is the decrypted known_hosts text (from
  /// [KnownHostsManager.exportToString]). Pass null to omit known_hosts.
  ///
  /// Returns the file path of the created archive.
  static Future<String> export({
    required String masterPassword,
    required List<Session> sessions,
    required AppConfig config,
    required String outputPath,
    ExportOptions options = const ExportOptions(),
    Set<String> emptyFolders = const {},
    String? knownHostsContent,
    List<SshKeyEntry> managerKeyEntries = const [],
  }) async {
    // Build ZIP archive in memory
    final archive = Archive();

    // Sessions with credentials (if included)
    if (options.includeSessions) {
      final sessionsJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(sessions.map((s) => s.toJsonWithCredentials()).toList());
      final sessionsBytes = utf8.encode(sessionsJson);
      archive.addFile(
        ArchiveFile(_sessionsFile, sessionsBytes.length, sessionsBytes),
      );

      // Empty folders (if sessions included)
      if (emptyFolders.isNotEmpty) {
        final foldersJson = const JsonEncoder.withIndent(
          '  ',
        ).convert(emptyFolders.toList());
        final foldersBytes = utf8.encode(foldersJson);
        archive.addFile(
          ArchiveFile(_emptyFoldersFile, foldersBytes.length, foldersBytes),
        );
      }
    }

    // Manager keys (if included)
    if (options.includeManagerKeys && managerKeyEntries.isNotEmpty) {
      final keysJson = const JsonEncoder.withIndent('  ').convert(
        managerKeyEntries
            .map(
              (e) => {
                'id': e.id,
                'label': e.label,
                'private_key': e.privateKey,
                'public_key': e.publicKey,
                'key_type': e.keyType,
                'is_generated': e.isGenerated,
                'created_at': e.createdAt.toIso8601String(),
              },
            )
            .toList(),
      );
      final keysBytes = utf8.encode(keysJson);
      archive.addFile(ArchiveFile(_keysFile, keysBytes.length, keysBytes));
    }

    // Config (if included)
    if (options.includeConfig) {
      final configJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(config.toJson());
      final configBytes = utf8.encode(configJson);
      archive.addFile(
        ArchiveFile(_configFile, configBytes.length, configBytes),
      );
    }

    // Known hosts (if included)
    if (options.includeKnownHosts &&
        knownHostsContent != null &&
        knownHostsContent.isNotEmpty) {
      final khBytes = utf8.encode(knownHostsContent);
      archive.addFile(ArchiveFile(_knownHostsFile, khBytes.length, khBytes));
    }

    // Encode ZIP
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    AppLogger.instance.log(
      'Export: ZIP archive ${zipBytes.length} bytes, '
      '${sessions.length} sessions, '
      'config=${options.includeConfig}, '
      'knownHosts=${options.includeKnownHosts && knownHostsContent != null}',
      name: 'ExportImport',
    );

    // Encrypt with master password (runs in isolate — PBKDF2 600k is CPU-heavy)
    final encrypted = await Isolate.run(
      () => _encryptWithPassword(zipBytes, masterPassword),
    );
    AppLogger.instance.log(
      'Export: encrypted ${encrypted.length} bytes',
      name: 'ExportImport',
    );

    // Write to file
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encrypted);

    return outputPath;
  }

  /// Decrypt an .lfs file and parse the archive contents.
  static Future<
    ({
      Archive archive,
      List<Session> sessions,
      Set<String> emptyFolders,
      List<SshKeyEntry> managerKeys,
    })
  >
  _decryptAndParseArchive({
    required String filePath,
    required String masterPassword,
  }) async {
    final file = File(filePath);
    final encData = await file.readAsBytes();

    // Decrypt in isolate — PBKDF2 600k iterations is CPU-heavy
    final zipBytes = await Isolate.run(
      () => _decryptWithPassword(encData, masterPassword),
    );
    final archive = ZipDecoder().decodeBytes(zipBytes);

    List<Session> sessions = [];
    final sessionsFile = archive.findFile(_sessionsFile);
    if (sessionsFile != null) {
      final json = utf8.decode(sessionsFile.content as List<int>);
      final list = jsonDecode(json) as List;
      sessions = list
          .map((e) => Session.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    Set<String> emptyFolders = {};
    final foldersFile = archive.findFile(_emptyFoldersFile);
    if (foldersFile != null) {
      final json = utf8.decode(foldersFile.content as List<int>);
      final list = jsonDecode(json) as List;
      emptyFolders = list.cast<String>().toSet();
    }

    List<SshKeyEntry> managerKeys = [];
    final keysFile = archive.findFile(_keysFile);
    if (keysFile != null) {
      final json = utf8.decode(keysFile.content as List<int>);
      final list = jsonDecode(json) as List;
      managerKeys = list.map((e) {
        final m = e as Map<String, dynamic>;
        return SshKeyEntry(
          id: m['id'] as String? ?? '',
          label: m['label'] as String? ?? '',
          privateKey: m['private_key'] as String? ?? '',
          publicKey: m['public_key'] as String? ?? '',
          keyType: m['key_type'] as String? ?? '',
          isGenerated: m['is_generated'] as bool? ?? false,
          createdAt:
              DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
    }

    AppLogger.instance.log(
      'Import: decrypted ${encData.length} bytes, '
      '${sessions.length} sessions, '
      '${managerKeys.length} manager keys, '
      '${emptyFolders.length} empty folders',
      name: 'ExportImport',
    );
    return (
      archive: archive,
      sessions: sessions,
      emptyFolders: emptyFolders,
      managerKeys: managerKeys,
    );
  }

  /// Preview contents of an .lfs archive without full import.
  static Future<LfsPreview> preview({
    required String filePath,
    required String masterPassword,
  }) async {
    final (
      :archive,
      :sessions,
      :emptyFolders,
      :managerKeys,
    ) = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
    );

    final hasConfig = archive.findFile(_configFile) != null;
    final hasKnownHosts = archive.findFile(_knownHostsFile) != null;

    return LfsPreview(
      sessions: sessions,
      hasConfig: hasConfig,
      hasKnownHosts: hasKnownHosts,
      emptyFolders: emptyFolders,
      managerKeyCount: managerKeys.length,
    );
  }

  /// Import data from an .lfs archive.
  ///
  /// [options] controls what data to import (only imports what's present).
  /// [mode] controls how sessions are merged:
  /// - `ImportMode.merge` — add new sessions, skip existing (by ID)
  /// - `ImportMode.replace` — replace all sessions with imported ones
  static Future<ImportResult> import_({
    required String filePath,
    required String masterPassword,
    required ImportMode mode,
    ExportOptions options = const ExportOptions(),
  }) async {
    final (
      :archive,
      :sessions,
      :emptyFolders,
      :managerKeys,
    ) = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
    );

    // Parse config (only if requested and present)
    AppConfig? config;
    if (options.includeConfig) {
      final configFile = archive.findFile(_configFile);
      if (configFile != null) {
        final json = utf8.decode(configFile.content as List<int>);
        config = AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
    }

    // Known hosts — return content only if requested
    String? knownHostsContent;
    if (options.includeKnownHosts) {
      final khFile = archive.findFile(_knownHostsFile);
      if (khFile != null) {
        knownHostsContent = utf8.decode(khFile.content as List<int>);
      }
    }

    return ImportResult(
      sessions: options.includeSessions ? sessions : [],
      emptyFolders: options.includeSessions ? emptyFolders : {},
      managerKeys: options.includeManagerKeys ? managerKeys : [],
      config: config,
      mode: mode,
      knownHostsContent: knownHostsContent,
    );
  }

  // --- Crypto helpers ---

  /// Encrypt bytes with password-derived key (PBKDF2 + AES-256-GCM).
  /// Format: [salt (32)] [iv (12)] [ciphertext + GCM tag]
  static Uint8List _encryptWithPassword(Uint8List data, String password) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final output = cipher.process(data);
    return Uint8List.fromList([...salt, ...iv, ...output]);
  }

  /// Decrypt bytes with password-derived key.
  static Uint8List _decryptWithPassword(Uint8List data, String password) {
    final salt = data.sublist(0, _saltLen);
    final iv = data.sublist(_saltLen, _saltLen + _ivLen);
    final ciphertext = data.sublist(_saltLen + _ivLen);

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    return cipher.process(ciphertext);
  }

  /// Derive 256-bit key from password using PBKDF2-SHA256.
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, 32));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }
}

/// Preview of .lfs archive contents.
class LfsPreview {
  final List<Session> sessions;
  final bool hasConfig;
  final bool hasKnownHosts;
  final Set<String> emptyFolders;
  final int managerKeyCount;

  const LfsPreview({
    required this.sessions,
    this.hasConfig = false,
    this.hasKnownHosts = false,
    this.emptyFolders = const {},
    this.managerKeyCount = 0,
  });

  /// Derived from [sessions] to prevent stale/inconsistent state.
  bool get hasSessions => sessions.isNotEmpty;
  int get emptyFoldersCount => emptyFolders.length;
}

/// Import mode for sessions.
enum ImportMode { merge, replace }

/// Result of importing an .lfs archive.
class ImportResult {
  final List<Session> sessions;
  final Set<String> emptyFolders;

  /// Manager keys to insert into KeyStore. Sessions with matching keyId
  /// should be linked after keys are saved.
  final List<SshKeyEntry> managerKeys;
  final AppConfig? config;
  final ImportMode mode;

  /// Decrypted known_hosts content (OpenSSH text format) from the archive.
  /// Null if known_hosts was not included or not requested.
  final String? knownHostsContent;

  const ImportResult({
    required this.sessions,
    this.emptyFolders = const {},
    this.managerKeys = const [],
    this.config,
    required this.mode,
    this.knownHostsContent,
  });
}
